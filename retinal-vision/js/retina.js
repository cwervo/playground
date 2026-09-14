/* retina.js -- light -> photoreceptors -> horizontal -> bipolar -> ganglion.
 *
 * Stage by stage (one camera frame per tick):
 *
 *   IN_R/G/B      linear reflectance from the camera, x light level
 *   I_L/M/S/ROD   per-receptor-class intensity (spectral weighting)
 *   PR_L/M/S/ROD  photoreceptor hyperpolarisation R (Naka-Rushton, adapting)
 *                 - cones: Weber adaptation, never saturate under steady light
 *                 - rods:  fixed half-saturation, saturate in bright light,
 *                          absent in the foveola, slow
 *   G_LUM         glutamate release (1 - R), rods mixed in mesopically
 *   HC            horizontal cells: blurred copy of G_LUM (surround)
 *   BP_ON/OFF     bipolar cells: sign-inverting (mGluR6) / sign-conserving,
 *                 rectified; *_T are the transient (amacrine high-passed) copies
 *   RG / BY       cone-opponent signals (L-M, S-(L+M))
 *   RGC_*         ganglion cells: DoG pooling -> leaky integrate-and-fire
 *                 midget (parvo, sustained) / parasol (magno, transient), ON/OFF
 *   DS_0..3       ON-OFF direction-selective ganglion cells (Barlow-Levick
 *                 null-direction inhibition from the transient channel)
 *
 * Every region lives in the shared LinearMemory; this file never allocates
 * per tick.
 */

