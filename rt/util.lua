local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, num, buf, vec, str = alloc.types, alloc.obj, alloc.num, alloc.buf, alloc.vec, alloc.str
local allocsize, newi64, newvec, newstr = alloc.allocsize, alloc.newi64, alloc.newvec, alloc.newstr

local _obj = require 'obj'

chex = func(i32, i32, function(f, ch)
	f:load(ch)
	f:i32(48)
	f:sub()
	f:tee(ch)
	f:i32(10)
	f:ltu()
	f:iff(i32, function()
		f:load(ch)
	end, function()
		f:load(ch)
		f:i32(17)
		f:sub()
		f:tee(ch)
		f:i32(6)
		f:geu()
		f:iff(function()
			f:i32(-1)
			f:load(ch)
			f:i32(32)
			f:sub()
			f:tee(ch)
			f:i32(6)
			f:geu()
			f:brif(f)
			f:drop()
		end)
		f:load(ch)
		f:i32(10)
		f:add()
	end)
end)

pushstr = func(i32, i32, i32, function(f, dst, ch)
	local s, cap, len = f:locals(i32, 3)
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:tee(len)
	f:i32(1)
	f:add()
	f:i32store(buf.len)

	f:load(dst)
	f:i32load(buf.ptr)
	f:tee(s)
	f:i32load(str.len)
	f:tee(cap)
	f:load(len)
	f:eq()
	f:iff(function()
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newstr)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(str.base)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(str.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)
	end)

	f:load(s)
	f:load(len)
	f:add()
	f:load(ch)
	f:i32store8(str.base)

	f:load(dst)
end)

pushvec = func(i32, i32, i32, function(f, dst, o)
	local s, cap, len = f:locals(i32, 3)
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:tee(len)
	f:i32(4)
	f:add()
	f:tee(cap)
	f:i32store(buf.len)

	f:load(dst)
	f:i32load(buf.ptr)
	f:tee(s)
	f:load(len)
	f:add()
	f:load(o)
	f:i32store(vec.base)

	f:load(cap)
	f:load(s)
	f:i32load(vec.len)
	f:tee(cap)
	f:eq()
	f:iff(function()
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newvec)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(vec.base)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(vec.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)
	end)
	f:load(dst)
end)

extendstr = func(i32, i32, i32, function(f, dst, n)
	local s, cap, len = f:locals(i32, 3)
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:load(n)
	f:add()
	f:tee(len)
	f:i32store(buf.len)

	f:load(len)
	f:load(dst)
	f:i32load(buf.ptr)
	f:i32load(str.len)
	f:tee(cap)
	f:geu()
	f:iff(function()
		f:loop(function(loop)
			f:load(len)
			f:load(cap)
			f:load(cap)
			f:add()
			f:tee(cap)
			f:geu()
			f:brif(loop)
		end)
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:call(newstr)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(str.base)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(str.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)
	end)
	f:load(dst)
end)

extendvec = func(i32, i32, i32, function(f, dst, n)
	local s, cap, len = f:locals(i32, 3)
	-- dst.len += n
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:load(n)
	f:add()
	f:tee(len)
	f:i32store(buf.len)

	-- dst.len >= dst.ptr.len?
	f:load(len)
	f:load(dst)
	f:i32load(buf.ptr)
	f:i32load(vec.len)
	f:tee(cap)
	f:geu()
	f:iff(function()
		-- compute new cap
		f:loop(function(loop)
			f:load(len)
			f:load(cap)
			f:load(cap)
			f:add()
			f:tee(cap)
			f:geu()
			f:brif(loop)
		end)
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:call(newvec)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(vec.base)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(vec.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)
	end)
	f:load(dst)
end)

popvec = func(i32, i32, function(f, box)
	local len = f:locals(i32)
	f:load(box)
	f:load(box)
	f:i32load(buf.len)
	f:i32(4)
	f:sub()
	f:tee(len)
	f:i32store(buf.len)

	f:load(box)
	f:i32load(buf.ptr)
	f:load(len)
	f:add()
	f:tee(len)
	f:i32load(vec.base)
	f:load(len)
	f:i32(NIL)
	f:i32store(vec.base)
end)

peekvec = func(i32, i32, i32, function(f, box, n)
	local len = f:locals(i32)
	f:load(box)
	f:i32load(buf.ptr)
	f:load(box)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:i32load(vec.base)
end)

function loadvecminus(f, x)
	if x <= vec.base then
		f:i32load(vec.base - x)
	else
		f:i32(x)
		f:sub()
		f:i32load(vec.base)
	end
end
function loadstrminus(f, x, meth)
	if not meth then
		meth = 'i32load'
	end
	if x <= str.base then
		f[meth](f, str.base - x)
	else
		f:i32(x)
		f:sub()
		f[meth](f, str.base)
	end
end

local mkhole = func(i32, i32, void, function(f, start, len)
	-- assumes (start&7) == 0, (len&7) == 0

	f:load(len)
	f:eqz()
	f:brif(f)

	f:load(start)
	f:loadg(markbit)
	f:i32store8(obj.gc)

	f:load(len)
	f:i32(8)
	f:eq()
	f:iff(function()
		f:load(start)
		f:i32(types.nul)
		f:i32store8(obj.type)
	end, function()
		f:load(start)
		f:i32(types.str)
		f:i32store8(obj.type)
		f:load(start)
		f:load(len)
		f:i32(str.base)
		f:sub()
		f:i32store(str.len)
	end)
end)

