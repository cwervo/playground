/* response-curves.js -- the stimulus/response functions the model is built from.
 *
 * Pure numeric functions, no state, usable from the worker, the main thread
 * (reference curves drawn over measured ones) and Node tests.
 */

(function (root) {
	'use strict';

	var CURVES = {};

	/* ---------- intensity / contrast response ---------- */

	/* Naka-Rushton: R = Rmax * I^n / (I^n + sigma^n) */
	CURVES.nakaRushton = function (I, sigma, n, rmax) {
		if (I <= 0) return 0;
		var a = Math.pow(I, n);
		return (rmax === undefined ? 1 : rmax) * a / (a + Math.pow(sigma, n));
	};

	/* sRGB byte -> linear intensity (gamma 2.2). */
	CURVES.srgbToLinear = function (byte) {
		return Math.pow(byte / 255, 2.2);
	};

	/* Discrete leaky integrate-and-fire (V *= leak; V += gain * I) and its
	 * analytic mean firing rate for a constant input, in spikes per tick. */
	CURVES.lifRate = function (I, leak, gain, threshold, refractory) {
		var vInf = gain * I / (1 - leak);
		if (vInf <= threshold) return 0;
		var tau = -1 / Math.log(leak);
		var t = -tau * Math.log(1 - threshold / vInf);
		return 1 / (refractory + t);
	};

	/* ---------- spatial kernels ---------- */

	var gaussCache = {};
	CURVES.gaussian1D = function (sigma) {
		var key = sigma.toFixed(4);
		if (gaussCache[key]) return gaussCache[key];
		var r = Math.max(1, Math.ceil(3 * sigma));
		var k = new Float32Array(2 * r + 1);
		var sum = 0;
		for (var i = -r; i <= r; i++) {
			k[i + r] = Math.exp(-(i * i) / (2 * sigma * sigma));
			sum += k[i + r];
		}
		for (var j = 0; j < k.length; j++) k[j] /= sum;
		gaussCache[key] = {kernel: k, radius: r};
		return gaussCache[key];
	};

	/* Gabor perceptron template.  theta = bar orientation in degrees measured
	 * from the x axis (0 = horizontal bar); the carrier modulates along
	 * theta + 90.  Zero-mean, unit L2 norm. */
	CURVES.gaborKernel = function (K, thetaDeg, lambda, sigma, phaseDeg, aspect) {
		var w = new Float32Array(K * K);
		var r = (K - 1) / 2;
		var t = (thetaDeg + 90) * Math.PI / 180;
		var ct = Math.cos(t), st = Math.sin(t);
		var ph = phaseDeg * Math.PI / 180;
		var g2 = aspect * aspect;
		var mean = 0;
		for (var y = -r; y <= r; y++) {
			for (var x = -r; x <= r; x++) {
				var xp = x * ct + y * st;
				var yp = -x * st + y * ct;
				var env = Math.exp(-(xp * xp + g2 * yp * yp) / (2 * sigma * sigma));
				var v = env * Math.cos(2 * Math.PI * xp / lambda + ph);
				w[(y + r) * K + (x + r)] = v;
				mean += v;
			}
		}
		mean /= K * K;
		var norm = 0;
		for (var i = 0; i < w.length; i++) { w[i] -= mean; norm += w[i] * w[i]; }
		norm = Math.sqrt(norm) || 1;
		for (var i2 = 0; i2 < w.length; i2++) w[i2] /= norm;
		return w;
	};

	/* Integrated response of a DoG receptive field to a centred disk of
	 * diameter d (area-summation curve). */
	CURVES.dogAreaSummation = function (d, sigmaC, sigmaS, gainS) {
		var r2 = (d / 2) * (d / 2);
		var c = 1 - Math.exp(-r2 / (2 * sigmaC * sigmaC));
		var s = 1 - Math.exp(-r2 / (2 * sigmaS * sigmaS));
		return c - gainS * s;
	};

	/* ---------- tuning curves (reference shapes) ---------- */

	/* Orientation tuning as a von Mises on the doubled angle (period 180). */
	CURVES.vonMisesOrientation = function (thetaDeg, prefDeg, hwhhDeg) {
		var kappa = CURVES.hwhhToKappa(hwhhDeg);
		var d = (thetaDeg - prefDeg) * Math.PI / 180;
		return Math.exp(kappa * (Math.cos(2 * d) - 1));
	};

	/* kappa such that exp(kappa (cos(2 hwhh) - 1)) = 1/2 */
	CURVES.hwhhToKappa = function (hwhhDeg) {
		var h = hwhhDeg * Math.PI / 180;
		return Math.log(2) / (1 - Math.cos(2 * h));
	};

	/* Contrast response (Naka-Rushton in contrast, n ~ 2 in V1). */
	CURVES.contrastResponse = function (c, c50, n, rmax) {
		return CURVES.nakaRushton(c, c50, n, rmax);
	};

	/* Spatial-frequency tuning: Gaussian in log frequency with the given
	 * full bandwidth in octaves (half-height). */
	CURVES.logGaussianSF = function (lambda, prefLambda, bandwidthOct) {
		var x = Math.log2(prefLambda / lambda);
		var sigma = bandwidthOct / (2 * Math.sqrt(2 * Math.log(2)));
		return Math.exp(-(x * x) / (2 * sigma * sigma));
	};

	/* Disparity tuning of an energy unit built from Gabors of wavelength
	 * lambda: Gabor in disparity. */
	CURVES.disparityGabor = function (d, prefD, sigma, lambda) {
		var x = d - prefD;
		return Math.exp(-(x * x) / (2 * sigma * sigma)) * 0.5 * (1 + Math.cos(2 * Math.PI * x / lambda));
	};

	/* ---------- misc ---------- */

	CURVES.clamp01 = function (v) {
		return v < 0 ? 0 : (v > 1 ? 1 : v);
	};

	/* Deterministic pseudo-random (xorshift32) so tests are repeatable. */
	CURVES.rng = function (seed) {
		var s = seed >>> 0 || 2463534242;
		return function () {
			s ^= s << 13; s >>>= 0;
			s ^= s >>> 17;
			s ^= s << 5; s >>>= 0;
			return s / 4294967296;
		};
	};

	root.CURVES = CURVES;
	if (typeof module !== 'undefined' && module.exports) module.exports = CURVES;
})(typeof self !== 'undefined' ? self : globalThis);
