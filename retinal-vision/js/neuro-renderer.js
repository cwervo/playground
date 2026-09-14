/* neuro-renderer.js -- draws populations straight out of the memory dump.
 *
 * Panels are 2D canvases; each reads one or more regions via BRIDGE.view()
 * and maps them to colour:
 *   ON  = green, OFF = magenta               (retinal / LGN polarity)
 *   hue = preferred orientation / direction  (V1)
 *   near = red, far = blue                   (disparity)
 * Also draws tuning-curve plots and receptive-field maps from probes.
 */

var RENDER = (function () {
	'use strict';

	var panels = {};
	var info = null;

	function hsv(h, s, v) {
		var i = Math.floor(h * 6), f = h * 6 - i;
		var p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
		var r, g, b;
		switch (i % 6) {
		case 0: r = v; g = t; b = p; break;
		case 1: r = q; g = v; b = p; break;
		case 2: r = p; g = v; b = t; break;
		case 3: r = p; g = q; b = v; break;
		case 4: r = t; g = p; b = v; break;
		default: r = v; g = p; b = q; break;
		}
		return [r * 255, g * 255, b * 255];
	}

	function panel(id, w, h) {
		var c = document.getElementById(id);
		if (!c) return null;
		if (!panels[id]) {
			c.width = w; c.height = h;
			panels[id] = {canvas: c, ctx: c.getContext('2d'), img: c.getContext('2d').createImageData(w, h), w: w, h: h};
		}
		return panels[id];
	}

	function put(p) { p.ctx.putImageData(p.img, 0, 0); }

	function clamp255(v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }

	/* grey map with optional gain */
	function drawGrey(id, map, W, H, gain) {
		var p = panel(id, W, H); if (!p || !map) return;
		var d = p.img.data;
		for (var i = 0, j = 0; i < W * H; i++, j += 4) {
			var v = clamp255(map[i] * gain * 255);
			d[j] = v; d[j + 1] = v; d[j + 2] = v; d[j + 3] = 255;
		}
		put(p);
	}

	/* signed map: positive green, negative magenta */
	function drawSigned(id, pos, neg, W, H, gain) {
		var p = panel(id, W, H); if (!p || !pos) return;
		var d = p.img.data;
		for (var i = 0, j = 0; i < W * H; i++, j += 4) {
			var a = pos[i] * gain, b = neg ? neg[i] * gain : 0;
			if (!neg && a < 0) { b = -a; a = 0; }
			d[j] = clamp255(b * 255); d[j + 1] = clamp255(a * 255); d[j + 2] = clamp255(b * 255); d[j + 3] = 255;
		}
		put(p);
	}

	function drawRGB(id, r, g, b, W, H, gain) {
		var p = panel(id, W, H); if (!p || !r) return;
		var d = p.img.data;
		for (var i = 0, j = 0; i < W * H; i++, j += 4) {
			d[j] = clamp255(r[i] * gain * 255); d[j + 1] = clamp255(g[i] * gain * 255); d[j + 2] = clamp255(b[i] * gain * 255); d[j + 3] = 255;
		}
		put(p);
	}

	/* spikes overlaid as bright dots on a dim rate map */
	function drawSpikes(id, spkOn, spkOff, rateOn, rateOff, W, H) {
		var p = panel(id, W, H); if (!p || !spkOn) return;
		var d = p.img.data;
		for (var i = 0, j = 0; i < W * H; i++, j += 4) {
			var g = 60 * rateOn[i] + (spkOn[i] ? 255 : 0);
			var m = 60 * rateOff[i] + (spkOff[i] ? 255 : 0);
			d[j] = clamp255(m); d[j + 1] = clamp255(g); d[j + 2] = clamp255(m * 0.8); d[j + 3] = 255;
		}
		put(p);
	}

	/* hue = argmax channel, value = its response */
	function drawArgmaxHue(id, maps, nChan, W, H, gain, hueSpan) {
		var p = panel(id, W, H); if (!p || !maps) return;
		var d = p.img.data, N = W * H;
		for (var i = 0, j = 0; i < N; i++, j += 4) {
			var best = 0, bi = 0, sum = 0;
			for (var c = 0; c < nChan; c++) {
				var v = maps[c * N + i];
				sum += v;
				if (v > best) { best = v; bi = c; }
			}
			var sel = sum > 0 ? (best - sum / nChan) / (sum + 1e-6) * nChan / (nChan - 1) : 0;
			var rgb = hsv((bi / nChan) * hueSpan, 0.4 + 0.6 * Math.min(1, sel), Math.min(1, best * gain));
			d[j] = rgb[0]; d[j + 1] = rgb[1]; d[j + 2] = rgb[2]; d[j + 3] = 255;
		}
		put(p);
	}

	/* per-orientation simple-cell polarity: green = ON-centre bar cell wins, magenta = OFF */
	function drawSimplePolarity(id, E, nChan, W, H, gain) {
		var p = panel(id, W, H); if (!p || !E) return;
		var d = p.img.data, N = W * H;
		for (var i = 0, j = 0; i < N; i++, j += 4) {
			var best = 0;
			for (var c = 0; c < nChan; c++) {
				var v = E[c * N + i];
				if (Math.abs(v) > Math.abs(best)) best = v;
			}
			var a = best > 0 ? best * gain : 0, b = best < 0 ? -best * gain : 0;
			d[j] = clamp255(b * 255); d[j + 1] = clamp255(a * 255); d[j + 2] = clamp255(b * 255); d[j + 3] = 255;
		}
		put(p);
	}

	function drawNearFar(id, near, zero, far, W, H, gain) {
		var p = panel(id, W, H); if (!p || !near) return;
		var d = p.img.data;
		for (var i = 0, j = 0; i < W * H; i++, j += 4) {
			d[j] = clamp255(near[i] * gain * 255); d[j + 1] = clamp255(zero[i] * gain * 255); d[j + 2] = clamp255(far[i] * gain * 255); d[j + 3] = 255;
		}
		put(p);
	}

	/* Weight templates as a strip of small tiles. */
	function drawTemplates(id, w, K, nT, scale) {
		var c = document.getElementById(id); if (!c || !w) return;
		var tw = K * scale, cols = nT, wpx = cols * (tw + 2);
		if (c.width !== wpx) { c.width = wpx; c.height = tw + 2; }
		var ctx = c.getContext('2d');
		var img = ctx.createImageData(tw, tw);
		for (var t = 0; t < nT; t++) {
			var base = t * K * K, m = 0;
			for (var i = 0; i < K * K; i++) m = Math.max(m, Math.abs(w[base + i]));
			for (var y = 0; y < tw; y++) for (var x = 0; x < tw; x++) {
				var v = w[base + Math.floor(y / scale) * K + Math.floor(x / scale)] / (m || 1);
				var j = (y * tw + x) * 4;
				img.data[j] = clamp255(128 + 127 * v); img.data[j + 1] = img.data[j]; img.data[j + 2] = img.data[j]; img.data[j + 3] = 255;
			}
			ctx.putImageData(img, t * (tw + 2), 1);
		}
	}

	/* ---------- main draw ---------- */

	function drawAll() {
		if (!info) info = BRIDGE.getInfo();
		if (!info) return;
		var W = info.W, H = info.H, VW = info.V1_W, VH = info.V1_H, NO = info.N_ORI, VN = VW * VH;
		var v = BRIDGE.view;

		/* camera */
		var cap = BRIDGE.getCaptureCanvas();
		var camPanel = document.getElementById('p-camera');
		if (camPanel && cap) { camPanel.width = W; camPanel.height = H; camPanel.getContext('2d').drawImage(cap, 0, 0); }

		/* photoreceptors */
		drawRGB('p-cones', v('RET.PR_L'), v('RET.PR_M'), v('RET.PR_S'), W, H, 1.3);
		drawGrey('p-rods', v('RET.PR_ROD'), W, H, 1.0);
		drawSigned('p-bipolar', v('RET.BP_ON'), v('RET.BP_OFF'), W, H, 2.0);
		drawSigned('p-color', v('RET.RG'), null, W, H, 6.0);
		drawSpikes('p-midget', v('RET.RGC_ON_M_SPK'), v('RET.RGC_OFF_M_SPK'), v('RET.RGC_ON_M_RATE'), v('RET.RGC_OFF_M_RATE'), W, H);
		drawSpikes('p-parasol', v('RET.RGC_ON_P_SPK'), v('RET.RGC_OFF_P_SPK'), v('RET.RGC_ON_P_RATE'), v('RET.RGC_OFF_P_RATE'), W, H);
		var ds = v('RET.DS_0');
		if (ds) {
			var dsAll = new Float32Array(4 * W * H);
			for (var d = 0; d < 4; d++) dsAll.set(v('RET.DS_' + d), d * W * H);
			drawArgmaxHue('p-ds', dsAll, 4, W, H, 4.0, 1.0);
		}
		drawSigned('p-lgn', v('LGN.D'), null, W, H, 1.5);

		/* V1 */
		var CN = v('V1.COMPLEX_NORM');
		if (CN) {
			drawArgmaxHue('p-v1-ori', CN, NO, VW, VH, 2.0, 1.0);
			drawArgmaxHue('p-v1-ori-sf1', CN.subarray(NO * VN), NO, VW, VH, 2.0, 1.0);
		}
		drawSimplePolarity('p-v1-simple', v('V1.SIMPLE_E'), NO, VW, VH, 1.5);
		var DIR = v('V1.DIRECTION');
		if (DIR) {
			/* reorder to 16 directions in angular order for a clean hue wheel */
			var dirs = new Float32Array(2 * NO * VN);
			for (var o = 0; o < NO; o++) {
				dirs.set(DIR.subarray((o * 2) * VN, (o * 2 + 1) * VN), o * VN);
				dirs.set(DIR.subarray((o * 2 + 1) * VN, (o * 2 + 2) * VN), (o + NO) * VN);
			}
			drawArgmaxHue('p-v1-dir', dirs, 2 * NO, VW, VH, 3.0, 1.0);
		}
		drawNearFar('p-v1-disp', v('V1.DISP_NEAR'), v('V1.DISP_ZERO'), v('V1.DISP_FAR'), VW, VH, 0.6);

		/* V2 */
		drawArgmaxHue('p-v2-corner', v('V2.CORNER'), NO / 2, VW, VH, 6.0, 1.0);
		drawArgmaxHue('p-v2-end', v('V2.END_STOPPED'), NO, VW, VH, 5.0, 1.0);
		var BO = v('V2.BORDER_OWNERSHIP');
		if (BO) {
			var bo = new Float32Array(2 * NO * VN);
			for (var o2 = 0; o2 < NO; o2++) {
				bo.set(BO.subarray((o2 * 2) * VN, (o2 * 2 + 1) * VN), o2 * VN);
				bo.set(BO.subarray((o2 * 2 + 1) * VN, (o2 * 2 + 2) * VN), (o2 + NO) * VN);
			}
			drawArgmaxHue('p-v2-bo', bo, 2 * NO, VW, VH, 4.0, 1.0);
		}
		drawGrey('p-v2-tex', v('V2.TEXTURE'), VW, VH, 1.0);

		drawTemplates('p-templates', v('V1.PERCEPTRON_W'), info.K, NO * 2, 3);
	}

	/* ---------- plots ---------- */

	var COLORS = ['#5ce0a0', '#ffb347', '#7fb8ff', '#ff6ec7', '#c8f060', '#ff8a5c'];

	function plotCurves(canvas, res) {
		var ctx = canvas.getContext('2d');
		var Wc = canvas.width, Hc = canvas.height;
		ctx.fillStyle = '#0d1117'; ctx.fillRect(0, 0, Wc, Hc);
		var L = 46, R = 12, T = 28, B = 34;
		var pw = Wc - L - R, ph = Hc - T - B;
		var xs = res.x, xlog = !!res.xlog;
		var xmin = xlog ? Math.log10(xs[0]) : xs[0], xmax = xlog ? Math.log10(xs[xs.length - 1]) : xs[xs.length - 1];
		var ymax = 1e-9;
		res.series.forEach(function (s) { s.y.forEach(function (v) { if (v > ymax) ymax = v; }); });
		ymax *= 1.08;
		function X(x) { var xv = xlog ? Math.log10(x) : x; return L + (xv - xmin) / (xmax - xmin) * pw; }
		function Y(y) { return T + ph - y / ymax * ph; }
		/* axes */
		ctx.strokeStyle = '#3a4250'; ctx.lineWidth = 1;
		ctx.beginPath(); ctx.moveTo(L, T); ctx.lineTo(L, T + ph); ctx.lineTo(L + pw, T + ph); ctx.stroke();
		ctx.fillStyle = '#9aa4b2'; ctx.font = '11px system-ui, sans-serif';
		ctx.textAlign = 'center';
		var nTicks = 5;
		for (var i = 0; i <= nTicks; i++) {
			var xv = xmin + (xmax - xmin) * i / nTicks;
			var label = xlog ? Math.pow(10, xv).toPrecision(2) : xv.toFixed(0);
			ctx.fillText(label, L + pw * i / nTicks, T + ph + 14);
		}
		ctx.textAlign = 'right';
		for (var k = 0; k <= 4; k++) ctx.fillText((ymax * k / 4).toPrecision(2), L - 4, T + ph - ph * k / 4 + 4);
		ctx.textAlign = 'center';
		ctx.fillText(res.xlabel || '', L + pw / 2, Hc - 6);
		ctx.textAlign = 'left';
		ctx.fillStyle = '#e6edf3'; ctx.font = 'bold 12px system-ui, sans-serif';
		ctx.fillText(res.title || '', L, 16);
		ctx.save(); ctx.translate(12, T + ph / 2); ctx.rotate(-Math.PI / 2); ctx.textAlign = 'center'; ctx.fillStyle = '#9aa4b2'; ctx.font = '11px system-ui, sans-serif'; ctx.fillText(res.ylabel || '', 0, 0); ctx.restore();
		/* series */
		var ly = T + 6;
		res.series.forEach(function (s, si) {
			ctx.strokeStyle = s.ref ? '#ffffff' : COLORS[si % COLORS.length];
			ctx.lineWidth = s.ref ? 1 : 2;
			ctx.setLineDash(s.ref ? [4, 4] : []);
			ctx.beginPath();
			for (var j = 0; j < xs.length; j++) { var px = X(xs[j]), py = Y(s.y[j]); if (j === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py); }
			ctx.stroke();
			ctx.setLineDash([]);
			if (!s.ref) { ctx.fillStyle = ctx.strokeStyle; for (var m = 0; m < xs.length; m++) { ctx.beginPath(); ctx.arc(X(xs[m]), Y(s.y[m]), 2.2, 0, 6.283); ctx.fill(); } }
			/* legend */
			ctx.fillStyle = s.ref ? '#ffffff' : COLORS[si % COLORS.length];
			ctx.font = '11px system-ui, sans-serif'; ctx.textAlign = 'right';
			ctx.fillText(s.name, L + pw - 4, ly + 10 + si * 13);
		});
	}

	/* RF maps: red = bright-spot excitation (ON), blue = dark-spot excitation (OFF) */
	function plotMaps(canvas, res) {
		var ctx = canvas.getContext('2d');
		var Wc = canvas.width, Hc = canvas.height;
		ctx.fillStyle = '#0d1117'; ctx.fillRect(0, 0, Wc, Hc);
		ctx.fillStyle = '#e6edf3'; ctx.font = 'bold 12px system-ui, sans-serif'; ctx.textAlign = 'left';
		ctx.fillText(res.title, 12, 16);
		var n = res.n, nm = res.maps.length;
		var size = Math.min((Wc - 24) / nm - 12, Hc - 60);
		var cell = size / n;
		res.maps.forEach(function (m, mi) {
			var ox = 12 + mi * (size + 12), oy = 30;
			var mx = 1e-9; m.data.forEach(function (v) { mx = Math.max(mx, Math.abs(v)); });
			for (var i = 0; i < n * n; i++) {
				var v = m.data[i] / mx;
				var r = v > 0 ? 255 : 40, b = v < 0 ? 255 : 40, a = Math.abs(v);
				ctx.fillStyle = 'rgba(' + r + ',40,' + b + ',' + (0.15 + 0.85 * a) + ')';
				ctx.fillRect(ox + (i % n) * cell, oy + Math.floor(i / n) * cell, cell + 0.5, cell + 0.5);
			}
			ctx.strokeStyle = '#3a4250'; ctx.strokeRect(ox, oy, size, size);
			ctx.fillStyle = '#9aa4b2'; ctx.font = '11px system-ui, sans-serif';
			ctx.fillText(m.name, ox, oy + size + 14);
		});
		ctx.fillStyle = '#9aa4b2';
		ctx.fillText('red = bright spot excites (ON), blue = dark spot excites (OFF); ' + n + ' x ' + n + ' px', 12, Hc - 8);
	}

	return {drawAll: drawAll, plotCurves: plotCurves, plotMaps: plotMaps};
})();