local function gentrunc(ty)
	return func(i32, i32, void, function(f, x, len)
		local oldsz = f:locals(i32, 1)
		f:load(x)
		f:call(_obj.sizeof)
		f:store(oldsz)

		f:load(x)
		f:load(len)
		f:i32store(ty.len)

		f:load(x)
		f:load(len)
		f:i32(ty.base)
		f:add()
		f:call(allocsize)
		f:tee(len)
		f:add()
		f:load(oldsz)
		f:load(len)
		f:sub()
		f:call(mkhole)
	end)
end

truncvec = gentrunc(vec)
truncstr = gentrunc(str)

local function genunbuf(truncfunc)
	return func(i32, i32, function(f, box)
		local x = f:locals(i32)
		f:load(box)
		f:i32load(buf.ptr)
		f:tee(x)
		f:load(box)
		f:i32load(buf.len)
		f:call(truncfunc)
		f:load(x)
	end)
end

unbufstr = genunbuf(truncstr)
unbufvec = genunbuf(truncvec)

memcpy1rl = func(i32, i32, i32, void, function(f, dst, src, len)
	f:loop(function(loop)
		f:load(len)
		f:eqz()
		f:brif(f)

		f:load(dst)
		f:load(len)
		f:i32(1)
		f:sub()
		f:tee(len)
		f:add()
		f:load(src)
		f:load(len)
		f:add()
		f:i32load8u()
		f:i32store8()

		f:br(loop)
	end)
end)

memcpy4 = func(i32, i32, i32, void, function(f, dst, src, len)
	local n = f:locals(i32)
	f:loop(function(loop)
		f:load(n)
		f:load(len)
		f:geu()
		f:brif(f)

		f:load(dst)
		f:load(n)
		f:add()
		f:load(src)
		f:load(n)
		f:add()
		f:i32load()
		f:i32store()

		f:load(n)
		f:i32(4)
		f:add()
		f:store(n)

		f:br(loop)
	end)
end)

memcpy8 = func(i32, i32, i32, void, function(f, dst, src, len)
	local n = f:locals(i32)
	f:loop(function(loop)
		f:load(n)
		f:load(len)
		f:geu()
		f:brif(f)

		f:load(dst)
		f:load(n)
		f:add()
		f:load(src)
		f:load(n)
		f:add()
		f:i64load()
		f:i64store()

		f:load(n)
		f:i32(8)
		f:add()
		f:store(n)

		f:br(loop)
	end)
end)

-- returns exponent on current lua stack
frexp = func(f64, f64, function(f, x)
	local xi, ee = f:locals(i64, 2)
	f:load(x)
	f:i64reinterpret()
	f:tee(xi)
	f:i64(23)
	f:shru()
	f:i64(0xff)
	f:band()
	f:tee(ee)
	f:eqz()
	f:eqz()
	f:iff(f64, function()
		f:load(x)
		f:load(ee)
		f:i64(0x7ff)
		f:eq()
		f:brif(f)
		f:drop()

		f:load(ee)
		f:i64(0x3fe)
		f:sub()
		f:call(newi64)
		f:call(tmppush)

		f:load(xi)
		f:i64(0x800fffffffffffff)
		f:band()
		f:i64(0x3fe0000000000000)
		f:bor()
		f:f64reinterpret()
	end, function()
		f:load(x)
		f:f64(0)
		f:eq()
		f:iff(f64, function()
			f:load(x)
			f:f64(0x1p64)
			f:mul()
			f:call(frexp)
			f:i32(4)
			f:call(nthtmp)
			f:i64load(num.val)
			f:i64(64)
			f:sub()
			f:call(newi64)
			f:i32(4)
			f:call(setnthtmp)
		end, function()
			f:load(x)
		end)
	end)
end)

tonum = func(i32, i32, function(f, x)
	local a = f:locals(i32)

	assert(types.int == 0 and types.float == 1)
	f:load(x)
	f:i32load8u(obj.type)
	f:tee(a)
	f:i32(types.float)
	f:leu()
	f:iff(i32, function()
		f:load(x)
	end, function()
		f:load(a)
		f:i32(types.str)
		f:eq()
		f:iff(i32, function()
			f:i32(NIL)
			-- TODO steal code from lexer
		end, function()
			f:i32(NIL)
		end)
	end)
end)

toint = func(i32, i32, function(f, x)
	local a64 = f:locals(f64)

	assert(types.int == 0)
	f:load(x)
	f:i32load8u(obj.type)
	f:iff(i32, function()
		f:load(x)
		f:call(tonum)
		f:tee(x)
		f:iff(function()
			f:load(x)
			f:f64load(num.val)
			f:tee(a64)
			f:load(a64)
			f:ceil()
			f:eq()
			f:iff(function()
				f:load(a64)
				f:i64truncs()
				f:call(newi64)
				f:ret()
			end)
		end)
		f:i32(NIL)
	end, function()
		f:load(x)
	end)
end)

return {
	chex = chex,
	pushstr = pushstr,
	pushvec = pushvec,
	extendstr = extendstr,
	extendvec = extendvec,
	popvec = popvec,
	peekvec = peekvec,
	truncvec = truncvec,
	truncstr = truncstr,
	unbufstr = unbufstr,
	unbufvec = unbufvec,
	memcpy1rl = memcpy1rl,
	memcpy4 = memcpy4,
	memcpy8 = memcpy8,
	frexp = frexp,
	tonum = tonum,
	toint = toint,
	loadvecminus = loadvecminus,
	loadstrminus = loadstrminus,
}
