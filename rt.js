const rtwa = typeof fetch !== 'undefined' ?
	fetch('rt.wasm', {cache:'no-cache'}).then(r => r.arrayBuffer()) :
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	);
function rtwathen(ab) {
	const mem = new WebAssembly.Memory({initial:1}), ffi = new FFI(mem);
	return WebAssembly.instantiate(ab, {'':{
		m: mem,
		echo: x => {
			console.log(x);
			return x;
		},
		echo2: (x, y) => {
			console.log(y, x);
			return x;
		},
		gcmark: x => {
			for (const h of ffi.handles) {
				ffi.mod.gcmark(h.val);
			}
		},
		gcfix: () => {
			let memta = new Uint8Array(mem.buffer);
			for (const h of ffi.handles) {
				h.val = util.readuint32(memta, h.val)&-8;
			}
		},
	}}).then(mod => {
		ffi.mod = mod.instance.exports;
		return ffi;
	});
}
module.exports = () => rtwa.then(rtwathen);
const util = require('./util');

function Handle(val) {
	this.val = val;
}
function FFI(mem) {
	this.mod = null;
	this.mem = mem;
	this.handles = new Set();
}
FFI.prototype.free = function(h) {
	this.handles.delete(h);
}
FFI.prototype.mkref = function(p) {
	switch (p) {
		case 0: return this.nil;
		case 8: return this.false;
		case 16: return this.true;
		default: {
			let h = new Handle(p);
			this.handles.add(h);
			return h;
		}
	}
}
FFI.prototype.newtable = function() {
	return this.mkref(this.mod.newtable());
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = util.asUtf8(s);
	let o = this.mod.newstr(s.length);
	let memta = new Uint8Array(this.mem.buffer);
	memta.set(s, o+13);
	return this.mkref(o);
}
FFI.prototype.newf64 = function(f) {
	return this.mkref(this.mod.newf64(f));
}
FFI.prototype.nil = new Handle(0);
FFI.prototype.true = new Handle(8);
FFI.prototype.false = new Handle(16);
FFI.prototype.gettypeid = function(h) {
	let memta = new Uint8Array(this.mem.buffer);
	return memta[h.val+4];
}
const tys = ["number", "number", "nil", "boolean", "table", "string"];
FFI.prototype.gettype = function(h) {
	return tys[this.gettypeid(h)];
}
FFI.prototype.strbytes = function(h) {
	const memta = new Uint8Array(this.mem.buffer);
	const len = util.readuint32(memta, h.val+5);
	return new Uint8Array(memta.buffer, h.val+13, util.readuint32(memta, h.val+5));
}
FFI.prototype.rawobj2js = function(p) {
	const memta = new Uint8Array(this.mem.buffer);
	switch (memta[p+4]) {
		case 0:
			return new Uint32Array(memta.slice(p+5, p+13).buffer);
		case 1:
			return new Float64Array(memta.slice(p+5, p+13).buffer)[0];
		case 2:
			return null;
		case 3:
			return memta[p+5] == 1;
		case 4: {
			const hash = util.readuint32(memta, p+17),
				hashlen = util.readuint32(memta, hash+5),
				map = new Map();
			for (let i=0; i<hashlen; i+=8) {
				const k = util.readuint32(memta, hash+9+i);
				if (k !== this.nil.val) {
					const v = util.readuint32(memta, hash+13+i);
					if (v !== this.nil.val) {
						map.set(this.rawobj2js(k), this.rawobj2js(v));
					}
				}
			}
			return map;
		}
		case 5:
			return new Uint8Array(memta.buffer, p+13, util.readuint32(memta, p+5));
		case 6: {
			const len = util.readuint32(memta, p+5), ret = [];
			for (let i=0; i<len; i+=4) {
				ret.push(this.rawobj2js(util.readuint32(memta, p + 9 + i)));
			}
			return ret;
		}
		default:
			throw "Unknown type: " + memta[p+4] + " @ " + p;
	}
}
FFI.prototype.obj2js = function(h) {
	return this.rawobj2js(h.val);
}
