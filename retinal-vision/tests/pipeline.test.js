/* Node tests for the retina -> V1 -> V2 pipeline.  Run: npm test */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const js = (f) => require(path.join(__dirname, '..', 'js', f));
const RV = js('constants.js');
const LinearMemory = js('linear-memory.js');
const CURVES = js('response-curves.js');
const STIM = js('stimuli.js');
const RETINA = js('retina.js');
const CORTEX = js('cortex.js');

const W = RV.GRID_W, H = RV.GRID_H, N = W * H;
const BG = 0.3;

function build() {
	const mem = new LinearMemory(RV.MEMORY_BYTES);
	const ret = RETINA.create(mem, RV);
	const retR = RETINA.createLite(mem, RV, 'RETR');
	const ctx = CORTEX.create(mem, RV, ret);
	ctx.right = retR;
	const field = new Float32Array(N);
	const fieldR = new Float32Array(N);
	const cxV = RV.V1_W >> 1, cyV = RV.V1_H >> 1;
	const s = {
		mem, ret, retR, ctx, field, fieldR,
		ci: cyV * RV.V1_W + cxV, cxV, cyV,
		cxR: W >> 1, cyR: H >> 1, ri: (H >> 1) * W + (W >> 1),
		reset(bg = BG) { RETINA.resetDynamics(ret, bg); CORTEX.resetDynamics(ctx); retR.ADAPT.fill(bg); },
		run(ticks, gen, record, opts = {}) {
			const rp = {lightLevel: 1, noise: 0, freezeAdaptation: !!opts.freeze};
			const cp = {stereo: opts.stereo || 'none', plasticity: !!opts.plasticity, plasticityRate: opts.rate, rng: opts.rng};
			for (let t = 0; t < ticks; t++) {
				gen(t);
				RETINA.setGreyInput(ret, field);
				if (opts.stereo) { retR.IN.set(fieldR); }
				RETINA.step(ret, rp);
				if (opts.stereo) { RETINA.stepLite(retR, rp); ctx.LGN_DR.set(retR.D); }
				CORTEX.step(ctx, cp);
				if (record) record(t);
			}
		}
	};
	return s;
}

/* ---------- linear memory ---------- */

test('linear memory: bump allocation, alignment, map and snapshot views', () => {
	const mem = new LinearMemory(1 << 20);
	const a = mem.alloc('A', 'f32', 10);
	const b = mem.alloc('B', 'u8', 3);
	const c = mem.alloc('C', 'f32', 4);
	assert.equal(mem.byName.A.offset, 0);
	assert.equal(mem.byName.B.offset % 64, 0);
	assert.equal(mem.byName.C.offset % 64, 0);
	assert.ok(mem.byName.C.offset > mem.byName.B.offset);
	a[3] = 1.5; b[1] = 7; c[0] = -2;
	const snap = mem.snapshot();
	const map = mem.map();
	assert.equal(LinearMemory.viewIn(snap, map[0])[3], 1.5);
	assert.equal(LinearMemory.viewIn(snap, map[1])[1], 7);
	assert.equal(LinearMemory.viewIn(snap, map[2])[0], -2);
	assert.throws(() => mem.alloc('A', 'f32', 1), /duplicate/);
	assert.throws(() => mem.alloc('huge', 'f32', 1 << 24), /out of memory/);
	assert.match(mem.dump(), /0x00000000/);
	if (typeof WebAssembly !== 'undefined') assert.ok(mem.wasm instanceof WebAssembly.Memory);
});

test('the whole model fits in one linear memory and every region is named', () => {
	const s = build();
	const names = s.mem.map().map((r) => r.name);
	for (const n of ['RET.PR_L', 'RET.PR_ROD', 'RET.BP_ON', 'RET.RGC_ON_M_SPK', 'RET.DS_0', 'LGN.D', 'V1.PERCEPTRON_W', 'V1.COMPLEX_NORM', 'V1.DIRECTION', 'V1.DISPARITY', 'V2.CORNER', 'V2.BORDER_OWNERSHIP']) {
		assert.ok(names.includes(n), n);
	}
	assert.ok(s.mem.brk < RV.MEMORY_BYTES);
});

/* ---------- response curves ---------- */

