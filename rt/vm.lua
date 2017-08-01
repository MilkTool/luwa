eval = func(i32, i32, function(f)
	-- stack frame consists of
	-- tmpstack: locals, frees, consts, bc, stack
	-- datastack: base, ispcall?, pc
	local a, b = f:locals(i32, 2)
	local locals, frees, consts, bc, stack, ispcall, pc = f:locals(i32, 8)

	f:loadg(odatastack)
	f:loadg(odatastacklen)
	f:add()
	f:i32(4)
	f:sub()
	f:i32load()
	f:store(pc)

	f:i32(4)
	f:call(nthtmp)
	f:store(stack)
	f:i32(8)
	f:call(nthtmp)
	f:store(bc)
	f:i32(12)
	f:call(nthtmp)
	f:store(consts)

	f:block(function(nop)
		f:block(function(opconst)
		f:block(function(opcallret)
		f:block(function(opcall)
		f:block(function(opret)
		f:block(function(opmktab)
			f:block(function(opnot)
				f:block(function(opadd)
					f:block(function(oploadtrue)
						f:block(function(oploadfalse)
							f:block(function(oploadnil)
								-- switch(bc[pc++])
								f:load(bc)
								f:load(pc)
								f:add()
								f:i32load8u(str.base)
								f:load(pc)
								f:i32(1)
								f:add()
								f:store(pc)
								f:brtable(nop, oploadnil, oploadfalse, oploadtrue, opadd, opnot, opmktab, opret, opcall, opcallret, opconst)
							end) -- LOAD_NIL
							f:load(stack)
							f:i32(NIL)
							f:call(pushvec)
							f:store(stack)
							f:br(nop)
						end) -- LOAD_FALSE
						f:load(stack)
						f:i32(FALSE)
						f:call(pushvec)
						f:store(stack)
						f:br(nop)
					end) -- LOAD_TRUE
					f:load(stack)
					f:i32(TRUE)
					f:call(pushvec)
					f:store(stack)
					f:br(nop)
				end) -- BIN_ADD
				-- pop x, y
				-- metacheck
				-- typecheck
				f:br(nop)
			end) -- UNARY_NOT
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(stack)
			f:i32(4)
			f:call(nthbuf)
			f:i32(TRUE)
			f:geu()
			f:select()
			f:load(stack)
			f:i32(4)
			f:call(setnthbuf)
			f:br(nop)
		end) -- MAKE_TABLE
		f:call(newtable)
		f:store(a)
		f:i32(4)
		f:call(nthtmp)
		f:load(a)
		f:call(pushvec)
		f:store(stack)
		f:br(nop)
	end) -- RETURN
	-- pop stack frame
		f:br(nop)
	end) -- CALL
	-- push stack frame header
		f:br(nop)
	end) -- RETURN_CALL
	-- pop stack frame, then call
		f:br(nop)
	end) -- LOAD_CONST
		f:load(stack)
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
		f:load(consts)
		f:i32load(buf.ptr)
		f:add()
		f:i32load(vec.base)
		f:call(pushvec)
		f:store(stack)
	end) -- NOP

	-- check whether to yield (for now we'll yield after each instruction)
	f:i32(0)
end)