(function (root) {
	'use strict';

	var RV = root.RV || (typeof require === 'function' ? require('./constants.js') : null);
	var CURVES = root.CURVES || (typeof require === 'function' ? require('./response-curves.js') : null);

	var RETINA = {};

	RETINA.RGC_TYPES = ['ON_M', 'OFF_M', 'ON_P', 'OFF_P'];
	RETINA.DS_DIRS = [[1, 0], [0, 1], [-1, 0], [0, -1]];   /* right, down, left, up */

	/* ---------- separable Gaussian blur with clamped edges ---------- */
	RETINA.blur = function (src, dst, W, H, sigma, scratch) {
		var g = CURVES.gaussian1D(sigma);
		var k = g.kernel, r = g.radius;
		var x, y, i, s, xx, yy;
		/* horizontal pass -> scratch */
		for (y = 0; y < H; y++) {
			var row = y * W;
			for (x = 0; x < W; x++) {
				s = 0;
				for (i = -r; i <= r; i++) {
					xx = x + i;
					if (xx < 0) xx = 0; else if (xx >= W) xx = W - 1;
					s += k[i + r] * src[row + xx];
				}
				scratch[row + x] = s;
			}
		}
		/* vertical pass -> dst */
		for (y = 0; y < H; y++) {
			for (x = 0; x < W; x++) {
				s = 0;
				for (i = -r; i <= r; i++) {
					yy = y + i;
					if (yy < 0) yy = 0; else if (yy >= H) yy = H - 1;
					s += k[i + r] * scratch[yy * W + x];
				}
				dst[y * W + x] = s;
			}
		}
	};

	/* ---------- allocation ---------- */

	RETINA.create = function (mem, cfg) {
		cfg = cfg || RV;
		var W = cfg.GRID_W, H = cfg.GRID_H, N = W * H;
		var st = {W: W, H: H, N: N, cfg: cfg, tick: 0};
		var A = function (name) { st[name] = mem.alloc('RET.' + name, 'f32', N); };
		var U = function (name) { st[name] = mem.alloc('RET.' + name, 'u8', N); };

		['IN_R', 'IN_G', 'IN_B',
		 'I_L', 'I_M', 'I_S', 'I_ROD',
		 'ADAPT_C', 'ADAPT_ROD',
		 'PR_L', 'PR_M', 'PR_S', 'PR_ROD',
		 'ECC_ROD', 'ECC_CONE',
		 'G_LUM', 'HC',
		 'BP_ON', 'BP_OFF', 'BP_ON_SLOW', 'BP_OFF_SLOW', 'BP_ON_T', 'BP_OFF_T', 'BP_T', 'BP_T_PREV',
		 'RG', 'BY'].forEach(A);

		RETINA.RGC_TYPES.forEach(function (t) {
			A('RGC_' + t + '_I');       /* synaptic drive (DoG of bipolar input) */
			A('RGC_' + t + '_V');       /* membrane potential */
			U('RGC_' + t + '_SPK');     /* fired this tick */
			U('RGC_' + t + '_REF');     /* refractory counter */
			A('RGC_' + t + '_RATE');    /* filtered spike rate (display) */
			A('RGC_' + t + '_FR');      /* analytic LIF rate f(I) handed to the LGN */
		});
		for (var d = 0; d < 4; d++) A('DS_' + d);
		['SCR_A', 'SCR_B', 'SCR_C'].forEach(A);

		RETINA.initEccentricity(st);
		RETINA.resetDynamics(st, 0.3);
		return st;
	};

	/* Rod-free foveola, rods ramping up with eccentricity; cone density
	 * falling off toward the periphery (Curcio et al. 1990). */
	RETINA.initEccentricity = function (st) {
		var p = st.cfg.PR, W = st.W, H = st.H;
		var cx = (W - 1) / 2, cy = (H - 1) / 2;
		var rmax = Math.sqrt(cx * cx + cy * cy);
		for (var y = 0; y < H; y++) {
			for (var x = 0; x < W; x++) {
				var r = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
				var rod = (r - p.foveaRodFreeRadius) / (p.foveaRodRampRadius - p.foveaRodFreeRadius);
				st.ECC_ROD[y * W + x] = CURVES.clamp01(rod);
				st.ECC_CONE[y * W + x] = 1 - (1 - p.coneEdgeDensity) * (r / rmax);
			}
		}
	};

	/* Zero all temporal state; set adaptation to `background`. */
	RETINA.resetDynamics = function (st, background) {
		var p = st.cfg.PR;
		var bg = background === undefined ? 0.3 : background;
		st.ADAPT_C.fill(Math.max(p.coneSigmaFloor, bg));
		st.ADAPT_ROD.fill(bg);
		var r = CURVES.nakaRushton(bg, Math.max(p.coneSigmaFloor, bg), p.coneN);
		st.PR_L.fill(r); st.PR_M.fill(r); st.PR_S.fill(r);
		st.PR_ROD.fill(CURVES.nakaRushton(bg, p.rodSigma, p.rodN));
		['BP_ON_SLOW', 'BP_OFF_SLOW', 'BP_T_PREV', 'DS_0', 'DS_1', 'DS_2', 'DS_3'].forEach(function (n) { st[n].fill(0); });
		RETINA.RGC_TYPES.forEach(function (t) {
			st['RGC_' + t + '_V'].fill(0);
			st['RGC_' + t + '_SPK'].fill(0);
			st['RGC_' + t + '_REF'].fill(0);
			st['RGC_' + t + '_RATE'].fill(0);
			st['RGC_' + t + '_FR'].fill(0);
		});
	};

	/* Write a grey stimulus (linear 0..1) into all three input channels. */
	RETINA.setGreyInput = function (st, field) {
		st.IN_R.set(field); st.IN_G.set(field); st.IN_B.set(field);
	};

	/* ---------- one tick ----------
	 * params: {lightLevel, noise, freezeAdaptation, rng}
	 */
	RETINA.step = function (st, params) {
		var cfg = st.cfg, p = cfg.PR, opl = cfg.OPL, gc = cfg.RGC;
		var W = st.W, H = st.H, N = st.N, i;
		var L = params.lightLevel === undefined ? 1 : params.lightLevel;
		var noise = params.noise || 0;
		var rng = params.rng || Math.random;
		var M = cfg.RGB_TO_LMS, MR = cfg.RGB_TO_ROD;

		/* 1. spectral weighting -> per-class intensity */
		var IR = st.IN_R, IG = st.IN_G, IB = st.IN_B;
		var IL = st.I_L, IM = st.I_M, IS = st.I_S, IRod = st.I_ROD;
		for (i = 0; i < N; i++) {
			var r = IR[i] * L, g = IG[i] * L, b = IB[i] * L;
			IL[i] = M[0] * r + M[1] * g + M[2] * b;
			IM[i] = M[3] * r + M[4] * g + M[5] * b;
			IS[i] = M[6] * r + M[7] * g + M[8] * b;
			IRod[i] = MR[0] * r + MR[1] * g + MR[2] * b;
		}

		/* 2. adaptation: sigma tracks the locally pooled mean intensity */
		if (!params.freezeAdaptation) {
			var scr = st.SCR_A;
			for (i = 0; i < N; i++) scr[i] = 0.5 * (IL[i] + IM[i]);
			RETINA.blur(scr, st.SCR_B, W, H, p.coneAdaptBlur, st.SCR_C);
			var AC = st.ADAPT_C, ar = p.coneAdaptRate;
			for (i = 0; i < N; i++) AC[i] += ar * (st.SCR_B[i] - AC[i]);
			RETINA.blur(IRod, st.SCR_B, W, H, p.coneAdaptBlur, st.SCR_C);
			var AR = st.ADAPT_ROD, rr = p.rodTemporal * 0.5;
			for (i = 0; i < N; i++) AR[i] += rr * (st.SCR_B[i] - AR[i]);
		}

		/* 3. Naka-Rushton hyperpolarisation + temporal integration */
		var PL = st.PR_L, PM = st.PR_M, PS = st.PR_S, PRod = st.PR_ROD;
		var floor = p.coneSigmaFloor, nC = p.coneN, tC = p.coneTemporal;
		var sR = p.rodSigma, nR = p.rodN, tR = p.rodTemporal;
		for (i = 0; i < N; i++) {
			var sig = st.ADAPT_C[i]; if (sig < floor) sig = floor;
			var nz = noise ? noise * (rng() - 0.5) : 0;
			PL[i] += tC * (CURVES.nakaRushton(IL[i], sig, nC) + nz - PL[i]);
			PM[i] += tC * (CURVES.nakaRushton(IM[i], sig, nC) + nz - PM[i]);
			PS[i] += tC * (CURVES.nakaRushton(IS[i], sig, nC) + nz - PS[i]);
			var nzr = noise ? 2 * noise * (rng() - 0.5) : 0;   /* rods are noisier */
			PRod[i] += tR * (CURVES.nakaRushton(IRod[i], sR, nR) + nzr - PRod[i]);
		}

		/* 4. glutamate release with mesopic rod/cone mixing (rod signals reach
		 *    cone bipolars through the AII amacrine pathway) */
		var GL = st.G_LUM, mixS = p.rodMixSigma;
		var dens = st.SCR_A;   /* effective receptor density gain per pixel */
		for (i = 0; i < N; i++) {
			var m = st.ECC_ROD[i] * mixS / (mixS + st.ADAPT_ROD[i]);
			var gCone = 1 - 0.5 * (PL[i] + PM[i]);
			var gRod = 1 - PRod[i];
			GL[i] = (1 - m) * gCone + m * gRod;
			dens[i] = m + (1 - m) * st.ECC_CONE[i];
		}

		/* 5. horizontal cells */
		RETINA.blur(GL, st.HC, W, H, opl.horizontalSigma, st.SCR_C);

		/* 6. bipolar cells, ON sign-inverting / OFF sign-conserving, rectified */
		var BON = st.BP_ON, BOFF = st.BP_OFF, HC = st.HC;
		var bg = opl.bipolarGain, hg = opl.horizontalGain;
		for (i = 0; i < N; i++) {
			var c = (hg * HC[i] - GL[i]) * bg * dens[i];     /* > 0 when centre brighter */
			BON[i] = c > 0 ? c : 0;
			BOFF[i] = c < 0 ? -c : 0;
		}

		/* 7. transient channel (amacrine feedback == subtract a low-passed copy) */
		var tr = opl.transientRate;
		var BONS = st.BP_ON_SLOW, BOFFS = st.BP_OFF_SLOW, BONT = st.BP_ON_T, BOFFT = st.BP_OFF_T, BT = st.BP_T;
		for (i = 0; i < N; i++) {
			var a = BON[i] - BONS[i]; BONT[i] = a > 0 ? a : 0; BONS[i] += tr * (BON[i] - BONS[i]);
			var o = BOFF[i] - BOFFS[i]; BOFFT[i] = o > 0 ? o : 0; BOFFS[i] += tr * (BOFF[i] - BOFFS[i]);
			BT[i] = BONT[i] + BOFFT[i];
		}

		/* 8. cone-opponent channels */
		for (i = 0; i < N; i++) st.SCR_A[i] = PL[i] - PM[i];
		RETINA.blur(st.SCR_A, st.RG, W, H, opl.colorBlur, st.SCR_C);
		for (i = 0; i < N; i++) st.SCR_A[i] = PS[i] - 0.5 * (PL[i] + PM[i]);
		RETINA.blur(st.SCR_A, st.BY, W, H, opl.colorBlur, st.SCR_C);

		/* 9. ganglion cells: DoG pooling -> LIF */
		RETINA.ganglion(st, 'ON_M', BON, gc.midget, params);
		RETINA.ganglion(st, 'OFF_M', BOFF, gc.midget, params);
		RETINA.ganglion(st, 'ON_P', BONT, gc.parasol, params);
		RETINA.ganglion(st, 'OFF_P', BOFFT, gc.parasol, params);

		/* 10. direction-selective ganglion cells (Barlow-Levick):
		 *     excitation now, minus delayed inhibition from the null side */
		var nS = gc.dsNullShifts, ng = gc.dsNullGain, TP = st.BP_T_PREV;
		for (var d = 0; d < 4; d++) {
			var ddx = RETINA.DS_DIRS[d][0], ddy = RETINA.DS_DIRS[d][1];
			var DS = st['DS_' + d];
			for (var y = 0; y < H; y++) {
				for (var x = 0; x < W; x++) {
					/* strongest delayed signal from the null side, 1..nS px away */
					var inh = 0;
					for (var s = 1; s <= nS; s++) {
						var xx = x + ddx * s, yy = y + ddy * s;
						if (xx < 0 || xx >= W || yy < 0 || yy >= H) break;
						var t = TP[yy * W + xx];
						if (t > inh) inh = t;
					}
					var v = BT[y * W + x] - ng * inh;
					DS[y * W + x] = v > 0 ? v : 0;
				}
			}
		}
		TP.set(BT);

		st.tick++;
	};

	RETINA.ganglion = function (st, type, src, rf, params) {
		var gc = st.cfg.RGC, W = st.W, H = st.H, N = st.N, i;
		var I = st['RGC_' + type + '_I'], V = st['RGC_' + type + '_V'];
		var SPK = st['RGC_' + type + '_SPK'], REF = st['RGC_' + type + '_REF'];
		var RATE = st['RGC_' + type + '_RATE'], FR = st['RGC_' + type + '_FR'];
		var noise = params.noise || 0, rng = params.rng || Math.random;

		/* centre - surround pooling of the bipolar drive */
		RETINA.blur(src, st.SCR_A, W, H, rf.centerSigma, st.SCR_C);
		RETINA.blur(src, st.SCR_B, W, H, rf.surroundSigma, st.SCR_C);
		for (i = 0; i < N; i++) {
			var v = st.SCR_A[i] - rf.surroundGain * st.SCR_B[i];
			I[i] = v > 0 ? v : 0;
		}

		/* leaky integrate-and-fire (flybrain-style: leak, threshold, refractory) */
		var leak = gc.lifLeak, gain = gc.lifGain, thr = gc.lifThreshold, refr = gc.lifRefractory;
		var bias = gc.lifBias || 0, rf_ = gc.rateFilter;
		for (i = 0; i < N; i++) {
			SPK[i] = 0;
			var drive = I[i] + bias;   /* tonic bias: maintained discharge sits just under threshold */
			if (REF[i] > 0) {
				REF[i]--;
				V[i] = 0;
			} else {
				V[i] = V[i] * leak + gain * drive + (noise ? noise * (rng() - 0.5) : 0);
				if (V[i] >= thr) {
					SPK[i] = 1;
					V[i] = 0;
					REF[i] = refr;
				}
			}
			RATE[i] += rf_ * (SPK[i] - RATE[i]);
			FR[i] = CURVES.lifRate(drive, leak, gain, thr, refr);
		}
	};

	/* ---------- "lite" monocular retina for the second eye ----------
	 * Cone luminance -> adapting Naka-Rushton -> horizontal surround ->
	 * signed bipolar contrast (ON - OFF).  Used only for disparity.
	 */
	RETINA.createLite = function (mem, cfg, prefix) {
		cfg = cfg || RV;
		var W = cfg.GRID_W, H = cfg.GRID_H, N = W * H;
		var st = {W: W, H: H, N: N, cfg: cfg};
		['IN', 'ADAPT', 'PR', 'HC', 'D', 'SCR_A', 'SCR_B'].forEach(function (n) {
			st[n] = mem.alloc(prefix + '.' + n, 'f32', N);
		});
		st.ADAPT.fill(0.3);
		st.PR.fill(CURVES.nakaRushton(0.3, 0.3, cfg.PR.coneN));
		return st;
	};

	RETINA.stepLite = function (st, params) {
		var p = st.cfg.PR, opl = st.cfg.OPL, N = st.N, i;
		var L = params.lightLevel === undefined ? 1 : params.lightLevel;
		var IN = st.IN, A = st.ADAPT, PR = st.PR;
		for (i = 0; i < N; i++) st.SCR_A[i] = IN[i] * L;
		if (!params.freezeAdaptation) {
			RETINA.blur(st.SCR_A, st.SCR_B, st.W, st.H, p.coneAdaptBlur, st.HC);
			for (i = 0; i < N; i++) A[i] += p.coneAdaptRate * (st.SCR_B[i] - A[i]);
		}
		for (i = 0; i < N; i++) {
			var sig = A[i] < p.coneSigmaFloor ? p.coneSigmaFloor : A[i];
			PR[i] += p.coneTemporal * (CURVES.nakaRushton(st.SCR_A[i], sig, p.coneN) - PR[i]);
			st.SCR_B[i] = 1 - PR[i];
		}
		RETINA.blur(st.SCR_B, st.HC, st.W, st.H, opl.horizontalSigma, st.SCR_A);
		for (i = 0; i < N; i++) st.D[i] = (opl.horizontalGain * st.HC[i] - st.SCR_B[i]) * opl.bipolarGain;
	};

	root.RETINA = RETINA;
	if (typeof module !== 'undefined' && module.exports) module.exports = RETINA;
})(typeof self !== 'undefined' ? self : globalThis);