test('Naka-Rushton: half response at sigma, saturates, monotone', () => {
	assert.ok(Math.abs(CURVES.nakaRushton(0.1, 0.1, 1) - 0.5) < 1e-9);
	assert.ok(CURVES.nakaRushton(100, 0.1, 1) > 0.99);
	let prev = 0;
	for (let I = 1e-4; I < 10; I *= 2) { const r = CURVES.nakaRushton(I, 0.05, 0.8); assert.ok(r > prev); prev = r; }
});

test('Gabor templates are zero-mean, unit-norm and orientation selective', () => {
	const K = RV.V1_K;
	const w0 = CURVES.gaborKernel(K, 0, 5, 2, 0, 0.8);
	let mean = 0, norm = 0;
	for (const v of w0) { mean += v; norm += v * v; }
	assert.ok(Math.abs(mean) < 1e-6);
	assert.ok(Math.abs(norm - 1) < 1e-5);
	/* horizontal-bar template vs horizontal and vertical gratings */
	const patch = new Float32Array(K * K);
	const dot = (theta) => {
		const r = (K - 1) / 2, a = (theta + 90) * Math.PI / 180;
		let s = 0;
		for (let y = 0; y < K; y++) for (let x = 0; x < K; x++) {
			const p = ((x - r) * Math.cos(a) + (y - r) * Math.sin(a)) / 5;
			patch[y * K + x] = Math.cos(2 * Math.PI * p);
			s += w0[y * K + x] * patch[y * K + x];
		}
		return s;
	};
	assert.ok(dot(0) > 5 * Math.abs(dot(90)));
});

test('LIF analytic rate is zero below threshold and increases with drive', () => {
	const g = RV.RGC;
	assert.equal(CURVES.lifRate(0.01, g.lifLeak, g.lifGain, g.lifThreshold, g.lifRefractory), 0);
	const r1 = CURVES.lifRate(0.2, g.lifLeak, g.lifGain, g.lifThreshold, g.lifRefractory);
	const r2 = CURVES.lifRate(0.5, g.lifLeak, g.lifGain, g.lifThreshold, g.lifRefractory);
	assert.ok(r1 > 0 && r2 > r1 && r2 <= 1);
});

/* ---------- retina ---------- */

test('photoreceptors hyperpolarise to light; rods saturate, cones adapt', () => {
	const s = build();
	const rodI = s.ri + 24;   /* off the rod-free foveola */
	assert.equal(s.ret.ECC_ROD[s.ri], 0);
	assert.ok(s.ret.ECC_ROD[rodI] > 0.9);
	const rod = [], cone = [];
	for (const I of [1e-4, 1e-2, 1, 10]) {
		s.reset(0); s.ret.PR_L.fill(0); s.ret.PR_ROD.fill(0);
		s.run(16, () => STIM.uniform(s.field, W, H, I), null, {freeze: true});
		rod.push(s.ret.PR_ROD[rodI]); cone.push(s.ret.PR_L[s.ri]);
	}
	assert.ok(rod[0] < 0.05 && rod[1] > 0.5 && rod[2] > 0.95 && rod[3] > 0.95, 'rods saturate ' + rod);
	assert.ok(cone[0] < cone[1] && cone[1] < cone[2] && cone[2] < cone[3], 'cones monotone ' + cone);
	/* Weber adaptation: same flash, brighter background -> smaller response */
	s.reset(0); s.run(8, () => STIM.uniform(s.field, W, H, 0.3), null, {freeze: true});
	const fromDark = s.ret.PR_L[s.ri];
	s.reset(1.0); s.run(8, () => STIM.uniform(s.field, W, H, 0.3), null, {freeze: true});
	assert.ok(s.ret.PR_L[s.ri] < fromDark);
});

test('rods carry the signal in dim light, cones in bright light', () => {
	const s = build();
	const contrastAt = (L) => {
		s.reset(BG * L);
		let m = 0;
		s.run(10, (t) => STIM.grating(s.field, W, H, 0, 8, t * 30, 0.6, BG * L), (t) => { if (t > 5) for (let i = 0; i < N; i++) m = Math.max(m, s.ret.BP_ON[i]); });
		return m;
	};
	assert.ok(contrastAt(1.0) > 0.05, 'photopic signal');
	assert.ok(contrastAt(1e-2) > 0.02, 'mesopic/scotopic signal through rods');
});

