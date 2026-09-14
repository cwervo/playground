/* main.js -- UI wiring: camera source, light level, stereo, plasticity, probes.
 * Loaded after constants.js, linear-memory.js, response-curves.js,
 * stimuli.js, worker-bridge.js and neuro-renderer.js.
 */

(function () {
	'use strict';

	var $ = function (id) { return document.getElementById(id); };
	var probeCanvas, probeBusy = false;

	function setStatus(text, cls) {
		var el = $('status');
		el.textContent = text;
		el.className = 'status ' + (cls || '');
	}

	function fmtLight(v) {
		var L = Math.pow(10, v);
		var name = L < 3e-3 ? 'scotopic (rods)' : L < 0.3 ? 'mesopic (rods + cones)' : 'photopic (cones)';
		return L.toExponential(1) + ' -- ' + name;
	}

	function pushParams() {
		BRIDGE.setParams({
			lightLevel: Math.pow(10, parseFloat($('light').value)),
			noise: parseFloat($('noise').value),
			stereo: $('stereo').value,
			syntheticShift: parseFloat($('shift').value),
			plasticity: $('plasticity').checked,
			plasticityRate: parseFloat($('eta').value)
		});
		$('lightLabel').textContent = fmtLight(parseFloat($('light').value));
		$('shiftLabel').textContent = $('shift').value + ' px';
		$('etaLabel').textContent = parseFloat($('eta').value).toFixed(4);
		$('noiseLabel').textContent = parseFloat($('noise').value).toFixed(3);
		$('disp-row').style.display = $('stereo').value === 'none' ? 'none' : '';
	}

	function populateCameras() {
		BRIDGE.listCameras().then(function (cams) {
			var sel = $('camera'), selR = $('cameraR');
			sel.innerHTML = ''; selR.innerHTML = '<option value="">(none)</option>';
			cams.forEach(function (c, i) {
				var o = document.createElement('option');
				o.value = c.deviceId; o.textContent = c.label || ('camera ' + (i + 1));
				sel.appendChild(o);
				var o2 = o.cloneNode(true);
				selR.appendChild(o2);
			});
			if (!cams.length) {
				var o3 = document.createElement('option');
				o3.value = ''; o3.textContent = '(no camera found)';
				sel.appendChild(o3);
			}
		});
	}

	function startCamera() {
		setStatus('requesting camera...', 'loading');
		BRIDGE.startCamera($('camera').value || undefined).then(function () {
			setStatus('camera -> retina', 'ok');
			populateCameras();  /* labels become available after permission */
		}).catch(function (err) {
			setStatus('camera unavailable (' + err.message + ') -- using synthetic scene', 'warn');
			BRIDGE.useSynthetic();
		});
	}

	function runProbe() {
		if (probeBusy) return;
		var kind = $('probe').value;
		probeBusy = true;
		$('runProbe').disabled = true;
		$('probeProgress').textContent = 'running ' + kind + '...';
		BRIDGE.probe(kind);
	}

	function init() {
		probeCanvas = $('plot');
		BRIDGE.on('ready', function (d) {
			$('memmap').textContent = d.dump;
			$('scale').textContent = d.map.length + ' regions, ' + (d.map[d.map.length - 1].offset + d.map[d.map.length - 1].bytes).toLocaleString() + ' bytes of linear memory; retina ' + d.W + 'x' + d.H + ', V1 ' + d.V1_W + 'x' + d.V1_H + ' x ' + (d.N_ORI * d.N_SF * 2) + ' simple + ' + (d.N_ORI * d.N_SF) + ' complex + ' + (d.N_ORI * 2) + ' direction + ' + d.N_DISP + ' disparity cells per column';
			pushParams();
			startCamera();
		});
		BRIDGE.on('tick', function (s) {
			RENDER.drawAll();
			$('stats').textContent = 'tick ' + s.tick + ' | ' + s.tickMs.toFixed(1) + ' ms/tick | ' + s.fps.toFixed(1) + ' fps | ' + s.spikes + ' ganglion spikes';
		});
		BRIDGE.on('probeProgress', function (d) {
			$('probeProgress').textContent = d.kind + ': ' + d.done + ' / ' + d.total;
		});
		BRIDGE.on('probeResult', function (res) {
			probeBusy = false;
			$('runProbe').disabled = false;
			$('probeProgress').textContent = 'done';
			if (res.maps) RENDER.plotMaps(probeCanvas, res); else RENDER.plotCurves(probeCanvas, res);
		});
		BRIDGE.on('error', function (msg) {
			setStatus('error: ' + msg, 'warn');
			probeBusy = false;
			$('runProbe').disabled = false;
			console.error(msg);
		});
		BRIDGE.on('source', function (src) {
			$('sourceBtn').textContent = src === 'camera' ? 'Source: camera' : 'Source: synthetic';
		});

		['light', 'noise', 'stereo', 'shift', 'plasticity', 'eta'].forEach(function (id) {
			$(id).addEventListener('input', pushParams);
			$(id).addEventListener('change', pushParams);
		});
		$('cameraR').addEventListener('change', function () {
			if ($('cameraR').value) {
				BRIDGE.startRightCamera($('cameraR').value).then(function () {
					$('stereo').value = 'camera'; pushParams();
				}).catch(function (err) { setStatus('right camera failed: ' + err.message, 'warn'); });
			}
		});
		$('camera').addEventListener('change', startCamera);
		$('sourceBtn').addEventListener('click', function () {
			if (BRIDGE.getSource() === 'camera') BRIDGE.useSynthetic(); else startCamera();
		});
		$('resetGabor').addEventListener('click', function () { BRIDGE.resetWeights('gabor'); });
		$('resetRandom').addEventListener('click', function () { BRIDGE.resetWeights('random'); $('plasticity').checked = true; pushParams(); });
		$('runProbe').addEventListener('click', runProbe);
		$('memmapToggle').addEventListener('click', function () {
			var pre = $('memmap');
			pre.style.display = pre.style.display === 'none' ? '' : 'none';
		});

		populateCameras();
		setStatus('allocating linear memory...', 'loading');
		BRIDGE.init();
	}

	if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
	else init();
})();
