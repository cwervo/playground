/* sim-worker.js -- the visual pathway simulation, off the main thread.
 *
 * Owns the one LinearMemory that holds every population.  Each camera frame
 * is one tick: retina -> LGN -> V1 -> V2.  After a tick the worker posts a
 * snapshot (memcpy) of the used memory segment plus the memory map, so the
 * renderer views populations straight out of the dump.
 *
 * Message protocol (mirrors flybrain's sim-worker.js):
 *   Main -> Worker:
 *     init            {}                                   allocate, build receptive fields
 *     frame           {rgba, right?}                       one camera frame (transferred buffers)
 *     setParams       {lightLevel, noise, stereo, syntheticShift, plasticity, plasticityRate}
 *     resetWeights    {mode: 'gabor' | 'random'}
 *     probe           {kind, ...}                          run a tuning-curve / RF-map experiment
 *     abortProbe      {}
 *   Worker -> Main:
 *     ready           {map, dump, W, H, V1_W, V1_H, N_ORI, N_SF, N_DISP, K}
 *     tick            {snapshot, tickMs, tick, spikes}
 *     probeProgress   {kind, done, total}
 *     probeResult     {kind, ...series}
 *     error           {message}
 */

importScripts('constants.js', 'linear-memory.js', 'response-curves.js', 'stimuli.js', 'retina.js', 'cortex.js');

/* ---------- module-level state ---------- */
var mem = null;
var ret = null;          /* left (or only) eye retina */
var retR = null;         /* right-eye lite retina */
var ctx = null;          /* LGN / V1 / V2 */
var W = RV.GRID_W, H = RV.GRID_H, N = W * H;
var linearLUT = new Float32Array(256);
var tickCount = 0;
var probeAbort = false;
var probeRunning = false;
var params = {
	lightLevel: 1.0,
	noise: 0.01,
	stereo: 'none',
	syntheticShift: 3,
	plasticity: false,
	plasticityRate: RV.PLASTICITY.rate
};
var field = new Float32Array(N);       /* scratch stimulus field for probes */
var fieldR = new Float32Array(N);

for (var b = 0; b < 256; b++) linearLUT[b] = CURVES.srgbToLinear(b);

/* ---------- init ---------- */

function init() {
	mem = new LinearMemory(RV.MEMORY_BYTES);
	ret = RETINA.create(mem, RV);
	retR = RETINA.createLite(mem, RV, 'RETR');
	ctx = CORTEX.create(mem, RV, ret);
	ctx.right = retR;
	tickCount = 0;
	self.postMessage({
		type: 'ready',
		map: mem.map(),
		dump: mem.dump(),
		W: W, H: H, V1_W: RV.V1_W, V1_H: RV.V1_H,
		N_ORI: RV.N_ORI, N_SF: RV.SF_LAMBDA.length, N_DISP: RV.N_DISP, DISP_MAX: RV.DISP_MAX, K: RV.V1_K,
		SF_LAMBDA: RV.SF_LAMBDA
	});
}

/* ---------- camera frame -> input regions ---------- */

function loadFrame(rgba, right) {
	var IR = ret.IN_R, IG = ret.IN_G, IB = ret.IN_B;
	for (var i = 0, j = 0; i < N; i++, j += 4) {
		IR[i] = linearLUT[rgba[j]];
		IG[i] = linearLUT[rgba[j + 1]];
		IB[i] = linearLUT[rgba[j + 2]];
	}
	if (params.stereo === 'camera' && right) {
		var RI = retR.IN;
		for (var k = 0, m = 0; k < N; k++, m += 4) {
			RI[k] = 0.5 * (linearLUT[right[m]] + linearLUT[right[m + 1]]);
		}
	} else if (params.stereo === 'synthetic') {
		synthesizeRightEye();
	}
}

/* Right eye = left luminance shifted horizontally by syntheticShift px
 * (uniform disparity, "far" if positive under our sign convention). */
function synthesizeRightEye() {
	var s = Math.round(params.syntheticShift), RI = retR.IN;
	for (var y = 0; y < H; y++) {
		for (var x = 0; x < W; x++) {
			var xx = x - s; if (xx < 0) xx = 0; else if (xx >= W) xx = W - 1;
			var k = y * W + xx;
			RI[y * W + x] = 0.5 * (ret.IN_R[k] + ret.IN_G[k]);
		}
	}
}

/* ---------- one tick ---------- */

