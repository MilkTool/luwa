"use strict";
module.exports = function () {
	var env = new Table();
	env.set("_G", env);
	env.set("_VERSION", "Luwa 0.0");

	var io = new Table();
	env.set("io", io);
	io.set("write", io_write);

	var os = new Table();
	env.set("os", os);
	os.set("clock", os_clock);
	os.set("difftime", os_difftime);

	var debug = new Table();
	env.set("debug", debug);

	var string = new Table();
	env.set("string", string);
	string.set("char", utf8_char);
	string.set("len", string_len);
	string.set("lower", string_lower);
	string.set("upper", string_upper);

	var table = new Table();
	env.set("table", table);
	table.set("concat", table_concat);
	table.set("pack", table_pack);
	table.set("remove", table_remove);
	table.set("unpack", table_unpack);

	var math = new Table();
	env.set("math", math);
	math.set("pi", Math.PI);
	math.set("maxinteger", Math.pow(2, 53));
	math.set("mininteger", -Math.pow(2, 53));
	math.set("huge", Infinity);
	math.set("abs", math_abs);
	math.set("acos", math_acos);
	math.set("asin", math_asin);
	math.set("ceil", math_ceil);
	math.set("cos", math_cos);
	math.set("deg", math_deg);
	math.set("exp", math_exp);
	math.set("floor", math_floor);
	math.set("log", math_log);
	math.set("log10", math_log10);
	math.set("rad", math_rad);
	math.set("sin", math_sin);
	math.set("sqrt", math_sqrt);
	math.set("tan", math_tan);
	math.set("tointeger", math_tointeger);
	math.set("type", math_type);
	math.set("ult", math_ult);

	var coroutine = new Table();
	env.set("coroutine", coroutine);
	coroutine.set("create", coroutine_create);
	coroutine.set("resume", coroutine_resume);
	coroutine.set("yield", coroutine_yield);

	var packge = new Table();
	env.set("package", packge);

	var utf8 = new Table();
	env.set("utf8", utf8);
	utf8.set("char", utf8_char);

	env.set("assert", assert);
	env.set("error", error);
	env.set("ipairs", ipairs);
	env.set("pairs", pairs);
	env.set("next", next);
	env.set("tonumber", tonumber);
	env.set("tostring", tostring);
	env.set("type", type);
	env.set("pcall", pcall);
	env.set("print", print);
	env.set("select", select);
	env.set("getmetatable", getmetatable);
	env.set("setmetatable", setmetatable);
	return env;
}

const obj = require("./obj"),
	Table = require("./table"),
	Thread = require("./thread"),
	runbc = require("./runbc");

function readarg(stack, base, i) {
	return base + i < stack.length ? stack[base+i] : null;
}

function assert(vm, stack, base) {
	if (cond) throw val;
}

function error(vm, stack, base) {
	throw val;
}

function pairs(vm, stack, base) {
	stack.length = base + 3;
	stack[base] = next;
	stack[base+2] = null;
}

function ipairs(vm, stack, base) {
	stack.length = base + 3;
	stack[base] = inext;
	stack[base+2] = 0;
}

function inext(vm, stack, base) {
	let t = stack[base+1], key = stack[base+2] + 1;
	if (key < t.array.length) {
		stack[base] = key;
		stack[base+1] = key in t.array ? t.array[key] : null;
		stack.length = base + 2;
	} else {
		stack.length = base;
	}
}

function next(vm, stack, base) {
	let t = readarg(stack, base, 1), key = readarg(stack, base, 2);
	if (!(t instanceof Table)) {
		throw "next #1: expected table";
	}
	if (key === null) {
		if (t.keys.length) {
			let k = t.keys[0];
			stack[base] = t.get(k);
			stack[base+1] = k;
			stack.length = base + 2;
		} else {
			stack[base] = null;
			stack.length = base + 1;
		}
	} else {
		let ki = t.keyidx.get(key);
		if (ki === null) {
			throw "next: table iteration corrupted";
		} else if (ki+1 >= t.keys.length) {
			stack[base] = null;
			stack.length = base + 1;
		} else {
			let k = t.keys[++ki];
			stack[base] = k;
			stack[base+1] = ki + 1 >= t.keys.length ? null : t.get(k);
			stack.length = base + 2;
		}
	}
}

