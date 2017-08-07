pcall = func(function(f)
	-- > func, p1, p2, ...
	-- < true, p1, p2, ...
	-- modify datastack: 2, 0, framesz, retc, base+1
	local a, valvec, base = f:locals(i32, 3)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:tee(valvec)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:load(a)
	f:i32load(buf.ptr)
	f:i32load(buf.len)
	f:add()
	-- TODO create constants for negative offsets
	-- TODO load localc from p0 & assign to dataframe

	loadstrminus(f, 4)
	f:tee(base)
	f:add()
	f:i32(TRUE)
	f:i32store(vec.base)

	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:load(a)
	f:i32load(buf.ptr)
	f:i32load(buf.len)
	f:add()
	f:i32(17)
	f:sub()
	f:tee(a)
	f:i32(calltypes.prot)
	f:i32store8(dataframe.type)

	f:load(a)
	f:i32(0)
	f:i32store(dataframe.pc)

	f:load(a)
	f:load(a)
	f:i32load(dataframe.retc)
	f:i32(1)
	f:sub()
	f:i32store(dataframe.retc)

	f:load(a)
	f:load(base)
	f:i32(4)
	f:add()
	f:i32store(dataframe.base)
end)

math_frexp = func(i32, function(f)
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
	f:i32(0)
end)