function stepAll(retParams, ctxParams) {
	RETINA.step(ret, retParams);
	if (ctxParams.stereo && ctxParams.stereo !== 'none') {
		RETINA.stepLite(retR, retParams);
		ctx.LGN_DR.set(retR.D);
	}
	CORTEX.step(ctx, ctxParams);
}

function tick(rgba, right) {
	var t0 = performance.now();
	loadFrame(rgba, right);
	stepAll(
		{lightLevel: params.lightLevel, noise: params.noise, freezeAdaptation: false},
		{stereo: params.stereo, plasticity: params.plasticity, plasticityRate: params.plasticityRate}
	);
	tickCount++;
	var spikes = 0;
	for (var t = 0; t < RETINA.RGC_TYPES.length; t++) {
		var S = ret['RGC_' + RETINA.RGC_TYPES[t] + '_SPK'];
		for (var i = 0; i < N; i++) spikes += S[i];
	}
	var snap = mem.snapshot();
	self.postMessage({type: 'tick', snapshot: snap, tickMs: performance.now() - t0, tick: tickCount, spikes: spikes}, [snap]);
}

/* ---------- probes: tuning curves and receptive-field maps ----------
 * Each probe presents a family of synthetic stimuli with adaptation frozen
 * at the background, noise and plasticity off, and records one cell.
 */

var V1C = {x: RV.V1_W >> 1, y: RV.V1_H >> 1};
var V1CI = V1C.y * RV.V1_W + V1C.x;
var RC = {x: W >> 1, y: H >> 1};
var RCI = RC.y * W + RC.x;
var BG = 0.3;

function probeReset(background) {
	RETINA.resetDynamics(ret, background);
	CORTEX.resetDynamics(ctx);
	retR.ADAPT.fill(background);
	retR.PR.fill(CURVES.nakaRushton(background, Math.max(RV.PR.coneSigmaFloor, background), RV.PR.coneN));
}

function present(ticks, gen, record, stereo) {
	var rp = {lightLevel: 1.0, noise: 0, freezeAdaptation: true};
	var cp = {stereo: stereo || 'none', plasticity: false};
	for (var t = 0; t < ticks; t++) {
		gen(t);
		RETINA.setGreyInput(ret, field);
		if (stereo) retR.IN.set(fieldR);
		stepAll(rp, cp);
		if (record) record(t);
	}
}

function lin(a, b, n) { var o = []; for (var i = 0; i < n; i++) o.push(a + (b - a) * i / (n - 1)); return o; }
function logs(a, b, n) { var o = []; for (var i = 0; i < n; i++) o.push(a * Math.pow(b / a, i / (n - 1))); return o; }
function maxOf(arr) { var m = -Infinity; for (var i = 0; i < arr.length; i++) if (arr[i] > m) m = arr[i]; return m; }
function scaleTo(ref, target) { var m = maxOf(ref) || 1, t = maxOf(target) || 1; return ref.map(function (v) { return v / m * t; }); }

var PROBES = {};

/* Orientation tuning of the V1 complex cell (SF 0, pref 0 deg) and its
 * even simple cell (peak over grating phases). */
PROBES.orientation = function (spec, progress) {
	var xs = lin(0, 180, 37), yC = [], yS = [];
	var base = CORTEX.mapIndex(ctx, 0, 0);
	for (var i = 0; i < xs.length; i++) {
		probeReset(BG);
		var pc = 0, ps = 0;
		present(10, function (t) { STIM.grating(field, W, H, xs[i], RV.SF_LAMBDA[0], t * 45, 0.5, BG); },
			function (t) { if (t >= 6) { pc = Math.max(pc, ctx.CN[base + V1CI]); ps = Math.max(ps, ctx.E[base + V1CI]); } });
		yC.push(pc); yS.push(ps);
		progress(i + 1, xs.length);
	}
	var ref = xs.map(function (th) { return CURVES.vonMisesOrientation(th, 0, RV.V1.refHWHH); });
	return {title: 'V1 orientation tuning (pref 0 deg)', xlabel: 'grating orientation (deg)', ylabel: 'response',
		x: xs, series: [{name: 'complex cell', y: yC}, {name: 'simple cell (even)', y: yS},
		{name: 'reference: von Mises, HWHH ' + RV.V1.refHWHH + ' deg', y: scaleTo(ref, yC), ref: true}]};
};

/* Direction tuning: drifting grating at 16 directions, V1 direction cell
 * (orientation 0, motion toward +normal) and retinal DS cells. */
