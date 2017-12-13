local ops = require'../luart/bc'

dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	base = str.base + 5, -- Base. params here
	dotdotdot = str.base + 9, -- base+dotdotdot = excess params here. Ends at base+locals
	retb = str.base + 11, -- base+retb = put return vals here
	retc = str.base + 13, -- base+retc = stack should be post return. 0xffff for piped return
	locals = str.base + 15, -- base+locals = locals here
	frame = str.base + 17, -- base+frame = objframe here
	sizeof = 19,
}
objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	tmpbc = 12,
	tmpconsts = 8,
	tmpfrees = 4,
	sizeof = 12,
}
calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}

init = export('init', func(i32, void, function(f, fn)
	-- Transition oluastack to having a stack frame from fn
	-- Assumes stack was previously setup

	local a, stsz, newstsz = f:locals(i32, 3)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.len)
	f:store(stsz)

	f:load(fn)
	f:call(tmppush)

	f:i32(dataframe.sizeof * 9)
	f:call(newstrbuf)
	f:tee(a)

	f:loadg(oluastack)
	f:load(a)
	f:i32store(coro.data)

	f:load(a)
	f:i32(dataframe.sizeof)
	f:i32store(buf.len)

	f:i32load(buf.ptr)
	f:tee(a)
	f:i32(calltypes.init)
	f:i32store8(dataframe.type)

	assert(dataframe.base == dataframe.pc + 4)
	f:load(a)
	f:i64(0)
	f:i64store(dataframe.pc)

	assert(dataframe.retb == dataframe.dotdotdot + 2)
	f:load(a)
	f:i32(4)
	f:i32store(dataframe.dotdotdot)

	f:load(a)
	f:i32(-1)
	f:i32store16(dataframe.retc)

	f:load(a)
	f:load(stsz)
	f:i32store16(dataframe.locals)

	f:load(a)
	f:load(stsz)
	f:i32(4)
	f:call(nthtmp)
	f:tee(fn)
	f:i32load(functy.localc)
	f:i32(2)
	f:shl()
	f:add()
	f:tee(newstsz)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.len)
	f:i32(4)
	f:sub()
	f:add()
	f:i32store16(dataframe.frame)

	f:load(newstsz)
	f:i32(objframe.sizeof)
	f:add()
	f:call(extendtmp)

	f:i32(4)
	f:store(fn)
	f:loop(function(loop)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(stsz)
		f:add()
		f:load(fn)
		f:add()
		f:i64(0)
		f:i64store(vec.base)

		f:load(fn)
		f:i32(8)
		f:add()
		f:tee(fn)
		f:load(newstsz)
		f:ltu()
		f:brif(loop)
	end)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:load(stsz)
	f:add()
	f:i32load(vec.base)
	f:tee(fn)

	f:call(tmppop)

	f:i32load(functy.bc)
	f:i32(objframe.tmpbc)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.consts)
	f:i32(objframe.tmpconsts)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.frees)
	f:i32(objframe.tmpfrees)
	f:call(setnthtmp)
end))

loadframebase = func(i32, function(f)
	local a = f:locals(i32)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
end)

param0 = func(i32, function(f)
	f:call(loadframebase)
	f:i32load(dataframe.base)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:add()
end)

