/* stimuli.js -- synthetic "field stimuli" written straight into the retinal
 * input regions: gratings, spots, uniform fields, and a fallback scene for
 * when no camera is available.  Intensities are linear, 0..1.
 *
 * theta is the BAR orientation in degrees from the x axis (0 = horizontal
 * bars), matching response-curves.js gaborKernel.
 */

(function (root) {
	'use strict';

	var STIM = {};

	STIM.uniform = function (out, W, H, level) {
		for (var i = 0; i < W * H; i++) out[i] = level;
	};

	/* Sinusoidal grating: I = mean * (1 + c * cos(2 pi (x cos a + y sin a) / lambda + phase)) */
	STIM.grating = function (out, W, H, thetaDeg, lambda, phaseDeg, contrast, mean) {
		var a = (thetaDeg + 90) * Math.PI / 180;
		var ca = Math.cos(a), sa = Math.sin(a);
		var ph = phaseDeg * Math.PI / 180;
		var cx = (W - 1) / 2, cy = (H - 1) / 2;
		for (var y = 0; y < H; y++) {
			for (var x = 0; x < W; x++) {
				var p = ((x - cx) * ca + (y - cy) * sa) / lambda;
				out[y * W + x] = mean * (1 + contrast * Math.cos(2 * Math.PI * p + ph));
			}
		}
	};

	/* Disk of diameter d centred at (cx, cy) with intensity `level` on `bg`. */
	STIM.spot = function (out, W, H, cx, cy, d, level, bg) {
		var r2 = (d / 2) * (d / 2);
		for (var y = 0; y < H; y++) {
			for (var x = 0; x < W; x++) {
				var dx = x - cx, dy = y - cy;
				out[y * W + x] = (dx * dx + dy * dy <= r2) ? level : bg;
			}
		}
	};

	/* Oriented bar of given length/width through (cx, cy). */
	STIM.bar = function (out, W, H, cx, cy, thetaDeg, length, width, level, bg) {
		var t = thetaDeg * Math.PI / 180;
		var ux = Math.cos(t), uy = Math.sin(t);
		for (var y = 0; y < H; y++) {
			for (var x = 0; x < W; x++) {
				var dx = x - cx, dy = y - cy;
				var along = dx * ux + dy * uy;
				var across = -dx * uy + dy * ux;
				out[y * W + x] = (Math.abs(along) <= length / 2 && Math.abs(across) <= width / 2) ? level : bg;
			}
		}
	};

	/* Fallback scene for no-camera mode: drifting shapes rendered as RGBA
	 * bytes (the same format the camera path produces). */
	STIM.sceneRGBA = function (rgba, W, H, t) {
		var cx1 = W * (0.5 + 0.3 * Math.cos(t * 0.6));
		var cy1 = H * (0.5 + 0.3 * Math.sin(t * 0.4));
		var ang = t * 0.5;
		var ux = Math.cos(ang), uy = Math.sin(ang);
		for (var y = 0; y < H; y++) {
			for (var x = 0; x < W; x++) {
				var i = (y * W + x) * 4;
				var r = 60, g = 70, b = 90;
				/* rotating bar */
				var dx = x - W / 2, dy = y - H / 2;
				var along = dx * ux + dy * uy, across = -dx * uy + dy * ux;
				if (Math.abs(along) < 22 && Math.abs(across) < 3) { r = 230; g = 220; b = 200; }
				/* drifting red disk */
				var ex = x - cx1, ey = y - cy1;
				if (ex * ex + ey * ey < 64) { r = 220; g = 60; b = 50; }
				/* drifting grating patch, bottom right */
				if (x > W * 0.65 && y > H * 0.6) {
					var v = 128 + 100 * Math.cos((x + t * 8) * 0.9);
					r = v; g = v; b = v;
				}
				rgba[i] = r; rgba[i + 1] = g; rgba[i + 2] = b; rgba[i + 3] = 255;
			}
		}
	};

	root.STIM = STIM;
	if (typeof module !== 'undefined' && module.exports) module.exports = STIM;
})(typeof self !== 'undefined' ? self : globalThis);
