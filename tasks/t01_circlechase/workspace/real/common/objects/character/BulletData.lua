--
-- $Id$
--

local bRunningServerCode = IsRunningServerCode()
local mt = {}
local cppmt = {}
CBulletMoveDataMemberTb = {
	m_Data_Freq = 1,
	m_Data_NoFreq = 1,
	m_Data_Spec = 1,
	m_FreqMP = 1,
	m_NoFreqMP = 1,
	m_SpecMP = 1,
	m_EngineObjectId = 1, --加一个属性，用于获取engine对象
}

local CBulletMoveDataMemberTb = CBulletMoveDataMemberTb
function RegisterBulletMoveDataMember()
    for k, v in pairs(CBulletMoveData) do
        if type(v) == 'function' then
            assert(not CBulletMoveDataMemberTb[k], "CBulletMoveDataMemberTb has same key: " .. k)
            CBulletMoveDataMemberTb[k] = -1
        end
    end

    local t = rawget(CBulletData_Freq, "Declared")
    for k, _ in pairs(t) do
        assert(not CBulletMoveDataMemberTb[k], "CBulletMoveDataMemberTb has same key: " .. k)
        CBulletMoveDataMemberTb[k] = 2
    end
    t = rawget(CBulletData_NoFreq, "Declared")
    for k, _ in pairs(t) do
        assert(not CBulletMoveDataMemberTb[k], "CBulletMoveDataMemberTb has same key: " .. k)
        CBulletMoveDataMemberTb[k] = 3
    end
end

function GetBulletMoveDataMT()
	return mt
end

function GetBulletMoveDataCppMT()
	return cppmt
end

function mt.__index(tbl, key)
	local kind = CBulletMoveDataMemberTb[key]
	if kind == 1 then 
		return rawget(tbl, key)
	elseif kind == 2 then
		return tbl.m_Data_Freq[key]
	elseif kind == 3 then
		return tbl.m_Data_NoFreq[key]
	elseif kind == -1 then
		return CBulletMoveData[key]
	else
		if tbl.m_Data_Spec then
			return tbl.m_Data_Spec[key]
		end
	end
	
	return nil
end

function mt.__newindex(tbl, key, value)
	local kind = CBulletMoveDataMemberTb[key]
	if kind == 1 then 
		rawset(tbl, key, value)
		return
	elseif kind == 2 then
		tbl.m_Data_Freq[key] = value
		if bRunningServerCode then
			rawset(tbl, "m_FreqMP", nil)
		end
		return
	elseif kind == 3 then
		tbl.m_Data_NoFreq[key] = value
		if bRunningServerCode then
			rawset(tbl, "m_NoFreqMP", nil)
		end
		return
	elseif kind == -1 then
		return
	else
		if tbl.m_Data_Spec then
			tbl.m_Data_Spec[key] = value
			if bRunningServerCode then
				rawset(tbl, "m_SpecMP", nil)
			end
			return
		end
	end
end

local CppKeyGetTbl = {
	m_CurX = 1,
	m_CurY = 2,
	m_CurZ = 3,
}
local CppKeySetTbl = {
	m_CurX = 1,
	m_CurY = 2,
	m_CurZ = 3,
	m_Trajectory = 4,
	m_BulletSpeed = 5,
	m_Accel = 6,
	m_MoveVectorX = 7,
	m_MoveVectorY = 8,
	m_MoveVectorZ = 9,
	m_MoveDistance = 10,
	m_MaxDistance = 11,
}
--如果是m_CurX, m_CurY, m_CurZ则从C++获取
function cppmt.__index(tbl, key)
	local kind = CBulletMoveDataMemberTb[key]
	if kind == 1 then
		return rawget(tbl, key)
	end

	local trajctoryId = tbl.m_Data_NoFreq.m_Trajectory
	if CppKeyGetTbl[key] and trajctoryId == EnumBulletTracjectory.Direction_Opt then
		local eid = rawget(tbl, "m_EngineObjectId")
		local o = GetCharacterByEngineObjectGlobalId(eid)
		if o then
			local argId = CppKeyGetTbl[key]
			local value = o.m_engineObject:GetLuaMoveArg(argId)
			--设置并更新一下
			if kind == 2 then
				tbl.m_Data_Freq[key] = value
				if bRunningServerCode then
					rawset(tbl, "m_FreqMP", nil)
				end
				return value
			elseif kind == 3 then
				tbl.m_Data_NoFreq[key] = value
				if bRunningServerCode then
					rawset(tbl, "m_NoFreqMP", nil)
				end
				return value
			elseif kind == -1 then
				return CBulletMoveData[key]
			else
				tbl.m_Data_Spec[key] = value
				if bRunningServerCode then
					rawset(tbl, "m_SpecMP", nil)
				end
				return value
			end
		end
		return nil
	end

	if kind == 2 then
		return tbl.m_Data_Freq[key]
	elseif kind == 3 then
		return tbl.m_Data_NoFreq[key]
	elseif kind == -1 then
		return CBulletMoveData[key]
	else
		if tbl.m_Data_Spec then
			return tbl.m_Data_Spec[key]
		end
	end
	
	return nil