PROBES.direction = function (spec, progress) {
	var xs = lin(0, 360, 17), yV = [], yR = [];
	for (var i = 0; i < xs.length; i++) {
		probeReset(BG);
		var dirDeg = xs[i];
		/* bars perpendicular to motion; drifting means phase decreasing for +normal motion */
		var theta = (dirDeg - 90 + 360) % 180;
		var sign = ((dirDeg - 90 + 360) % 360) < 180 ? -1 : 1;
		var pv = 0, pr = 0;
		present(10, function (t) { STIM.grating(field, W, H, theta, RV.SF_LAMBDA[0], sign * t * 40, 0.5, BG); },
			function (t) {
				if (t >= 6) {
					pv = Math.max(pv, ctx.DIR[V1CI]);                     /* orientation 0, +normal */
					var s = 0; for (var k = 0; k < N; k++) s += ret.DS_0[k]; /* rightward DSGC population */
					pr = Math.max(pr, s / N);
				}
			});
		yV.push(pv); yR.push(pr);
		progress(i + 1, xs.length);
	}
	return {title: 'Direction tuning', xlabel: 'motion direction (deg, 90 = down)', ylabel: 'response',
		x: xs, series: [{name: 'V1 direction cell (pref 90 deg)', y: yV}, {name: 'retinal DSGC, rightward (pref 0 deg)', y: scaleTo(yR, yV)}]};
};

/* Contrast response function of the V1 complex cell. */
PROBES.contrast = function (spec, progress) {
	var xs = logs(0.01, 1, 15), y = [];
	var base = CORTEX.mapIndex(ctx, 0, 0);
	for (var i = 0; i < xs.length; i++) {
		probeReset(BG);
		var pk = 0;
		present(10, function (t) { STIM.grating(field, W, H, 0, RV.SF_LAMBDA[0], t * 45, xs[i], BG); },
			function (t) { if (t >= 6) pk = Math.max(pk, ctx.CN[base + V1CI]); });
		y.push(pk);
		progress(i + 1, xs.length);
	}
	var ref = xs.map(function (c) { return CURVES.contrastResponse(c, RV.V1.refC50, RV.V1.refN); });
	return {title: 'V1 contrast response', xlabel: 'contrast (log)', ylabel: 'response', xlog: true,
		x: xs, series: [{name: 'complex cell', y: y}, {name: 'reference: Naka-Rushton c50 ' + RV.V1.refC50 + ', n ' + RV.V1.refN, y: scaleTo(ref, y), ref: true}]};
};

/* Spatial-frequency tuning of both SF channels. */
PROBES.sf = function (spec, progress) {
	var xs = logs(2, 40, 17), y0 = [], y1 = [];
	var b0 = CORTEX.mapIndex(ctx, 0, 0), b1 = CORTEX.mapIndex(ctx, 1, 0);
	for (var i = 0; i < xs.length; i++) {
		probeReset(BG);
		var p0 = 0, p1 = 0;
		present(10, function (t) { STIM.grating(field, W, H, 0, xs[i], t * 45, 0.5, BG); },
			function (t) { if (t >= 6) { p0 = Math.max(p0, ctx.CN[b0 + V1CI]); p1 = Math.max(p1, ctx.CN[b1 + V1CI]); } });
		y0.push(p0); y1.push(p1);
		progress(i + 1, xs.length);
	}
	var r0 = xs.map(function (l) { return CURVES.logGaussianSF(l, RV.SF_LAMBDA[0], RV.V1.refSFBandwidthOct); });
	var r1 = xs.map(function (l) { return CURVES.logGaussianSF(l, RV.SF_LAMBDA[1], RV.V1.refSFBandwidthOct); });
	return {title: 'V1 spatial-frequency tuning', xlabel: 'grating wavelength (px, log)', ylabel: 'response', xlog: true,
		x: xs, series: [{name: 'lambda ' + RV.SF_LAMBDA[0] + ' px cell', y: y0}, {name: 'lambda ' + RV.SF_LAMBDA[1] + ' px cell', y: y1},
		{name: 'reference 1.5-octave log-Gaussian', y: scaleTo(r0, y0), ref: true}, {name: 'reference (2nd)', y: scaleTo(r1, y1), ref: true}]};
};

/* Photoreceptor intensity-response: cone flashed from dark and from a
 * photopic background; rod flashed from dark (measured off-fovea). */