test('ON/OFF polarity: bright spot drives ON-centre cells, dark spot drives OFF-centre', () => {
	const s = build();
	s.reset();
	s.run(6, () => STIM.spot(s.field, W, H, s.cxR, s.cyR, 3, 0.9, BG));
	assert.ok(s.ret.RGC_ON_M_I[s.ri] > 0.1 && s.ret.RGC_OFF_M_I[s.ri] === 0);
	assert.ok(s.ret.RGC_ON_M_FR[s.ri] > 0);
	assert.ok(s.ctx.LGN_D[s.ri] > 0);
	s.run(6, () => STIM.spot(s.field, W, H, s.cxR, s.cyR, 3, 0.05, BG));
	assert.ok(s.ret.RGC_OFF_M_I[s.ri] > 0.1 && s.ret.RGC_ON_M_I[s.ri] === 0);
	assert.ok(s.ctx.LGN_D[s.ri] < 0);
});

test('ganglion cells spike (LIF) and area summation shows a surround', () => {
	const s = build();
	let spikes = 0;
	s.reset();
	s.run(8, () => STIM.spot(s.field, W, H, s.cxR, s.cyR, 4, 0.9, BG), () => { spikes += s.ret.RGC_ON_M_SPK[s.ri]; });
	assert.ok(spikes >= 2, 'spikes ' + spikes);
	const drive = (d) => { s.reset(); s.run(6, () => STIM.spot(s.field, W, H, s.cxR, s.cyR, d, 0.9, BG)); return s.ret.RGC_ON_M_I[s.ri]; };
	const curve = [1, 2, 3, 4, 6, 10, 24].map(drive);
	const peak = Math.max(...curve), peakAt = [1, 2, 3, 4, 6, 10, 24][curve.indexOf(peak)];
	/* rises to a small optimal spot (the centre), then the surround cancels it */
	assert.ok(curve[0] < peak && peakAt >= 2 && peakAt <= 6, `area summation ${curve}`);
	assert.ok(curve[curve.length - 1] < 0.1 * peak, `large spot suppressed ${curve}`);
});

test('retinal direction-selective cells prefer one direction', () => {
	const s = build();
	const index = (dir) => {
		s.reset();
		let r = 0, l = 0;
		s.run(14, (t) => STIM.bar(s.field, W, H, s.cxR - 14 * dir + 2 * dir * t, s.cyR, 90, 30, 3, 0.9, BG), (t) => { if (t > 2) for (let i = 0; i < N; i++) { r += s.ret.DS_0[i]; l += s.ret.DS_2[i]; } });
		return (r - l) / (r + l + 1e-9);
	};
	assert.ok(index(1) > 0.6);
	assert.ok(index(-1) < -0.6);
});

/* ---------- V1 ---------- */

function orientationCurve(s, sf = 0, cell = 'CN') {
	const base = CORTEX.mapIndex(s.ctx, sf, 0);
	const out = [];
	for (let th = 0; th < 180; th += 15) {
		s.reset();
		let pk = 0;
		s.run(10, (t) => STIM.grating(s.field, W, H, th, RV.SF_LAMBDA[sf], t * 45, 0.5, BG), (t) => { if (t >= 6) pk = Math.max(pk, s.ctx[cell][base + s.ci]); });
		out.push(pk);
	}
	return out;
}

test('V1 complex cell orientation tuning: peaked at its Gabor orientation, HWHH within 10-35 deg', () => {
	const s = build();
	const y = orientationCurve(s);
	const peak = y[0];
	assert.ok(peak > 0.2, 'peak ' + peak);
	assert.ok(y[6] < 0.05 * peak, 'orthogonal ' + y[6]);
	/* half-width: first sample below half, 15 deg steps */
	let hw = 0;
	for (let i = 1; i < y.length / 2; i++) { if (y[i] < peak / 2) { hw = i * 15; break; } }
	assert.ok(hw >= 15 && hw <= 45, 'hwhh bucket ' + hw);
});

test('V1 simple cells have polarity: even cell prefers a bright bar over a dark bar', () => {
	const s = build();
	const base = CORTEX.mapIndex(s.ctx, 0, 0);
	s.reset(); s.run(6, () => STIM.bar(s.field, W, H, s.cxR, s.cyR, 0, 40, 3, 0.9, BG));
	const bright = s.ctx.E[base + s.ci];
	s.reset(); s.run(6, () => STIM.bar(s.field, W, H, s.cxR, s.cyR, 0, 40, 3, 0.05, BG));
	const dark = s.ctx.E[base + s.ci];
	assert.ok(bright > 0.1 && dark < -0.1, `bright ${bright} dark ${dark}`);
});