function tonumber(vm, stack, base) {
	let e = readarg(stack, base, 1), base = readarg(stack, base, 2);
	if (base === null) {
		if (typeof e == "number") {
			stack[base] = e;
		} else if (typeof e == "string") {
			stack[base] = parseFloat(e);
			if (Number.isNaN(stack[base])) {
				stack[base] = null;
			}
		} else {
			throw "tonumber #1: expected number or string";
		}
	} else if (typeof base == "number") {
		if (base < 2 || base > 36) {
			stack[base] = null;
		} else if(typeof e == "string") {
			stack[base] = parseInt(e, base);
		} else {
			throw "tonumber #1: expected string";
		}
	} else {
		throw "tonumber #2: expected number";
	}
	stack.length = base + 1;
}

function tostring(vm, stack, base) {
	let v = readarg(stack, base, 1);
	let __tostring = obj.metaget(v, "__tostring");
	stack.length = base;
	if (__tostring) {
		stack.push(__tostring, v);
		runbc.callObj(vm, __tostring, stack, base);
		if (stack.length == base) return stack.push(null);
	} else {
		stack[base] = v === null ? "nil" : v + "";
	}
	stack.length = base + 1;
}

function type(vm, stack, base) {
	stack.length = base + 1;
	let obj = stack[base];
	if (obj === null) stack[base] = "nil";
	else {
		switch (typeof obj) {
			case "string":stack[base] = "string";return;
			case "number":stack[base] = "number";return;
			case "boolean":stack[base] = "boolean";return;
			case "function":stack[base] = "function";return;
			case "object":
				stack[base] = obj instanceof Table ? "table" :
					obj instanceof Thread ? "thread" : "userdata";
		}
	}
}

function pcall(vm, stack, base) {
	let f = stack.splice(base, 2)[1];
	if (!f) {
		throw "Unexpected nil to pcall";
	}
	try {
		if (typeof f == "function") {
			f(vm, stack, base);
		} else {
			// invoke VM
		}
	} catch (e) {
		return stack.push(false, e);
	}
	stack.splice(base, 0, true);
}

function print(vm, stack, base) {
	console.log(stack.slice(base+1));
	stack.length = base;
}

function select(vm, stack, base) {
	let i = readarg(stack, base, 1);
	if (i === '#') {
		stack[base] = stack.length - base - 1;
	} else {
		if (typeof i != "number") throw "select #1: expected number";
		stack[base] = readarg(stack, base, i+1);
	}
	stack.length = base + 1;
}

function getmetatable(vm, stack, base) {
	let arg = readarg(stack, base, 1);
	stack.length = base + 1;
	stack[base] = obj.getmetatable(arg);
}

function setmetatable(vm, stack, base) {
	let arg2 = readarg(stack, base, 2);
	stack.length = base + 1;
	obj.setmetatable(stack[base], arg2);
}

function io_write(vm, stack, base) {
	for (var i=base+1; i<stack.length; i++) {
		console.log(stack[i]);
	}
	stack.length = base;
}

function os_clock(vm, stack, base) {
	stack[base] = new Date()/1000;
	stack.length = base + 1;
}

function os_difftime(vm, stack, base) {
	stack[base] = readarg(stack, base, 1) - readarg(stack, base, 2);
	stack.length = base + 1;
}