end

--如果是set，则设置并修改C++的值
function cppmt.__newindex(tbl, key, value)
	local kind = CBulletMoveDataMemberTb[key]
	if kind == 1 then
		rawset(tbl, key, value)
		return
	end

	local trajctoryId = tbl.m_Data_NoFreq.m_Trajectory
	if CppKeySetTbl[key] and trajctoryId == EnumBulletTracjectory.Direction_Opt then
		local eid = rawget(tbl, "m_EngineObjectId")
		local o = GetCharacterByEngineObjectGlobalId(eid)
		if o then
			local argId = CppKeySetTbl[key]
			o.m_engineObject:UpdateLuaMoveArg(argId, value or 0)
		end
	end

	if kind == 2 then
		tbl.m_Data_Freq[key] = value
		if bRunningServerCode then
			rawset(tbl, "m_FreqMP", nil)
		end
		return
	elseif kind == 3 then
		tbl.m_Data_NoFreq[key] = value
		if bRunningServerCode then
			rawset(tbl, "m_NoFreqMP", nil)
		end
		return
	elseif kind == -1 then
		return
	else
		tbl.m_Data_Spec[key] = value
		if bRunningServerCode then
			rawset(tbl, "m_SpecMP", nil)
		end
		return
	end
end

-- {{{Bullet MoveData Pool Begin	------------------------------------------
if bRunningServerCode then 
	BULLET_MOVEDATA_POOL_MAX_SIZE = 500
	g_BulletMoveDataPool = table.new(500, 0)
else
	BULLET_MOVEDATA_POOL_MAX_SIZE = 100
	g_BulletMoveDataPool = table.new(100, 0)
end

if IsInner() then
	--内网
	function CBulletMoveData:new(...)
		local inst = table.remove(g_BulletMoveDataPool) or table.new(0, 31)
		setmetatable(inst, nil)
		self.Ctor(inst, ...)
		return inst
	end
else
	function CBulletMoveData:new(...)
		local inst = table.remove(g_BulletMoveDataPool) or table.new(0, 31)
		self.Ctor(inst, ...)
		return inst
	end
end

function NewBulletMoveDataToObj(obj, ...)
	ReturnBulletMoveDataFromObj(obj) --尝试回收下
	obj.m_BulletMoveData = CBulletMoveData:new(...)
end


if IsInner() then
	--内网
	local RELEASE_MOVEDATA_MT = {
		__index = function(t, k)
			print(ERR, "attempt to read a released bullet move data: " .. tostring(k))
			LogCallContext_lua() 	
		end,
		__newindex = function(t, k, v) 
			print(ERR, "attempt to write a released bullet move data: " .. tostring(k))
			LogCallContext_lua() 
		end
	}
	
	function ReturnBulletMoveDataFromObj(obj)
		local data = obj.m_BulletMoveData
		if data then 
			obj.m_BulletMoveData = nil
			if #g_BulletMoveDataPool >= BULLET_MOVEDATA_POOL_MAX_SIZE then 
				return 
			end
			if bRunningServerCode then 
				data:ReturnDataToPool()
				setmetatable(data, RELEASE_MOVEDATA_MT)
			end
			table.clear(data)
			table.insert(g_BulletMoveDataPool, data)
		end
	end
else
	function ReturnBulletMoveDataFromObj(obj)
		local data = obj.m_BulletMoveData
		if data then 
			obj.m_BulletMoveData = nil
			if #g_BulletMoveDataPool >= BULLET_MOVEDATA_POOL_MAX_SIZE then 
				return 
			end
			if bRunningServerCode then 
				data:ReturnDataToPool()
				setmetatable(data, nil)
			end
			table.clear(data)
			table.insert(g_BulletMoveDataPool, data)
		end
	end
end
-- }}}Bullet MoveData Pool End  	------------------------------------------

