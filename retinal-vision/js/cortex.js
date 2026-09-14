/* cortex.js -- LGN -> V1 -> V2.
 *
 * V1 cells are perceptrons: a weight template w (K x K) in linear memory,
 * a dot product with the LGN contrast field, and a nonlinearity.  One
 * template is shared by every position (a cortical hypercolumn replicated
 * across the visual field), so V1.W holds N_SF x N_ORI x 2 templates:
 *
 *   even (phase 0)   -> ON-centre simple cell = relu(+E), OFF-centre = relu(-E)
 *   odd  (phase 90)  -> edge-polarity simple cells relu(+O) / relu(-O)
 *   complex          -> sqrt(E^2 + O^2)             (energy model)
 *   normalised       -> C^2 / (sigma^2 + pool)        (divisive normalisation)
 *   direction        -> relu(+-(E O_prev - O E_prev)) (spatiotemporal quadrature)
 *   disparity        -> ((E_L + E_R(x+d))^2 + (O_L + O_R(x+d))^2)  (binocular energy)
 *
 * The push-pull ON/OFF arrangement (ON subregions excited by ON-LGN and
 * inhibited by OFF-LGN, and vice versa) is exactly w . (ON - OFF), so the LGN
 * hands V1 the signed contrast field D = ON - OFF.
 *
 * V2 reads the normalised complex maps: corners (co-located orthogonal
 * orientations), end-stopped cells, border ownership (which side of an edge
 * the figure is on), and a texture channel.
 */