PROBES.intensity = function (spec, progress) {
	var xs = logs(1e-5, 10, 25), yCd = [], yCb = [], yR = [];
	var rodI = RC.y * W + RC.x + 24;
	var bgs = [0, 0.3];
	for (var i = 0; i < xs.length; i++) {
		for (var b = 0; b < bgs.length; b++) {
			probeReset(bgs[b]);
			ret.PR_L.fill(0); ret.PR_M.fill(0); ret.PR_S.fill(0); ret.PR_ROD.fill(0);
			present(16, function () { STIM.uniform(field, W, H, xs[i]); });
			if (b === 0) { yCd.push(ret.PR_L[RCI]); yR.push(ret.PR_ROD[rodI]); } else { yCb.push(ret.PR_L[RCI]); }
		}
		progress(i + 1, xs.length);
	}
	var refCd = xs.map(function (I) { return CURVES.nakaRushton(I, RV.PR.coneSigmaFloor, RV.PR.coneN); });
	var refR = xs.map(function (I) { return CURVES.nakaRushton(I, RV.PR.rodSigma, RV.PR.rodN); });
	return {title: 'Photoreceptor intensity-response (Naka-Rushton)', xlabel: 'flash intensity (log)', ylabel: 'hyperpolarisation R', xlog: true,
		x: xs, series: [{name: 'L cone, dark adapted', y: yCd}, {name: 'L cone, adapted to 0.3', y: yCb}, {name: 'rod, dark adapted', y: yR},
		{name: 'ref cone: I/(I+' + RV.PR.coneSigmaFloor + ')', y: refCd, ref: true}, {name: 'ref rod: I/(I+' + RV.PR.rodSigma + ')', y: refR, ref: true}]};
};

/* Area summation of an ON-centre midget ganglion cell. */
PROBES.area = function (spec, progress) {
	var xs = lin(1, 25, 25), yOn = [], yOff = [];
	for (var i = 0; i < xs.length; i++) {
		probeReset(BG);
		present(6, function () { STIM.spot(field, W, H, RC.x, RC.y, xs[i], 0.9, BG); });
		yOn.push(ret.RGC_ON_M_I[RCI]);
		probeReset(BG);
		present(6, function () { STIM.spot(field, W, H, RC.x, RC.y, xs[i], 0.05, BG); });
		yOff.push(ret.RGC_OFF_M_I[RCI]);
		progress(i + 1, xs.length);
	}
	var m = RV.RGC.midget;
	var ref = xs.map(function (d) { return CURVES.dogAreaSummation(d, m.centerSigma + RV.OPL.horizontalSigma * 0.3, m.surroundSigma, m.surroundGain); });
	return {title: 'Ganglion-cell area summation (midget)', xlabel: 'spot diameter (px)', ylabel: 'drive',
		x: xs, series: [{name: 'ON-centre, bright spot', y: yOn}, {name: 'OFF-centre, dark spot', y: yOff}, {name: 'reference: DoG disk integral', y: scaleTo(ref, yOn), ref: true}]};
};

/* Receptive-field map by spot flashing: bright minus dark spot response at
 * each position, for an ON-midget ganglion cell and a V1 even simple cell. */
PROBES.rfmap = function (spec, progress) {
	var n = 13, r = (n - 1) >> 1, step = 1;
	var rgc = new Float32Array(n * n), v1 = new Float32Array(n * n);
	var base = CORTEX.mapIndex(ctx, 0, 0);
	var k = 0;
	for (var dy = -r; dy <= r; dy++) {
		for (var dx = -r; dx <= r; dx++) {
			var idx = (dy + r) * n + (dx + r);
			var lv = [0.9, 0.05], res = [[0, 0], [0, 0]];
			for (var pol = 0; pol < 2; pol++) {
				probeReset(BG);
				present(4, function () { STIM.spot(field, W, H, RC.x + dx * step, RC.y + dy * step, 2, lv[pol], BG); });
				res[pol][0] = ret.RGC_ON_M_I[RCI] - ret.RGC_OFF_M_I[RCI];
				res[pol][1] = ctx.E[base + V1CI];
			}
			rgc[idx] = res[0][0] - res[1][0];
			v1[idx] = res[0][1] - res[1][1];
			k++;
			if ((k & 7) === 0) progress(k, n * n);
		}
	}
	progress(n * n, n * n);
	return {title: 'Receptive fields by spot mapping (bright - dark)', n: n, step: step,
		maps: [{name: 'ON-centre midget ganglion cell', data: Array.from(rgc)}, {name: 'V1 even simple cell (pref 0 deg)', data: Array.from(v1)}]};
};

