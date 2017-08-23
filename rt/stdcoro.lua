coro_create = func(function(f)
	
end)

coro_running = func(function(f)
	-- TODO discard parameters
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:loadg(oluastack)
	f:call(pushvec)
	f:i32(TRUE)
	f:i32(FALSE)
	f:loadg(oluastack)
	f:i32load(coro.caller)
	f:select()
	f:call(pushvec)
	f:drop()
end)

coro_status = func(function(f)
	local a = f:locals(i32)

	f:i32(4)
	f:call(nthtmp)
	f:tee(a)
	f:i32load8u(obj.type)
	f:i32(types.coro)
	f:eq()
	f:iff(i32, function(res)
		f:switch(function()
			f:load(a)
			f:i32load(coro.state)
		end, corostate.dead, function()
			f:i32(GS.dead)
			f:br(res)
		end, corostate.norm, function()
			f:i32(GS.normal)
			f:br(res)
		end, corostate.live, function()
			f:i32(GS.running)
			f:br(res)
		end, corostate.wait)
		f:i32(GS.suspended)
	end, function()
		-- error
		f:unreachable()
	end)
	f:i32(4)
	f:call(setnthtmp)
end)

