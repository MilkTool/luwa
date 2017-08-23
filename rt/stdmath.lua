math_abs = func(function(f)
	local a = f:locals(i32)
	local a64 = f:locals(i64)

	f:switch(function()
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
	end, types.int, function()
		f:load(a)
		f:i64load(num.base)
		f:tee(a64)
		f:i64(0)
		f:lts()
		f:iff(function()
			f:i64(0)
			f:load(a64)
			f:sub()
			f:call(newi64)
			f:i32(4)
			f:call(setnthtmp)
		end)
		f:ret()
	end, types.float, function()
		f:load(a)
		f:f64load(num.base)
		f:abs()
		f:call(newf64)
		f:i32(4)
		f:call(setnthtmp)
		f:ret()
	end, -1)
	f:unreachable()
end)

local function genmathround(op)
	return func(function(f)
		local a = f:locals(i32)

		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:i32(1)
		f:eq()
		f:iff(function()
			f:load(a)
			f:f64load(num.base)
			f[op](f)
			f:i64truncs()
			f:call(newi64)
			f:i32(4)
			f:call(setnthtmp)
		end, function()
			f:unreachable()
		end)
	end)
end

math_ceil = genmathround('ceil')
math_floor = genmathround('floor')

math_frexp = func(function(f)
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
end)

math_type = func(function(f)
	f:block(i32, function(res)
		assert(types.int == 0 and types.float == 1)
		f:switch(function()
			f:i32(4)
			f:call(nthtmp)
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
	f:i32(4)
	f:call(setnthtmp)
end)