test('V1 complex cells are phase invariant, simple cells are not', () => {
	const s = build();
	const base = CORTEX.mapIndex(s.ctx, 0, 0);
	const c = [], e = [];
	for (const ph of [0, 90, 180, 270]) {
		s.reset();
		s.run(6, () => STIM.grating(s.field, W, H, 0, RV.SF_LAMBDA[0], ph, 0.5, BG));
		c.push(s.ctx.C[base + s.ci]); e.push(s.ctx.E[base + s.ci]);
	}
	const cvar = (Math.max(...c) - Math.min(...c)) / Math.max(...c);
	const evar = (Math.max(...e) - Math.min(...e)) / Math.max(...e.map(Math.abs));
	assert.ok(cvar < 0.35, 'complex modulation ' + cvar);
	assert.ok(evar > 1.0, 'simple modulation ' + evar);
});

test('V1 contrast response rises with contrast and saturates (Naka-Rushton-like)', () => {
	const s = build();
	const base = CORTEX.mapIndex(s.ctx, 0, 0);
	const y = [];
	for (const c of [0.02, 0.1, 0.3, 1.0]) {
		s.reset();
		let pk = 0;
		s.run(10, (t) => STIM.grating(s.field, W, H, 0, RV.SF_LAMBDA[0], t * 45, c, BG), (t) => { if (t >= 6) pk = Math.max(pk, s.ctx.CN[base + s.ci]); });
		y.push(pk);
	}
	assert.ok(y[0] < y[1] && y[1] < y[2] && y[2] <= y[3] * 1.05, 'monotone ' + y);
	assert.ok(y[0] < 0.4 * y[3], 'low contrast is low ' + y);
	assert.ok(y[2] > 0.6 * y[3], 'saturating ' + y);
});

test('V1 direction cells: sign of the temporal quadrature follows drift direction', () => {
	const s = build();
	const VN = s.ctx.VN;
	for (const sign of [-1, 1]) {
		s.reset();
		s.run(8, (t) => STIM.grating(s.field, W, H, 0, RV.SF_LAMBDA[0], sign * t * 40, 0.5, BG));
		const plus = s.ctx.DIR[s.ci], minus = s.ctx.DIR[VN + s.ci];
		if (sign < 0) assert.ok(plus > 0.1 && minus < 0.02 * plus, `+normal ${plus} ${minus}`);
		else assert.ok(minus > 0.1 && plus < 0.02 * minus, `-normal ${plus} ${minus}`);
	}
});

test('V1 disparity energy peaks at the stimulus disparity (random-dot stereogram)', () => {
	const s = build();
	const rng = CURVES.rng(11);
	const dots = new Float32Array(N);
	const measure = (shift) => {
		s.reset();
		const acc = new Float32Array(RV.N_DISP);
		s.run(8, (t) => {
			if (t % 2 === 0) for (let i = 0; i < N; i++) dots[i] = rng() < 0.5 ? 0.05 : 0.9;
			s.field.set(dots);
			for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
				let xx = x - shift; if (xx < 0) xx = 0; else if (xx >= W) xx = W - 1;
				s.fieldR[y * W + x] = dots[y * W + xx];
			}
		}, (t) => {
			if (t >= 3) for (let d = 0; d < RV.N_DISP; d++) {
				for (let yy = -3; yy <= 3; yy++) for (let xx = -3; xx <= 3; xx++) acc[d] += s.ctx.DISP[d * s.ctx.VN + (s.cyV + yy) * RV.V1_W + s.cxV + xx];
			}
		}, {stereo: 'synthetic'});
		let best = 0;
		for (let d = 1; d < RV.N_DISP; d++) if (acc[d] > acc[best]) best = d;
		return best - RV.DISP_MAX;
	};
	assert.equal(measure(0), 0);
	assert.ok(Math.abs(measure(3) - 3) <= 1);
	assert.ok(Math.abs(measure(-3) + 3) <= 1);
});

/* ---------- V2 ---------- */

test('V2 corner cells respond at an L-junction, not along a bar', () => {
	const s = build();
	s.reset();
	const tmp = new Float32Array(N);
	s.run(6, () => {
		STIM.bar(s.field, W, H, s.cxR + 10, s.cyR, 0, 20, 3, 0.9, BG);
		STIM.bar(tmp, W, H, s.cxR, s.cyR + 10, 90, 20, 3, 0.9, BG);
		for (let i = 0; i < N; i++) s.field[i] = Math.max(s.field[i], tmp[i]);
	});
	const vertex = s.ctx.V2_CORNER[s.ci], mid = s.ctx.V2_CORNER[s.ci + 5];
	assert.ok(vertex > 5 * mid && vertex > 0.05, `vertex ${vertex} mid ${mid}`);
});

