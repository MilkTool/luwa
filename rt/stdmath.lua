local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, num, vec, newi64, newf64 = alloc.types, alloc.obj, alloc.num, alloc.vec, alloc.newi64, alloc.newf64

local stack = require 'stack'
local tmppush, nthtmp, setnthtmp = stack.tmppush, stack.nthtmp, stack.setnthtmp

local rt = require 'rt'

math_abs = func(function(f)
	local a = f:locals(i32)
	local a64 = f:locals(i64)

	f:call(param0)
	f:i32load(vec.base)
	f:call(tonum)
	f:tee(a)
	f:iff(function()
		assert(types.int == 0)
		f:load(a)
		f:i32load8u(obj.type)
		f:iff(i32, function()
			f:load(a)
			f:i64load(num.base)
			f:tee(a64)
			f:i64(0)
			f:lts()
			f:iff(i32, function()
				f:i64(0)
				f:load(a64)
				f:sub()
				f:call(newi64)
			end, function()
				f:load(a)
			end)
		end, function()
			f:load(a)
			f:f64load(num.base)
			f:abs()
			f:call(newf64)
		end)
		f:call(tmppush)
	end, function()
		f:unreachable()
	end)
end)

local function genmathround(op)
	return func(function(f)
		local a = f:locals(i32)

		f:call(param0)
		f:i32load(vec.base)
		f:call(tonum)
		f:tee(a)
		f:iff(function()
			assert(types.int == 0)
			f:load(a)
			f:i32load8u(obj.type)
			f:iff(i32, function()
				f:load(a)
				f:f64load(num.base)
				f[op](f)
				f:i64truncs()
				f:call(newi64)	
			end, function()
				f:load(a)
			end)
			f:call(tmppush)
		end, function()
			f:unreachable()
		end)
	end)
end

math_ceil = genmathround('ceil')
math_floor = genmathround('floor')

local function genmathmathcore(f, fn, a)
	f:call(tonum)
	f:tee(a)
	f:iff(function()
		f:load(a)
		f:i32load8u(obj.type)
		f:iff(f64, function()
			f:load(a)
			f:f64load(num.base)
		end, function()
			f:load(a)
			f:i64load(num.base)
			f:f64converts()
		end)
		f:call(fn)
		f:call(newf64)
		f:call(tmppush)
	end, function()
		f:unreachable()
	end)
end
local function genmathmath(fn)
	return func(function(f)
		local a = f:locals(i32)

		f:call(param0)
		f:i32load(vec.base)
		genmathmathcore(f, fn, a)
	end)
end

math_sin = genmathmath(rt.sin)
math_cos = genmathmath(rt.cos)
math_tan = genmathmath(rt.tan)
math_asin = genmathmath(rt.asin)
math_acos = genmathmath(rt.acos)
math_exp = genmathmath(rt.exp)

math_log = func(function(f)
	local a, b = f:locals(i32, 2)
	f:call(param0)
	f:i32load(vec.base + 4)
	f:tee(a)
	f:iff(function()
		f:load(a)
		f:call(tonum)
		f:tee(a)
		f:iff(function()
			f:call(param0)
			f:tee(b)
			f:load(a)
			f:i32store(vec.base + 4)

			f:load(b)
			f:i32load(vec.base)
			f:call(tonum)
			f:tee(a)
			f:iff(function()
				f:call(param0)
				f:i32load(vec.base + 4)
				f:tee(b)
				f:i32load8u(obj.type)
				f:iff(f64, function()
					f:load(b)
					f:f64load(num.base)
				end, function()
					f:load(b)
					f:i64load(num.base)
					f:f64converts()
				end)
				f:call(log)
				f:load(a)
				f:iff(f64, function()
					f:load(b)
					f:f64load(num.base)
				end, function()
					f:load(b)
					f:i64load(num.base)
					f:f64converts()
				end)
				f:call(log)
				f:div()
				f:call(newf64)
				f:call(tmppush)
				f:ret()
			end)
		end)
		f:unreachable()
	end, function()
		f:load(a)
		genmathmathcore(f, log, a)
	end)
end)

math_atan = func(function(f)
	local a, b = f:locals(i32, 2)

	f:call(param0)
	f:i32load(vec.base + 4)
	f:tee(a)
	f:iff(function()
		f:load(a)
		f:call(tonum)
		f:tee(a)
		f:iff(function()
			f:call(param0)
			f:tee(b)
			f:load(a)
			f:i32store(vec.base + 4)

			f:load(b)
			f:i32load(vec.base)
			f:call(tonum)
			f:tee(a)
			f:iff(function()
				f:call(param0)
				f:i32load(vec.base + 4)
				f:tee(b)
				f:i32load8u(obj.type)
				f:iff(f64, function()
					f:load(b)
					f:f64load(num.base)
				end, function()
					f:load(b)
					f:i64load(num.base)
					f:f64converts()
				end)
				f:load(a)
				f:iff(f64, function()
					f:load(b)
					f:f64load(num.base)
				end, function()
					f:load(b)
					f:i64load(num.base)
					f:f64converts()
				end)
				f:call(atan2)
				f:call(newf64)
				f:call(tmppush)
				f:ret()
			end)
		end)
		f:unreachable()
	end, function()
		f:load(a)
		genmathmathcore(f, atan, a)
	end)
end)

math_frexp = func(function(f)
	--[[
	-- TODO come up with a DRY type checking strategy
	-- TODO update ABI
	f:i32(4)
	f:call(nthtmp)
	f:f64load(num.val)
	f:call(frexp)
	-- Replace param x with ret of frexp
	-- 2nd retval is already in place
	f:call(newf64)
	f:i32(8)
	f:call(setnthtmp)
	]]
end)

math_type = func(function(f)
	f:block(i32, function(res)
		assert(types.int == 0 and types.float == 1)
		f:switch(function()
			f:call(param0)
			f:i32load(vec.base)
			f:i32load8u(obj.type)
		end, types.int, function()
			f:i32(GS.integer)
			f:br(res)
		end, types.float, function()
			f:i32(GS.float)
			f:br(res)
		end, -1)
		f:i32(NIL)
	end)
	f:call(tmppush)
end)

return {
	math_abs = math_abs,
	math_asin = math_asin,
	math_acos = math_acos,
	math_atan = math_atan,
	math_exp = math_exp,
	math_frexp = math_frexp,
	math_sin = math_sin,
	math_cos = math_cos,
	math_tan = math_tan,
	math_log = math_log,
	math_floor = math_floor,
	math_ceil = math_ceil,
	math_type = math_type,
}