/* Disparity tuning with random-dot stereograms: right eye = left shifted by d. */
PROBES.disparity = function (spec, progress) {
	var xs = lin(-8, 8, 17);
	var cells = [-3, 0, 3], ys = cells.map(function () { return []; });
	var rng = CURVES.rng(99);
	var dots = new Float32Array(N);
	for (var i = 0; i < N; i++) dots[i] = rng() < 0.5 ? 0.05 : 0.9;
	for (var d = 0; d < xs.length; d++) {
		probeReset(BG);
		var shift = Math.round(xs[d]);
		var sums = [0, 0, 0], nRec = 0;
		present(36, function (t) {
			/* fresh dot pattern every tick: the tuning curve is an average over patterns */
			for (var i2 = 0; i2 < N; i2++) dots[i2] = rng() < 0.5 ? 0.05 : 0.9;
			field.set(dots);
			for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) {
				var xx = x - shift; if (xx < 0) xx = 0; else if (xx >= W) xx = W - 1;
				fieldR[y * W + x] = dots[y * W + xx];
			}
		}, function (t) {
			if (t >= 4) {
				nRec++;
				for (var c = 0; c < cells.length; c++) {
					var m = 0, di = cells[c] + RV.DISP_MAX;
					/* average over a central patch of identically tuned cells */
					for (var yy = -10; yy <= 10; yy++) for (var xx2 = -10; xx2 <= 10; xx2++) m += ctx.DISP[di * ctx.VN + (V1C.y + yy) * RV.V1_W + V1C.x + xx2];
					sums[c] += m / 441;
				}
			}
		}, 'synthetic');
		for (var c2 = 0; c2 < cells.length; c2++) ys[c2].push(sums[c2] / nRec);
		progress(d + 1, xs.length);
	}
	var series = cells.map(function (c, i2) { return {name: (c < 0 ? 'near' : c > 0 ? 'far' : 'tuned-zero') + ' cell (pref ' + c + ' px)', y: ys[i2]}; });
	var lam = RV.SF_LAMBDA[0];
	series.push({name: 'reference: Gabor in disparity (pref 0)', y: scaleTo(xs.map(function (x) { return CURVES.disparityGabor(x, 0, RV.GABOR_SIGMA_PER_LAMBDA * lam, lam); }), ys[1]), ref: true});
	return {title: 'Binocular disparity tuning (random-dot stereogram)', xlabel: 'disparity (px, right - left)', ylabel: 'binocular energy', x: xs, series: series};
};

function runProbe(spec) {
	if (probeRunning) return;
	probeRunning = true;
	probeAbort = false;
	var kind = spec.kind;
	var fn = PROBES[kind];
	if (!fn) { self.postMessage({type: 'error', message: 'unknown probe ' + kind}); probeRunning = false; return; }
	var savedW = new Float32Array(ctx.W1);   /* probes never learn */
	try {
		var result = fn(spec, function (done, total) {
			self.postMessage({type: 'probeProgress', kind: kind, done: done, total: total});
		});
		result.type = 'probeResult';
		result.kind = kind;
		self.postMessage(result);
	} catch (err) {
		self.postMessage({type: 'error', message: 'probe ' + kind + ' failed: ' + err.message});
	}
	ctx.W1.set(savedW);
	probeReset(BG);
	probeRunning = false;
}

/* ---------- message handler ---------- */

self.onmessage = function (e) {
	var d = e.data;
	try {
		switch (d.type) {
		case 'init':
			init();
			break;
		case 'frame':
			if (!mem || probeRunning) { self.postMessage({type: 'tick', snapshot: null, tickMs: 0, tick: tickCount, spikes: 0}); break; }
			tick(new Uint8Array(d.rgba), d.right ? new Uint8Array(d.right) : null);
			break;
		case 'setParams':
			for (var k in d.params) if (Object.prototype.hasOwnProperty.call(d.params, k)) params[k] = d.params[k];
			break;
		case 'resetWeights':
			if (d.mode === 'random') CORTEX.randomizeWeights(ctx, d.seed || (Date.now() & 0xffff));
			else CORTEX.buildGabors(ctx);
			break;
		case 'probe':
			/* run on a macrotask so the 'frame' backlog is not blocked by the switch */
			setTimeout(function () { runProbe(d); }, 0);
			break;
		case 'abortProbe':
			probeAbort = true;
			break;
		}
	} catch (err) {
		self.postMessage({type: 'error', message: err.message + '\n' + (err.stack || '')});
	}
};
