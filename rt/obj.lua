eq = func(i32, i32, i32, function(f, a, b)
	local i, j = f:locals(i32, 2)
	f:load(a)
	f:i32load8u(obj.type)
	f:tee(i)
	f:load(b)
	f:i32load8u(obj.type)
	f:tee(j)
	f:ne()
	f:iff(function()
		-- check for flt/int eq
		f:i32(0)
		f:load(i)
		f:i32(1)
		f:leu()
		f:load(j)
		f:i32(1)
		f:leu()
		f:brif(f)
		f:drop()

		f:load(i)
		f:iff(function()
			f:load(a)
			f:load(b)
			f:store(a)
			f:store(b)
		end)
		f:load(b)
		f:f64load(num.base)
		f:load(a)
		f:i64load(num.base)
		f:f64converts()
		f:eq()
		f:ret()
	end)

	f:switch(function()
		f:load(i)
	end, types.int, function()
		f:load(a)
		f:i64load(int.val)
		f:load(b)
		f:i64load(int.val)
		f:eq()
		f:ret()
	end, types.float, function()
		f:load(a)
		f:f64load(float.val)
		f:load(b)
		f:f64load(float.val)
		f:eq()
		f:ret()
	end, types.nul, function()
		f:i32(1)
		f:ret()
	end, types.bool, types.tbl, function()
		f:load(a)
		f:load(b)
		f:eq()
		f:ret()
	end, types.str)
	f:i32(1)
	f:load(a)
	f:load(b)
	f:eq()
	f:brif(f)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load(str.len)
	f:tee(i)
	f:load(b)
	f:i32load(str.len)
	f:ne()
	f:brif(f)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load16u(str.base)
	f:load(b)
	f:i32load16u(str.base)
	f:ne()
	f:brif(f)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load8u(str.base + 2)
	f:load(b)
	f:i32load8u(str.base + 2)
	f:ne()
	f:brif(f)
	f:drop()

	f:i32(3)
	f:store(j)

	f:loop(i32, function(loop)
		f:i32(1)
		f:load(i)
		f:load(j)
		f:leu()
		f:brif(f)
		f:drop()

		f:i32(0)
		f:load(a)
		f:load(j)
		f:add()
		f:i64load(str.base)
		f:load(b)
		f:load(j)
		f:add()
		f:i64load(str.base)
		f:ne()
		f:brif(f)
		f:drop()

		f:load(j)
		f:i32(8)
		f:add()
		f:store(j)
		f:br(loop)
	end)
end)

hash = func(i32, i32, function(f, o)
	local n, m = f:locals(i32, 2)
	local h = f:locals(i64, 1)
	local of = f:locals(f64, 1)
	f:switch(function()
		f:load(o)
		f:i32load8u(obj.type)
	end, types.int, function()
		f:load(o)
		f:i32load(int.val)
		f:load(o)
		f:i32load(int.val + 4)
		f:xor()
		f:ret()
	end, types.float, function()
		f:load(o)
		f:f64load(float.val)
		f:tee(of)
		f:load(of)
		f:trunc()
		f:eq()
		f:iff(i32, function()
			f:load(of)
			f:i64truncs()
			f:tee(h)
			f:i64(32)
			f:shru()
			f:load(h)
			f:xor()
			f:i32wrap()
		end, function()
			f:load(o)
			f:i32load(float.val)
			f:load(o)
			f:i32load(float.val + 4)
			f:xor()
		end)
		f:ret()
	end, types.nul, types.bool, function()
		f:load(o)
		f:ret()
	end, types.tbl, types.functy, types.coro, function()
		assert(tbl.id == functy.id and functy.id == coro.id)
		f:load(o)
		f:i32load(5)
		f:ret()
	end, types.str, function()
		f:load(o)
		f:i32load(str.hash)
		f:eqz()
		f:iff(function(blif)
			-- h = s.len^(s.len>>24|s0<<40|s1<<48|s2<<56), n=s+3, m=s+s.len
			f:load(o)
			f:load(o)
			f:i32load(str.len)
			f:add()
			f:store(m)

			assert(str.len < 8)
			f:load(o)
			f:i64load(str.len)
			f:load(o)
			f:i64load(8)
			f:xor()
			f:store(h)

			f:load(o)
			f:i32(8 - str.len)
			f:add()
			f:store(n)

			f:loop(function(loop)
				f:load(n)
				f:load(m)
				f:ltu()
				f:iff(function(blif)
					-- h = (^ (+ (rol h 15) h) *n)
					f:load(h)
					f:i64(15)
					f:rotl()
					f:load(h)
					f:add()
					f:load(n)
					f:i64load(str.base)
					f:xor()
					f:store(h)

					f:load(n)
					f:i32(8)
					f:add()
					f:store(n)
					f:br(loop)
				end)
			end)

			f:load(o)
			f:load(h)
			f:i64(32)
			f:shru()
			f:load(h)
			f:xor()
			f:i32wrap()
			f:tee(n)
			f:i32(113)
			f:load(n)
			f:select()
			f:i32store(str.hash)
		end)
		f:load(o)
		f:i32load(str.hash)
		f:ret()
	end, types.vec, types.buf)
	f:i32(0)
end)

sizeof = func(i32, i32, function(f, o)
	f:switch(function()
		f:load(o)
		f:i32load8u(obj.type)
	end, types.nul, types.bool, function()
		f:i32(8)
		f:ret()
	end, types.int, types.float, types.buf, function()
		f:i32(16)
		f:ret()
	end, types.tbl, types.coro, types.functy, function()
		f:i32(32)
		f:ret()
	end, types.str, function()
		f:load(o)
		f:i32load(str.len)
		f:i32(str.base)
		f:add()
		f:call(allocsize)
		f:ret()
	end, types.vec)
	f:load(o)
	f:i32load(vec.len)
	f:i32(vec.base)
	f:add()
	f:call(allocsize)
end)