test('V2 end-stopped cells fire at bar ends but not along the bar', () => {
	const s = build();
	s.reset();
	s.run(6, () => STIM.bar(s.field, W, H, s.cxR, s.cyR, 0, 40, 3, 0.9, BG));
	const middle = s.ctx.V2_END[s.ci], end = s.ctx.V2_END[s.ci + 8];
	assert.ok(end > 0.1 && middle < 0.2 * end, `end ${end} middle ${middle}`);
});

test('V2 border ownership assigns an edge to the side with the figure', () => {
	const s = build();
	s.reset();
	s.run(6, () => { for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) s.field[y * W + x] = (x >= s.cxR && x < s.cxR + 16 && y > s.cyR - 8 && y < s.cyR + 8) ? 0.9 : BG; });
	const vo = RV.N_ORI / 2, VN = s.ctx.VN;
	/* orientation 90: + side is -x.  Left edge: figure on +x => '-' cell.  Right edge: figure on -x => '+' cell. */
	const leftPlus = s.ctx.V2_BO[(vo * 2) * VN + s.ci], leftMinus = s.ctx.V2_BO[(vo * 2 + 1) * VN + s.ci];
	const rightPlus = s.ctx.V2_BO[(vo * 2) * VN + s.ci + 8], rightMinus = s.ctx.V2_BO[(vo * 2 + 1) * VN + s.ci + 8];
	assert.ok(leftMinus > 0.05 && leftPlus === 0, `left ${leftPlus} ${leftMinus}`);
	assert.ok(rightPlus > 0.05 && rightMinus === 0, `right ${rightPlus} ${rightMinus}`);
});

test('V2 texture cells prefer noise texture over a single bar', () => {
	const s = build();
	const rng = CURVES.rng(5);
	s.reset(); s.run(6, () => STIM.bar(s.field, W, H, s.cxR, s.cyR, 0, 40, 3, 0.9, BG));
	const bar = s.ctx.V2_TEX[s.ci];
	s.reset(); s.run(6, () => { for (let i = 0; i < N; i++) s.field[i] = BG + 0.5 * (rng() - 0.5); });
	assert.ok(s.ctx.V2_TEX[s.ci] > 1.5 * bar);
});

/* ---------- plasticity ---------- */

test('Hebbian (GHA) learning keeps templates unit-norm and moves them toward the input statistics', () => {
	const s = build();
	CORTEX.randomizeWeights(s.ctx, 7);
	const KK = RV.V1_K * RV.V1_K;
	const before = Float32Array.from(s.ctx.W1.subarray(0, KK));
	const rng = CURVES.rng(3);
	s.reset();
	/* only horizontal gratings: the first component should become horizontal */
	s.run(60, (t) => STIM.grating(s.field, W, H, 0, 6, t * 30, 0.6, BG), null, {plasticity: true, rate: 0.02, rng});
	const after = s.ctx.W1.subarray(0, KK);
	let norm = 0, changed = 0;
	for (let i = 0; i < KK; i++) { norm += after[i] * after[i]; changed += Math.abs(after[i] - before[i]); }
	assert.ok(Math.abs(Math.sqrt(norm) - 1) < 1e-3);
	assert.ok(changed > 0.5);
	/* response of the learned template to a horizontal vs vertical grating patch */
	const patchResp = (theta) => {
		const K = RV.V1_K, r = (K - 1) / 2, a = (theta + 90) * Math.PI / 180;
		let best = 0;
		for (let ph = 0; ph < 360; ph += 30) {
			let sum = 0;
			for (let y = 0; y < K; y++) for (let x = 0; x < K; x++) {
				const p = ((x - r) * Math.cos(a) + (y - r) * Math.sin(a)) / 6;
				sum += after[y * K + x] * Math.cos(2 * Math.PI * p + ph * Math.PI / 180);
			}
			best = Math.max(best, Math.abs(sum));
		}
		return best;
	};
	assert.ok(patchResp(0) > 2 * patchResp(90), `learned horizontal ${patchResp(0)} vs vertical ${patchResp(90)}`);
	/* Gabor reset restores the reference templates */
	CORTEX.buildGabors(s.ctx);
	assert.equal(s.ctx.W1[0], s.ctx.W1_GABOR[0]);
});