function string_len(vm, stack, base) {
	let s = readarg(stack, base, 1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.length;
	stack.length = base + 1;
}

function string_lower(vm, stack, base) {
	let s = readarg(stack, base, 1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.toLowerCase();
	stack.length = base + 1;
}

function string_upper(vm, stack, base) {
	let s = readarg(stack, base, 1);
	if (typeof s != "string") throw "string.upper #1: expected string";
	stack[base] = s.toUpperCase();
	stack.length = base + 1;
}

function table_concat(vm, stack, base) {
	let t = readarg(stack, base, 1);
	if (!(t instanceof Table)) throw "table.concat #1: expected table";
	if (!t.array.length) return '';
	let sep = readarg(stack, base, 2);
	if (sep === null) sep = '';
	let i = readarg(stack, base, 3);
	if (i === null) i = 1;
	let j = readarg(stack, base, 4);
	if (j === null) j = t.array.length - 1;
	if (i > j) return '';
	let ret = '';
	while (i <= j) {
		let val = t.array[i];
		if (typeof val != "number" && typeof val != "string") throw "table.concat: expected sequence of numbers & strings";
		ret += t.array[i];
	}
	stack[base] = ret;
	stack.length = base + 1;
}

function table_pack(vm, stack, base) {
	let t = new Table();
	t.array = stack.slice(base + 1);
	t.set("n", stack.length - base - 1);
	stack[base] = t;
	stack.length = base + 1;
}

function table_unpack(vm, stack, base) {
	let t = readarg(stack, base, 1);
	if (!(t instanceof Table)) throw "table.unpack #1: expected table";
	let i = readarg(stack, base, 2) || 1;
	let j = readarg(stack, base, 3) || t.array.length - 1;
	stack.length = base;
	while (i<=j) stack.push(t.array[i++]);
}

function table_remove(vm, stack, base) {
	let t = readarg(stack, base, 1);
	if (!(t instanceof Table)) throw "table.unpack #1: expected table";
	let i = readarg(stack, base, 2);
	if (i === null) {
		t.array.pop();
		stack.length = base;
	} else {
		if (typeof i != "number") throw "table.unpack #2: expected number";
		if (t.array.length == 0 && i === 0) {
			stack.length = base;
		} else if (i > 0 && i < t.array.length) {
			stack[base] = t.array.splice(i, 1)[0];
			stack.length = base + 1;
		} else {
			throw "position out of bounds";
		}
	}
}

function math_abs(vm, stack, base) {
	stack[base] = Math.abs(stack[base+1]);
	stack.length = base + 1;
}

function math_acos(vm, stack, base) {
	stack[base] = Math.acos(stack[base+1]);
	stack.length = base + 1;
}

function math_asin(vm, stack, base) {
	stack[base] = Math.asin(stack[base+1]);
	stack.length = base + 1;
}

function math_ceil(vm, stack, base) {
	stack[base] = Math.ceil(stack[base+1]);
	stack.length = base + 1;
}

function math_cos(vm, stack, base) {
	stack[base] = Math.cos(stack[base+1]);
	stack.length = base + 1;
}

function math_deg(vm, stack, base) {
	stack[base] = stack[base+1] * (180 / Math.PI);
	stack.length = base + 1;
}

function math_exp(vm, stack, base) {
	stack[base] = Math.exp(stack[base+1]);
	stack.length = base + 1;
}

function math_floor(vm, stack, base) {
	stack[base] = Math.floor(stack[base+1]);
	stack.length = base + 1;
}

function math_log(vm, stack, base) {
	let n = readarg(stack, base, 1);
	let b = readarg(stack, base, 2);
	stack[base] = b === null ? Math.log(n) : Math.log(n, b);
	stack.length = base + 1;
}

function math_log10(vm, stack, base) {
	stack[base] = Math.log10(stack[base+1]);
	stack.length = base + 1;
}

function math_rad(vm, stack, base) {
	stack[base] = stack[base+1] * (Math.PI / 180);
	stack.length = base + 1;
}

function math_sin(vm, stack, base) {
	stack[base] = Math.sin(stack[base+1]);
	stack.length = base + 1;
}

function math_sqrt(vm, stack, base) {
	stack[base] = Math.sqrt(stack[base+1]);
	stack.length = base + 1;
}

function math_tan(vm, stack, base) {
	stack[base] = Math.tan(stack[base+1]);
	stack.length = base + 1;
}

function math_tointeger(vm, stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? v : null;
	stack.length = base + 1;
}

function math_type(vm, stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? "integer" : "float";
	stack.length = base + 1;
}

function math_ult(vm, stack, base) {
	let u32 = new Uint32Array([stack[base+1], stack[base+2]]);
	stack[base] = u32[0] < u32[1];
	stack.length = base + 1;
}

function coroutine_create(vm, stack, base) {
	var subvm = readarg(stack, base, 1);
	var substack = stack.slice(base+1);
	subvm.readarg(substack, 0);
	stack[base] = new Thread(subvm, substack);
	stack.length = base + 1;
}

function coroutine_resume(vm, stack, base) {
	var thread = readarg(stack, base, 1);
	if (!(thread instanceof Thread)) throw "coroutine.resume #1: expected thread"
	for (let i=base+2; i<stack.length; i++) {
		thread.stack.push(stack[i]);
	}
	// run vm with stack
}

function coroutine_yield(vm, stack, base) {
	// TODO how do we return to resume?
}

function utf8_char(vm, stack, base) {
	let ret = "";
	for (var i = base+1; i<stack.length; i++) {
		// TODO reject invalid character codes
		if (typeof stack[i] != "number") throw "utf8.char: expected numbers";
		ret += String.fromCharCode(stack[i]);
	}
	stack[base] = ret;
	stack.length = base + 1;
}