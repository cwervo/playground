/* linear-memory.js -- one flat linear memory for every neuron population.
 *
 * All cell potentials, firing rates, spike flags and perceptron weights live
 * in a single WebAssembly.Memory (falls back to an ArrayBuffer when
 * WebAssembly is unavailable).  Populations are carved out of it by a bump
 * allocator, exactly like a static data segment in assembly: each region has
 * a name, an element type, a count and a byte offset.  Typed-array views are
 * handed back for compute; the whole segment can be snapshotted (a memcpy)
 * and re-viewed on another thread using only the memory map, so the renderer
 * literally reads a memory dump.
 *
 * Layout is struct-of-arrays like flybrain's sim-worker.js: one contiguous
 * run per population so each stage of the pipeline streams through memory.
 */

(function (root) {
	'use strict';

	var PAGE = 65536;
	var ALIGN = 64;

	var TYPES = {
		f32: {ctor: Float32Array, bytes: 4},
		u8:  {ctor: Uint8Array,   bytes: 1},
		i32: {ctor: Int32Array,   bytes: 4},
		u32: {ctor: Uint32Array,  bytes: 4}
	};

	function LinearMemory(bytes) {
		var pages = Math.ceil(bytes / PAGE);
		if (typeof WebAssembly !== 'undefined' && WebAssembly.Memory) {
			this.wasm = new WebAssembly.Memory({initial: pages, maximum: pages});
			this.buffer = this.wasm.buffer;
		} else {
			this.wasm = null;
			this.buffer = new ArrayBuffer(pages * PAGE);
		}
		this.bytes = pages * PAGE;
		this.brk = 0;                /* program break: first free byte */
		this.regions = [];
		this.byName = {};
	}

	/* Reserve `count` elements of `type` under `name`; returns a typed view. */
	LinearMemory.prototype.alloc = function (name, type, count) {
		var t = TYPES[type];
		if (!t) throw new Error('LinearMemory: unknown type ' + type);
		if (this.byName[name]) throw new Error('LinearMemory: duplicate region ' + name);
		var offset = (this.brk + ALIGN - 1) & ~(ALIGN - 1);
		var size = count * t.bytes;
		if (offset + size > this.bytes) {
			throw new Error('LinearMemory: out of memory allocating ' + name +
				' (' + size + ' bytes at 0x' + offset.toString(16) + ', capacity ' + this.bytes + ')');
		}
		var region = {name: name, type: type, count: count, offset: offset, bytes: size};
		this.regions.push(region);
		this.byName[name] = region;
		this.brk = offset + size;
		return new t.ctor(this.buffer, offset, count);
	};

	LinearMemory.prototype.view = function (name) {
		var r = this.byName[name];
		if (!r) throw new Error('LinearMemory: no region ' + name);
		return new TYPES[r.type].ctor(this.buffer, r.offset, r.count);
	};

	LinearMemory.prototype.has = function (name) {
		return !!this.byName[name];
	};

	/* Serialisable memory map (what the worker posts to the main thread). */
	LinearMemory.prototype.map = function () {
		return this.regions.map(function (r) {
			return {name: r.name, type: r.type, count: r.count, offset: r.offset, bytes: r.bytes};
		});
	};

	/* Copy of the used segment [0, brk) as a fresh, transferable ArrayBuffer. */
	LinearMemory.prototype.snapshot = function () {
		return this.buffer.slice(0, this.brk);
	};

	/* View a region inside a snapshot (or any buffer) given its map entry. */
	LinearMemory.viewIn = function (buffer, region) {
		return new TYPES[region.type].ctor(buffer, region.offset, region.count);
	};

	/* Human-readable listing, assembler .map style. */
	LinearMemory.prototype.dump = function () {
		var lines = ['offset      bytes     type  count   name'];
		for (var i = 0; i < this.regions.length; i++) {
			var r = this.regions[i];
			lines.push('0x' + hex8(r.offset) + '  ' + pad(String(r.bytes), 8) +
				'  ' + pad(r.type, 4) + '  ' + pad(String(r.count), 6) + '  ' + r.name);
		}
		lines.push('brk = 0x' + this.brk.toString(16) + ' (' + this.brk + ' of ' + this.bytes + ' bytes)');
		return lines.join('\n');
	};

	function pad(s, n) {
		while (s.length < n) s = ' ' + s;
		return s;
	}

	function hex8(v) {
		var s = v.toString(16);
		while (s.length < 8) s = '0' + s;
		return s;
	}

	LinearMemory.TYPES = TYPES;
	root.LinearMemory = LinearMemory;
	if (typeof module !== 'undefined' && module.exports) module.exports = LinearMemory;
})(typeof self !== 'undefined' ? self : globalThis);