function CBulletMoveData:Ctor( FreqDataStr, NoFreqDataStr, SpecialDataStr)
	CBulletMoveData.Init(self, FreqDataStr, NoFreqDataStr, SpecialDataStr)
end

function CBulletMoveData:Init( FreqDataStr, NoFreqDataStr, SpecialDataStr)
	if not bRunningServerCode then 
		table.clear(self)
		if FreqDataStr then 
			local freq = g_ObjPoolMgr:GetObj(CBulletData_Freq)
			msgpack.unpack(FreqDataStr, CBulletData_Freq, freq)
			local declared = GetClassDeclared(freq)
			for k in pairs(declared or EMPTY_TABLE) do 
				local value = freq[k]
				if value then
					self[k] = value
				end
			end
			g_ObjPoolMgr:ReturnObj(freq)
		end
		if NoFreqDataStr then 
			local noFreq = g_ObjPoolMgr:GetObj(CBulletData_NoFreq)
			msgpack.unpack(NoFreqDataStr, CBulletData_NoFreq, noFreq)
			local declared = GetClassDeclared(noFreq)
			for k in pairs(declared or EMPTY_TABLE) do 
				local value = noFreq[k]
				if value then
					self[k] = value
				end
			end
			g_ObjPoolMgr:ReturnObj(noFreq)
		end
		local trajectory = self.m_Trajectory
		if SpecialDataStr and not IsNilUserData(SpecialDataStr) and trajectory and BulletTrajectoryClassTb[trajectory] then
			local spec = BulletTrajectory2PublicObj[trajectory]
			ClearAllClassData(spec)
			msgpack.unpack(SpecialDataStr, BulletTrajectoryClassTb[trajectory], spec)
			local declared = GetClassDeclared(spec)
			for k in pairs(declared or EMPTY_TABLE) do 
				local value = spec[k]
				if value then
					self[k] = value
				end
			end
		end
	else
		local freq = g_ObjPoolMgr:GetObj(CBulletData_Freq)
		self.m_Data_Freq = freq
		local noFreq = g_ObjPoolMgr:GetObj(CBulletData_NoFreq)
		self.m_Data_NoFreq = noFreq
		
		setmetatable(self, mt)
	end
end

function CBulletMoveData:ReturnDataToPool()
	g_ObjPoolMgr:ReturnObj(self.m_Data_Freq)
	g_ObjPoolMgr:ReturnObj(self.m_Data_NoFreq)
end

function CBulletMoveData:GetMsgPack()
	self.m_FreqMP = self.m_FreqMP or msgpack.pack_object_for_sync(self.m_Data_Freq)
	self.m_NoFreqMP = self.m_NoFreqMP or msgpack.pack_object_for_sync(self.m_Data_NoFreq)
	self.m_SpecMP = self.m_SpecMP or msgpack.pack_object_for_sync(self.m_Data_Spec)
	
	return self.m_FreqMP, self.m_NoFreqMP, self.m_SpecMP
end

function CBulletData_Freq:Ctor()
	self.m_NewBorn = true
end

function CBulletData_Freq:OnReturnToPool(...)
	OnReturnToPoolDefault(self, nil, ...)
end

function CBulletData_Freq:OnReuseFromPool(...)
	OnReuseFromPoolDefault(self, ...)
end

function CBulletData_NoFreq:Ctor()
end

function CBulletData_NoFreq:OnReturnToPool(...)
	OnReturnToPoolDefault(self, nil, ...)
end

function CBulletData_NoFreq:OnReuseFromPool(...)
	OnReuseFromPoolDefault(self, ...)
end

function CBulletData_Direction:Ctor()
	self.m_MoveDistance = 0
end

function CBulletMoveDataOpt:Ctor()
	self.m_NewBorn = true
	self.m_MoveDistance = 0
end


RegisterBulletMoveDataMember()