(function (root) {
	'use strict';

	var RV = root.RV || (typeof require === 'function' ? require('./constants.js') : null);
	var CURVES = root.CURVES || (typeof require === 'function' ? require('./response-curves.js') : null);
	var RETINA = root.RETINA || (typeof require === 'function' ? require('./retina.js') : null);

	var CORTEX = {};

	/* ---------- the perceptron field ----------
	 * dst[oy, ox] = sum_k w[k] * src[oy*stride + ky, ox*stride + kx], zero padded.
	 */
	CORTEX.applyTemplate = function (src, W, H, w, K, stride, dst, dW, dH) {
		var r = (K - 1) >> 1;
		for (var oy = 0; oy < dH; oy++) {
			var cy = oy * stride;
			var yInside = (cy - r >= 0) && (cy + r < H);
			for (var ox = 0; ox < dW; ox++) {
				var cx = ox * stride;
				var sum = 0, ky, kx, row, wrow;
				if (yInside && cx - r >= 0 && cx + r < W) {
					/* interior: no bounds checks */
					for (ky = -r; ky <= r; ky++) {
						row = (cy + ky) * W + cx - r;
						wrow = (ky + r) * K;
						for (kx = 0; kx < K; kx++) sum += w[wrow + kx] * src[row + kx];
					}
				} else {
					for (ky = -r; ky <= r; ky++) {
						var y = cy + ky; if (y < 0 || y >= H) continue;
						row = y * W; wrow = (ky + r) * K + r;
						for (kx = -r; kx <= r; kx++) {
							var x = cx + kx; if (x < 0 || x >= W) continue;
							sum += w[wrow + kx] * src[row + x];
						}
					}
				}
				dst[oy * dW + ox] = sum;
			}
		}
	};

	/* ---------- allocation ---------- */

	CORTEX.create = function (mem, cfg, ret) {
		cfg = cfg || RV;
		var W = cfg.GRID_W, H = cfg.GRID_H, N = W * H;
		var VW = cfg.V1_W, VH = cfg.V1_H, VN = VW * VH;
		var K = cfg.V1_K, NO = cfg.N_ORI, NS = cfg.SF_LAMBDA.length;
		var st = {cfg: cfg, ret: ret, W: W, H: H, N: N, VW: VW, VH: VH, VN: VN, K: K, NO: NO, NS: NS,
			nTemplates: NS * NO * 2, tick: 0};

		st.LGN_D = mem.alloc('LGN.D', 'f32', N);            /* signed contrast (ON - OFF) */
		st.LGN_POOL = mem.alloc('LGN.POOL', 'f32', N);
		st.LGN_SCR = mem.alloc('LGN.SCR_A', 'f32', N);
		st.LGN_SCR2 = mem.alloc('LGN.SCR_B', 'f32', N);
		st.LGN_DR = mem.alloc('LGN.D_RIGHT', 'f32', N);

		st.W1 = mem.alloc('V1.PERCEPTRON_W', 'f32', st.nTemplates * K * K);
		st.W1_GABOR = mem.alloc('V1.PERCEPTRON_W_GABOR', 'f32', st.nTemplates * K * K);
		st.E = mem.alloc('V1.SIMPLE_E', 'f32', NS * NO * VN);   /* even-phase drive (signed) */
		st.O = mem.alloc('V1.SIMPLE_O', 'f32', NS * NO * VN);   /* odd-phase drive (signed) */
		st.E_PREV = mem.alloc('V1.SIMPLE_E_PREV', 'f32', NO * VN);
		st.O_PREV = mem.alloc('V1.SIMPLE_O_PREV', 'f32', NO * VN);
		st.C = mem.alloc('V1.COMPLEX', 'f32', NS * NO * VN);
		st.POOL = mem.alloc('V1.NORM_POOL', 'f32', VN);
		st.CN = mem.alloc('V1.COMPLEX_NORM', 'f32', NS * NO * VN);
		st.DIR = mem.alloc('V1.DIRECTION', 'f32', NO * 2 * VN);
		st.ER = mem.alloc('V1.RIGHT_E', 'f32', N);            /* right eye, vertical bars, full res */
		st.OR = mem.alloc('V1.RIGHT_O', 'f32', N);
		st.DISP = mem.alloc('V1.DISPARITY', 'f32', cfg.N_DISP * VN);
		st.NEAR = mem.alloc('V1.DISP_NEAR', 'f32', VN);
		st.ZERO = mem.alloc('V1.DISP_ZERO', 'f32', VN);
		st.FAR = mem.alloc('V1.DISP_FAR', 'f32', VN);
		st.VSCR_A = mem.alloc('V1.SCR_A', 'f32', VN);
		st.VSCR_B = mem.alloc('V1.SCR_B', 'f32', VN);

		st.V2_T = mem.alloc('V2.TOTAL_ENERGY', 'f32', VN);
		st.V2_CORNER = mem.alloc('V2.CORNER', 'f32', (NO / 2) * VN);
		st.V2_END = mem.alloc('V2.END_STOPPED', 'f32', NO * VN);
		st.V2_BO = mem.alloc('V2.BORDER_OWNERSHIP', 'f32', NO * 2 * VN);
		st.V2_TEX = mem.alloc('V2.TEXTURE', 'f32', VN);
		st.V2_SCR_A = mem.alloc('V2.SCR_A', 'f32', VN);
		st.V2_SCR_B = mem.alloc('V2.SCR_B', 'f32', VN);
		st.V2_SCR_C = mem.alloc('V2.SCR_C', 'f32', VN);

		st.patch = new Float32Array(K * K);                    /* plasticity scratch (not neural state) */
		st.yv = new Float32Array(NO * 2);
		st.boOffsets = CORTEX.buildHalfDiscs(cfg);

		CORTEX.buildGabors(st);
		return st;
	};

	CORTEX.templateIndex = function (st, sf, ori, phase) {
		return ((sf * st.NO + ori) * 2 + phase) * st.K * st.K;
	};

	CORTEX.mapIndex = function (st, sf, ori) {
		return (sf * st.NO + ori) * st.VN;
	};

	CORTEX.orientationDeg = function (st, ori) {
		return ori * 180 / st.NO;
	};

	/* Gabor templates: even (phase 0) and odd (phase 90) per orientation and SF. */
	CORTEX.buildGabors = function (st) {
		var cfg = st.cfg, K = st.K;
		for (var sf = 0; sf < st.NS; sf++) {
			var lambda = cfg.SF_LAMBDA[sf];
			var sigma = cfg.GABOR_SIGMA_PER_LAMBDA * lambda;
			for (var o = 0; o < st.NO; o++) {
				var theta = CORTEX.orientationDeg(st, o);
				for (var ph = 0; ph < 2; ph++) {
					var w = CURVES.gaborKernel(K, theta, lambda, sigma, ph * 90, cfg.GABOR_ASPECT);
					st.W1_GABOR.set(w, CORTEX.templateIndex(st, sf, o, ph));
				}
			}
		}
		st.W1.set(st.W1_GABOR);
	};

	/* "Newborn" cortex: random zero-mean unit-norm templates for SF 0. */
	CORTEX.randomizeWeights = function (st, seed) {
		var rng = CURVES.rng(seed || 12345);
		var KK = st.K * st.K;
		for (var t = 0; t < st.NO * 2; t++) {
			var base = t * KK, mean = 0, norm = 0, i;
			for (i = 0; i < KK; i++) { st.W1[base + i] = rng() - 0.5; mean += st.W1[base + i]; }
			mean /= KK;
			for (i = 0; i < KK; i++) { st.W1[base + i] -= mean; norm += st.W1[base + i] * st.W1[base + i]; }
			norm = Math.sqrt(norm) || 1;
			for (i = 0; i < KK; i++) st.W1[base + i] /= norm;
		}
	};

	CORTEX.resetDynamics = function (st) {
		['E_PREV', 'O_PREV', 'CN', 'DIR', 'DISP', 'NEAR', 'ZERO', 'FAR', 'LGN_POOL'].forEach(function (n) { st[n].fill(0); });
	};

	/* Half-disc offset tables for border ownership: for each orientation,
	 * the pixels on the + side and the - side of the normal. */
	CORTEX.buildHalfDiscs = function (cfg) {
		var R = cfg.V2.boRadius, band = cfg.V2.boBand, out = [];
		for (var o = 0; o < cfg.N_ORI; o++) {
			var t = o * Math.PI / cfg.N_ORI;
			var nx = -Math.sin(t), ny = Math.cos(t);
			var plus = [], minus = [];
			for (var dy = -R; dy <= R; dy++) {
				for (var dx = -R; dx <= R; dx++) {
					if (dx * dx + dy * dy > R * R) continue;
					var s = dx * nx + dy * ny;
					if (s > band) plus.push(dx, dy); else if (s < -band) minus.push(dx, dy);
				}
			}
			out.push([new Int32Array(plus), new Int32Array(minus)]);
		}
		return out;
	};

	/* ---------- one tick ----------
	 * params: {stereo: 'none'|'synthetic'|'camera', plasticity, plasticityRate, rng}
	 */
	CORTEX.step = function (st, params) {
		var cfg = st.cfg, ret = st.ret, i;
		var W = st.W, H = st.H, N = st.N, VW = st.VW, VH = st.VH, VN = st.VN, K = st.K;
		var stride = cfg.V1_STRIDE;

		/* ---- LGN: relay + contrast gain control ---- */
		var D = st.LGN_D, mw = cfg.LGN.magnoWeight;
		var onM = ret.RGC_ON_M_FR, offM = ret.RGC_OFF_M_FR, onP = ret.RGC_ON_P_FR, offP = ret.RGC_OFF_P_FR;
		for (i = 0; i < N; i++) {
			D[i] = (onM[i] - offM[i]) + mw * (onP[i] - offP[i]);
			st.LGN_SCR[i] = D[i] < 0 ? -D[i] : D[i];
		}
		RETINA.blur(st.LGN_SCR, st.LGN_POOL, W, H, cfg.LGN.gainBlur, st.LGN_SCR2);
		var gs = cfg.LGN.gainSigma;
		for (i = 0; i < N; i++) D[i] /= (gs + st.LGN_POOL[i]);

		/* ---- V1 simple + complex ---- */
		var sf, o, base, ti;
		for (sf = 0; sf < st.NS; sf++) {
			for (o = 0; o < st.NO; o++) {
				base = CORTEX.mapIndex(st, sf, o);
				var E = st.E.subarray(base, base + VN), O = st.O.subarray(base, base + VN);
				CORTEX.applyTemplate(D, W, H, st.W1.subarray(CORTEX.templateIndex(st, sf, o, 0), CORTEX.templateIndex(st, sf, o, 0) + K * K), K, stride, E, VW, VH);
				CORTEX.applyTemplate(D, W, H, st.W1.subarray(CORTEX.templateIndex(st, sf, o, 1), CORTEX.templateIndex(st, sf, o, 1) + K * K), K, stride, O, VW, VH);
				var C = st.C.subarray(base, base + VN);
				for (i = 0; i < VN; i++) C[i] = Math.sqrt(E[i] * E[i] + O[i] * O[i]);
			}
		}

		/* normalisation pool: spatially blurred sum of energy over all channels */
		var pool = st.VSCR_A;
		pool.fill(0);
		for (ti = 0; ti < st.NS * st.NO; ti++) {
			var Cm = st.C.subarray(ti * VN, (ti + 1) * VN);
			for (i = 0; i < VN; i++) pool[i] += Cm[i] * Cm[i];
		}
		RETINA.blur(pool, st.POOL, VW, VH, cfg.V1.normPoolBlur, st.VSCR_B);
		var s2 = cfg.V1.normSigma50 * cfg.V1.normSigma50, tau = cfg.V1.temporal;
		for (ti = 0; ti < st.NS * st.NO; ti++) {
			var Cc = st.C.subarray(ti * VN, (ti + 1) * VN), CNm = st.CN.subarray(ti * VN, (ti + 1) * VN);
			for (i = 0; i < VN; i++) {
				var target = Cc[i] * Cc[i] / (s2 + st.POOL[i]);
				CNm[i] += tau * (target - CNm[i]);
			}
		}

		/* ---- V1 direction selectivity (SF 0), spatiotemporal quadrature ---- */
		for (o = 0; o < st.NO; o++) {
			base = CORTEX.mapIndex(st, 0, o);
			var Ed = st.E.subarray(base, base + VN), Od = st.O.subarray(base, base + VN);
			var Ep = st.E_PREV.subarray(o * VN, (o + 1) * VN), Op = st.O_PREV.subarray(o * VN, (o + 1) * VN);
			var Dp = st.DIR.subarray((o * 2) * VN, (o * 2 + 1) * VN);
			var Dm = st.DIR.subarray((o * 2 + 1) * VN, (o * 2 + 2) * VN);
			for (i = 0; i < VN; i++) {
				var m = (Ed[i] * Op[i] - Od[i] * Ep[i]) / (s2 + st.POOL[i]);   /* > 0: motion toward +normal */
				Dp[i] += tau * ((m > 0 ? m : 0) - Dp[i]);
				Dm[i] += tau * ((m < 0 ? -m : 0) - Dm[i]);
			}
			Ep.set(Ed); Op.set(Od);
		}

		/* ---- binocular disparity energy (vertical bars, SF 0) ---- */
		if (params.stereo && params.stereo !== 'none' && st.right) {
			var vo = st.NO / 2;   /* theta = 90 deg: vertical bar, horizontal disparity */
			var wE = st.W1.subarray(CORTEX.templateIndex(st, 0, vo, 0), CORTEX.templateIndex(st, 0, vo, 0) + K * K);
			var wO = st.W1.subarray(CORTEX.templateIndex(st, 0, vo, 1), CORTEX.templateIndex(st, 0, vo, 1) + K * K);
			CORTEX.applyTemplate(st.LGN_DR, W, H, wE, K, 1, st.ER, W, H);
			CORTEX.applyTemplate(st.LGN_DR, W, H, wO, K, 1, st.OR, W, H);
			base = CORTEX.mapIndex(st, 0, vo);
			var EL = st.E.subarray(base, base + VN), OL = st.O.subarray(base, base + VN);
			st.NEAR.fill(0); st.FAR.fill(0);
			for (var dI = 0; dI < cfg.N_DISP; dI++) {
				var d = dI - cfg.DISP_MAX;
				var DM = st.DISP.subarray(dI * VN, (dI + 1) * VN);
				for (var vy = 0; vy < VH; vy++) {
					for (var vx = 0; vx < VW; vx++) {
						var rx = vx * stride + d; if (rx < 0) rx = 0; else if (rx >= W) rx = W - 1;
						var ri = vy * stride * W + rx, vi = vy * VW + vx;
						var se = EL[vi] + st.ER[ri], so = OL[vi] + st.OR[ri];
						var en = (se * se + so * so) / (s2 + st.POOL[vi]);
						DM[vi] += tau * (en - DM[vi]);
						if (d < 0) st.NEAR[vi] += DM[vi]; else if (d > 0) st.FAR[vi] += DM[vi]; else st.ZERO[vi] = DM[vi];
					}
				}
			}
		}

		/* ---- V2 ---- */
		CORTEX.stepV2(st);

		/* ---- plasticity ---- */
		if (params.plasticity) CORTEX.learn(st, params.plasticityRate || cfg.PLASTICITY.rate, params.rng || Math.random);

		st.tick++;
	};

	CORTEX.stepV2 = function (st) {
		var cfg = st.cfg, VW = st.VW, VH = st.VH, VN = st.VN, NO = st.NO, i, o;
		var T = st.V2_T;
		T.fill(0);
		var vx = st.V2_SCR_A, vy = st.V2_SCR_B;
		vx.fill(0); vy.fill(0);
		for (o = 0; o < NO; o++) {
			var CNm = st.CN.subarray(o * VN, (o + 1) * VN);
			var c2 = Math.cos(2 * o * Math.PI / NO), s2 = Math.sin(2 * o * Math.PI / NO);
			for (i = 0; i < VN; i++) { T[i] += CNm[i]; vx[i] += CNm[i] * c2; vy[i] += CNm[i] * s2; }
		}

		/* corners: co-located orthogonal orientations */
		for (o = 0; o < NO / 2; o++) {
			var A = st.CN.subarray(o * VN, (o + 1) * VN), B = st.CN.subarray((o + NO / 2) * VN, (o + NO / 2 + 1) * VN);
			var out = st.V2_CORNER.subarray(o * VN, (o + 1) * VN);
			for (i = 0; i < VN; i++) out[i] = Math.sqrt(A[i] * B[i]);
		}

		/* end-stopped: response at a bar end, suppressed by same-orientation
		 * energy further along the bar */
		var off = cfg.V2.endStopOffset, eg = cfg.V2.endStopGain;
		for (o = 0; o < NO; o++) {
			var t = o * Math.PI / NO;
			var ux = Math.round(Math.cos(t) * off), uy = Math.round(Math.sin(t) * off);
			var C = st.CN.subarray(o * VN, (o + 1) * VN), E = st.V2_END.subarray(o * VN, (o + 1) * VN);
			for (var y = 0; y < VH; y++) {
				var y1 = Math.min(VH - 1, Math.max(0, y + uy)), y2 = Math.min(VH - 1, Math.max(0, y - uy));
				for (var x = 0; x < VW; x++) {
					var x1 = Math.min(VW - 1, Math.max(0, x + ux)), x2 = Math.min(VW - 1, Math.max(0, x - ux));
					var v = C[y * VW + x] - eg * 0.5 * (C[y1 * VW + x1] + C[y2 * VW + x2]);
					E[y * VW + x] = v > 0 ? v : 0;
				}
			}
		}

		/* border ownership: which side of the edge has more "figure" energy */
		for (o = 0; o < NO; o++) {
			var Cb = st.CN.subarray(o * VN, (o + 1) * VN);
			var Bp = st.V2_BO.subarray((o * 2) * VN, (o * 2 + 1) * VN);
			var Bm = st.V2_BO.subarray((o * 2 + 1) * VN, (o * 2 + 2) * VN);
			var plus = st.boOffsets[o][0], minus = st.boOffsets[o][1];
			for (var by = 0; by < VH; by++) {
				for (var bx = 0; bx < VW; bx++) {
					var idx = by * VW + bx;
					if (Cb[idx] <= 1e-4) { Bp[idx] = 0; Bm[idx] = 0; continue; }
					var fp = CORTEX.sumOffsets(T, VW, VH, bx, by, plus);
					var fm = CORTEX.sumOffsets(T, VW, VH, bx, by, minus);
					var diff = (fp - fm) / (fp + fm + 1e-3) * cfg.V2.boGain;
					Bp[idx] = diff > 0 ? Cb[idx] * diff : 0;
					Bm[idx] = diff < 0 ? -Cb[idx] * diff : 0;
				}
			}
		}

		/* texture: pooled energy x orientation heterogeneity (1 - resultant length) */
		RETINA.blur(T, st.V2_TEX, VW, VH, cfg.V2.textureBlur, st.V2_SCR_C);
		RETINA.blur(vx, st.VSCR_A, VW, VH, cfg.V2.textureBlur, st.V2_SCR_C);
		RETINA.blur(vy, st.VSCR_B, VW, VH, cfg.V2.textureBlur, st.V2_SCR_C);
		for (i = 0; i < VN; i++) {
			var res = Math.sqrt(st.VSCR_A[i] * st.VSCR_A[i] + st.VSCR_B[i] * st.VSCR_B[i]);
			var het = 1 - res / (st.V2_TEX[i] + 1e-4);
			st.V2_TEX[i] *= het > 0 ? het : 0;
		}
	};

	CORTEX.sumOffsets = function (map, W, H, x, y, offs) {
		var s = 0;
		for (var k = 0; k < offs.length; k += 2) {
			var xx = x + offs[k], yy = y + offs[k + 1];
			if (xx < 0 || xx >= W || yy < 0 || yy >= H) continue;
			s += map[yy * W + xx];
		}
		return s;
	};

	/* ---------- plasticity: Sanger's generalised Hebbian algorithm ----------
	 * For random patches x of the LGN contrast field and the SF-0 templates
	 * w_i (i ordered), y_i = w_i . x and
	 *   dw_i = eta * y_i * (x - sum_{j <= i} y_j w_j)
	 * which converges to the principal components of the input patches.
	 */
	CORTEX.learn = function (st, eta, rng) {
		var cfg = st.cfg, K = st.K, KK = K * K, r = (K - 1) >> 1, W = st.W, H = st.H;
		var nT = st.NO * 2, x = st.patch, y = st.yv, D = st.LGN_D, Wt = st.W1;
		for (var p = 0; p < cfg.PLASTICITY.patchesPerTick; p++) {
			var cx = r + Math.floor(rng() * (W - 2 * r)), cy = r + Math.floor(rng() * (H - 2 * r));
			var mean = 0, i, ky, kx;
			for (ky = 0; ky < K; ky++) for (kx = 0; kx < K; kx++) {
				var v = D[(cy - r + ky) * W + cx - r + kx];
				x[ky * K + kx] = v; mean += v;
			}
			mean /= KK;
			var norm = 0;
			for (i = 0; i < KK; i++) { x[i] -= mean; norm += x[i] * x[i]; }
			if (norm < 1e-6) continue;
			norm = Math.sqrt(norm);
			for (i = 0; i < KK; i++) x[i] /= norm;
			/* responses */
			for (var t = 0; t < nT; t++) {
				var s = 0, b = t * KK;
				for (i = 0; i < KK; i++) s += Wt[b + i] * x[i];
				y[t] = s;
			}
			/* GHA update with a running residual; x is consumed as the residual */
			for (var t2 = 0; t2 < nT; t2++) {
				var b2 = t2 * KK, yi = y[t2], n2 = 0;
				for (i = 0; i < KK; i++) x[i] -= yi * Wt[b2 + i];
				for (i = 0; i < KK; i++) { Wt[b2 + i] += eta * yi * x[i]; n2 += Wt[b2 + i] * Wt[b2 + i]; }
				n2 = Math.sqrt(n2) || 1;
				for (i = 0; i < KK; i++) Wt[b2 + i] /= n2;
			}
		}
	};

	root.CORTEX = CORTEX;
	if (typeof module !== 'undefined' && module.exports) module.exports = CORTEX;
})(typeof self !== 'undefined' ? self : globalThis);
