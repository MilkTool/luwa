calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}
dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	localc = str.base + 5, -- # of locals
	retc = str.base + 9, -- # of values requested from call, -1 for no limit
	base = str.base + 13, -- index of parameter 0 on intermediate stack
}
objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	locals = vec.base + 16,
}

-- TODO settle on base/retc units & absolute vs relative. Then fix mismatchs everywhere
eval = func(i32, i32, i32, function(f)
	local a, b, c, d,
		datastack, bc, baseptr, valstack, valvec,
		callty, pc, localc, retc, base = f:locals(i32, 4+5+5)
	local offBc, offConst, offFree, offLocal = 0, 4, 8, 12

	local function loadframe(tmp)
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:tee(datastack)
		f:load(datastack)
		f:i32load(buf.ptr)
		f:i32load(buf.len)
		f:add()
		f:tee(tmp)
		loadstrminus(f, 4)
		f:store(base)

		f:load(tmp)
		loadstrminus(f, 8)
		f:store(retc)

		f:load(tmp)
		loadstrminus(f, 12)
		f:store(localc)

		f:load(tmp)
		loadstrminus(f, 16)
		f:store(pc)

		f:load(tmp)
		loadstrminus(f, 17, 'i32load8u')
		f:store(callty)
	end
	local function readArg()
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
	end

	loadframe(c)

	f:block(function(nop)
		f:block(function(opstorelocal)
		f:block(function(oploadlocal)
		f:block(function(opconst)
		f:block(function(opcallret)
		f:block(function(opcall)
		f:block(function(opret)
		f:block(function(optabadd)
		f:block(function(optabset)
		f:block(function(opmktab)
			f:block(function(opnot)
				f:block(function(opidx)
				f:block(function(opadd)
				f:block(function(opeq)
					f:block(function(oploadtrue)
						f:block(function(oploadfalse)
							f:block(function(oploadnil)
								-- valstack = ls.stack
								-- baseptr = ls.obj.ptr + base
								-- bc = baseptr.bc
								-- switch bc[pc++]
								f:loadg(oluastack)
								f:i32load(obj.stack)
								f:store(valstack)

								f:loadg(oluastack)
								f:i32load(coro.obj)
								f:i32load(buf.ptr)
								f:load(base)
								f:add()
								f:tee(baseptr)
								f:i32load(objframe.bc)
								f:tee(bc)
								f:load(pc)
								f:add()
								f:i32load8u(str.base)
								f:load(pc)
								f:i32(1)
								f:add()
								f:store(pc)
								f:brtable(nop, oploadnil, oploadfalse, oploadtrue, opeq, opadd, opidx, opnot, opmktab, optabset, optabset, opret, opcall, opcallret, opconst, oploadlocal, opstorelocal)
							end) -- LOAD_NIL
							f:load(valstack)
							f:i32(NIL)
							f:call(pushvec)
							f:drop()
							f:br(nop)
						end) -- LOAD_FALSE
						f:load(valstack)
						f:i32(FALSE)
						f:call(pushvec)
						f:drop()
						f:br(nop)
					end) -- LOAD_TRUE
					f:load(valstack)
					f:i32(TRUE)
					f:call(pushvec)
					f:drop()
					f:br(nop)
				end) -- BIN_EQ
					f:block(function(resmeta)
						f:load(valvec)
						f:load(valstack)
						f:i32load(buf.len)
						f:tee(b)
						f:add()
						f:tee(a)
						loadvecminus(f, 4)
						f:tee(c)
						f:load(a)
						loadvecminus(f, 8)
						f:tee(d)
						f:call(eq)
						f:iff(i32, function()
							f:i32(TRUE)
						end, function()
							-- if neq, check if both tables
							-- if both tables, check if same meta
							-- if same meta, push metaeqframe
							f:load(c)
							f:i32load8u(obj.type)
							f:i32(types.tbl)
							f:eq()
							f:load(d)
							f:i32load8u(obj.type)
							f:i32(types.tbl)
							f:eq()
							f:band()
							f:iff(function()
								f:load(c)
								f:i32load(tbl.meta)
								f:load(d)
								f:i32load(tbl.meta)
								f:tee(c)
								f:eq()
								f:iff(function()
									f:load(c)
									f:i32(0) -- TODO "__eq"
									f:call(tabget)
									f:tee(d)
									f:iff(function()
										-- push objframe
										f:loadg(oluastack)
										f:i32load(coro.obj)
										f:loadg(oluastack)
										f:i32(16)
										f:load(d)
										f:i32load(functy.localc)
										f:tee(b)
										f:i32(2)
										f:shl()
										f:add()
										f:call(extendvec)
										f:drop()

										-- push dataframe
										f:loadg(oluastack)
										f:i32load(coro.data)
										f:i32(17)
										f:call(extendstr)
										-- defer until writedataframe

										-- writeobjframe
										f:loadg(oluastack)
										f:i32load(coro.obj)
										f:tee(c)
										f:load(c)
										f:i32load(buf.ptr)
										f:i32load(buf.len)
										f:add()
										f:tee(c)
										assert(functy.consts == functy.bc + 4)
										assert(objframe.consts == objframe.bc + 4)

										-- reload metafunc
										f:loadg(oluastack)
										f:i32load(coro.stack)
										f:tee(d)
										f:load(d)
										f:i32load(buf.ptr)
										f:i32load(buf.len)
										f:add()
										loadvecminus(f, 4)
										f:i32load(tbl.meta)
										f:tee(d)
										f:i64load(functy.bc)
										f:i64store(objframe.bc)

										f:load(c)
										f:load(d)
										f:i32load(functy.frees)
										f:i32store(objframe.frees)

										-- write dataframe
										f:tee(datastack)
										f:load(datastack)
										f:i32load(buf.ptr)
										f:i32load(buf.len)
										f:add()
										f:i32(17)
										f:sub()
										f:tee(d)
										f:sub()
										f:i32(calltypes.bool)
										f:i32store8(dataframe.type)

										f:load(d)
										f:i32(0)
										f:i32store(dataframe.pc)

										f:load(d)
										f:load(b)
										f:i32store(dataframe.localc)

										f:load(d)
										f:i32(1)
										f:i32store(dataframe.retc)

										f:load(d)
										f:loadg(oluastack)
										f:i32load(obj.stack)
										f:i32load(buf.len)
										f:i32store(dataframe.base)

										f:br(resmeta)
									end)
								end)
							end)
							f:i32(FALSE)
						end)
						-- s[-2:] = boolres
						f:store(c)
						f:load(valstack)
						f:load(b)
						f:i32(4)
						f:sub()
						f:i32store(buf.len)
						f:load(valvec)
						f:load(b)
						f:add()
						f:tee(b)
						f:i32(NIL)
						f:i32store(vec.base - 4)
						f:load(b)
						f:load(c)
						f:i32store(vec.base - 8)
					end)
				end) -- BIN_ADD
				-- pop x, y
				-- metacheck
				-- typecheck
				f:br(nop)
				end) -- BIN_IDX
				-- pop x, y
				-- metacheck
				-- typecheck
				f:br(nop)
			end) -- UNARY_NOT
			f:load(valvec)
			f:load(valstack)
			f:i32load(buf.len)
			f:add()
			f:tee(a)
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i32load(vec.base)
			f:i32(TRUE)
			f:geu()
			f:select()
			f:i32store(vec.base)
			f:br(nop)
		end) -- MAKE_TABLE
		f:call(newtable)
		f:store(a)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:load(a)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- TABLE_SET
		-- s[-3][s[-2]] = s[-1]
		f:load(valvec)
		f:load(valstack)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		loadvecminus(f, 12)
		f:load(a)
		loadvecminus(f, 8)
		f:load(a)
		loadvecminus(f, 4)
		f:call(tabset)

		-- del s[-2:]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:load(a)
		f:i32load(buf.ptr)
		f:i32load(buf.len)
		f:tee(b)
		f:add()
		assert(vec.base >= 8 and NIL == 0)
		f:i64(0)
		f:i64store(vec.base - 8)
		f:load(a)
		f:load(b)
		f:i32(8)
		f:sub()
		f:i32store(buf.len)
	end) -- APPEND
		readArg()
		f:i64extendu()
		f:call(newi64)
		f:store(c)

		-- s[-2][c] = s[-1]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:load(a)
		f:i32load(buf.ptr)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		loadvecminus(f, 8)
		f:load(c)
		f:load(a)
		loadvecminus(f, 4)
		f:call(tabset)

		-- del s[-1]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:load(a)
		f:i32load(buf.ptr)
		f:i32load(buf.len)
		f:tee(b)
		f:add()
		assert(vec.base >= 4)
		f:i32(NIL)
		f:i32store(vec.base - 4)
		f:load(a)
		f:load(b)
		f:i32(4)
		f:sub()
		f:i32store(buf.len)
	end) -- RETURN
	-- pop stack frame

		f:load(datastack)
		f:load(datastack)
		f:i32load(buf.len)
		f:i32(17)
		f:sub()
		f:i32store(buf.len)

		f:load(retc)
		f:i32(-1)
		f:ne()
		f:load(valstack)
		f:i32load(buf.len)
		f:tee(b)
		f:load(retc)
		f:load(base)
		f:add()
		f:tee(c)
		f:ne()
		f:band()
		-- check ne to avoid lt/gt checks most of the time
		f:iff(function()
			f:load(b)
			f:load(c)
			f:gtu()
			f:iff(function()
				-- shrink stack
				f:loop(function(loop)
					f:load(valstack)
					f:call(popvec)
					f:drop()
					f:load(b)
					f:i32(1)
					f:sub()
					f:tee(b)
					f:load(c)
					f:gtu()
					f:brif(loop)
				end)
			end, function()
				-- pad stack with nils
				f:loop(function(loop)
					f:load(valstack)
					f:i32(NIL)
					f:call(pushvec)
					f:store(valstack)
					f:load(b)
					f:i32(1)
					f:add()
					f:tee(b)
					f:load(c)
					f:ltu()
					f:brif(loop)
				end)
			end)
		end)
		f:block(function(boolify)
			f:block(function(endprog)
				f:block(function(loadframe)
					-- read callty from freed memory
					f:load(callty)
					f:brtable(loadframe, endprog, loadframe, loadframe, loadframe, boolify)
				end) -- loadframe
				-- LOADFRAME
				f:br(nop)
			end) -- endprog
			f:load(valstack)
			f:ret()
		end) -- boolify
		f:load(valstack)
		f:i32load(buf.ptr)
		f:load(b)
		f:add()
		f:tee(b)
		f:i32(FALSE)
		f:i32(TRUE)
		f:load(b)
		loadvecminus(f, 4)
		f:i32(TRUE)
		f:geu()
		f:select()
		f:i32store(vec.base - 4)
		-- LOADFRAME
		f:br(nop)
	end) -- CALL
	-- push stack frame header
		f:br(nop)
	end) -- RETURN_CALL
	-- pop stack frame, then call
		f:br(nop)
	end) -- LOAD_CONST
		f:load(valstack)
		f:load(baseptr)
		f:i32load(vec.base + offConst)
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- LOAD_LOCAL
		f:load(valstack)
		f:load(baseptr)
		readArg()
		f:i32load(vec.base + offLocal)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- STORE_LOCAL
		f:load(baseptr)
		readArg()
		f:add()
		f:load(valstack)
		f:call(popvec)
		f:i32store(vec.base + offLocal)
		f:br(nop)
	end) -- NOP

	-- check whether to yield (for now we'll yield after each instruction)
	f:i32(0)
end)