gccollect = func(function(f)
	local freetip, livetip, sz, n, m = f:locals(i32, 5)
	f:loadg(markbit)
	f:eqz()
	f:storeg(markbit)

	-- Phase0 marking phase
	f:loadg(otmp)
	f:call(gcmark)
	f:loadg(oluastack)
	f:call(gcmark)
	f:loadg(ostrmt)
	f:call(gcmark)

	f:call(igcmark)

	-- Phase1 set reloc pointers
	f:loadg(markbit)
	f:i32(HEAPBASE)
	f:add()
	f:store(freetip)

	f:i32(HEAPBASE)
	f:store(livetip)

	f:loop(function(loop)
		f:load(livetip)
		f:load(livetip)
		f:call(sizeof)
		f:tee(sz)
		f:add()

		f:load(livetip)
		f:i32load(obj.gc)
		f:loadg(markbit)
		f:eq()
		f:iff(function()
			f:load(livetip)
			f:load(freetip)
			f:i32store(obj.gc)

			f:load(freetip)
			f:load(sz)
			f:add()
			f:store(freetip)
		end)

		f:tee(livetip)
		f:loadg(heaptip)
		f:ne()
		f:brif(loop)
	end)

	-- Phase2 fix reloc pointers
	f:loadg(otmp)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(otmp)

	f:loadg(oluastack)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(oluastack)

	f:loadg(ostrmt)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(ostrmt)

	local function updateptr(offset)
		f:load(livetip)
		f:load(livetip)
		f:i32load(offset)
		f:i32load(obj.gc)
		f:i32(-8)
		f:band()
		f:i32store(offset)
	end

	f:i32(HEAPBASE)
	f:store(livetip)
	f:loop(function(loop)
		f:load(livetip)
		f:i32load(obj.gc)
		f:i32(1)
		f:band()
		f:loadg(markbit)
		f:eq()
		f:iff(function(terminal)
			f:switch(function()
				f:load(livetip)
				f:i32load8u(obj.type)
			end, {types.int, types.float, types.nul, types.bool, types.str, terminal}, types.tbl, function()
				updateptr(tbl.arr)
				updateptr(tbl.hash)
				updateptr(tbl.meta)
				f:br(terminal)
			end, types.vec, function()
				f:load(livetip)
				f:tee(n)
				f:load(livetip)
				f:i32load(vec.len)
				f:add()
				f:store(m)
				f:loop(function(loop)
					f:load(n)
					f:load(m)
					f:eq()
					f:brif(terminal)

					f:load(n)
					f:load(n)
					f:i32load(vec.base)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:i32store(vec.base)

					f:load(n)
					f:i32(4)
					f:add()
					f:store(n)

					f:br(loop)
				end)
				f:br(terminal)
			end, types.buf, function()
				updateptr(buf.ptr)
				f:br(terminal)
			end, types.functy, function()
				updateptr(functy.bc)
				updateptr(functy.consts)
				updateptr(functy.frees)
				f:br(terminal)
			end, types.coro)
			updateptr(coro.caller)
			updateptr(coro.stack)
			updateptr(coro.data)
		end)

		f:load(livetip)
		f:load(livetip)
		f:call(sizeof)
		f:add()
		f:tee(livetip)
		f:loadg(heaptip)
		f:ne()
		f:brif(loop)
	end)

	f:call(igcfix)

	-- Phase3 move it
	f:i32(HEAPBASE)
	f:store(livetip)
	f:block(function(foundshift)
	f:loop(function(loop)
		f:load(livetip)
		f:call(sizeof)
		f:tee(sz)

		f:load(livetip)
		f:i32load(obj.gc)
		f:i32(1)
		f:band()
		f:loadg(markbit)
		f:eq()
		f:iff(function()
			f:load(livetip)
			f:load(livetip)
			f:i32load(obj.gc)
			f:i32(-8)
			f:band()
			f:tee(n)
			f:ne()
			f:brif(foundshift)
		end)

		f:load(livetip)
		f:add()
		f:tee(livetip)
		f:loadg(heaptip)
		f:eq()
		f:brtable(loop, f)
	end)
	end)

	f:load(n)
	f:load(livetip)
	f:load(sz)
	f:call(memcpy8)

	f:load(livetip)
	f:load(sz)
	f:add()
	f:tee(livetip)
	f:loadg(heaptip)
	f:ne()
	f:iff(function(blif)
		f:loop(function(loop)
			f:load(livetip)
			f:call(sizeof)
			f:store(sz)

			f:load(livetip)
			f:i32load(obj.gc)
			f:i32(1)
			f:band()
			f:loadg(markbit)
			f:eq()
			f:iff(function()
				f:load(livetip)
				f:i32load(obj.gc)
				f:i32(-8)
				f:band()
				f:load(livetip)
				f:load(sz)
				f:call(memcpy8)
			end)

			f:load(livetip)
			f:load(sz)
			f:add()
			f:tee(livetip)
			f:loadg(heaptip)
			f:eq()
			f:brtable(loop, blif)
		end)
	end)

	f:load(freetip)
	f:i32(-8)
	f:band()
	f:storeg(heaptip)
end)

gcmark = export('gcmark', func(i32, void, function(f, o)
	local m = f:locals(i32)

	local function markptr(offset)
		f:load(o)
		f:i32load(offset)
		f:call(gcmark)
	end

	-- check liveness bit
	f:load(o)
	f:i32(HEAPBASE)
	f:ltu()
	f:load(o)
	f:i32load(obj.gc)
	f:i32(1)
	f:band()
	f:loadg(markbit)
	f:eq()
	f:bor()
	f:brif(f)
	f:load(o)
	f:loadg(markbit)
	f:i32store(obj.gc)

	f:switch(function()
		f:load(o)
		f:i32load8u(obj.type)
	end, { types.int, types.float, types.nul, types.bool, types.str, gcmark}, types.tbl, function()
		markptr(tbl.arr)
		markptr(tbl.hash)
		markptr(tbl.meta)
		f:ret()
	end, types.vec, function()
		f:load(o)
		f:load(o)
		f:i32load(vec.len)
		f:add()
		f:store(m)
		f:loop(function(loop)
			f:load(o)
			f:load(m)
			f:eq()
			f:brif(f)

			markptr(vec.base)

			f:load(o)
			f:i32(4)
			f:add()
			f:store(o)

			f:br(loop)
		end)
		f:ret()
	end, types.buf, function()
		markptr(buf.ptr)
		f:ret()
	end, types.functy, function()
		markptr(functy.bc)
		markptr(functy.consts)
		markptr(functy.frees)
		f:ret()
	end, types.coro)
	markptr(coro.caller)
	markptr(coro.stack)
	markptr(coro.data)
end))
