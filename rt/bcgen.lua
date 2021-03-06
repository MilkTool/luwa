local lex = require 'lex'
local ast = require 'ast'
local bc = require 'bc'

local function nop()
end

local asmmeta = {}
local asmmt = { __index = asmmeta }
local function Assembler()
	return setmetatable({
		params = {},
		locals = {},
		frees = {},
		isdotdotdot = false,
		scopes = nil,
		breaks = nil,
		consts = {},
		labels = {},
		gotos = {},
		labelscope = {},
		gotoscope = {},
		funcs = {},
		namety = {},
		rconsts = {
			integer = {},
			float = {},
			string = {},
			table = {},
		},
		names = {},
		bc = {},
	}, asmmt)
end

function asmmeta:push(op, ...)
	self.bc[#self.bc+1] = assert(op)
	for i=1,select('#', ...) do
		self:patch(#self.bc+1, (select(i, ...)))
	end
end
function asmmeta:patch(idx, x)
	self.bc[idx],self.bc[idx+1],self.bc[idx+2],self.bc[idx+3] = string.byte(string.pack('<i4', assert(x)), 1, 4)
end
function asmmeta:breakscope(f)
	self.breaks = { prev = self.breaks }
	f(self)
	for i=1,#self.breaks do
		self:patch(self.breaks[i], #self.bc)
	end
	self.breaks = self.breaks.prev
end
function asmmeta:scope(f)
	self.scopes = setmetatable({ prev = self.scopes }, { __index = self.scopes })
	f()
	for i=1, #self.scopes do
		local name = self.scopes[i]
		self.names[name] = self.names[name].prev
	end
	self.scopes = self.scopes.prev
end
function asmmeta:const(c)
	local ty = math.type(c) or type(c)
	local n = self.rconsts[ty][c]
	if not n then
		n = #self.consts
		self.consts[n+1] = c
		self.rconsts[ty][c] = n
	end
	return n
end

function asmmeta:name(n, isparam)
	assert(type(n) == 'string')
	local prevscope = self.names[n]
	local paramidx
	if isparam then
		paramidx = #self.params
	end
	local newscope = { prev = prevscope, func = self, isparam = paramidx }
	if isparam then
		self.params[#self.params+1] = newscope
	end
	self.scopes[#self.scopes+1] = n
	self.names[n] = newscope
	return newscope
end

function asmmeta:usename(node)
	local name = self.names[node.arg]
	if name then
		self.namety[node] = name
	else
		name = assert(self.names._ENV)
		self.namety[node] = { env = name }
	end
	if name.func ~= self then
		if name.free then
			name.free[self] = true
		else
			name.free = { [self] = true }
		end
	end
end

local namety_loads = {
	Param = bc.LoadParam,
	Local = bc.LoadLocal,
	ParamBox = bc.LoadParamBox,
	LocalBox = bc.LoadLocalBox,
	FreeBox = bc.LoadFreeBox,
	Env = bc.Idx,
}
local namety_stores = {
	Param = bc.StoreParam,
	Local = bc.StoreLocal,
	ParamBox = bc.StoreParamBox,
	LocalBox = bc.StoreLocalBox,
	FreeBox = bc.StoreFreeBox,
	Env = bc.TblSet,
}
local function idxtbl(tbl, namety)
	local idx = #tbl
	tbl[namety] = idx
	tbl[idx+1] = namety
	return idx
end
function asmmeta:nameidx(namety)
	assert(namety)
	if namety.isparam then
		return namety.isparam
	elseif namety.func ~= self then
		return self.frees[namety] or idxtbl(self.frees, namety)
	else
		return self.locals[namety] or idxtbl(self.locals, namety)
	end
end
function asmmeta:opnamety(ops, name, namety)
	local idx = self:nameidx(namety)
	if namety.env then
		self:opnamety(namety_loads, nil, namety.env)
		self:push(bc.LoadConst, self:const(name.arg))
		self:push(ops.Env)
	elseif namety.free then
		if namety.func ~= self then
			self:push(ops.FreeBox, idx)
		elseif namety.isparam then
			self:push(ops.ParamBox, idx)
		else
			self:push(ops.LocalBox, idx)
		end
	elseif namety.isparam then
		self:push(ops.Param, idx)
	else
		self:push(ops.Local, idx)
	end
end
function asmmeta:loadname(name)
	return self:opnamety(namety_loads, name, self.namety[name])
end
function asmmeta:storename(name)
	return self:opnamety(namety_stores, name, self.namety[name])
end

local nextNode = {}
for k,ty in pairs(ast) do
	nextNode[ty] = function(node, i)
		while i <= #node do
			local child = node[i]
			i = i + 1
			if (child.type & 31) == ty then
				return i, child
			end
		end
	end
end

local function hasToken(node, ty)
	for i=1, #node do
		local child = node[i]
		if child.type == -1 and child.val == ty then
			return true
		end
	end
	return false
end

local function nextMask(ty)
	return function(node, i)
		while i <= #node do
			local child = node[i]
			i = i + 1
			if child.type == -1 and child.val == ty then
				return i, child
			end
		end
	end
end
local nextString = nextMask(lex._string)
local nextNumber = nextMask(lex._number)
local nextIdent = nextMask(lex._ident)

local function selectNodes(node, ty)
	return nextNode[ty], node, 1
end
local function selectNode(node, ty)
	local i, n = nextNode[ty](node, 1)
	return n
end

local function selectIdents(node)
	return nextIdent, node, 1
end
local function selectIdent(node)
	local i, n = nextIdent(node, 1)
	return n
end

local unOps = { bc.Neg, bc.Not, bc.Len, bc.BNot }
local binOps = { bc.Add, bc.Sub, bc.Mul, bc.Div, bc.IDiv, bc.Pow, bc.Mod,
	bc.BAnd, bc.BXor, bc.BOr, bc.Shr, bc.Shl, bc.Concat,
	bc.CmpLt, bc.CmpLe, bc.CmpGt, bc.CmpGe, bc.CmpEq }
local scopeStatSwitch, emitStatSwitch, emitValueSwitch, emitFieldSwitch, visitScope, emitScope

local function singleNode(self, node, ty, fn, ...)
	local sn = selectNode(node, ty)
	if sn then
		return fn(self, sn, ...)
	end
end
local function multiNodes(self, node, ty, fn, ...)
	for i, node in selectNodes(node, ty) do
		fn(self, node, ...)
	end
end
local function scopeNode(self, node, ty)
	return singleNode(self, node, ty, visitScope[ty])
end
local function emitNode(self, node, ty, ...)
	return singleNode(self, node, ty, visitEmit[ty], ...)
end
local function scopeNodes(self, node, ty, ...)
	return multiNodes(self, node, ty, visitScope[ty], ...)
end
local function emitNodes(self, node, ty, ...)
	return multiNodes(self, node, ty, visitEmit[ty], ...)
end

local ExpValue = ast.Exp+64
local precedenceTable = {7, 7, 8, 8, 8, 9, 8, 5, 4, 3, 6, 6, 2, 1, 1, 1, 1, 1, 1}
local function precedence(node)
	if (node.type&31) == ast.Binop then
		return precedenceTable[node.type >> 5]
	else
		return 0
	end
end
local function shunt(node)
	return coroutine.wrap(function()
		local ops = {}
		while node.type == ExpValue and #node == 3 do
			local lson, op, rson = table.unpack(node)
			coroutine.yield(lson)
			while #ops > 0 do
				local oprec = precedence(op)
				if precedence(ops[#ops]) < oprec or oprec == 9 then
					break
				end
				coroutine.yield(ops[#ops])
				ops[#ops] = nil
			end
			ops[#ops+1] = op
			node = rson
		end
		if node.type == ExpValue then
			coroutine.yield(selectNode(node, ast.Value))
		else
			coroutine.yield(node)
		end
		for i=#ops, 1, -1 do
			coroutine.yield(ops[i])
		end
	end)
end

scopeStatSwitch = {
	function(self, node) -- 1 vars=exps
		scopeNodes(self, node, ast.ExpOr)
		scopeNodes(self, node, ast.Var)
	end,
	function(self, node) -- 2 call
		scopeNode(self, node, ast.Prefix)
		scopeNodes(self, node, ast.Suffix)
		scopeNode(self, node, ast.Args)
	end,
	function(self, node, block) -- 3 label
		local name = selectIdent(node).arg
		if self.labelscope[name] then
			error('Duplicate label', name)
		end
		if block[#block] == node then
			self.labelscope[name] = self.scopes.prev
		else
			self.labelscope[name] = self.scopes
		end
	end,
	nop, -- 4 break
	function(self, node) -- 5 goto
		self.gotoscope[node] = self.scopes
	end,
	function(self, node) -- 6 do-end
		self:scope(function()
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 7 while
		self:scope(function()
			scopeNode(self, node, ast.ExpOr)
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 8 repeat
		self:scope(function()
			scopeNode(self, node, ast.Block)
			scopeNode(self, node, ast.ExpOr)
		end)
	end,
	function(self, node) -- 9 if
		scopeNodes(self, node, ast.ExpOr)
		for i, block in selectNodes(node, ast.Block) do
			self:scope(function()
				visitScope[ast.Block](self, block)
			end)
		end
	end,
	function(self, node) -- 10 for
		self:scope(function()
			scopeNodes(self, node, ast.ExpOr)
			local name = selectIdent(node)
			self:name(name.arg)
			self:usename(name)
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 11 generic for
		self:scope(function()
			scopeNodes(self, node, ast.ExpOr)
			for i, name in selectIdents(node) do
				self:name(name.arg)
				self:usename(name)
			end
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 12 func
		self:usename(selectIdent(node))
		scopeNode(self, node, ast.Funcbody, hasToken(node, lex._colon))
	end,
	function(self, node) -- 13 local func
		local name = selectIdent(node)
		self:name(name.arg)
		self:usename(name)
		scopeNode(self, node, ast.Funcbody)
	end,
	function(self, node) -- 14 locals=exps
		scopeNodes(self, node, ast.ExpOr)
		for i, name in selectIdents(node) do
			self:name(name.arg)
			self:usename(name)
		end
	end,
}
local function emitCall(self, node, outputs)
	local methname = selectIdent(node)
	if methname then
		local temp = idxtbl(self.locals, methname)
		self:push(bc.StoreLocal, temp)
		self:push(bc.LoadLocal, temp)
		self:push(bc.LoadConst, self:const(methname.arg))
		self:push(bc.Idx)
		self:push(bc.LoadLocal, temp)
	end
	return emitNode(self, node, ast.Args, outputs)
end
local function emitExplist(self, node, outputs)
	local n, lastv = 0
	for i, v in selectNodes(node, ast.ExpOr) do
		if lastv then
			if outputs == 0 then
				visitEmit[ast.ExpOr](self, lastv, 0)
			else
				if outputs ~= -1 then
					outputs = outputs - 1
				end
				n = n + visitEmit[ast.ExpOr](self, lastv, 1)
			end
		end
		lastv = v
	end
	if lastv then
		return n, visitEmit[ast.ExpOr](self, lastv, outputs)
	else
		return n, 0
	end
end
emitStatSwitch = {
	function(self, node) -- 1 vars=exps
		local vars = {}
		for i, v in selectNodes(node, ast.Var) do
			vars[#vars+1] = v
		end
		emitExplist(self, node, #vars)
		-- TODO evaluate in order
		for i=#vars,1,-1 do
			visitEmit[ast.Var](self, vars[i], false)
		end
	end,
	function(self, node) -- 2 call
		emitNode(self, node, ast.Prefix)
		emitNodes(self, node, ast.Suffix, function(node)
			emitCall(self, node, 0)
		end)
	end,
	function(self, node) -- 3 label
		local name = selectIdent(node)
		self.labels[name.arg] = #self.bc
	end,
	function(self, node) -- 4 break
		assert(self.breaks, "break outside of loop")
		self.breaks[#self.breaks+1] = #self.bc+2
		self:push(bc.Jmp, 0)
	end,
	function(self, node) -- 5 goto
		local name = selectIdent(node)
		local namei = name.arg
		local gotosc = self.gotoscope[node]
		local labelsc = self.labelscope[namei]
		while gotosc ~= labelsc do
			gotosc = gotosc.prev
			if not gotosc then
				error('Jmp out of scope', nami)
			end
		end
		self.gotos[#self.bc+2] = namei
		self:push(bc.Jmp, 0)
	end,
	function(self, node) -- 6 do-end
		return emitNode(self, node, ast.Block)
	end,
	function(self, node) -- 7 while
		self:breakscope(function()
			local soc = #self.bc
			emitNode(self, node, ast.ExpOr, 1)
			local jmp = #self.bc+2
			self:push(bc.JifNot, 0)
			emitNode(self, node, ast.Block)
			self:push(bc.Jmp, soc)
			self:patch(jmp, #self.bc)
		end)
	end,
	function(self, node) -- 8 repeat
		self:breakscope(function()
			local soc = #self.bc
			emitNode(self, node, ast.Block)
			emitNode(self, node, ast.ExpOr, 1)
			self:push(bc.JifNot, soc)
		end)
	end,
	function(self, node) -- 9 if
		local eob, condbr = {}
		for i=1, #node do
			local child = node[i]
			local ty = child.type&31
			if ty == ast.ExpOr then
				visitEmit[ast.ExpOr](self, child, 1)
				condbr = #self.bc+2
				self:push(bc.JifNot, 0)
			elseif ty == ast.Block then
				visitEmit[ast.Block](self, child)
				if i > 2 then
					eob[#eob+1] = #self.bc+2
					self:push(bc.Jmp, 0)
				end
				if condbr then
					self:patch(condbr, #self.bc)
					condbr = nil
				end
			end
		end
		for i=1,#eob do
			self:patch(eob[i], #self.bc)
		end
	end,
	function(self, node) -- 10 for
		-- TODO float increment causes initial value to be a float
		local exps=0
		for i, n in selectNodes(node, ast.ExpOr) do
			visitEmit[ast.ExpOr](self, n, 1)
			exps = exps+1
		end
		if exps == 2 then
			self:push(bc.LoadConst, self:const(1))
		end
		local tempi = idxtbl(self.locals, {})
		local tempc = idxtbl(self.locals, {})
		local temps = idxtbl(self.locals, {})
		local temptemp = idxtbl(self.locals, {})
		self:push(bc.StoreLocal, temps)
		self:push(bc.StoreLocal, tempc)
		self:push(bc.StoreLocal, tempi)
		self:push(bc.LoadLocal, temps)
		self:push(bc.LoadConst, self:const(0))
		self:push(bc.CmpGe)
		self:push(bc.StoreLocal, temptemp)
		local incrdecr = #self.bc
		self:push(bc.LoadLocal, tempi)
		self:push(bc.LoadLocal, tempc)
		self:push(bc.LoadLocal, temptemp)
		local cmp0 = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.CmpLt)
		local cmp1 = #self.bc+2
		self:push(bc.Jmp, 0)
		self:push(bc.CmpGt)
		self:patch(cmp0, #self.bc)
		self:patch(cmp1, #self.bc)
		local forxit = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.LoadLocal, tempi)
		self:storename(selectIdent(node))
		self:breakscope(function()
			emitNode(self, node, ast.Block)
			self:push(bc.LoadLocal, tempi)
			self:push(bc.LoadLocal, temps)
			self:push(bc.Add)
			self:push(bc.StoreLocal, tempi)
			self:push(bc.Jmp, incrdecr)
		end)
		self:patch(forxit, #self.bc)
	end,
	function(self, node) -- 11 generic for
		emitExplist(self, node, 3)
		local tempf = idxtbl(self.locals, {})
		local temps = idxtbl(self.locals, {})
		local tempv = idxtbl(self.locals, {})
		self:push(bc.StoreLocal, tempv)
		self:push(bc.StoreLocal, temps)
		self:push(bc.StoreLocal, tempf)
		local begfor = #self.bc
		self:push(bc.LoadLocal, tempf)
		self:push(bc.LoadLocal, temps)
		self:push(bc.LoadLocal, tempv)
		local vars = {}
		for i, v in selectIdents(node) do
			vars[#vars+1] = v
		end
		self:push(bc.Call, #vars, 1, 1)
		for i=#vars,2,-1 do
			self:storename(vars[i])
		end
		self:push(bc.StoreLocal, tempv)
		self:push(bc.LoadLocal, tempv)
		self:push(bc.LoadNil)
		self:push(bc.CmpEq)
		local forxit = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.LoadLocal, tempv)
		self:storename(vars[1])
		self:breakscope(function()
			emitNode(self, node, ast.Block)
			self:push(bc.Jmp, begfor)
		end)
		self:patch(forxit, #self.bc)
	end,
	function(self, node) -- 12 func
		emitNode(self, node, ast.Funcbody)
		local first, nlast = true
		for i, name in selectIdents(node) do
			if nlast then
				if first then
					self:loadname(nlast)
					first = false
				else
					self:push(bc.LoadConst, self:const(nlast.arg))
					self:push(bc.TblGet)
				end
			end
			nlast = name
		end
		if first then
			self:storename(nlast)
		else
			self:push(bc.LoadConst, self:const(nlast.arg))
			self:push(bc.TblSet)
		end
	end,
	function(self, node) -- 13 local func
		emitNode(self, node, ast.Funcbody)
		self:storename(selectIdent(node))
	end,
	function(self, node) -- 14 locals=exps
		local vars = {}
		for i, v in selectIdents(node) do
			vars[#vars+1] = v
		end
		emitExplist(self, node, #vars)
		for i=#vars,1,-1 do
			self:storename(vars[i])
		end
	end,
}
local function emit0(fn)
	return function(self, node, outputs)
		if outputs == 0 then
			return 0
		else
			return fn(self, node, outputs)
		end
	end
end
emitValueSwitch = {
	emit0(function(self, node, outputs) -- 1 nil
		self:push(bc.LoadNil)
		return 1
	end),
	emit0(function(self, node, outputs) -- 2 false
		self:push(bc.LoadFalse)
		return 1
	end),
	emit0(function(self, node, outputs) -- 3 true
		self:push(bc.LoadTrue)
		return 1
	end),
	emit0(function(self, node, outputs) -- 4 num
		local i, val = nextNumber(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		return 1
	end),
	emit0(function(self, node, outputs) -- 5 str
		local i, val = nextString(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		return 1
	end),
	emit0(function(self, node, outputs) -- 6 ...
		if outputs == -1 then
			return { varg = true }
		else
			self:push(bc.LoadVarg, outputs)
			return outputs
		end
	end),
	emit0(function(self, node, outputs) -- 7 Funcbody
		emitNode(self, node, ast.Funcbody)
		return 1
	end),
	function(self, node, outputs) -- 8 Table
		emitNode(self, node, ast.Table)
		return 1
	end,
	function(self, node, outputs) -- 9 Prefix Suffix?
		emitNode(self, node, ast.Prefix)
		local res = 1
		emitNodes(self, node, ast.Suffix, function(node)
			if node.type >> 5 == 1 then
				res = emitCall(self, node, outputs)
			else
				emitNode(self, node, ast.Index, true)
			end
		end)
		return res
	end,
}
emitFieldSwitch = {
	function(self, node) -- 1 [exp] = exp
		local f, obj, idx = selectNodes(node, ast.ExpOr)
		local i, key = f(obj, idx)
		visitEmit[ast.ExpOr](self, key, 1)
		local i, val = f(obj, i)
		visitEmit[ast.ExpOr](self, val, 1)
		self:push(bc.TblAdd)
	end,
	function(self, node) -- 2 name = exp
		local i, val = nextIdent(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		emitNode(self, node, ast.ExpOr, 1)
		self:push(bc.TblAdd)
	end,
	function(self, node, ary) -- 3 exp
		ary[#ary+1] = node
	end
}
visitScope = {
	[ast.Block] = function(self, node)
		scopeNodes(self, node, ast.Stat, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Stat] = function(self, node, block)
		return scopeStatSwitch[node.type >> 5](self, node, block)
	end,
	[ast.Var] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.Prefix)
			scopeNodes(self, node, ast.Suffix)
			scopeNode(self, node, ast.Index)
		else
			self:usename(selectIdent(node))
		end
	end,
	[ast.Exp] = function(self, node)
		scopeNodes(self, node, ast.Value)
		scopeNodes(self, node, ast.Exp)
	end,
	[ast.Prefix] = function(self, node)
		if node.type >> 5 == 1 then
			self:usename(selectIdent(node))
		else
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Args] = function(self, node)
		local t = node.type >> 5
		if t == 1 then
			scopeNodes(self, node, ast.ExpOr)
		elseif t == 2 then
			scopeNode(self, node, ast.Table)
		end
	end,
	[ast.Funcbody] = function(self, node, isMeth)
		local names = {}
		for i, n in selectIdents(node) do
			names[#names+1] = n
		end
		local asm = Assembler()
		asm.scopes = self.scopes
		asm.names = self.names
		asm.isdotdotdot = hasToken(node, lex._dotdotdot)
		asm:scope(function()
			if isMeth then
				asm:name('self', true)
			end
			for i=1,#names do
				asm:name(names[i].arg, true)
			end
			scopeNode(asm, node, ast.Block)
		end)
		asm:genBoxPrologue()
		emitNode(asm, node, ast.Block)
		asm:synth()
		local func = { func = asm }
		local already = {}
		for k, v in pairs(asm.namety) do
			if v.free and v.free[asm] and v.func ~= asm and not already[v] then
				already[v] = true
				v.free[self] = true
				func[#func+1] = v
			end
		end
		table.sort(func, function(a, b)
			return asm:nameidx(a) < asm:nameidx(b)
		end)
		self.funcs[node] = func
	end,
	[ast.Table] = function(self, node)
		scopeNodes(self, node, ast.Field)
	end,
	[ast.Field] = function(self, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Binop] = nop,
	[ast.Unop] = nop,
	[ast.Value] = function(self, node)
		local t = node.type >> 5
		if t == 7 then
			scopeNode(self, node, ast.Funcbody)
		elseif t == 8 then
			scopeNode(self, node, ast.Table)
		elseif t == 9 then
			scopeNode(self, node, ast.Prefix)
			scopeNodes(self, node, ast.Suffix)
			scopeNode(self, node, ast.Args)
		elseif t == 10 then
			scopeNode(self, node, ast.Var)
		elseif t == 11 then
			scopeNode(self, node, ast.ExpOr)
		else
			assert(t ~= 6 or self.isdotdotdot, '... outside of ... context')
		end
	end,
	[ast.Index] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Suffix] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.Args)
		else
			scopeNode(self, node, ast.Index)
		end
		return scopeNode(self, node, ast.Suffix)
	end,
	[ast.ExpOr] = function(self, node)
		return scopeNodes(self, node, ast.ExpAnd)
	end,
	[ast.ExpAnd] = function(self, node)
		return scopeNodes(self, node, ast.Exp)
	end,
}
local function emitShortCircuitFactory(ty, opcode)
	return function(self, node, out)
		local prod
		if #node == 1 then
			prod = visitEmit[ty](self, node[1], out)
		else
			local lab
			for i, n in selectNodes(node, ty) do
				visitEmit[ty](self, n, 1)
				if lab then
					self:patch(lab, #self.bc)
				end
				if i > 1 then
					lab = #self.bc+2
					self:push(opcode, 0)
				end
			end
			prod = 1
		end
		if out ~= -1 then
			for i=prod+1, out do
				self:push(bc.Pop)
			end
			for i=prod-1, out, -1 do
				self:push(bc.LoadNil)
			end
			return out
		else
			return prod
		end
	end
end
visitEmit = {
	[ast.Block] = function(self, node)
		emitNodes(self, node, ast.Stat)
		if hasToken(node, lex._return) then
			local n, res = emitExplist(self, node, -1)
			if type(res) == 'number' then
				self:push(bc.Return)
			elseif not res.varg then
				assert(#res > 0, 'None varg, no call, yet complex return')
				self:push(bc.ReturnCall, #res, table.unpack(res))
			elseif #res > 0 then
				self:push(bc.ReturnCallVarg, #res, table.unpack(res))
			else
				self:push(bc.ReturnVarg)
			end
		end
	end,
	[ast.Stat] = function(self, node)
		return emitStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Var] = function(self, node, isload)
		if node.type >> 5 == 1 then
			emitNode(self, node, ast.Prefix)
			emitNodes(self, node, ast.Suffix, function(node)
				emitNode(self, node, ast.Index, isload)
			end)
		else
			local name = selectIdent(node)
			if isload then
				self:loadname(name)
			else
				self:storename(name)
			end
		end
	end,
	[ast.Exp] = function(self, node, out)
		if node.type >> 5 == 1 then
			emitNode(self, node, ast.Exp, 1)
			emitNode(self, node, ast.Unop)
			return 1
		else
			if #node == 1 then
				return visitEmit[ast.Value](self, node[1], out)
			else
				for op in shunt(node) do
					local ty = op.type & 31
					if ty == ast.Binop then
						visitEmit[ast.Binop](self, op)
					elseif ty == ast.Value then
						visitEmit[ast.Value](self, op, 1)
					else
						assert(op.type >> 5 == 1)
						visitEmit[ast.Exp](self, op, 1)
					end
				end
				return 1
			end
		end
	end,
	[ast.Prefix] = function(self, node)
		if node.type >> 5 == 1 then
			self:loadname(selectIdent(node))
		else
			emitNode(self, node, ast.ExpOr, 1)
		end
	end,
	[ast.Args] = function(self, node, outputs)
		local ty, res = node.type >> 5
		if ty == 1 then
			local n
			n, res = emitExplist(self, node, -1)
			if type(res) == 'number' then
				res = { n + res }
			else
				res[#res+1] = n
			end
		elseif ty == 2 then
			emitNode(self, node, ast.Table)
			res = { 1 }
		else
			self:push(bc.LoadConst, self:const(node[1].arg))
			res = { 1 }
		end
		if outputs == -1 then
			return res
		else
			local op
			if res.varg then
				op = bc.CallVarg
			else
				op = bc.Call
			end
			self:push(op, outputs, #res, table.unpack(res))
			return outputs
		end
	end,
	[ast.Funcbody] = function(self, node)
		local func = self.funcs[node]
		for i=1, #func do
			local name = func[i]
			local idx = self:nameidx(name)
			if name.func ~= self then
				self:push(bc.LoadFree, idx)
			elseif name.isparam then
				self:push(bc.LoadParam, idx)
			else
				self:push(bc.LoadLocal, idx)
			end
		end
		self:push(bc.LoadFunc, #func, self:const(func.func))
	end,
	[ast.Table] = function(self, node)
		self:push(bc.TblNew)
		local ary = {}
		emitNodes(self, node, ast.Field, ary)
		if #ary > 0 then
			for i=1,#ary-1 do
				emitNode(self, ary[i], ast.ExpOr, 1)
			end
			local res = emitNode(self, ary[#ary], ast.ExpOr, -1)
			if type(res) == 'number' then
				assert(res == 1, 'Somehow appending finite multiple values to table')
				self:push(bc.Append, #ary)
			elseif not res.varg then
				assert(#res > 0, 'None varg, no call, yet complex append')
				self:push(bc.AppendCall, #ary-1, #res, table.unpack(res))
			elseif #res > 0 then
				self:push(bc.AppendCallVarg, #ary-1, #res, table.unpack(res))
			else
				self:push(bc.AppendVarg, #ary-1)
			end
		end
	end,
	[ast.Field] = function(self, node, ary)
		return emitFieldSwitch[node.type >> 5](self, node, ary)
	end,
	[ast.Binop] = function(self, node)
		local op = binOps[node.type >> 5]
		if op then
			self:push(op)
		else
			self:push(bc.CmpEq)
			self:push(bc.Not)
		end
	end,
	[ast.Unop] = function(self, node)
		self:push(unOps[node.type >> 5])
	end,
	[ast.Value] = function(self, node, outputs)
		local results = emitValueSwitch[node.type >> 5](self, node, outputs)
		if outputs ~= -1 then
			for i=results+1, outputs do
				self:push(bc.Pop)
			end
			for i=results-1, outputs, -1 do
				self:push(bc.LoadNil)
			end
			return outputs
		else
			return results
		end
	end,
	[ast.Index] = function(self, node, isload)
		if node.type >> 5 == 1 then
			emitNode(self, node, ast.ExpOr, 1)
		else
			self:push(bc.LoadConst, self:const(selectIdent(node).arg))
		end
		if isload then
			self:push(bc.Idx)
		else
			self:push(bc.TblSet)
		end
	end,
	[ast.Suffix] = function(self, node, tailfn)
		local nx = selectNode(node, ast.Suffix)
		if not nx then
			return tailfn(node)
		elseif node.type >> 5 == 1 then
			emitCall(self, node, 1)
		else
			emitNode(self, node, ast.Index, true)
		end
		return visitEmit[ast.Suffix](self, nx, tailfn)
	end,
	[ast.ExpOr] = emitShortCircuitFactory(ast.ExpAnd, bc.JifOrPop),
	[ast.ExpAnd] = emitShortCircuitFactory(ast.Exp, bc.JifNotOrPop),
}

function asmmeta:genBoxPrologue()
	for i=1,#self.params do
		local v = self.params[i]
		if v.free and v.func == self then
			self:push(bc.BoxParam, v.isparam)
		end
	end
	local pastlocal = {}
	for k,v in pairs(self.namety) do
		if v.free and v.func == self and not pastlocal[v] then
			pastlocal[v] = true
			self:push(bc.BoxLocal, self:nameidx(v))
		end
	end
end

function asmmeta:synth()
	for k, v in pairs(self.namety) do
		if not (v.isparam or self.locals[v] or self.frees[v]) then
			self.namety[k] = nil
		end
	end
	self:push(bc.Return)
	for k,v in pairs(self.gotos) do
		self:patch(k, self.labels[v])
	end
	return self
end

return function(root)
	local asm = Assembler()
	asm.isdotdotdot = true
	asm:scope(function()
		asm:name('_ENV', true)
		visitScope[ast.Block](asm, root)
	end)
	asm:genBoxPrologue()
	visitEmit[ast.Block](asm, root)
	return asm:synth()
end