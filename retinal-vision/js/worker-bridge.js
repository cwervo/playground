/* worker-bridge.js -- main-thread side of the simulation.
 *
 * Grabs camera frames (getUserMedia), downsamples them to the retinal grid,
 * ships them to sim-worker.js with flow control (one frame in flight), and
 * exposes the latest memory snapshot + memory map to the renderer.
 *
 * Falls back to a synthetic drifting scene when no camera is available, so
 * the pathway can be explored without hardware.  Optional second camera for
 * real binocular input.
 */

var BRIDGE = (function () {
	'use strict';

	var worker = null;
	var ready = false;
	var info = null;            /* 'ready' payload: memory map, sizes */
	var regions = {};           /* name -> map entry */
	var snapshot = null;        /* latest ArrayBuffer dump of linear memory */
	var inFlight = false;
	var listeners = {};
	var stats = {tickMs: 0, tick: 0, spikes: 0, fps: 0, lastTickTime: 0, frames: 0};
	var W = RV.GRID_W, H = RV.GRID_H;

	/* capture */
	var video = null, videoR = null;
	var stream = null, streamR = null;
	var capCanvas = null, capCtx = null, capCanvasR = null, capCtxR = null;
	var source = 'none';        /* 'camera' | 'synthetic' | 'none' */
	var syntheticT = 0;
	var frameTimer = null;
	var targetFps = 15;
	var stereoMode = 'none';

	function on(type, fn) { (listeners[type] = listeners[type] || []).push(fn); }
	function emit(type, data) {
		var l = listeners[type] || [];
		for (var i = 0; i < l.length; i++) l[i](data);
	}

	function init() {
		capCanvas = document.createElement('canvas');
		capCanvas.width = W; capCanvas.height = H;
		capCtx = capCanvas.getContext('2d', {willReadFrequently: true});
		capCanvasR = document.createElement('canvas');
		capCanvasR.width = W; capCanvasR.height = H;
		capCtxR = capCanvasR.getContext('2d', {willReadFrequently: true});

		worker = new Worker('js/sim-worker.js');
		worker.onmessage = handleMessage;
		worker.onerror = function (e) { emit('error', 'worker: ' + e.message); };
		worker.postMessage({type: 'init'});
	}

	function handleMessage(e) {
		var d = e.data;
		switch (d.type) {
		case 'ready':
			info = d;
			regions = {};
			for (var i = 0; i < d.map.length; i++) regions[d.map[i].name] = d.map[i];
			ready = true;
			emit('ready', d);
			startFramePump();
			break;
		case 'tick':
			inFlight = false;
			if (d.snapshot) {
				snapshot = d.snapshot;
				stats.tickMs = d.tickMs;
				stats.tick = d.tick;
				stats.spikes = d.spikes;
				var now = performance.now();
				if (stats.lastTickTime) stats.fps = 0.9 * stats.fps + 0.1 * (1000 / (now - stats.lastTickTime));
				stats.lastTickTime = now;
				emit('tick', stats);
			}
			break;
		case 'probeProgress':
			emit('probeProgress', d);
			break;
		case 'probeResult':
			emit('probeResult', d);
			break;
		case 'error':
			emit('error', d.message);
			break;
		}
	}

	/* ---- camera ---- */

	function listCameras() {
		if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return Promise.resolve([]);
		return navigator.mediaDevices.enumerateDevices().then(function (devs) {
			return devs.filter(function (d) { return d.kind === 'videoinput'; });
		});
	}

	function startCamera(deviceId) {
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			return Promise.reject(new Error('getUserMedia unavailable (needs https or localhost)'));
		}
		var constraints = {video: {width: {ideal: 320}, height: {ideal: 240}}, audio: false};
		if (deviceId) constraints.video.deviceId = {exact: deviceId};
		return navigator.mediaDevices.getUserMedia(constraints).then(function (s) {
			stopCamera();
			stream = s;
			video = document.createElement('video');
			video.muted = true; video.playsInline = true;
			video.srcObject = s;
			return video.play().then(function () { source = 'camera'; emit('source', source); });
		});
	}

	function startRightCamera(deviceId) {
		var constraints = {video: {width: {ideal: 320}, height: {ideal: 240}, deviceId: {exact: deviceId}}, audio: false};
		return navigator.mediaDevices.getUserMedia(constraints).then(function (s) {
			if (streamR) streamR.getTracks().forEach(function (t) { t.stop(); });
			streamR = s;
			videoR = document.createElement('video');
			videoR.muted = true; videoR.playsInline = true;
			videoR.srcObject = s;
			return videoR.play();
		});
	}

	function stopCamera() {
		if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
		video = null;
	}

	function useSynthetic() {
		stopCamera();
		source = 'synthetic';
		emit('source', source);
	}

	/* ---- frame pump with flow control ---- */

	function startFramePump() {
		if (frameTimer) clearInterval(frameTimer);
		frameTimer = setInterval(pumpFrame, 1000 / targetFps);
	}

	function pumpFrame() {
		if (!ready || inFlight) return;
		var rgba;
		if (source === 'camera' && video && video.readyState >= 2) {
			capCtx.drawImage(video, 0, 0, W, H);
			rgba = capCtx.getImageData(0, 0, W, H).data;
		} else if (source === 'synthetic') {
			var img = capCtx.createImageData(W, H);
			syntheticT += 1 / targetFps;
			STIM.sceneRGBA(img.data, W, H, syntheticT);
			capCtx.putImageData(img, 0, 0);
			rgba = img.data;
		} else {
			return;
		}
		var right = null;
		if (stereoMode === 'camera' && videoR && videoR.readyState >= 2) {
			capCtxR.drawImage(videoR, 0, 0, W, H);
			right = capCtxR.getImageData(0, 0, W, H).data;
		}
		var buf = rgba.buffer.slice(0);
		var msg = {type: 'frame', rgba: buf, right: null};
		var transfer = [buf];
		if (right) { msg.right = right.buffer.slice(0); transfer.push(msg.right); }
		inFlight = true;
		stats.frames++;
		worker.postMessage(msg, transfer);
		emit('frame', capCanvas);
	}

	/* ---- control ---- */

	function setParams(p) {
		if (p.stereo !== undefined) stereoMode = p.stereo;
		worker.postMessage({type: 'setParams', params: p});
	}

	function resetWeights(mode) {
		worker.postMessage({type: 'resetWeights', mode: mode});
	}

	function probe(kind) {
		worker.postMessage({type: 'probe', kind: kind});
	}

	/* View a population straight out of the latest memory dump. */
	function view(name) {
		if (!snapshot) return null;
		var r = regions[name];
		if (!r) return null;
		return LinearMemory.viewIn(snapshot, r);
	}

	return {
		init: init, on: on,
		listCameras: listCameras, startCamera: startCamera, startRightCamera: startRightCamera,
		stopCamera: stopCamera, useSynthetic: useSynthetic,
		setParams: setParams, resetWeights: resetWeights, probe: probe,
		view: view,
		getInfo: function () { return info; },
		getStats: function () { return stats; },
		getSource: function () { return source; },
		getCaptureCanvas: function () { return capCanvas; }
	};
})();