eval = export('eval', func(i32, function(f)
	local a, b, c, d, e,
		meta_callty, meta_retb, meta_retc, meta_key, meta_off,
		framebase, objbase, base, bc, pc = f:locals(i32, 5+5+5)
	local a64 = f:locals(i64, 1)

	local function loadframe()
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load(dataframe.base)
		f:store(base)

		f:load(framebase)
		f:i32load(dataframe.pc)
		f:store(pc)
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
	local function readArg4()
		readArg()
		f:i32(2)
		f:shl()
	end

	loadframe()

	f:switch(function(scopes)
		-- baseptr = ls.obj.ptr + base
		-- bc = baseptr.bc
		-- switch bc[pc++]
		f:call(loadframebase)
		f:tee(framebase)
		f:i32load16u(dataframe.frame)
		f:load(base)
		f:add()
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:add()
		f:tee(objbase)
		f:i32load(objframe.bc)
		f:tee(bc)
		f:load(pc)
		f:add()
		f:i32load8u(str.base)
		f:load(pc)
		f:call(echo)
		f:i32(1)
		f:add()
		f:store(pc)
		f:call(echo)
	end, ops.LoadNil, function(scopes)
		f:i32(NIL)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.LoadFalse, function(scopes)
		f:i32(FALSE)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.LoadTrue, function(scopes)
		f:i32(TRUE)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.CmpEq, function(scopes)
		f:i32(8)
		f:call(nthtmp)
		f:tee(c)
		f:i32(4)
		f:call(nthtmp)
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
					f:i32(GS.__eq)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.bool)
						f:store(meta_callty)
						f:i32(8)
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__eq)
						f:store(meta_key)
						f:i32(8)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
			end)
			f:i32(FALSE)
		end)
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.Add, function(scopes)
		-- pop x, y
		-- metacheck
		-- typecheck
		f:br(scopes.nop)
	end, ops.Idx, function(scopes)
		f:loop(function(loop)
			-- TODO Lua limits chains to 2000 length to try detect infinite loops
			f:i32(8)
			f:call(nthtmp)
			f:tee(a)
			f:i32load8u(obj.type)
			f:tee(b)
			f:i32(types.tbl)
			f:eq()
			f:iff(function()
				f:load(a)
				f:i32(4)
				f:call(nthtmp)
				f:call(tblget)
				f:tee(b)
				f:eqz()
				f:iff(function()
					f:load(a)
					f:i32load(tbl.meta)
					f:tee(b)
					f:iff(function()
						f:load(b)
						f:i32(GS.__index)
						f:call(tblget)
						f:tee(d)
						f:iff(function()
							f:load(d)
							f:i32load8u(obj.type)
							f:i32(types.functy)
							f:eq()
							f:iff(function()
								f:i32(calltypes.norm)
								f:store(meta_callty)
								f:i32(8)
								f:store(meta_retb)
								f:i32(1)
								f:store(meta_retc)
								f:i32(GS.__index)
								f:store(meta_key)
								f:i32(8)
								f:store(meta_off)
								f:br(scopes.meta)
							end)
							f:i32(8)
							f:load(d)
							f:call(setnthtmp)
							f:br(loop)
						end)
					end)
				end)
				f:load(b)
				f:i32(8)
				f:call(setnthtmp)
				f:call(tmppop)
				f:br(scopes.nop)
			end, function()
				f:load(b)
				f:i32(types.str)
				f:eq()
				f:iff(function()
					f:loadg(ostrmt)
					f:i32(8)
					f:call(setnthtmp)
					f:br(loop)
				end)
				f:unreachable()
			end)
		end)
	end, ops.Not, function(scopes)
		f:i32(TRUE)
		f:i32(FALSE)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:select()
		f:i32(4)
		f:call(setnthtmp)
		f:br(scopes.nop)
	end, ops.Len, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(b)
		f:i32(types.str)
		f:eq()
		f:iff(i32, function()
			f:load(a)
			f:i32load(str.len)
		end, function()
			f:load(b)
			f:i32(types.tbl)
			f:eq()
			f:iff(i32, function()
				f:load(a)
				f:i32load(tbl.meta)
				f:tee(b)
				f:iff(function()
					f:load(b)
					f:i32(GS.__len)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.norm)
						f:store(meta_callty)
						f:i32(4)
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__len)
						f:store(meta_key)
						f:i32(4)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
				f:load(a)
				f:i32load(tbl.len)
			end, function()
				f:unreachable()
			end)
		end)
		f:i64extendu()
		f:call(newi64)
		f:i32(4)
		f:call(setnthtmp)
		f:br(scopes.nop)
	end, ops.TblNew, function(scopes)
		f:call(newtbl)
		f:store(a)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:load(a)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, ops.TblSet, function(scopes)
		-- s[-2][s[-3]] = s[-1]
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(nthtmp)
		f:i32(12)
		f:call(nthtmp)
		f:call(tblset)

		f:call(tmppop)
		f:call(tmppop)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.TblAdd, function(scopes)
		-- rawset(s[-3], s[-2], s[-1])
		f:i32(12)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(nthtmp)
		f:call(tblset)

		f:call(tmppop)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.Return, function(scopes)
		f:load(framebase)
		f:i32load16s(dataframe.retb)
		f:load(base)
		f:add()
		f:store(meta_retb)

		f:block(function(skiptopopframe)
			f:load(framebase)
			f:i32load8u(dataframe.type)
			f:tee(meta_callty)
			f:i32(calltypes.init)
			f:eq()
			f:iff(function()
				-- if init: setup ret for resume call in caller coro
				f:loadg(oluastack)
				f:i32load(coro.caller)
				f:tee(a)
				f:iff(function()
					-- extend caller stack to fit our ret stack
					f:load(a)
					f:i32load(coro.stack)
					f:tee(a)
					f:load(a)
					f:i32load(buf.len)
					f:store(b)

					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:i32load(buf.len)
					f:load(base)
					f:sub()
					f:load(framebase)
					f:i32load16u(dataframe.frame)
					f:i32(objframe.sizeof)
					f:add()
					f:sub()

					f:call(extendvec)
					-- memcpy(caller.stack+b,
					---- d = oluastack.stack+base+frame+sizeof(frame),
					---- oluastack.stack.len-d)
					f:tee(a)
					f:i32load(buf.ptr)
					f:load(b)
					f:add()

					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:tee(b)
					f:i32load(buf.ptr)
					f:load(base)
					f:add()
					f:call(loadframebase)
					f:i32load16u(dataframe.frame)
					f:add()
					f:i32(dataframe.sizeof)
					f:add()
					f:tee(d)

					f:load(b)
					f:i32load(buf.len)
					f:load(d)
					f:sub()
					f:call(memcpy4)

					-- oluastack = oluastack.caller
					f:loadg(oluastack)
					f:i32load(coro.caller)
					f:storeg(oluastack)

					-- reload framebase for what follows's sake
					f:call(loadframebase)
					f:tee(framebase)
					f:i32load(dataframe.base)
					f:store(base)
				end, function()
					-- Return from main let's caller work things out
					f:i32(1)
					f:ret()
				end)
			end, function()
				f:load(meta_callty)
				f:i32(calltypes.bool)
				f:eq()
				f:iff(function()
					-- assume retc == 1
					-- b = stack.ptr
					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:i32load(buf.ptr)
					f:tee(b)
					f:load(meta_retb)
					f:add()

					-- return false if stack empty
					f:load(base)
					f:load(framebase)
					f:i32load16u(dataframe.frame)
					f:add()
					f:i32(objframe.sizeof)
					f:add()
					f:tee(a)
					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:i32load(buf.len)
					f:eq()
					f:iff(i32, function()
						f:i32(FALSE)
					end, function()
						-- *retb = pop()?TRUE:FALSE
						f:i32(TRUE)
						f:i32(FALSE)
						f:load(a)
						f:load(b)
						f:add()
						f:i32load(vec.base)
						f:i32(TRUE)
						f:geu()
						f:select()
					end)
					f:i32store(vec.base)

					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:load(meta_retb)
					f:i32(4)
					f:add()
					f:i32store(buf.len)

					f:br(skiptopopframe)
				end)
			end)

			-- TODO handle retc ~= stack size
			f:load(framebase)
			f:i32load16u(dataframe.frame)
			f:load(base)
			f:add()
			f:store(e)

			f:load(framebase)
			f:i32load16u(dataframe.retc)
			f:tee(c)
			f:i32(65535)
			f:eq()
			f:iff(function()
				f:load(e)
				f:loadg(oluastack)
				f:i32load(data.stack)
				f:i32load(buf.len)
				f:sub()
				f:i32(objframe.sizeof)
				f:sub()
				f:store(c)
			end)

			f:load(c)
			f:iff(function()
				f:i32(0)
				f:store(a)
				f:load(c)
				f:i32(2)
				f:shl()
				f:store(c)

				f:load(meta_callty)
				f:i32(calltypes.push)
				f:eq()
				f:iff(function()
					-- copy to tbl @ retb
					f:unreachable()
				end, function()
					-- copy to retb
					f:loop(function(loop)
						f:loadg(oluastack)
						f:i32load(buf.ptr)
						f:load(meta_retb)
						f:add()
						f:loadg(oluastack)
						f:i32load(buf.ptr)
						f:load(e)
						f:add()
						f:load(a)
						f:add()
						f:i32load(vec.base + objframe.sizeof)
						f:i32store(vec.base)

						f:load(a)
						f:i32(4)
						f:add()
						f:tee(a)
						f:load(c)
						f:ltu()
						f:brif(loop)
					end)
				end)
			end)

			-- call? blargh
		end)

		-- pop stack frame
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:load(a)
		f:i32load(buf.len)
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(b)
		f:i32store(buf.len)

		-- set pc, base
		f:load(a)
		f:i32load(buf.ptr)
		f:load(b)
		f:add()
		f:tee(framebase)
		f:i32load(dataframe.pc)
		f:store(pc)

		f:load(framebase)
		f:i32load(dataframe.base)
		f:store(base)

		f:br(scopes.nop)
	end, ops.Call, function(scopes)
		readArg()
		f:store(b)

		-- setup to reload bc after extendstr
		f:load(base)
		f:load(framebase)
		f:i32load16u(dataframe.frame)
		f:add()

		-- Setup to find current data frame after extendstr
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:i32load(buf.len)
		f:i32(dataframe.sizeof)
		f:sub()

		-- Setup for extendstr before loop
		f:loadg(oluastack)
		f:i32load(coro.data)
		readArg()
		f:tee(a)
		f:i32(dataframe.sizeof)
		f:mul()

		f:load(framebase)
		f:load(pc)
		f:load(a)
		f:i32(2)
		f:shl()
		f:add()
		f:i32store(dataframe.pc)

		f:i32(0)
		f:store(c)
		f:load(a)
		f:store(d)
		f:loop(function(loop)
			f:load(bc)
			f:load(pc)
			f:add()
			f:load(c)
			f:add()
			f:i32load(str.base)
			f:load(d)
			f:add()
			f:store(d)

			f:load(c)
			f:i32(1)
			f:add()
			f:tee(c)
			f:load(a)
			f:ltu()
			f:brif(loop)
		end)
		f:load(d)
		f:i32(2)
		f:shl()
		f:store(d)

		f:call(extendstr)
		f:i32load(buf.ptr)
		f:add()
		f:store(c)

		f:i32(objframe.sizeof)
		f:call(extendtmp)

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:add()
		f:i32load(objframe.bc)
		f:store(bc)

		-- a numcalls
		-- b retc
		-- set c to current dataframe base
		-- nthtmp(d) == last function of call chain
		-- set e to coro.stack + coro.stack.len - d

		f:load(c)
		f:i32(calltypes.norm)
		f:i32store8(dataframe.type + dataframe.sizeof)

		f:load(c)
		f:i32(0)
		f:i32store(dataframe.pc + dataframe.sizeof)

		f:load(c)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.len)
		f:load(d)
		f:sub()
		f:i32(8)
		f:sub()
		f:tee(base)
		f:i32store(dataframe.base + dataframe.sizeof)

		f:load(c)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:tee(e)
		f:load(base)
		f:add()
		f:i32load(vec.base - 4)
		f:i32load(functy.paramc)
		f:i32(2)
		f:shl()
		f:i32store16(dataframe.dotdotdot + dataframe.sizeof)

		f:load(c)
		f:i32(-4)
		f:i32store16(dataframe.retb + dataframe.sizeof)

		f:load(c)
		f:load(b)
		f:i32store16(dataframe.retc + dataframe.sizeof)

		--for b=1;b<a;b++
		--	c += dataframe.sizeof
		--	base += readArg4()+4
		f:i32(1)
		f:tee(b)
		f:load(a)
		f:ltu()
		f:iff(function()
			f:loop(function(loop)
				f:load(c)
				f:i32(dataframe.sizeof)
				f:add()
				f:tee(c)
				f:i32(0)
				f:i32store(dataframe.pc + dataframe.sizeof)

				f:load(c)
				readArg4()
				f:i32(4)
				f:add()
				f:load(base)
				f:add()
				f:tee(base)
				f:i32store(dataframe.base + dataframe.sizeof)

				f:load(c)
				f:load(e)
				f:load(base)
				f:add()
				f:i32load(vec.base - 4)
				f:i32load(functy.paramc)
				f:i32(2)
				f:shl()
				f:i32store16(dataframe.dotdotdot + dataframe.sizeof)

				f:load(c)
				f:i32(-4)
				f:i32store16(dataframe.retb + dataframe.sizeof)

				f:load(c)
				f:i32(-1)
				f:i32store16(dataframe.retc + dataframe.sizeof)

				f:load(b)
				f:i32(1)
				f:add()
				f:tee(b)
				f:load(a)
				f:ltu()
				f:brif(loop)
			end)
		end)

		f:load(c)
		readArg4()
		f:tee(b)
		f:i32store16(dataframe.locals + dataframe.sizeof)

		f:load(c)
		f:load(b)
		f:load(e)
		f:load(base)
		f:add()
		f:i32load(vec.base - 4)
		f:tee(b)
		f:i32load(functy.localc)
		f:i32(2)
		f:shl()
		f:add()
		f:i32store16(dataframe.frame + dataframe.sizeof)

		f:i32(0)
		f:store(pc)

		f:load(b)
		f:i32load(functy.bc)
		f:i32(objframe.tmpbc)
		f:call(setnthtmp)

		f:load(b)
		f:i32load(functy.consts)
		f:i32(objframe.tmpconsts)
		f:call(setnthtmp)

		f:load(b)
		f:i32load(functy.frees)
		f:i32(objframe.tmpfrees)
		f:call(setnthtmp)

		f:br(scopes.nop)
	end, ops.ReturnCall, function(scopes)
	-- pop stack frame, then call
		f:unreachable()
		f:br(scopes.nop)
	end, ops.LoadConst, function(scopes)
		f:load(objbase)
		f:i32load(objframe.consts)
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.LoadLocal, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:add()
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.StoreLocal, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:add()
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.LoadParam, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.StoreParam, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.Jif, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:brtable(scopes.pcp4, scopes[ops.Jmp])
	end, ops.JifNot, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:ltu()
		f:brtable(scopes.pcp4, scopes[ops.Jmp])
	end, ops.JifOrPop, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:brif(scopes[ops.Jmp])
		f:call(tmppop)
		f:br(scopes.pcp4)
	end, ops.JifNotOrPop, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:ltu()
		f:brif(scopes[ops.Jmp])
		f:call(tmppop)
		f:br(scopes.pcp4)
	end, ops.Pop, function(scopes)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.Neg, function(scopes)
		assert(types.int == 0 and types.float == 1 and types.tbl == 4 and types.str == 5)
		f:loop(function(loop)
			f:switch(function()
				f:i32(4)
				f:call(nthtmp)
				f:tee(a)
				f:i32load8u(obj.type)
			end, types.int, function()
				f:i64(0)
				f:load(a)
				f:i64load(num.val)
				f:sub()
				f:call(newi64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, types.float, function()
				f:load(a)
				f:f64load(num.val)
				f:neg()
				f:call(newf64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, types.tbl, function()
				f:load(a)
				f:i32load(tbl.meta)
				f:tee(b)
				f:iff(function()
					f:load(b)
					f:i32(GS.__unm)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.norm)
						f:store(meta_callty)
						f:i32(4)
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__unm)
						f:store(meta_key)
						f:i32(4)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
				f:unreachable()
			end, types.str, function()
				f:load(a)
				f:call(tonum)
				f:i32(4)
				f:call(setnthtmp)
				f:br(loop)
			end, 2, 3, -1)
			f:unreachable()
		end)
	end, ops.BNot, function(scopes)
		f:loop(function(loop)
			f:i32(4)
			f:call(nthtmp)
			f:tee(a)
			f:i32load8u(obj.type)
			f:tee(b)
			f:iff(function()
				f:load(a)
				f:i64load(num.base)
				f:i64(-1)
				f:xor()
				f:call(newi64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, function()
				f:load(b)
				f:i32(types.tbl)
				f:eq()
				f:iff(function()
					f:load(a)
					f:i32load(tbl.meta)
					f:tee(b)
					f:iff(function()
						f:load(b)
						f:i32(GS.__bnot)
						f:call(tblget)
						f:tee(d)
						f:iff(function()
							f:i32(calltypes.norm)
							f:store(meta_callty)
							f:i32(4)
							f:store(meta_retb)
							f:i32(1)
							f:store(meta_retc)
							f:i32(GS.__bnot)
							f:store(meta_key)
							f:i32(4)
							f:store(meta_off)
							f:br(scopes.meta)
						end)
					end)
				end, function()
					f:load(a)
					f:call(toint)
					f:i32(4)
					f:call(setnthtmp)
					f:br(loop)
				end)
			end)
			f:unreachable()
		end)
	end, ops.CmpGe, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(setnthtmp)
		f:i32(8)
		f:call(setnthtmp)
		f:br(scopes[ops.CmpLt])
	end, ops.CmpGt, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(setnthtmp)
		f:i32(8)
		f:call(setnthtmp)
		f:br(scopes[ops.CmpLe])
	end, ops.CmpLe, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(c)
		f:i32(8)
		f:call(nthtmp)
		f:tee(b)
		f:i32load8u(obj.type)
		f:tee(d)
		f:i32(4)
		f:shl()
		f:bor()
		f:tee(e)
		assert(types.int == 0)
		f:eqz()
		f:iff(i32, function()
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i64load(num.val)
			f:load(b)
			f:i64load(num.val)
			f:les()
			f:select()
		end, function()
			f:load(e)
			f:i32(types.float|types.float<<4)
			f:eq()
			f:iff(i32, function()
				f:i32(TRUE)
				f:i32(FALSE)
				f:load(a)
				f:f64load(num.val)
				f:load(b)
				f:f64load(num.val)
				f:le()
				f:select()
			end, function()
				f:load(e)
				f:i32(types.str|types.str<<4)
				f:eq()
				f:iff(i32, function()
					f:i32(TRUE)
					f:i32(FALSE)
					f:load(a)
					f:load(b)
					f:call(strcmp)
					f:i32(-1)
					f:eq()
					f:select()
				end, function()
					f:load(e)
					f:i32(types.int|types.float<<4)
					f:eq()
					f:iff(i32, function()
						f:i32(TRUE)
						f:i32(FALSE)
						f:load(a)
						f:i64load(num.base)
						f:f64converts()
						f:load(b)
						f:f64load(num.base)
						f:le()
						f:select()
					end, function()
						f:load(e)
						f:i32(types.float|types.int<<4)
						f:eq()
						f:iff(i32, function()
							f:i32(TRUE)
							f:i32(FALSE)
							f:load(a)
							f:i64load(num.base)
							f:f64converts()
							f:load(b)
							f:f64load(num.base)
							f:le()
							f:select()
						end, function()
							-- TODO metamethod stuff
							f:unreachable()
						end)
					end)
				end)
			end)
		end)
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.CmpLt, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(c)
		f:i32(8)
		f:call(nthtmp)
		f:tee(b)
		f:i32load8u(obj.type)
		f:tee(d)
		f:i32(4)
		f:shl()
		f:bor()
		f:tee(e)
		assert(types.int == 0)
		f:eqz()
		f:iff(i32, function()
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i64load(num.val)
			f:load(b)
			f:i64load(num.val)
			f:lts()
			f:select()
		end, function()
			f:load(e)
			f:i32(types.float|types.float<<4)
			f:eq()
			f:iff(i32, function()
				f:i32(TRUE)
				f:i32(FALSE)
				f:load(a)
				f:f64load(num.val)
				f:load(b)
				f:f64load(num.val)
				f:lt()
				f:select()
			end, function()
				f:load(e)
				f:i32(types.str|types.str<<4)
				f:eq()
				f:iff(i32, function()
					f:i32(TRUE)
					f:i32(FALSE)
					f:load(a)
					f:load(b)
					f:call(strcmp)
					f:i32(-1)
					f:eq()
					f:select()
				end, function()
					f:load(e)
					f:i32(types.int|types.float<<4)
					f:eq()
					f:iff(i32, function()
						f:i32(TRUE)
						f:i32(FALSE)
						f:load(a)
						f:i64load(num.base)
						f:f64converts()
						f:load(b)
						f:f64load(num.base)
						f:lt()
						f:select()
					end, function()
						f:load(e)
						f:i32(types.float|types.int<<4)
						f:eq()
						f:iff(i32, function()
							f:i32(TRUE)
							f:i32(FALSE)
							f:load(a)
							f:i64load(num.base)
							f:f64converts()
							f:load(b)
							f:f64load(num.base)
							f:lt()
							f:select()
						end, function()
							-- TODO metamethod stuff
							f:unreachable()
						end)
					end)
				end)
			end)
		end)
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.LoadVarg, function(scopes)
		f:i32(0)
		f:store(a)
		readArg4()
		f:store(b)
		f:loop(function(loop)
			-- TODO handle nils when b > dotdotdot.len
			f:load(a)
			f:load(b)
			f:eq()
			f:brif(scopes.nop)

			f:load(framebase)
			f:i32load16u(dataframe.dotdotdot)
			f:load(base)
			f:add()
			f:loadg(oluastack)
			f:i32load(coro.stack)
			f:i32load(buf.ptr)
			f:add()
			f:load(a)
			f:add()
			f:i32load(vec.base)
			f:call(tmppush)

			f:load(a)
			f:i32(4)
			f:add()
			f:store(a)
			f:br(loop)
		end)
	end, ops.Syscall, function(scopes)
		f:switch(function()
			f:load(bc)
			f:load(pc)
			f:add()
			f:i32load8u(str.base)
			f:load(pc)
			f:i32(1)
			f:add()
			f:store(pc)
		end, 0, function()
			f:call(std_pcall)
			f:br(scopes.nop)
		end, 1, function()
			f:call(std_select)
			f:br(scopes.nop)
		end, 2, function()
			f:call(coro_status)
			f:br(scopes.nop)
		end, 3, function()
			f:call(coro_running)
			f:br(scopes.nop)
		end, 4, function()
			f:call(debug_getmetatable)
			f:br(scopes.nop)
		end, 5, function()
			f:call(debug_setmetatable)
			f:br(scopes.nop)
		end)
		f:call(coro_create)
		f:br(scopes.nop)
	end, ops.Jmp, function(scopes)
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:store(pc)
		f:br(scopes.nop)
	end, ops.LoadFreeBox, function(scopes)
		f:load(objbase)
		f:i32load(objframe.frees)
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.StoreFreeBox, function(scopes)
		f:load(objbase)
		f:i32load(objframe.frees)
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.LoadParamBox, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.StoreParamBox, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.BoxParam, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg4()
		f:tee(b)
		f:add()
		f:i32load(vec.base)
		f:call(newvec1)
		f:store(a)

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		f:load(b)
		f:add()
		f:load(a)
		f:i32store(vec.base)
		f:br(scopes.nop)
	end, ops.BoxLocal, function(scopes)
		f:i32(NIL)
		f:call(newvec1)
		f:store(a)

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:add()
		f:load(a)
		f:i32store(vec.base)
		f:br(scopes.nop)
	end, ops.LoadLocalBox, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:add()
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.StoreLocalBox, function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:load(base)
		f:add()
		readArg4()
		f:add()
		f:add()
		f:i32load(vec.base)
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:call(tmppop)
		f:br(scopes.nop)
	end, ops.GetMeth, function(scopes)
		f:unreachable()
	end, ops.AppendCall, function(scopes)
		f:unreachable()
	end, ops.CallVarg, function(scopes)
		f:unreachable()
	end, ops.ReturnCallVarg, function(scopes)
		f:unreachable()
	end, ops.AppendCallVarg, function(scopes)
		f:unreachable()
	end, ops.ReturnVarg, function(scopes)
		f:unreachable()
	end, ops.AppendVarg, function(scopes)
		readArg4()
		f:tee(a)
		f:i32(4)
		f:add()
		f:store(c)

		f:i64(1)
		f:store(a64)

		f:load(a)
		f:iff(function()
			f:loop(function(loop)
				f:load(a64)
				f:call(newi64)
				f:store(b)

				f:load(c)
				f:call(nthtmp)
				f:load(b)
				f:load(a)
				f:call(nthtmp)
				f:call(tblset)

				f:load(a)
				f:i32(4)
				f:sub()
				f:tee(a)
				f:brif(loop)
			end)
			f:loadg(oluastack)
			f:i32load(coro.stack)
			f:tee(a)
			f:load(a)
			f:i32load(buf.len)
			f:load(c)
			f:i32(4)
			f:sub()
			f:sub()
			f:i32store(buf.len)
		end)

		f:i32(0)
		f:store(c)

		f:call(loadframebase)
		f:tee(framebase)
		f:i32load16u(dataframe.dotdotdot)
		f:load(base)
		f:add()
		f:store(d)

		f:load(framebase)
		f:i32load16u(dataframe.locals)
		f:load(base)
		f:add()
		f:tee(e)

		f:load(d)
		f:gtu()
		f:iff(function()
			f:loop(function(loop)
				f:load(a64)
				f:call(newi64)
				f:store(b)

				f:i32(4)
				f:call(nthtmp)
				f:load(b)
				f:loadg(oluastack)
				f:i32load(coro.data)
				f:i32load(buf.ptr)
				f:load(d)
				f:add()
				f:i32load(vec.base)
				f:call(tblset)

				f:load(e)
				f:load(d)
				f:i32(4)
				f:add()
				f:tee(d)
				f:gtu()
				f:brif(loop)
			end)
		end)

		f:br(scopes.nop)
	end, ops.Sub, function(scopes)
		f:unreachable()
	end, ops.Mul, function(scopes)
		f:unreachable()
	end, ops.Div, function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(b)
		f:i32load8u(obj.type)
		f:i32(8)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:i32(4)
		f:shl()
		f:bor()
		f:tee(c)
		f:i32(17)
		f:eq()
		f:iff(function()
			f:load(a)
			f:f64load(num.base)
			f:load(b)
			f:f64load(num.base)
			f:div()
			f:call(newf64)
			f:call(tmppop)
			f:i32(4)
			f:call(setnthtmp)
		end, function()
			f:load(c)
			f:iff(function()
				-- TODO UNWIND
				f:unreachable()
			end, function()
				f:load(a)
				f:i64load(num.base)
				f:f64converts()
				f:load(b)
				f:i64load(num.base)
				f:f64converts()
				f:div()
				f:call(newf64)
				f:call(tmppop)
				f:i32(4)
				f:call(setnthtmp)
			end)
		end)
		f:br(scopes.nop)
	end, ops.IDiv, function(scopes)
		f:unreachable()
	end, ops.Pow, function(scopes)
		f:unreachable()
	end, ops.Mod, function(scopes)
		f:unreachable()
	end, ops.BAnd, function(scopes)
		f:unreachable()
	end, ops.BXor, function(scopes)
		f:unreachable()
	end, ops.BOr, function(scopes)
		f:unreachable()
	end, ops.Shr, function(scopes)
		f:unreachable()
	end, ops.Shl, function(scopes)
		f:unreachable()
	end, ops.Concat, function(scopes)
		f:unreachable()
	end, ops.LoadFree, function(scopes)
		f:load(objbase)
		f:i32load(objframe.frees)
		readArg4()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, ops.Append, function(scopes)
		-- invariant: arg > 0
		-- TODO implement table arrays, then this becomes a memcpy4
		readArg4()
		f:tee(a)
		f:i32(4)
		f:add()
		f:store(c)

		f:i64(1)
		f:store(a64)

		f:loop(function(loop)
			f:load(a64)
			f:call(newi64)
			f:store(b)

			f:load(c)
			f:call(nthtmp)
			f:load(b)
			f:load(a)
			f:call(nthtmp)
			f:call(tblset)

			f:load(a)
			f:i32(4)
			f:sub()
			f:tee(a)
			f:brif(loop)
		end)

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:load(a)
		f:i32load(buf.len)
		f:load(c)
		f:i32(4)
		f:sub()
		f:sub()
		f:i32store(buf.len)

		f:br(scopes.nop)
	end, 'meta', function(scopes)
		-- TODO fill in nils when paramc > metaparamc
		-- d is func
		-- push objframe
		-- a, c, e = stack.len, localc*4, paramc*4
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(b)
		f:i32load(buf.len)
		f:tee(a)
		f:load(meta_retb)
		f:sub()
		f:store(base)

		f:load(b)
		f:i32(objframe.sizeof)
		f:load(d)
		f:i32load(functy.localc)
		f:i32(2)
		f:shl()
		f:tee(b)
		f:add()
		f:load(d)
		f:i32load(functy.paramc)
		f:i32(2)
		f:shl()
		f:tee(e)
		f:add()
		f:call(extendvec)

		-- writeobjframe
		f:tee(c)
		f:i32load(buf.ptr)
		f:load(c)
		f:i32load(buf.len)
		f:add()
		f:tee(c)
		assert(functy.consts == functy.bc + 4)
		assert(objframe.consts == objframe.bc + 4)

		-- reload metafunc
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(d)
		f:i32load(buf.ptr)
		f:load(d)
		f:i32load(buf.len)
		f:add()
		f:load(meta_off)
		f:sub()
		f:i32load(vec.base)
		f:store(d)

		f:load(meta_key)
		f:iff(function()
			f:load(d)
			f:i32load(tbl.meta)
			f:load(meta_key)
			f:call(tblget)
			f:store(d)
		end)

		f:load(d)
		f:i64load(functy.bc)
		f:i64store(objframe.bc)

		f:load(c)
		f:load(d)
		f:i32load(functy.frees)
		f:i32store(objframe.frees)

		f:load(d)
		f:i32load(functy.paramc)

		-- push dataframe
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:i32(dataframe.sizeof)
		f:call(extendstr)

		-- write dataframe
		f:tee(framebase)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load(buf.len)
		f:add()
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(framebase)
		f:load(meta_callty)
		f:i32store8(dataframe.type)

		f:load(framebase)
		f:i32(0)
		f:i32store(dataframe.pc)

		f:load(framebase)
		f:load(base)
		f:i32store(dataframe.base)

		f:load(framebase)
		f:load(e)
		f:i32store16(dataframe.dotdotdot)

		f:load(framebase)
		f:i32(0)
		f:i32store16(dataframe.retb)

		f:load(framebase)
		f:load(meta_retc)
		f:i32store16(dataframe.retc)

		f:load(framebase)
		f:load(a)
		f:load(base)
		f:sub()
		f:tee(a)
		f:i32store16(dataframe.locals)

		f:load(framebase)
		f:load(a)
		f:load(c)
		f:add()
		f:i32store16(dataframe.frame)

		f:br(scopes.nop)
	end, 'pcp4', function()
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
	end, ops.Nop, function() f:unreachable() end, 'nop')

	-- check whether to yield (for now we'll yield after each instruction)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:load(pc)
	f:i32store(dataframe.pc)

	f:i32(0)
end))
