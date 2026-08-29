local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local bServer = IsRunningServerCode()
local sqrt, sin, cos, tan, rad, abs, floor = math.sqrt, math.sin, math.cos, math.tan, math.rad, math.abs, math.floor

local Skill_SkillChange_f = AllFormulas.Skill_SkillChange

-- 引擎 Z 轴筛选开关：true=无pitch技能由引擎做Z筛选，false=全部走Lua旧逻辑
g_EngineZFilterEnabled = true

function LoadBehaviorTree(bt)
	if bt[0] == "seq" or bt[0] == "sel" then
		local idx = 1
		while idx <= #bt do
			local cur = bt[idx]
			if type(cur) == "table" then
				bt[idx] = LoadBehaviorTree(bt[idx])
				bt[idx].Parent = bt
			end
			idx = idx + 1
		end
	end
	return bt
end

-- 技能套路类型，按ID区分，1-100是普通套路
ExploreSkillBuildId = 1000
ExploreSkillBuildRealId = 232 -- 内功套路存盘id是uint8，上限255，服务器存盘截断1000实际存的ID为232，非常坑，导致技能套路存的id是1000，内功存的id是232，以后套路ID上限就定为232
NormalSkillBuildMaxId = 100 -- 普通套路最大ID
function IdIsNormalSkillBuild(id)
	if not id then return false end
	return 0 < id and id < NormalSkillBuildMaxId
end

function IdIsExploreSkillBuild(id)
	if not id then return false end
	return id == ExploreSkillBuildId or id == ExploreSkillBuildRealId
end

function IdIsFunctionLiveSkill(id)
	return not not SkillUI_LifeSkill[id]
end

function CSkillMgrBase:Ctor()
	self.DEFAULT_MAX_SKILL_TARGET_NUM = 20
	self.DEFAULT_MAX_SKILL_PLAYER_TARGET_NUM = 20
	self.m_MAX_TARGET_NUM = 100
	self.m_MAX_PLAYER_TARGET_NUM = 100
	self.m_MAX_SKILL_TARGET_NUM_FOR_SET = 1000

	self.m_TempMonsterPartIgnoreIdMap = {}
	self.m_TempMonsterPartChemiIgnoreIdMap = {}

	self.m_SkillCls2SubWeaponId = {}
	self.m_CanUpgradeSubWeaponSkill = {}
	self:ParseSkillOrderDisData()
	self:ParsePuGongList()
	self:ParseSubWeaponList()
end

--副武器相关 Start
function CSkillMgrBase:ParseSubWeaponList()
	for subWeaponId, design in bddpairs(Skill_SubWeapon) do
		if design.Skill and design.Skill > 0 then
			self.m_SkillCls2SubWeaponId[design.Skill] = subWeaponId
		end
		if design.CanUpgradeSkills and #design.CanUpgradeSkills > 0 then
			for _, skillCls in bddipairs(design.CanUpgradeSkills or EMPTY_TABLE) do
				self.m_CanUpgradeSubWeaponSkill[skillCls] = true
			end
		end
	end
end

function CSkillMgrBase:GetUnlockedSubWeaponCount(player)
	local count = 0
	local data = GetPlayerSubWeaponData(player)
	for subWeaponId in data:UnlockedMap_Pairs() do
		count = count + 1
	end
	return count
end

function CSkillMgrBase:GetSkillSubWeaponType(skillCls, p)
    if not IsRunningServerCode() then
		p = g_MainPlayer
	end 
    local skillCls = _DoGetSwitchGroupRealCls(p, skillCls) or skillCls
	return Skill_Skill[skillCls] and Skill_Skill[skillCls].SubWeaponType or 0
end

function CSkillMgrBase:CheckIsSubWeaponCanUseSkill(skillCls, subWeaponId, p)
    if not skillCls or not subWeaponId then return false end
    if self:GetSkillSubWeaponType(skillCls, p) == subWeaponId then
        return true
    end
    local subWeaponId2SubIdx = Skill_SkillChange_Main2SubWeaponId2SubIdx[skillCls]
    if subWeaponId2SubIdx and subWeaponId2SubIdx[subWeaponId] then
        return true
    end
    return false
end

function CSkillMgrBase:GetSubWeaponIdBySkillCls(skillCls)
    return skillCls and self.m_SkillCls2SubWeaponId[skillCls]
end

function CSkillMgrBase:IsSubWeaponSkill(skillCls)
    return skillCls and self.m_SkillCls2SubWeaponId[skillCls] ~= nil
end

function CSkillMgrBase:IsCanUpgradeSubWeaponSkill(skillCls)
	return skillCls and self.m_CanUpgradeSubWeaponSkill[skillCls] 
end

-- 判断技能是否为副武器共鸣技能
-- 共鸣技能：该技能所属的变体组 groupId 在 Skill_SkillChange_Main2SubWeaponId2SubIdx 中有配置
-- @param skillCls number 技能 cls
-- @return bool
function CSkillMgrBase:IsSubWeaponResonanceSkill(skillCls)
    if not skillCls then return false end
    local skillChangeInfo = Skill_SkillChange_Rev2[skillCls]
    if not skillChangeInfo then return false end
    local groupId = skillChangeInfo.ID
    return Skill_SkillChange_Main2SubWeaponId2SubIdx[groupId] ~= nil
end

-- 根据技能 cls 和副武器 ID，获取共鸣技能的实际技能 cls
-- @param skillCls number 技能 cls（变体组的主 cls）
-- @param iSubWeaponId number 副武器 ID
-- @return number|nil 实际共鸣技能的 cls；若不匹配返回 nil
function CSkillMgrBase:GetResonanceSkillCls(skillCls, iSubWeaponId)
    if not skillCls or not iSubWeaponId then return nil end
    local skillChangeInfo = Skill_SkillChange_Rev2[skillCls]
    if not skillChangeInfo then return skillCls end
    local groupId = skillChangeInfo.ID
    local subWeaponId2SubIdx = Skill_SkillChange_Main2SubWeaponId2SubIdx[groupId]
    if not subWeaponId2SubIdx then return skillCls end
    local subIdx = subWeaponId2SubIdx[iSubWeaponId]
    if not subIdx then return skillCls end
    local skills = skillChangeInfo.Skills
    return skills and skills[subIdx] or skillCls
end

function GetCurPlayerSubWeaponId(player)
    local data = GetPlayerSubWeaponData(player)
    return data and data:GetCurSubWeaponId() or 0
end

function GetCurPlayerSubWeaponMainSkill(player)
    local subWeaponId = GetCurPlayerSubWeaponId(player)
    return GetSubWeaponMainSkill(subWeaponId) or 0
end

function GetSubWeaponDesignData(subWeaponId)
    return subWeaponId and Skill_SubWeapon[subWeaponId]
end

-- 判断处决副武器是否开放(OpenSeason等配置), 供处决模块泛用
-- offHandWeaponId: 处决模块的副武器Id, 通过BOSS_EXECUTION_WEAPONID_2_ID转换为Skill_SubWeapon表的Id
-- 转换不到时按原Id处理(与UploadDivide.lua:137-138模式一致); 没有配置的副武器视为开放; 未开放返回false
function CheckExecutionOffHandWeaponOpen(offHandWeaponId)
    if offHandWeaponId == nil then
        return false
    end

    -- 处决副武器Id -> Skill_SubWeapon表Id
    local subWeaponId = table.safe_get(CombatMech_Setting, "BOSS_EXECUTION_WEAPONID_2_ID", "TblVal", offHandWeaponId)
    if subWeaponId == nil then
        subWeaponId = offHandWeaponId
    end

    local designData = GetSubWeaponDesignData(subWeaponId)
    if designData == nil then
        -- 没有配置的副武器视为开放(不拦截)
        return true
    end

    -- 服务端按服务器组判定, 客户端按本服(SeasonFunctionFixServerId内部处理)
    local serverId = nil
    if bServer then
        serverId = SERVER_GROUP_ID
    end
    return CheckDesignDataOpenDaysAndDate(designData, serverId)
end

function GetSubWeaponMainSkill(subWeaponId)
    return subWeaponId and Skill_SubWeapon[subWeaponId] and Skill_SubWeapon[subWeaponId].Skill
end

function GetSubWeaponGroupIndex(subWeaponId)
	local design = GetSubWeaponDesignData(subWeaponId)
	return design and design.GroupIndex
end

function GetPlayerSubWeaponData(player)
	local playProp = player:PlayProp()
	if not playProp then
		return
	end
    local data = playProp:GetSubWeaponData()
    if not data then
        data = CSubWeaponData:new()
        player:PlayProp():SetSubWeaponData(data)
    end
    return data
end

function IsPlayerSubWeaponUnlocked(player, subWeaponId)
    if not (player and subWeaponId) then  
        return false 
    end
    local data = GetPlayerSubWeaponData(player)
    return data and data:GetUnlockedMap_At(subWeaponId) == 1
end

function IsYearEnhanceSkill(skillCls)
    if not IsRunningServerCode() then
        if g_MainPlayer:IsActivatingTrialCoupon(EnumTrialCouponType.eSkill_And_Passive) then
            return false
        end
    end
    local data = Skill_Skill[skillCls]
    if data and data.YearEnhance == 1 then
        return true
    end
    return false
end

function IsInForbidSubWeaponGameplay(gameplayId)
	return gameplayId and Gameplay_Gameplay[gameplayId] and Gameplay_Gameplay[gameplayId].ForbidSubWeapon == 1
end

function IsSkillClsInKeepOriFxConfig(skillStyleId)
    if not skillStyleId then return false end
    local cfg =  Skill_Settings.SUBWEAPON_KEEP_ORI_FX_CONFIG.tblVal
    if not cfg or not cfg.SkillStyleTbl then return false end
    for _, id in bddpairs(cfg.SkillStyleTbl) do
        if id == skillStyleId then
            return true
        end
    end
    return false
end

function IsKeepSkillStyleOriWeaponFx(player, skillStyleId)
    if not IsSkillClsInKeepOriFxConfig(skillStyleId) then
        return false
    end
    local data = GetPlayerSubWeaponData(player)
    if not data then return false end
    return (data:GetKeepOriWeaponFxMap_At(skillStyleId) or 0) == 1
end

--副武器相关 End


function CSkillMgrBase:BaseLoad()
	self.m_EffectCheckFuntionTable = GetEffectCheckFuntionTable()
	self:LoadPlatformWhiteSkills()
	self:CheckClientHitSkillsValid()
end

-- 启动时扫描：ClientHit==1 但 Scope 不合法的技能，打 warning 并清掉 ClientHit，
-- 回退到服务器命中流程，避免客户端 _CheckHitTargetByScope 因 scope=nil 崩溃。
function CSkillMgrBase:CheckClientHitSkillsValid()
	for cls, v in bddpairs(Skill_Skill) do
		if v.ClientHit == 1 then
			local ok, scopeType = pcall(ParseSkillScope, v.Scope)
			if not ok or scopeType == "none" then
				PQLOGF("[SkillMgrBase] Skill cls=%s ClientHit=1 but Scope invalid (Scope=%s, parseOk=%s, scopeType=%s), disable ClientHit",
					tostring(cls), tostring(v.Scope), tostring(ok), tostring(scopeType))
				v.ClientHit = nil
			end
		end
	end
end

function CSkillMgrBase:LoadSingleSkillFeature(skillFeatureStr)
	local featureTbl = self.m_SkillFeatureName2Id
	local ret = {}
	local ret2 = {}
	for w in string.gmatch(skillFeatureStr, "([^;]+)") do
		local wNum = tonumber(w)
		if type(wNum) == "number" then
			table.insert(ret, wNum)
			ret2[wNum] = true
		else
			local fid = featureTbl[w]
			if fid then
				table.insert(ret, fid)
				ret2[fid] = true
			end
		end
	end
	return ret, ret2
end

function CSkillMgrBase:ReadStepSkills()
	self.m_StepSkills = {}
	local StepSkills = self.m_StepSkills

	for k,v in bddpairs(Skill_Skill) do
		local skillCls = k
		if not StepSkills[skillCls] and v.StepSkillId then
			local tblStep = {}
			for w in string.gmatch(v.StepSkillId, "(%d+);?") do
				table.insert(tblStep, tonumber(w))
			end
			StepSkills[skillCls] = tblStep
		end
	end
end

---统一分段链读取入口：obj 带 StepSkillId 的 Replace delta（13010023 Col="StepSkillId"）时返回替换链，
---否则返回静态 m_StepSkills（快路径零开销）。mainSkillCls 必须是主技能 cls。
---Replace 直接填段技能数组（Add 时校验已保证格式与归属），无需解析与缓存。
---注意：Ori 旧路径（ENABLE_SKILL_COL_MOD_FIELD_GROUP=false）不消费 StepSkillId，本函数在新路径下生效。
function CSkillMgrBase:GetSkillSteps(mainSkillCls, obj)
	return obj and obj:GetSkillColDelta(mainSkillCls, "StepSkillId", nil) or self.m_StepSkills[mainSkillCls]
end

---m_XueHeComboSkills[skillcl]
--	key: index
--	value:{Interval, Step, NextSkillCl}
local XHCiTiaoTbl = Skill_Settings["Xue_He_Ci_Tiao_Main_Skills"].tblVal
function CSkillMgrBase:ReadXueHeSkill()
	self.m_XueHeComboSkills = {}
	self.m_XueHeComboLastSkill = {}
	self.m_XueHeComboSkillsGP = {}
	self.m_XueHeComboLastSkillGP = {}
	local Xue_He_Ci_Tiao_Main_Skills = XHCiTiaoTbl[0]

	local XueheComboSkills = self.m_XueHeComboSkills
	local XueHeComboLastSkill = self.m_XueHeComboLastSkill
	for k, v in bddpairs(Skill_XueHeSkill) do
		if v.skill_step2 then
			if v.gameplayId then
				assert(Gameplay_Gameplay[v.gameplayId] and XHCiTiaoTbl[v.gameplayId], "Skill_XueHeSkill "..k.." error with wrong gameplayid"..(v.gameplayId) ) 
				self.m_XueHeComboSkillsGP[v.gameplayId] = self.m_XueHeComboSkillsGP[v.gameplayId] or {}
				XueheComboSkills = self.m_XueHeComboSkillsGP[v.gameplayId] 
				self.m_XueHeComboLastSkillGP[v.gameplayId] = self.m_XueHeComboLastSkillGP[v.gameplayId] or {}
				XueHeComboLastSkill = self.m_XueHeComboLastSkillGP[v.gameplayId]
				Xue_He_Ci_Tiao_Main_Skills = XHCiTiaoTbl[v.gameplayId]
			else
				XueheComboSkills = self.m_XueHeComboSkills
				XueHeComboLastSkill = self.m_XueHeComboLastSkill
				Xue_He_Ci_Tiao_Main_Skills = XHCiTiaoTbl[0]
			end
			local skillcl, interval
			local comboIndex = 1
			for w in string.gmatch(v.skill_step2, "([^;]+)") do
				local s = string.split(w, ",")	
				if not s[1] then assert(false, "Skill_XueHeSkill "..k.." error") end
				local lastSkillcl = skillcl
				local lastInterval = interval
				skillcl = tonumber(s[1]) 
				if s[2] then 
					interval = tonumber(s[2]) 
				else 
					XueHeComboLastSkill[skillcl] = true
				end
			
				if lastSkillcl then
					local mainSkillCls = self:GetMainSkillClsBySkillCls(skillcl)
					if not mainSkillCls or not Xue_He_Ci_Tiao_Main_Skills[mainSkillCls] then 
						assert(false, "Skill_XueHeSkill "..k.." error")  return
					end
					local stepTb = self.m_StepSkills[mainSkillCls]
					if not stepTb then LogCallContext_lua() stepTb = {} end
					local step
					for l1,l2 in pairs(stepTb) do
						if l2 == skillcl then
							step = l1 - 1
							break
						end
					end
					if not step then LogCallContext_lua() end
					if not XueheComboSkills[lastSkillcl] then XueheComboSkills[lastSkillcl] = {} end
					if step then
						comboIndex = comboIndex +1
						table.insert(XueheComboSkills[lastSkillcl], {Interval = lastInterval, Step = step, NextSkillCl = skillcl,ComboIndex = comboIndex})
					end
				end
			end
		end
	end
end

function CSkillMgrBase:ReadBehavior()
	--for reload
	for k,p in pairs(g_ServerPlayerMgr.m_IdPlayers) do
		p:LuaDataProp().m_SkillBehaviors = {}
	end
end


function CSkillMgrBase:ParseFakeRecover(str, id)
	if not str then return nil end
	local tbl = nil
	for v in string.gmatch(str, "([^|]+)|?") do
		local status, lastTime = string.match(v, "([^;]+);([^;]+)")
		lastTime = tonumber(lastTime)
		assert(EPropStatus[status] ~= nil and lastTime > 0, "No Status or LastTime Error " .. tostring(status) .. " " .. tostring(lastTime))
		tbl = tbl or {}
		table.insert(tbl, { Status = EPropStatus[status], LastTime = lastTime })
	end
	if tbl and #tbl > 10 then assert(false, "Skill:" .. tostring(id) .. " FakeRecover Num Exceed Limit 10") end
	return tbl
end

function CSkillMgrBase:_DoParseSkillEvent(eventStr, SkillProp)
	local AutoInsertAttEvent = true
	local AutoInsertClientMotion = true
	local AutoInsertCanCastDuringControlled = false
	local tbl = {}
	local isNoAtt = false
	local beatEvent 

	if eventStr then
		for event in string.gmatch(eventStr,"([%d%w_]+)") do
			if EnumEvent[event] then
				tbl = tbl or {}
				table.insert(tbl, event)
			elseif event == "NoAtt" then
				AutoInsertAttEvent = false
			elseif event == "NoClientMotion" then
				AutoInsertClientMotion = false
			elseif event == "CastDuringControlled" then 
				AutoInsertClientMotion = false	
				AutoInsertCanCastDuringControlled = true			
			end
			if event == "NoAtt" then
				isNoAtt = true
			end
		end
	end

	local autoAttClientMotion = 0
	if AutoInsertClientMotion then
		tbl = tbl or {}
		table.insert(tbl, "clientmotion")
		autoAttClientMotion = autoAttClientMotion + 1
	end
	if AutoInsertAttEvent then
		tbl = tbl or {}
		table.insert(tbl, SkillProp.AttMode .. "Att")
		beatEvent = EnumEvent[SkillProp.AttMode .. "Beat"]	
		autoAttClientMotion = autoAttClientMotion + 1
	end
	if AutoInsertCanCastDuringControlled then 
		tbl = tbl or {}
		table.insert(tbl, "CanCastDuringControlled")
	end		
	return tbl, isNoAtt, beatEvent, autoAttClientMotion == 2
end

function CSkillMgrBase:ParseSkillDynEvent(SkillProp)
	local eventStr = SkillProp.SkillEvent 
	if eventStr then
		return
	end
	local cls = SkillProp.ID
	local eventF = AllFormulas.Skill_DynSkillEvent and AllFormulas.Skill_DynSkillEvent[cls]
	local eventFunc = eventF and eventF.DynSkillEvent
	if not eventFunc then
		return
	end

	local res = {} --{[order1] = {tbl, isNoAtt, beatEvent}, [order2] = {tbl, isNoAtt, beatEvent}, ...}
	local maxOrder = CPropertySkill._GetMaxOrder(cls)
	for i=0, maxOrder do
		local eventStr = eventFunc(i)
		local tbl, isNoAtt, beatEvent, bAutoACM = self:_DoParseSkillEvent(eventStr, SkillProp)
		res[i] = {[1] = tbl, [2] = isNoAtt, [3] = beatEvent, [4] = bAutoACM}
	end
	return res
end

function CSkillMgrBase:ParseSkillEvent(SkillProp, Player)
	local eventStr = SkillProp.SkillEvent 
	if not eventStr and Player then
		local eventF = AllFormulas.Skill_DynSkillEvent[SkillProp.ID]
		eventStr = eventF and eventF.DynSkillEvent(Player:GetSkillOrder(SkillProp.ID))
	end

	return self:_DoParseSkillEvent(eventStr, SkillProp)
end

function CSkillMgrBase:OnCastSkill(Character,SkillId,TargetId,DestPosX, DestPosY, DestPosZ)
	local behObj = Character:LuaDataProp():GetSkillBehavior(SkillId, Character)
	if not behObj then return end
	behObj:OnFlowchartEvent("SkillCast", SkillId,TargetId,DestPosX, DestPosY, DestPosZ)
	if g_SkillMgr:IsNeedAddObOnCast(math.floor(SkillId / 100)) then
		behObj:AddOb()
	end
end

function CSkillMgrBase:StopCastSkill(Character,SkillId)
	if SkillId then
		local behObj = Character:LuaDataProp():GetSkillBehavior(SkillId, Character)
		if not behObj then return end

		behObj:RemoveAOITrigger()
		Character:RemoveEventObserver(behObj)
		flowchart.stop(behObj)
	else
		Character:LuaDataProp():ForAllSkillBeh(function(skillCls, behObj) flowchart.stop(behObj) behObj:RemoveAOITrigger() Character:RemoveEventObserver(behObj) end)
	end
end

function CSkillMgrBase:GetStepSkillCls(Character, SkillCls, step)
	SkillCls = self:GetMainSkillClsBySkillCls(SkillCls) or SkillCls
	local skillStep = step or Character and Character:GetSkillStep(SkillCls)
	local tbl = skillStep and self:GetSkillSteps(SkillCls, Character)
	if tbl then
		return tbl[skillStep + 1] or tbl[1]
	else
		return SkillCls
	end
end

function CSkillMgrBase:GetStepSkillId(Character, MainSkillId, step)
	local MainSkillCls = math.floor(MainSkillId/100)
	MainSkillCls = self:GetMainSkillClsBySkillCls(MainSkillCls) or MainSkillCls
	local skillStep = step or Character and Character:GetSkillStep(MainSkillCls)
	local stepTbls = skillStep and self:GetSkillSteps(MainSkillCls, Character)
	if stepTbls then
		local stepSkillCls = stepTbls[skillStep + 1] or stepTbls[1]
		return stepSkillCls and stepSkillCls * 100 + MainSkillId % 100
	end
end

function CSkillMgrBase:GetActualSkillId(Character, SkillId)
	--需经过分段技能判定现在尝试施放的技能具体是哪个
	--新增在HitRecoverCombo状态下切换到连击技能
	if not SkillId then return nil end
	local skillCls = math.floor(SkillId/100)
	local lv = SkillId % 100
	if g_StatusMgr:GetStatus(Character, EPropStatus.HitRecoverCombo) == 1 then
		local comboCheckSkillCls = skillCls
		local bIsMainSkillId = self:IsMainSkillId(SkillId)
		if bIsMainSkillId then
			comboCheckSkillCls = self:GetComboSkillSourceClsByCls(skillCls) or skillCls
		else
			local mainSkillCls = self:GetMainSkillCls(SkillId)
			if mainSkillCls then
				comboCheckSkillCls = self:GetComboSkillSourceClsByCls(mainSkillCls) or mainSkillCls
			end
		end
		
		local isSkillInCombo = false
		if bServer then
			isSkillInCombo = Character:OccupationFunc("IsSkillInComboSkillTb", skillCls)
		else
			isSkillInCombo = Character.m_RecoverComboSkills and Character.m_RecoverComboSkills[comboCheckSkillCls]
		end
		if isSkillInCombo then
			local comboSkill = self:GetComboSkill(Character, comboCheckSkillCls * 100 + lv)
			if comboSkill then
				skillCls = comboSkill
				SkillId = comboSkill * 100 + lv
			end
		end
	end
		
	SkillId = self:GetSkillChangeV(Character, skillCls, lv) or SkillId
	skillCls = math.floor(SkillId/100)

	local StepTb = self:GetSkillSteps(skillCls, Character)
	if StepTb then
		return self:GetStepSkillId(Character, SkillId)
	elseif Character and IdIsUGCSkillCls(skillCls) then
		local ugcSkillTbl = g_UGCLevelMgr:GetUGCSkillTbl(Character, skillCls)
		if ugcSkillTbl then
			return g_UGCLevelMgr:GetUGCStepSkillId(Character, skillCls) or SkillId
		else
			return SkillId
		end
	else
		return SkillId
	end
end

function CSkillMgrBase:GetMainSkillId(SkillId)
	local SkillProp = Skill_Skill[GetSkillClass(SkillId)]
	if SkillProp and SkillProp.MainSkillId then
		return SkillProp.MainSkillId * 100 + SkillId % 100
	end
	return nil
end

function CSkillMgrBase:GetMainSkillCls(SkillId)
	return self:GetMainSkillClsBySkillCls(GetSkillClass(SkillId))
end

function CSkillMgrBase:GetMainSkillClsBySkillCls(skillCls)
	local row = Skill_Skill[skillCls]
	return row and row.MainSkillId
end

function CSkillMgrBase:IsStepSkillId(SkillId)
	return self:GetMainSkillCls(SkillId) ~= nil
end

function CSkillMgrBase:IsStepSkillCls(SkillCls)
	return self:GetMainSkillClsBySkillCls(SkillCls) ~= nil
end

function CSkillMgrBase:IsMainSkillId(SkillId)
	if not SkillId then return false end
	local SkillProp = Skill_Skill[GetSkillClass(SkillId)]
	if SkillProp and SkillProp.StepSkillId then
		return true
	end

	return false
end

function CSkillMgrBase:IsMainSkillCls(SkillCls)
	return self:IsMainSkillId(SkillCls * 100 + 1)
end

function CSkillMgrBase:IsForceUpdateCastCount(realSkillCls)
	if not realSkillCls then return false end
	local data = Skill_Skill[realSkillCls]
	return data and data.IsForceUpdateCastCount and true or false
end

function CSkillMgrBase:IsFirstStepSkillId(skillId, obj)
	local mainSkillCls = self:GetMainSkillCls(skillId)
	if not mainSkillCls then
		return false
	end

	--分段技能的话，只有第一段技能算次数
	local skillCls = GetSkillClass(skillId)
	local steps = self:GetSkillSteps(mainSkillCls, obj)
	if not (steps and next(steps)) then
		return false
	end
	return steps[1] == skillCls
end

function CSkillMgrBase:GetFirstStepSkillCls(skillCls, obj)
	local mainSkillCls = self:GetMainSkillClsBySkillCls(skillCls) or skillCls
	local steps = self:GetSkillSteps(mainSkillCls, obj)
	if not (steps and steps[1]) then
		return mainSkillCls
	end
	return steps[1]
end

function CSkillMgrBase:GetCastCountStatisticSkillCls(skillId, obj)
	local mainSkillCls = self:GetMainSkillCls(skillId)
	if not mainSkillCls then
		return GetRealSkillClsBySourceId(skillId)
	end

	--分段技能的话，只有第一段技能算次数
	local skillCls = GetSkillClass(skillId)
	local steps = self:GetSkillSteps(mainSkillCls, obj)
	if not (steps and next(steps)) then
		return GetRealSkillClsBySourceId(skillId)
	end
	if steps[1] == skillCls then
		return GetRealSkillClsBySourceId(skillId)
	end
end

function CSkillMgrBase:GetComboSkillSource(SkillId)
	local row = Skill_Skill[GetSkillClass(SkillId)]
	return row and row.ComboSource
end

function CSkillMgrBase:GetComboSkillSourceClsByCls(SkillCls)
	local row = Skill_Skill[SkillCls]
	return  row and row.ComboSource
end

function CSkillMgrBase:GetSkillChangeV(Character, skillCls, lv)
	if Character and Character:IsPlayerOrFake() then
		local retCls = GetActualSkillClsWhenStatusChange(skillCls, Character)
		if retCls then
			return retCls * 100 + lv
		end
	end
end

function CSkillMgrBase:GetComboSkill(Character, SkillId)
	local skillCls,lv = GetSkillClsLv(SkillId)
	SkillId = self:GetSkillChangeV(Character, skillCls, lv) or SkillId -- combo 技能有可能配置了skillchange的，所以这里取一下
	local row = Skill_Skill[GetSkillClass(SkillId)]
	return row and row.ComboSkill
end

function CSkillMgrBase:GetComboSkillSourceId(SkillId)
	local comboSource = self:GetComboSkillSource(SkillId)

	if comboSource then
		return comboSource * 100 + SkillId % 100
	end
	return nil
end

function CSkillMgrBase:GetStepSkillIdByStepSkillCls(SkillCls, Character)
	if not Character:IsPlayerOrFake() then return end

	local mainSkillCls = self:GetMainSkillClsBySkillCls(SkillCls)
	if not mainSkillCls then return end

	local mainSkillId = Character:GetSkillByCls(mainSkillCls)
	if not mainSkillId then
		mainSkillId = Character:GetSkillByCls(self:GetComboSkillSource(mainSkillCls * 100 + 1))
	end
	return SkillCls * 100 + mainSkillId % 100
end

function CSkillMgrBase:IsFromSameMainSkill(SkillId, OtherSkillId)
	if not ( SkillId and OtherSkillId) then return false end

	local mainSkillCls = self:GetMainSkillCls(SkillId)
	if not mainSkillCls then return false end

	local otherMainSkillCls = self:GetMainSkillCls(OtherSkillId)
	if not otherMainSkillCls then return false end

	return mainSkillCls == otherMainSkillCls
end

function CSkillMgrBase:LoadSkillLvSource(onlyTbl)
	self.m_SkillLvSourceTb = {}
	for _,v in bddpairs(Skill_SkillChange) do
		for _,v1 in bddpairs(v) do
			for _,v2 in bddpairs(v1.Skills) do
				self.m_SkillLvSourceTb[v2] = v1.Skill
			end
		end
	end

	for _,v in bddpairs(Skill_LYJianYiChaseSkill) do
		local lvSource = self.m_SkillLvSourceTb[v.Skill] or v.Skill
		for chaseSkillCls in string.gmatch(v.ChaseSkills, "(%d+);?") do
			chaseSkillCls = tonumber(chaseSkillCls)
			self.m_SkillLvSourceTb[chaseSkillCls] = lvSource
		end
	end

	if bServer and not onlyTbl then
		for k, v in pairs(self.m_SkillLvSourceTb) do
			--CEngineSkillMgr.Inst():AddLvSourceDesignData(k, v)
			if IsRunningServerCode() and GetServerType() == "gas" then
				CEngineActionMgr.Inst():AddLvSourceDesignData(k, v)
			end
		end
	end
end

function CSkillMgrBase:LoadPlatformWhiteSkills()
	self.m_PlateformWhiteSkillTbl = {}
	for k, v in bddpairs(Platform_Setting.WHITE_SKILL_LIST.TblValue) do
		self.m_PlateformWhiteSkillTbl[v] = 1
	end
end

local __CanUseSkillPlatforms = 
{
	--尽量不要加，平台上放位移技能可能有坑，要经过充分测试
	[55000419] = true, --镜天阁巨大缓慢移动海龟
}

local __CanUseSkillOnPlatformScenes =
{
	--尽量不要加，平台上放位移技能可能有坑，要经过充分测试
	[16100426] = true, --诸神黄昏
	[16100469] = true, --诸神黄昏02
	[16100590] = true, --诸神黄昏03
}

function CSkillMgrBase:IsCanUseSkillOnPlatformScene(sceneTemplateId)
	return __CanUseSkillOnPlatformScenes[sceneTemplateId]
end

function CSkillMgrBase:IsPlatformWhite(skillId, platformEngineId)
	if not skillId then return false end
	local skillCls = IdIsSkill(skillId) and GetSkillClass(skillId) or skillId
	if not IdIsSkillCls(skillCls) then return false end

	local bCommonWhite = self.m_PlateformWhiteSkillTbl[skillCls] or IdIsUGCSkillCls(skillCls)
	if platformEngineId then
		local platform = GetCharacterByEngineObjectGlobalId(platformEngineId)
		if not platform then return false end
		local platformId = platform:GetTemplateId()
		if __CanUseSkillPlatforms[platformId] then
			return true
		end
		local sceneTemplateId = platform:GetSceneTemplateId()

		if self:IsCanUseSkillOnPlatformScene(sceneTemplateId) then
			return true
		end

		local whiteListTbl = Platform_Platform[platformId] and Platform_Platform[platformId].ExclusiveSkillWhiteList
		local bExclusiveWhite = whiteListTbl and whiteListTbl[skillCls]
		return bCommonWhite or bExclusiveWhite
	else
		return bCommonWhite
	end
end

--bSkipSkillChange: 有一类分支技能在判定技能学会的时候，可以不学会主技能（ChangeSkill状态下才适用）
function CSkillMgrBase:GetSkillLvSource(skillCls, bSkipSkillChange)
	return (bSkipSkillChange and self.m_SkillLvSourceCache[skillCls] or self.m_SkillLvSourceCache2[skillCls]) or skillCls
end

function CSkillMgrBase:CacheSkillLvSource()
	self.m_SkillLvSourceCache = {}
	self.m_SkillLvSourceCache2 = {}
	for skillCls,v in bddpairs(Skill_Skill) do
		self.m_SkillLvSourceCache[skillCls], self.m_SkillLvSourceCache2[skillCls] = self:CacheOneSkillLvSource(skillCls)
	end
end

function CSkillMgrBase:CacheOneSkillLvSource(skillCls)
	skillCls = self:GetMainSkillClsBySkillCls(skillCls) or skillCls
	skillCls = self:GetComboSkillSourceClsByCls(skillCls) or skillCls
	local skillCls2 = self.m_SkillLvSourceTb[skillCls] or skillCls
	return self:GetComboSkillSourceClsByCls(skillCls) or skillCls, self:GetComboSkillSourceClsByCls(skillCls2) or skillCls2
end

function CSkillMgrBase:GetSkillCdSkill(skillCls)
	skillCls = self:GetMainSkillClsBySkillCls(skillCls) or skillCls
	
	skillCls = self:GetComboSkillSourceClsByCls(skillCls) or skillCls

	return skillCls
end

function CSkillMgrBase:IdIsDerivedSkillCls(cls)
	local group = Skill_SkillChange_Rev[cls]
	if not group then return false end
	local scCfg = Skill_SkillChange[group[1]][group[2]]
	return scCfg and scCfg['AppearChange'] == EnumSkillAppearChange.Derived or false
end

-- 是否是策划公式控制的分支技能，程序侧只记录，不控制分支
function CSkillMgrBase:IdIsDesignerActionDerivedSkillCls(cls)
    local group = Skill_SkillChange_Rev[cls]
    if not group then return false end
    local scCfg = Skill_SkillChange[group[1]][group[2]]
    return scCfg and scCfg['AppearChange'] == EnumSkillAppearChange.OnlyInBuild or false
end

function CSkillMgrBase:IdIsNeedSaveToBuildSkillCls(cls)
    local group = Skill_SkillChange_Rev[cls]
    if not group then return false end
    local scCfg = Skill_SkillChange[group[1]][group[2]]
    return scCfg and (scCfg['AppearChange'] == EnumSkillAppearChange.OnlyInBuild or scCfg['AppearChange'] == EnumSkillAppearChange.Derived) or false
end

function CSkillMgrBase:GetSkillChangeGroupIdByMainCls(cls)
    local group = type(cls) == "number" and Skill_SkillChange_Rev[cls]
	return group and group[1]
end

function CSkillMgrBase:IdIsDerivedSkillGroupId(GroupId)
	return (Skill_SkillChange[GroupId] and Skill_SkillChange[GroupId][1] and Skill_SkillChange[GroupId][1].AppearChange) == EnumSkillAppearChange.Derived
end

function CSkillMgrBase:IdIsDesignerActionDerivedSkillGroupId(GroupId)
    return (Skill_SkillChange[GroupId] and Skill_SkillChange[GroupId][1] and Skill_SkillChange[GroupId][1].AppearChange) == EnumSkillAppearChange.OnlyInBuild
end

function CSkillMgrBase:IdIsNeedSaveToBuildGroupId(GroupId)
	local appearChange = Skill_SkillChange[GroupId] and Skill_SkillChange[GroupId][1] and Skill_SkillChange[GroupId][1].AppearChange
	return appearChange == EnumSkillAppearChange.Derived or appearChange == EnumSkillAppearChange.OnlyInBuild
end

--- @return type subtype class
function CSkillMgrBase:GetClassSkillType(SkillCls)
	local tbl = SkillUI_SkillMapType[SkillCls]
	if tbl then
		return tbl[1], tbl[2], tbl[3]
	end
end

function CSkillMgrBase:IsSkillForbidEquip(skillCls)
	if Skill_Appear[skillCls] and Skill_Appear[skillCls].ForbidEquip and Skill_Appear[skillCls].ForbidEquip == 1 then	
		return true
	end
	return false
end

-- 检查Skill是否是流派技能
function CSkillMgrBase:IsProfessionalSkill(skillCls)
	skillCls = self:GetMainSkillClsBySkillCls(skillCls) or skillCls
	local skillType, skillSubType = self:GetClassSkillType(skillCls)
	return skillType and skillType == EnumClassSkillType.ProfessionalSkill
end

-- 检查Skill是否是流派技能但是排除偷师流派技能
function CSkillMgrBase:IsProfessionalSkillExceptSteal(skillCls)
	skillCls = self:GetMainSkillClsBySkillCls(skillCls) or skillCls
	local skillType, skillSubType = self:GetClassSkillType(skillCls)
	return skillType == EnumClassSkillType.ProfessionalSkill and skillSubType ~= -1
end


--绝技、江湖百家、江湖伙伴技能才可能加熟练度
function CSkillMgrBase:IsProficiencySkill(cls)
	local t, subt = self:GetClassSkillType(cls)
	return (t == EnumClassSkillType.UniqueSkill or (t == EnumClassSkillType.JianghuSkill and (subt == GetJianghuBaiJiaSubType() or subt == GetJianghuHuoBanSubType())) or self:IsCanUpgradeSubWeaponSkill(cls))
end

local _get_skill_proficiency_f_args = {0, 0}
local profSkillLvf = GetFormulaFunc("Formula", 11700575, "Formula")
function CSkillMgrBase:GetProficiencySkillLv(cls, player)
	if not self:IsProficiencySkill(cls) or not player.m_IsPlayer then return end
	local propSkill = player:SkillProp()
	local proficiency = 0
	local t, subt = self:GetClassSkillType(cls)
	if t == EnumClassSkillType.JianghuSkill and subt == GetJianghuBaiJiaSubType() then
		proficiency = propSkill:GetTotalProficiency(subt)
	elseif t == EnumClassSkillType.UniqueSkill or (t == EnumClassSkillType.JianghuSkill and subt == GetJianghuHuoBanSubType()) then
		proficiency = propSkill:GetProficiency(cls)
	end

	local f = profSkillLvf-- GetFormulaFunc("Formula", 11700575, "Formula")
	if f then
		_get_skill_proficiency_f_args[1] = proficiency or 0
		_get_skill_proficiency_f_args[2] = (t == EnumClassSkillType.UniqueSkill and 1) or (subt == GetJianghuHuoBanSubType() and 2) or 3		 
		local calcLv = f(player, nil, _get_skill_proficiency_f_args) or 0
		local deltaLv = propSkill:GetSkillsDelta_At(cls) or 0
		local newLv = math.max(calcLv + deltaLv, 1)
		local maxLevel = CPropertySkill._GetSkillMaxLevel(cls)
		return math.min(newLv, maxLevel)
	else
		LogCallContext_lua()
		return
	end
end

function CSkillMgrBase:GetIgnoreDegreeStealSkillLv(cls, player)
	if bServer then
		if not g_StealSkillMgr:IsStealSkill(player, cls) then return end
		if not g_StealSkillMgr:IsIgnoreDegreeStealSkill(cls) then return end
	else
		if not g_SkillTheifMgr:IsStealSkill4Me(cls) then return end
		if not g_SkillTheifMgr:IsIgnoreDegreeStealSkill(cls) then return end
	end

	local f = profSkillLvf
	if f then
		local calcLv = f(player, nil, _get_skill_proficiency_f_args) or 0
		local propSkill = player:SkillProp()
		local deltaLv = propSkill:GetSkillsDelta_At(cls) or 0
		local newLv = math.max(calcLv + deltaLv, 1)
		local maxLevel = CPropertySkill._GetSkillMaxLevel(cls)
		return math.min(newLv, maxLevel)
	else
		LogCallContext_lua()
	end
end

function CSkillMgrBase:GetPlayerSkillProficiency(Player, SkillCls)
	if not self:IsProficiencySkill(SkillCls) or not Player.m_IsPlayer then return end
	local propSkill = Player:SkillProp()
	local proficiency = 0
	local t, subt = self:GetClassSkillType(SkillCls)
	if t == EnumClassSkillType.JianghuSkill and subt == GetJianghuBaiJiaSubType() then
		proficiency = propSkill:GetTotalProficiency(subt)
	elseif t == EnumClassSkillType.UniqueSkill or (t == EnumClassSkillType.JianghuSkill and subt == GetJianghuHuoBanSubType()) then
		proficiency = propSkill:GetProficiency(SkillCls)
	end
	return proficiency
end

-- TODO: 取代CSkillUIMgr:GetPlayerLimitSkillProficiency
function CSkillMgrBase:GetPlayerSkillProficiencyLimit(Player, SkillCls)
	local t, subt = self:GetClassSkillType(SkillCls)
	local degreeName = nil
	if t == EnumClassSkillType.UniqueSkill then
		degreeName = "SkillDegreeJJ"
	elseif t == EnumClassSkillType.JianghuSkill then
		if subt == GetJianghuHuoBanSubType() then
			degreeName = "SkillDegreeJHHB"
		elseif subt == GetJianghuBaiJiaSubType() then
			degreeName = "SkillDegreeJHBJ"
		end
	end
	return g_SkillLearnInfoMgr:GetSkillDegreeLimit(Player, degreeName) or 0
end

function CSkillMgrBase:IsSkillCanNotDrag(SkillCls)
	if IdIsCanNotDragFlySkillCls(SkillCls) then
		return true
	end
	
	local data = Skill_Skill[SkillCls]
	return data and data.Category == 0
end

function CSkillMgrBase:FixSkillId(SkillId, Character)
	local skillCls,lv = GetSkillClsLv(SkillId)
	if lv == 0 then
		SkillId = SkillId + 1
	end	
	local maxLevel = CPropertySkill._GetSkillMaxLevel(skillCls) or 0
	--TODO GJX
	if not bServer then
		return math.min(skillCls * 100 + maxLevel, SkillId)
	end

	local serverLevel = GetHomeServerLevel(Character)
	local sealSkillLevel = maxLevel
	if IdIsClassSkillClsIgnoreAllFly(skillCls) then
		sealSkillLevel = GetSealSkillLevel(serverLevel)
	end

	return math.min(skillCls * 100 + math.min(maxLevel, sealSkillLevel), SkillId)
end

function CSkillMgrBase:IsAllowNoTargetEnemySkill(SkillProp)
	return SkillProp and SkillProp.Target == "Enemy" and SkillProp.AllowNoTarget == 1 
end

function CSkillMgrBase:GetSkillRangeNearFar(SkillData, Lv, Player)
	assert(false, "Base GetSkillRangeNearFar Err")
end

function CSkillMgrBase:_FixSkillDestPosParam(SkillProp, Character, SkillContext)
	if SkillProp.Target == "None" then --没有释放目标的技能，坐标设成自己
		SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ = Character.m_engineObject:GetPixelPosv3()
	elseif SkillProp.Target == "Location" or SkillProp.Target == "Direction" then --方向性的技能，不传坐标，但是有目标引擎Id，默认朝他放
		if not (SkillContext.DestPosX and SkillContext.DestPosY and SkillContext.DestPosZ) then
			local Targeter = SkillContext.TargetId and GetCharacterByEngineObjectGlobalId(SkillContext.TargetId)
			if Targeter then
				SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
			end
		end
	else --其他选中目标的技能，坐标强制设成目标的位置
		local Targeter = SkillContext.TargetId and GetCharacterByEngineObjectGlobalId(SkillContext.TargetId)
		if Targeter then
			SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
		end
	end

	if not SkillContext.DestPosZ then
		if SkillContext.DestPosX and SkillContext.DestPosY then
			--TODO 如果x，y的坐标都有，只有z没有，可能是服务端放对象放技能，接口还没改全，z轴设成它自己的坐标
			SkillContext.DestPosZ = Character.m_engineObject:GetPixelZ()
			--print("ERROR SKILL POS1 ", SkillContext.DestPosX , SkillContext.DestPosY , SkillContext.DestPosZ)
		else
			--x，y，z的坐标都没有，就设成他自己的坐标
			--print("ERROR SKILL POS2 ", SkillContext.DestPosX , SkillContext.DestPosY , SkillContext.DestPosZ)
			SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ = Character.m_engineObject:GetPixelPosv3()
		end
	end
	
	local cls = GetSkillClsLv(SkillContext.SkillId or 0)
	-- TODO: 空战技能的destpos也需要服务器修正，以防外挂。暂时先确保功能实现
	local bSpecialSkill = IdIsAirSkillCls(cls) or IdIsFlySkill(SkillContext.SkillId) or IsAirLocationSkillProp(SkillProp)
	if SkillContext.IsClientRequest and (SkillProp.Target == "Location" or SkillProp.Target == "Direction") and not bSpecialSkill then
		local rangeNear, rangeFar = self:GetSkillRangeNearFar(SkillProp, SkillContext.Lv, Character)
		local sourceX, sourceY = Character.m_engineObject:GetPixelPosv()
		local dist = Dist_XY2(sourceX, sourceY, SkillContext.DestPosX, SkillContext.DestPosY)
		local x, y, z = SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ
		if dist < rangeNear * pixel_per_grid then
			x, y = RayIntercept2(sourceX, sourceY, nil, x, y, nil, rangeNear * pixel_per_grid)
			z = Character.m_Scene.m_CoreScene:GetNearestGridZ(x/pixel_per_grid, y/pixel_per_grid, math.floor(z/pixel_per_grid))
		elseif dist > rangeFar * pixel_per_grid then
			x, y = RayIntercept2(sourceX, sourceY, nil, x, y, nil, rangeFar * pixel_per_grid)
			z = Character.m_Scene.m_CoreScene:GetNearestGridZ(x/pixel_per_grid, y/pixel_per_grid, math.floor(z/pixel_per_grid))
		end

		-- 潜水时不需要取水面格子
		if g_StatusMgr:GetStatus(Character, EPropStatus.SinkingCamera) == 0 then
			z = math.max(z, GetSceneWaterGridHeight(Character.m_Scene.m_CoreScene, x / pixel_per_grid,
				y / pixel_per_grid, z / pixel_per_grid) * pixel_per_grid)
		end

		SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ = x, y, z
	end
	
	if SkillProp.Target == "Direction" and SkillContext.AttackDir == nil then
		local sx, sy, sz = Character.m_engineObject:GetPixelPosv3()	
		local dx, dy, dz = SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ
		local attackDir = VectorToDirection2(sx, sy, dx, dy)
		if sx == dx and sy == dy then attackDir = Character:GetFaceDirection()  end
		SkillContext.AttackDir = attackDir
		SkillContext.AttackOffsetX = dx - sx 
		SkillContext.AttackOffsetY = dy - sy
		SkillContext.AttackOffsetZ = dz - sz 
	end
end

function CSkillMgrBase:GetSkillTurnAngle(SkillProp, Character, SkillContext)
	local destDir = nil
	if SkillContext.YHFSkillTurnDir and 
		(SkillContext.YHFSkillMoveDir == "DOWN" or SkillContext.YHFSkillMoveDir == "LEFT" or SkillContext.YHFSkillMoveDir == "RIGHT")then
		destDir = SkillContext.YHFSkillTurnDir
	elseif SkillProp.Target == "Direction" then
		destDir = SkillContext.AttackDir
		if destDir == nil then
			LogCallContext_lua()
		end
	else
		local sx, sy = Character.m_engineObject:GetPixelPosv()
		local dx, dy = SkillContext.DestPosX, SkillContext.DestPosY
		if sx == dx and sy == dy then
			return EnumSkillTurnAngleResult.eTurnNoNeed, Character.m_engineObject:GetDirectionDegree()
		end
		destDir = VectorToDirection2(sx, sy, dx, dy)
	end
	local curDir = Character.m_engineObject:GetDirectionDegree()
	local diff_angle = math.abs(destDir - curDir)%360
	if(diff_angle > 180) then
		diff_angle = 360 - diff_angle
	end
	
	if SkillProp.FaceDirectly == 1 then
		return EnumSkillTurnAngleResult.eFaceToDirection, destDir
	elseif SkillProp.FaceDirectly == 2 then
		return EnumSkillTurnAngleResult.eFaceToDirection, destDir
	end
	
	return EnumSkillTurnAngleResult.eTurnNoNeed, destDir
end

function CSkillMgrBase:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
	--ScopeOrigin*: 调用方指定的 Scope 基准点(客户端上报打击点等)
	local sourceX, sourceY, sourceZ, sourceDir
	if SkillContext and SkillContext.ScopeOriginX then
		sourceX, sourceY, sourceZ = SkillContext.ScopeOriginX, SkillContext.ScopeOriginY, SkillContext.ScopeOriginZ
		sourceDir = SkillContext.ScopeOriginDir or Sourcer:GetFaceDirection()
	else
		sourceX, sourceY, sourceZ = Sourcer.m_engineObject:GetPixelPosv3()
		sourceDir = Sourcer:GetFaceDirection()
	end
	return self:_GetSkillScopeBasePointAndAngleWithPos(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData, sourceX, sourceY, sourceZ, sourceDir)
end

function CSkillMgrBase:_GetSkillScopeBasePointAndAngleWithPos(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData, sourceX, sourceY, sourceZ, sourceDir)
	local targetX, targetY, targetZ = nil, nil, nil

	local SkillTarget = SkillProp.Target
	targetX, targetY, targetZ = SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ
	
	local angle
	if SkillContext.ScopeOriginDir then		
		angle = math.rad(SkillContext.ScopeOriginDir)
	elseif SkillTarget == "None" then
		angle = math.rad(sourceDir)
	elseif SkillTarget == "Direction" then
	    angle = math.rad(SkillContext.AttackDir or sourceDir)
	else
		angle = math.atan2(targetY - sourceY, targetX - sourceX)
	end

	local retAngle = angle
	if ScopeData.Rotate and ScopeData.Rotate > 0 then
		retAngle = retAngle - math.rad(ScopeData.Rotate)
	end

	if ScopeData.TargetPos == "self" then
		return sourceX, sourceY, sourceZ, retAngle
	end

	if ScopeData.TargetPos == "pos" then
		return targetX, targetY, targetZ, retAngle
	end

	if ScopeData.TargetPos == "selfoffset" then
		local len = ScopeData.DirPosOffset * (1 + Sourcer:GetParam(EFightProp.Offset))
		local retX = sourceX + len * math.cos(angle) * pixel_per_grid
		local retY = sourceY + len * math.sin(angle) * pixel_per_grid
		local retZ = sourceZ
		if ScopeData.DirVerticalOffset then
			local vertLen = ScopeData.DirVerticalOffset * (1 + Sourcer:GetParam(EFightProp.Offset))
			-- positive => right, negative => left
			local vertAngle = angle - PI / 2
			retX = retX + vertLen * math.cos(vertAngle) * pixel_per_grid
			retY = retY + vertLen * math.sin(vertAngle) * pixel_per_grid
		end

		return retX, retY, retZ, retAngle
	end

	if ScopeType ~= "allplayersinscene" and ScopeType ~= "allplayersinscenewithfake" then	
		LogCallContext_lua()
	end
	return sourceX, sourceY, sourceZ, retAngle --确保万一用的
end


--假玩家躲避技能用的--手游
function CSkillMgrBase:CheckPosInScope2D_Simple(sourcer, scopePos, dir, scopeType, scopeData, skillContext, checkPos)
	local scopeFactor = skillContext and self:GetScopeFactor(sourcer, skillContext.Cls) or 1
	if scopeType == "area" then
		return IsPointInCircle(scopePos, scopeData.Randius * 64 * scopeFactor, checkPos)
	
	elseif scopeType == "fan" or scopeType == "semicircle" then
		local fanAngle
		if scopeType == "fan" then
			fanAngle = math.rad(scopeData.Degree)
		else
			fanAngle = math.pi * 0.5
		end
		return IsPointInFan(scopePos, scopeData.Randius * 64 * scopeFactor, fanAngle, {x = math.cos(dir), y = math.sin(dir)}, checkPos)
	
	elseif scopeType == "line" then
		return IsPointInRect(scopePos, scopeData.Width * 64, scopeData.Length * 64 * scopeFactor, {x = math.cos(dir), y = math.sin(dir)}, checkPos)

	elseif scopeType == "eqtri" then
		return IsPointInEqTri(scopePos, scopeData.Randius * 64 * scopeFactor, {x = math.cos(dir), y = math.sin(dir)}, checkPos)

	elseif scopeType == "union" then
		-- 优先用 scope 创建时预存的子 scope 几何（union/intersect/except 子 scope 中心/朝向可能不同）
		local pos1 = scopeData.SubPos1 or scopePos
		local ang1 = scopeData.SubAngle1 or dir
		local pos2 = scopeData.SubPos2 or scopePos
		local ang2 = scopeData.SubAngle2 or dir
		return self:CheckPosInScope2D_Simple(sourcer, pos1, ang1, scopeData.SubScopeType1, scopeData.SubScopeData1, skillContext, checkPos) 
			or self:CheckPosInScope2D_Simple(sourcer, pos2, ang2, scopeData.SubScopeType2, scopeData.SubScopeData2, skillContext, checkPos)

	elseif scopeType == "intersect" then
		local pos1 = scopeData.SubPos1 or scopePos
		local ang1 = scopeData.SubAngle1 or dir
		local pos2 = scopeData.SubPos2 or scopePos
		local ang2 = scopeData.SubAngle2 or dir
		return self:CheckPosInScope2D_Simple(sourcer, pos1, ang1, scopeData.SubScopeType1, scopeData.SubScopeData1, skillContext, checkPos) 
			and self:CheckPosInScope2D_Simple(sourcer, pos2, ang2, scopeData.SubScopeType2, scopeData.SubScopeData2, skillContext, checkPos)

	elseif scopeType == "except" then
		local pos1 = scopeData.SubPos1 or scopePos
		local ang1 = scopeData.SubAngle1 or dir
		local pos2 = scopeData.SubPos2 or scopePos
		local ang2 = scopeData.SubAngle2 or dir
		return self:CheckPosInScope2D_Simple(sourcer, pos1, ang1, scopeData.SubScopeType1, scopeData.SubScopeData1, skillContext, checkPos) 
			and not self:CheckPosInScope2D_Simple(sourcer, pos2, ang2, scopeData.SubScopeType2, scopeData.SubScopeData2, skillContext, checkPos)
	end
	return false
end

function CSkillMgrBase:LoadJiangHuJueXingSKills()
	self.m_JiangHuJueXingClsInfo = {}
	for buddyId, v in bddpairs(Buddy_BuddyInfo) do
		if v.JianghuSkill and bddtype(v.JianghuSkill) == "table" then
			for i = 2, #(v.JianghuSkill) do
				self.m_JiangHuJueXingClsInfo[ v.JianghuSkill[i] ] = v.JianghuSkill[1]
			end
		end
	end
end

function CSkillMgrBase:GetJiangHuJueXingOriSKill(cls)
	return self.m_JiangHuJueXingClsInfo[cls]
end 

function CSkillMgrBase:LoadExploreSkillGuide()
	
	local tblVal = GameSetting_Common.GUIDE_EXPLORE_DEFAULT_SKILL.tblVal[ExploreSkillBuildId]
	assert(tblVal ~= nil,  "fatal error, GUIDE_EXPLORE_DEFAULT_SKILL.tblVal[ExploreSkillBuildId] == nil")
	assert(#tblVal == 8,  "fatal error, #GUIDE_EXPLORE_DEFAULT_SKILL.tblVal[ExploreSkillBuildId] ~= 8")

	local dest = {
		id = ExploreSkillBuildId,
		name = LOCALIZESTRING.EXPLORE_SKILL_BUILD_NAME,		
		[EnumSkillType2HotSlot.ProfessionalSkill] = {tblVal[1], tblVal[2], tblVal[3], tblVal[4], tblVal[5]},
		[EnumSkillType2HotSlot.JianghuSkill] = {tblVal[6], tblVal[7]},			
		[EnumSkillType2HotSlot.UniqueSkill] = {tblVal[8]},	
		[EnumSkillType2HotSlot.MainSkill] = {},	--src.m_MainSkillBtn
		[EnumSkillType2HotSlot.PassiveSkill] = {1},--src.m_PassiveID or 1
		[EnumSkillType2HotSlot.TalentSkill] = {0}, --src.m_TalentID or 0
		[EnumSkillType2HotSlot.OccupationStatus] = {0},
		[EnumSkillType2HotSlot.ManufactureConfig] = {0},
		[EnumSkillType2HotSlot.IdentityPassiveSkill] = {0, 0, 0, 0, 0, 0},
		-- desc = src.Desc,
		-- unlockGrade = 0,
		-- gpTag = {},
	}

	self.m_SkillExploreGuideData = {}
	self.m_SkillExploreGuideData[ExploreSkillBuildId] = dest
end

function CSkillMgrBase:LoadSkillGuide()
	self.m_SkillGuideData = {}
	GetSkillGuide(self.m_SkillGuideData)
	self:LoadExploreSkillGuide()
end

function CSkillMgrBase:LoadYHFStatusSkills()
	self.m_YHFStatusSkills = {}
	for k, v in bddpairs(SkillUI_YHFStatusSkill) do
		local lvFunc = AllFormulas.SkillUI_YHFStatusSkill[k]
		assert(type(v.Class) == "number" and type(v.SkillCls) == "number")
		local priority = v.Priority or 0
		local lv = lvFunc and lvFunc.SkillLv or 1
		table.safe_set(self.m_YHFStatusSkills, v.Class, "status", k, {v.SkillCls, lv, priority, v.FlySkillCls or 0, v.QJZSkillCls or 0})
		table.safe_set(self.m_YHFStatusSkills, v.Class, "cls", v.SkillCls, {k, lv, priority})
		if v.FlySkillCls then
			table.safe_set(self.m_YHFStatusSkills, v.Class, "cls", v.FlySkillCls, {k, lv, priority})
		end
	end
end

function CSkillMgrBase:_GetStatusSkill(player, idx, forcePlayerClass)
	local playerClass = forcePlayerClass or player:GetClass()
	local cfg = self.m_YHFStatusSkills[playerClass] and self.m_YHFStatusSkills[playerClass].status

	for k, v in pairs(cfg  or EMPTY_TABLE) do
		if v[idx] > 0 and EPropStatus[k] and g_StatusMgr:GetStatus(player, EPropStatus[k]) == 1 then
			--print("GetYHFStatusSkill", k, g_StatusMgr:GetStatus(player, EPropStatus[ k ]), v[1], v[2])
			return true, ((v[idx])*100 + ( type(v[2])=="function" and (v[2])(player, player, nil) or v[2] )), v[3]
		end
	end

	cfg = self.m_YHFStatusSkills[0] and self.m_YHFStatusSkills[0].status
	for k, v in pairs(cfg  or EMPTY_TABLE) do
		if v[idx] > 0 and EPropStatus[k] and g_StatusMgr:GetStatus(player, EPropStatus[k]) == 1 then
			--print("GetYHFStatusSkill", k, g_StatusMgr:GetStatus(player, EPropStatus[ k ]), v[1], v[2])
			return true, ((v[idx])*100 + ( type(v[2])=="function" and (v[2])(player, player, nil) or v[2] )), v[3]
		end
	end	
end

function CSkillMgrBase:GetYHFStatusSkill(player, forcePlayerClass)
	local inStatus, skillId, priority = self:_GetStatusSkill(player, 1, forcePlayerClass)
	local effectReplaceSkillId, effectReplacePriority = player:GetEffectReplaceYHFSkill()

	-- 比较选优先级更高的
	if priority and (not effectReplacePriority or priority > effectReplacePriority) then
		return inStatus, skillId, priority
	elseif effectReplacePriority then
		return true, effectReplaceSkillId, effectReplacePriority
	end
end

function CSkillMgrBase:GetFlyStatusSkill(player)
	local inStatus, skillId, priority = self:_GetStatusSkill(player, 4)
	local effectReplaceSkillId, effectReplacePriority = player:GetEffectReplaceFlySkill()

	-- 比较选优先级更高的
	if priority and (not effectReplacePriority or priority > effectReplacePriority) then
		return inStatus, skillId, priority
	elseif effectReplacePriority then
		return true, effectReplaceSkillId, effectReplacePriority
	end
end

function CSkillMgrBase:GetQJZStatusSkill(player)
	local inStatus, skillId, priority = self:_GetStatusSkill(player, 5)
	local effectReplaceSkillId, effectReplacePriority = player:GetEffectReplaceQJZSkill()

	-- 比较选优先级更高的
	if priority and (not effectReplacePriority or priority > effectReplacePriority) then
		return inStatus, skillId, priority
	elseif effectReplacePriority then
		return true, effectReplaceSkillId, effectReplacePriority
	end
end

function CSkillMgrBase:CheckYHFStatusSkill(player, cls)
	local playerClass = player:GetClass()
	local cfg = self.m_YHFStatusSkills[playerClass] and self.m_YHFStatusSkills[playerClass].cls
	local s = cfg and cfg[cls] 
	if s and EPropStatus[ s[1] ] and g_StatusMgr:GetStatus(player, EPropStatus[ s[1] ]) == 1 then
		--print("CheckYHFStatusSkill", s[1],s[2], g_StatusMgr:GetStatus(player, EPropStatus[ s[1] ]), cls)
		return true,  type(s[2])=="function" and (s[2])(player, player, nil) or s[2]
	end

	cfg = self.m_YHFStatusSkills[0] and self.m_YHFStatusSkills[0].cls
	s = cfg and cfg[cls] 
	if s and EPropStatus[ s[1] ] and g_StatusMgr:GetStatus(player, EPropStatus[ s[1] ]) == 1 then
		--print("CheckYHFStatusSkill", s[1],s[2], g_StatusMgr:GetStatus(player, EPropStatus[ s[1] ]), cls)
		return true,  type(s[2])=="function" and (s[2])(player, player, nil) or s[2]
	end

	return player:CheckYHFEffectReplaceSkill(cls)
end

function CSkillMgrBase:GetSkillGuide(player, class)
	if not class then
		class = GetPlayerRealClass(player)
		if class == 0 then
			class = player:GetClass()
		end
	end
	return self.m_SkillGuideData[class]	or {}
end

function CSkillMgrBase:GetCurSkillBuildId(player)
	if not player or not player.m_IsPlayer then return end

	local index = player:GetCharacterSetting(EnumCharacterSettings.eSkillBuildId)
	return index or 1
end

function CSkillMgrBase:ShouldUseUnifiedSwitch(player)
	local settingUD = player:GetCharacterSetting(EnumCharacterSettings.eSkillEditSettingInfo) 
	local settingData = settingUD and msgpack.unpack(settingUD)
	if settingData then
		return settingData.CurSelectBuildGroupPage == 1 and settingData.AutoSwitchGroup == 1
	end
	return false
end

---@see 将名字修改标记和技能修改标记合在一起存了
function CSkillMgrBase:SetSKillBuildTag(player,buildId)
	local changeTags = player:GetCharacterSetting(EnumCharacterSettings.eSkillGuideChangeTag) or EMPTY_TBL_UD
	changeTags = msgpack.unpack(changeTags)
	if not changeTags[buildId] then
		changeTags[buildId] = true
		changeTags[buildId * 100] = true
		player:SaveCharacterSetting(EnumCharacterSettings.eSkillGuideChangeTag, msgpack.pack(changeTags), false)
	end
end

function CSkillMgrBase:SetSKillBuildNameTag(player, buildId)
	local changeTags = player:GetCharacterSetting(EnumCharacterSettings.eSkillGuideChangeTag) or EMPTY_TBL_UD
	changeTags = msgpack.unpack(changeTags)
	if not changeTags[buildId * 100] then
		changeTags[buildId * 100] = true
		player:SaveCharacterSetting(EnumCharacterSettings.eSkillGuideChangeTag, msgpack.pack(changeTags), false)
	end
end

function CSkillMgrBase:GetChangeSkillBuildNameTag(player,buildId)
	return self:GetChangeSkillBuildTag(player, buildId * 100)
end

-- 套路标签 副本等等
function CSkillMgrBase:SetSkillBuildTagTag(player, buildId)
	local changeTags = player:GetCharacterSetting(EnumCharacterSettings.eSkillBuildTag) or EMPTY_TBL_UD
	changeTags = msgpack.unpack(changeTags)
	if not changeTags[buildId * 100] then
		changeTags[buildId * 100] = true
		player:SaveCharacterSetting(EnumCharacterSettings.eSkillBuildTag, msgpack.pack(changeTags), false)
	end
end

function CSkillMgrBase:SetSkillBuildAutoSwitch(player, bAuto)
	local auto = player:GetCharacterSetting(EnumCharacterSettings.eSkillBuildAutoSwitch) or 0
	if auto ~= bAuto then
		player:SaveCharacterSetting(EnumCharacterSettings.eSkillBuildAutoSwitch, bAuto, false)
	end
end

function CSkillMgrBase:GetSkillBuildTagTag(player, buildId)
	local changeTags = player:GetCharacterSetting(EnumCharacterSettings.eSkillBuildTag) or EMPTY_TBL_UD
	changeTags = msgpack.unpack(changeTags)
	return changeTags[buildId]
end

function CSkillMgrBase:GetSkillBuildAutoSwitch(player)
	local auto = player:GetCharacterSetting(EnumCharacterSettings.eSkillBuildAutoSwitch) or 0
	return auto
end

function CSkillMgrBase:GetChangeSkillBuildTag(player,buildId)
	local changeTags = player:GetCharacterSetting(EnumCharacterSettings.eSkillGuideChangeTag) or EMPTY_TBL_UD
	changeTags = msgpack.unpack(changeTags)
	return changeTags[buildId]
end


function CSkillMgrBase:GetAllSkillBuild_Custom(player, class)
	if not player or not player.m_IsPlayer then return end
	local buildData = player:GetCharacterSetting(EnumCharacterSettings.eCustomSkillBuild)
	buildData = buildData and msgpack.unpack(buildData) or {}
	self:_GetAllSkillBuild_Custom(player, buildData, class)
	return buildData
end

function CSkillMgrBase:_GetAllSkillBuild_Custom(player, buildData, class)
	if not class then
		class = GetPlayerRealClass(player)
		if class == 0 then
			class = player:GetClass()
		end
	end
	local skillTypes = EnumSkillBuildTypes
	local guideCnt = GameSetting_Common.GUIDE_SKILL_BUILD_NUM.numVal
	-- 预设数据
	local guideData = self:GetSkillGuide(player, class)
	for i = 1, guideCnt do
		if not buildData[i] or not next(buildData[i]) then
			buildData[i] = guideData[i] and DeepCopyDesignTable(guideData[i]) or {}
		else
			local playerData = buildData[i]
			local designData = guideData[i] or EMPTY_TABLE
			for _, skillType in ipairs(skillTypes) do
				for j = 1, EnumHotItemSkillTypeSize[skillType] do
					if not playerData[skillType] or not playerData[skillType][j] then
						playerData[skillType] = playerData[skillType] or {}
						playerData[skillType][j] = designData[skillType][j]
					end
				end
			end		

			playerData.desc = designData.desc
			if not self:GetChangeSkillBuildNameTag(player, i) then
				playerData.name = designData.name
			end
			playerData.nameUnlock=designData.nameUnlock
			playerData.unlockGrade=designData.unlockGrade
		end
	end
	-- 自定义数据
	for i = 1, player:GetCustomSkillBuildNum() do
		local index = guideCnt + i
		if not buildData[index] or not next(buildData[index]) then
			buildData[index] = {id = index, name = LOCALIZESTRING.STR_SKILLGUILDE_DEFAULT_PREX .. i,}
		end
	end
	if not buildData[ExploreSkillBuildId] then
		buildData[ExploreSkillBuildId] = DeepCopyTable(self.m_SkillExploreGuideData[ExploreSkillBuildId])
	end
	local stealDesign = SkillUI_StealSkill[class] and SkillUI_StealSkill[class].PassiveSkills
	if stealDesign then
		-- 把非基础套路的偷师固定特质给加上下
		for i, v in pairs(buildData) do
			if i > guideCnt then
				local data = v[EnumSkillType2HotSlot.StealPassiveSkill]
				if not data then
					data = {}
					v[EnumSkillType2HotSlot.StealPassiveSkill] = data
				end
				local i = 1
				for _, v in bddipairs(stealDesign) do 
					if v[2] == 1 then
						data[i] = v[1]
						i = i + 1
					end
				end
			end
		end
	end

	-- 如果没有默认技能，设置为0
	for i, v in pairs(buildData) do
		for _, skillType in ipairs(skillTypes) do
			if not v[skillType] then
				v[skillType] = {}
			end
			for j = 1, EnumHotItemSkillTypeSize[skillType] do
				if not v[skillType][j] then
					v[skillType][j] = 0
				end
			end
		end	
	end
end

-- 精简数据存储，只保留主要五个技能的位置，其他数据例如绝技，江湖，名字等都是从customskillbuild和默认字符串，因此不再存储
function CSkillMgrBase:SimplifyRogueCustomSkillBuild(buildData)
	if not buildData then return {} end
	buildData.name = nil
	-- 删掉除了EnumSkillType2HotSlot.ProfessionalSkill的部分
	for _, skillType in ipairs(EnumSkillBuildTypes) do
		if skillType ~= EnumSkillType2HotSlot.ProfessionalSkill then
			buildData[skillType] = nil
		end
	end	

	return buildData
end

function CSkillMgrBase:GetRougeSkillBuildEnumType(player)
	local secondClass, mainClass = player:GetSecondClass()
	if secondClass then
		return EnumCharacterSettings.eRogueCustomSkillBuildSecondClass
	else
		return EnumCharacterSettings.eRogueCustomSkillBuild
	end
end

function CSkillMgrBase:GetAllSkillBuild_Rogue(player)
	if not player or not player.m_IsPlayer then return end
	local buildData = player:GetCharacterSetting(self:GetRougeSkillBuildEnumType(player))
	buildData = buildData and msgpack.unpack(buildData) or {}
	local skillTypes = EnumSkillBuildTypes
	local guideCnt = 0
	local cfg = Rogue_Weapon
	local class = player:GetClass()

	-- 自定义数据, 从共3个
	for i = 1, 3 do
		local index = guideCnt + i
		if not buildData[index] 
			or not next(buildData[index]) 
			or not buildData[index][EnumSkillType2HotSlot.ProfessionalSkill] 
			or not next(buildData[index][EnumSkillType2HotSlot.ProfessionalSkill]) then
			
			buildData[index] = {id = index, name = Rogue_Weapon[class][i].Name or (LOCALIZESTRING.STR_SKILLGUILDE_DEFAULT_PREX .. i)}
			local class = player:GetClass()
			local defaultSkillTbl = Rogue_Weapon[class][i].DefaultSkills
			buildData[index][EnumSkillType2HotSlot.ProfessionalSkill] = {}
			local skillSlotCnt = EnumHotItemSkillTypeSize[EnumSkillType2HotSlot.ProfessionalSkill]
			if defaultSkillTbl then
				for k, v in bddpairs(defaultSkillTbl) do
					buildData[index][EnumSkillType2HotSlot.ProfessionalSkill][skillSlotCnt + 1 - k] = IdIsSkillCls(v) and v or 0
				end
			end
		else
			buildData[index].id = index
			buildData[index].name = Rogue_Weapon[class][i].Name or (LOCALIZESTRING.STR_SKILLGUILDE_DEFAULT_PREX .. i)
		end
	end

	-- 如果没有默认技能，设置为0
	for i, v in ipairs(buildData) do
		for _, skillType in ipairs(skillTypes) do
			if not v[skillType] then
				v[skillType] = {}
			end
			for j = 1, EnumHotItemSkillTypeSize[skillType] do
				if not v[skillType][j] then
					v[skillType][j] = 0
				end
			end
		end	
	end

	return buildData
end

function CSkillMgrBase:GetSkillBuildType_Mojin(player)
	local secondClass = player:GetSecondClass()
	if secondClass then
		return EnumCharacterSettings.eMoJinPreCustomSkillBuildSecondClass
	else
		return EnumCharacterSettings.eMoJinPreCustomSkillBuild
	end
end
function CSkillMgrBase:GetAllSkillBuild_MoJin(player)
	if not player or not player.m_IsPlayer then return end
	
	local buildType = self:GetSkillBuildType_Mojin(player)
	local buildData = player:GetCharacterSetting(buildType)
	buildData = buildData and msgpack.unpack(buildData) or {}

	return buildData
end

function CSkillMgrBase:GetAllSkillBuildByType(player, buildType, cls)
	if buildType == EnumCharacterSettings.eCustomSkillBuild then
		return self:GetAllSkillBuild_Custom(player, cls)
	elseif buildType == EnumCharacterSettings.eRogueCustomSkillBuild or
			buildType == EnumCharacterSettings.eRogueCustomSkillBuildSecondClass then
		return self:GetAllSkillBuild_Rogue(player)
	elseif buildType == EnumCharacterSettings.eMoJinPreCustomSkillBuildSecondClass 
		or buildType == EnumCharacterSettings.eMoJinPreCustomSkillBuild  then
		return self:GetAllSkillBuild_MoJin(player)
	else
		-- LogCallContext_lua()
		return self:GetAllSkillBuild_Custom(player)
	end
end

function CSkillMgrBase:GetAllSkillBuild( player, class )
	if not player or not player.m_IsPlayer then return end
	return self:GetAllSkillBuild_Custom(player, class)
end


function CSkillMgrBase:ConvertSkillIdToOrigin(id)
	local mainSkillId = Skill_Skill[id].MainSkillId
	if mainSkillId then
		id = mainSkillId
	end
	if Skill_SkillChange_Rev[id] then
		local switchGroup, switchIdx = Skill_SkillChange_Rev[id][1], Skill_SkillChange_Rev[id][2]
		id = Skill_SkillChange[switchGroup][switchIdx].Skill
	end
	return id
end


function CSkillMgrBase:LoadSkillTypeData()
	-- 解析见SkillUIExt.lua
	self.m_SkillType2SkillCls = SkillUI_SkillType2SkillCls
	self.m_SkillCls2SkillType = SkillUI_SkillCls2SkillType
end

function CSkillMgrBase:GetSkillTbWithType(Player, SkillType)
	local skillTb = {}
	if self.m_SkillType2SkillCls[Player:GetClass()] and self.m_SkillType2SkillCls[Player:GetClass()][SkillType] then
		for i,v in bddpairs(self.m_SkillType2SkillCls[Player:GetClass()][SkillType]) do
			skillTb[v.SkillCls] = true
		end
	end
	if self.m_SkillType2SkillCls[0] and self.m_SkillType2SkillCls[0][SkillType] then
		for i,v in bddpairs(self.m_SkillType2SkillCls[0][SkillType]) do
			skillTb[v.SkillCls] = true
		end
	end

	--伙伴也是通用的
	if self.m_SkillType2SkillCls[100] and self.m_SkillType2SkillCls[100][SkillType] then
		for i,v in bddpairs(self.m_SkillType2SkillCls[100][SkillType]) do
			skillTb[v.SkillCls] = true
		end
	end

	return skillTb
end

function CSkillMgrBase:CheckSkillTypeByClassAndCls(characterClass,skillCls, skillType)
	return skillType == (self.m_SkillCls2SkillType[characterClass] and self.m_SkillCls2SkillType[characterClass][skillCls])
end

function CSkillMgrBase:GetSkillTypeBySkillCls(characterClass,skillCls)
	if self.m_SkillCls2SkillType[0][skillCls] ~=nil then 
		return self.m_SkillCls2SkillType[0][skillCls]
	end  

	-- 伙伴技能
	if self.m_SkillCls2SkillType[100][skillCls] ~=nil then
		return self.m_SkillCls2SkillType[100][skillCls]
	end

	-- 大荒技能
	if self.m_SkillCls2SkillType[101][skillCls] ~= nil then
		return self.m_SkillCls2SkillType[101][skillCls]
	end

	-- 趣味技能
	if self.m_SkillCls2SkillType[102][skillCls] ~= nil then
		return self.m_SkillCls2SkillType[102][skillCls]
	end

	-- 江湖被动特质
	if self.m_SkillCls2SkillType[103][skillCls] ~= nil then
		return self.m_SkillCls2SkillType[103][skillCls]
	end

	-- 机甲技能
	if self.m_SkillCls2SkillType[104][skillCls] ~= nil then
		return self.m_SkillCls2SkillType[104][skillCls]
	end

	-- 偷师
	if not bServer then
		if g_SkillTheifMgr and g_SkillTheifMgr:IsStealSkill(skillCls) then
			return EnumClassSkillType.StealPassiveSkill
		end
	else
        if g_StealSkillMgr:IsStealSkillByPlayerClass(characterClass, skillCls) then
			return EnumClassSkillType.StealPassiveSkill
		end
	end
	
    -- 身份特质
    if LiveSkill_Trait[skillCls] then
        return EnumClassSkillType.IdentityPassiveSkill
    end

	if self.m_SkillCls2SkillType[characterClass]==nil then
		return nil
	end

	if self.m_SkillCls2SkillType[characterClass][skillCls]==nil then
		return nil
	end
	return self.m_SkillCls2SkillType[characterClass][skillCls]
end

--- {{{ 技能z轴区域判断，支持上下俯仰

--- @brief 初始化技能z轴命中的上下文SkillZContext，并预处理相关数据
-- @param SourceX, SourceY, SourceZ, TargetX, TargetY, TargetZ, ZAbove, ZBelow 均为pixel单位
-- @param MaxPitch和MinPitch：最大最小俯仰角度，范围是[-90,90]，必传，不传代表不支持俯仰旋转
-- 注意：这个函数返回的context不可重入，前一个用完了才能创建下一个
local _skillZContext = {}
function CSkillMgrBase:SkillZContext_Create(SourceX, SourceY, SourceZ, DestX, DestY, DestZ, ZAbove, ZBelow, MaxPitch,
                                            MinPitch)
    _skillZContext.center = SourceZ
    _skillZContext.above = ZAbove or -1
    _skillZContext.below = ZBelow or -1

    -- 清空，避免残留污染
    _skillZContext.sourceToDestZ = nil

    local sourceToDestZ = DestZ - SourceZ
    -- 没有俯仰角限制、没有高度差、没有高度限制时，不初始化俯仰数据
    if MaxPitch and MinPitch and sourceToDestZ ~= 0 and (_skillZContext.above ~= -1 or _skillZContext.below ~= -1) then
        -- 特殊处理：srcpos跟dstpos在同一个grid，判断范围为垂直范围的情况，不适用斜率的方式，而是直接增扩z轴判断范围
        local sgx, sgy = GetGridByPixel2(SourceX, SourceY)
        local dgx, dgy = GetGridByPixel2(DestX, DestY)
        if sgx == dgx and sgy == dgy and (sourceToDestZ > 0 and MaxPitch == 90 or sourceToDestZ < 0 and MinPitch == -90) then
            return self:SkillZContext_CreateVertical(_skillZContext, SourceZ, sourceToDestZ)
        end

        local vecDestX, vecDestY = DestX - SourceX, DestY - SourceY
        local vecDestLen2 = vecDestX ^ 2 + vecDestY ^ 2
        local vecDestLen = sqrt(vecDestLen2)
        local sourceToDestZMax = vecDestLen * tan(rad(MaxPitch))
        local sourceToDestZMin = vecDestLen * tan(rad(MinPitch))
        sourceToDestZ = clamp(sourceToDestZ, sourceToDestZMin, sourceToDestZMax)

        -- 确保需要技能倾斜时，再更新SkillZContext
        if sourceToDestZ ~= 0 then
            _skillZContext.sourceToDestZ = sourceToDestZ
            _skillZContext.sourcePosX = SourceX
            _skillZContext.sourcePosY = SourceY
            _skillZContext.vecDestX = vecDestX
            _skillZContext.vecDestY = vecDestY
            _skillZContext.vecDestLen2 = vecDestLen2
        end
    end
    return _skillZContext
    -- pppf("attacker pos", SourceX, SourceY, SourceZ)
    -- pppf("dest pos", DestX, DestY, DestZ)
    -- pppf("ScopeType", ScopeType)
end

-- 特殊处理：srcpos跟dstpos在同一个grid，创建垂直范围的Ctx
function CSkillMgrBase:SkillZContext_CreateVertical(Ctx, SourceToDestZ)
    Ctx.sourceToDestZ = nil
    local sourceToDestZHalf = SourceToDestZ / 2
    local sourceToDestZHalfAbs = abs(sourceToDestZHalf)
    if Ctx.above ~= -1 then Ctx.above = sourceToDestZHalfAbs end
    if Ctx.below ~= -1 then Ctx.below = sourceToDestZHalfAbs end
    Ctx.center = Ctx.center + sourceToDestZHalf
	return Ctx
end

--- @brief 返回在（TargetX,TargetY）位置的z轴命中技能中心高度。
function CSkillMgrBase:SkillZContext_GetCenter(SkillZContext, TargetX, TargetY)
    if not SkillZContext.sourceToDestZ then
        return SkillZContext.center
    end

    -- solve the project ratio
    -- 1. 在xy平面上，计算vt（source到target的向量）到vd（source到dest的向量）的投影长度 = vt . vd / |vd|
    -- 2. 再除以|vd|算出缩放比 = (vt . vd) / (vd . vd)
    -- 3. 最后将缩放比乘到dest与source之间的高度差上，求出target xy位置的技能命中高度
    local vecTargetX, vecTargetY = TargetX - SkillZContext.sourcePosX, TargetY - SkillZContext.sourcePosY
    local dotVal = vecTargetX * SkillZContext.vecDestX + vecTargetY * SkillZContext.vecDestY
    local ratio = dotVal / SkillZContext.vecDestLen2

    local skillZCenter = SkillZContext.center + SkillZContext.sourceToDestZ * ratio
    -- pppf("update skill z center", SkillZContext.center, skillZCenter)
    return skillZCenter
end

--- @brief 判断目标位置与高度是否在技能高度范围内
function CSkillMgrBase:SkillZContext_Check(SkillZContext, TargetX, TargetY, TargetZBelow, TargetZAbove)
    local SkillZAbove = SkillZContext.above
    local SkillZBelow = SkillZContext.below

    if SkillZAbove < 0 and SkillZBelow < 0 then
        return true
    end

    local SkillZCenter = self:SkillZContext_GetCenter(SkillZContext, TargetX, TargetY)

    -- pppf("SkillTargetRange", SkillZCenter - SkillZBelow, SkillZCenter + SkillZAbove, targetZBelow,
    --     targetZBelow + Target:GetAABBHeight())
    if (SkillZBelow >= 0 and TargetZAbove < SkillZCenter - SkillZBelow) or
        (SkillZAbove >= 0 and TargetZBelow > SkillZCenter + SkillZAbove) then
        return false
    end

    return true
end

--- }}} 技能z轴区域判断，支持上下俯仰

local function _SkillScopeGridListToSet(gridList)
	local gridSet = {}
	if gridList then
		for _, gridId in ipairs(gridList) do
			gridSet[gridId] = true
		end
	end
	return gridSet
end

local function _SkillScopeGridSetToList(gridSet)
	local gridList = {}
	for gridId in pairs(gridSet) do
		table.insert(gridList, gridId)
	end
	return gridList
end

function CSkillMgrBase:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter)
	local Scene = Sourcer:GetCoreScene()
	local gridList 
	--圆形范围
	if ScopeType == "area" then
		local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		gridList = Scene:QueryGridsWithPixelInRoundvt(x, y, z, ScopeData.ZAbove, ScopeData.ZBelow, ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)))

	--长方形范围
	elseif ScopeType == "line" then
		local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		gridList = Scene:QueryGridsWithAngleInDirectionRectanglevt(x, y, z, angle, ScopeData.ZAbove, ScopeData.ZBelow, ScopeData.Width, ScopeData.Length * (self:GetScopeFactor(Sourcer, SkillProp.ID)))
	--半圆范围
	elseif ScopeType == "semicircle" then
		local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		gridList = Scene:QueryGridsWithAngleInFanvt(x, y, z, angle, ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)), DegreeToRadian(90), ScopeData.ZAbove, ScopeData.ZBelow)		
	--扇形范围
	elseif ScopeType == "fan" then
		local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		gridList = Scene:QueryGridsWithAngleInFanvt(x, y, z, angle, ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)), DegreeToRadian(ScopeData.Degree), ScopeData.ZAbove, ScopeData.ZBelow)
	elseif ScopeType == "union" then
		local gridList1 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter)
		local gridList2 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter)
		if not gridList1 or not gridList2 then return end
		local gridSet = _SkillScopeGridListToSet(gridList1)
		for _, gridId in ipairs(gridList2) do
			gridSet[gridId] = true
		end
		gridList = _SkillScopeGridSetToList(gridSet)
	elseif ScopeType == "intersect" then
		local gridList1 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter)
		local gridList2 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter)
		if not gridList1 or not gridList2 then return end
		local gridSet2 = _SkillScopeGridListToSet(gridList2)
		local gridSet = {}
		for _, gridId in ipairs(gridList1) do
			if gridSet2[gridId] then
				gridSet[gridId] = true
			end
		end
		gridList = _SkillScopeGridSetToList(gridSet)
	elseif ScopeType == "except" then
		local gridList1 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter)
		local gridList2 = self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter)
		if not gridList1 or not gridList2 then return end
		local gridSet2 = _SkillScopeGridListToSet(gridList2)
		local gridSet = {}
		for _, gridId in ipairs(gridList1) do
			if not gridSet2[gridId] then
				gridSet[gridId] = true
			end
		end
		gridList = _SkillScopeGridSetToList(gridSet)
	else
		PQLOG("GetSkillEffectedGrids Failed", SkillProp.ID, ScopeType)
		--LogCallContext_lua()
		return
	end
	-- for i, v in ipairs(gridList) do
	-- 	print("==========", i, v, math.floor(v/4096), v - 4096 * math.floor(v/4096), x, y, z, ScopeData.ZAbove, ScopeData.ZBelow, SkillProp.ID, ScopeData.Randius, ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)))
	-- end
	return gridList
end

function CSkillMgrBase:GetSkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter)
	return self:_QuerySkillEffectedGrids(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter)
end

-- ============================================================
-- #1241421 技能 Scope 内 2D 点采样 (golden-angle + Halton, 不依赖整格离散化)
-- 给不靠整格列表的范围效果用 (花路点采样/特效/光影掩膜等)
-- 支持: area / line / fan / semicircle 原子 + union / intersect / except 组合
-- 不支持: eqtri 等 (静默跳过)
-- ============================================================

local _SCOPE_PT_DEFAULT_SPACING = 64                                -- 像素, 默认 1 游戏格
local _SCOPE_PT_GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))

local function _ScopePtHalton(index, base)
	local r, f, i = 0, 1 / base, index
	while i > 0 do
		r = r + f * (i % base)
		i = math.floor(i / base)
		f = f / base
	end
	return r
end

local function _ScopePtHasIntersectOrExcept(ScopeType, ScopeData)
	if ScopeType == "intersect" or ScopeType == "except" then return true end
	if ScopeType == "union" then
		return _ScopePtHasIntersectOrExcept(ScopeData.SubScopeType1, ScopeData.SubScopeData1)
			or _ScopePtHasIntersectOrExcept(ScopeData.SubScopeType2, ScopeData.SubScopeData2)
	end
	return false
end

-- 判定一个像素点是否在 Scope 内; 递归处理 union/intersect/except
-- padding > 0: 形状内缩 (圆/扇半径减, 矩形宽长减; except 子 2 不内缩, 保证完整排除)
function CSkillMgrBase:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter, padding)
	padding = padding or 0
	if ScopeType == "union" then
		return self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter, padding)
			or self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter, padding)
	elseif ScopeType == "intersect" then
		return self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter, padding)
		   and self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter, padding)
	elseif ScopeType == "except" then
		return self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter, padding)
		   and not self:IsPointInSkillScope(px, py, SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter, 0)
	end
	if ScopeType ~= "area" and ScopeType ~= "line" and ScopeType ~= "fan" and ScopeType ~= "semicircle" then return false end
	local x, y, _, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
	if not x then return false end
	local factor = self:GetScopeFactor(Sourcer, SkillProp.ID) or 1
	if ScopeType == "area" then
		local R = (ScopeData.Randius or 0) * factor * pixel_per_grid - padding
		if R <= 0 then return false end
		local dx, dy = px - x, py - y
		return dx * dx + dy * dy <= R * R
	elseif ScopeType == "fan" or ScopeType == "semicircle" then
		local R = (ScopeData.Randius or 0) * factor * pixel_per_grid - padding
		if R <= 0 then return false end
		local dx, dy = px - x, py - y
		if dx * dx + dy * dy > R * R then return false end
		local halfRadian = (ScopeType == "semicircle") and (math.pi / 2) or math.rad(ScopeData.Degree or 0)
		if halfRadian <= 0 then return false end
		local diff = math.atan2(dy, dx) - (angle or 0)
		while diff > math.pi do diff = diff - 2 * math.pi end
		while diff < -math.pi do diff = diff + 2 * math.pi end
		return math.abs(diff) <= halfRadian
	elseif ScopeType == "line" then
		local W = (ScopeData.Width or 0) * pixel_per_grid - 2 * padding
		local L = (ScopeData.Length or 0) * factor * pixel_per_grid - padding
		if W <= 0 or L <= 0 then return false end
		local rad = (angle or 0) - math.pi / 2
		local cosR, sinR = math.cos(rad), math.sin(rad)
		local dx, dy = px - x, py - y
		local lx = dx * cosR + dy * sinR
		local ly = -dx * sinR + dy * cosR
		return lx >= -W / 2 and lx <= W / 2 and ly >= 0 and ly <= L
	end
	return false
end

-- 把 Scope 树拍平为原子 (atom) 列表; union 收集两个子, intersect/except 只收子 1 (sub1 ⊇ 结果)
function CSkillMgrBase:_CollectScopePointAtoms(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter, padding, atoms)
	if ScopeType == "union" then
		self:_CollectScopePointAtoms(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter, padding, atoms)
		self:_CollectScopePointAtoms(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType2, ScopeData.SubScopeData2, Targeter, padding, atoms)
		return
	end
	if ScopeType == "intersect" or ScopeType == "except" then
		self:_CollectScopePointAtoms(SkillProp, Sourcer, SkillContext, ScopeData.SubScopeType1, ScopeData.SubScopeData1, Targeter, padding, atoms)
		return
	end
	if ScopeType ~= "area" and ScopeType ~= "line" and ScopeType ~= "fan" and ScopeType ~= "semicircle" then return end
	local x, y, _, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
	if not x then return end
	local factor = self:GetScopeFactor(Sourcer, SkillProp.ID) or 1
	local atom = { Type = ScopeType, CenterX = x, CenterY = y, Angle = angle, Padding = padding }
	if ScopeType == "area" then
		atom.Radius = (ScopeData.Randius or 0) * factor * pixel_per_grid
	elseif ScopeType == "line" then
		atom.Width = (ScopeData.Width or 0) * pixel_per_grid
		atom.Length = (ScopeData.Length or 0) * factor * pixel_per_grid
	elseif ScopeType == "fan" then
		atom.Radius = (ScopeData.Randius or 0) * factor * pixel_per_grid
		atom.HalfRadian = math.rad(ScopeData.Degree or 0)
	elseif ScopeType == "semicircle" then
		atom.Radius = (ScopeData.Randius or 0) * factor * pixel_per_grid
		atom.HalfRadian = math.pi / 2
	end
	atoms[#atoms + 1] = atom
end

function CSkillMgrBase:_SampleScopePointAtom(atom, spacing, rand, positions, maxCount, filterCtx)
	local maxAdd = (maxCount > 0) and (maxCount * 2 - #positions) or math.huge
	local function tryPush(px, py)
		if maxAdd <= 0 then return false end
		if filterCtx and not self:IsPointInSkillScope(px, py, filterCtx.SkillProp, filterCtx.Sourcer,
				filterCtx.SkillContext, filterCtx.Type, filterCtx.Data, filterCtx.Targeter, filterCtx.Padding) then
			return true   -- 跳点不停采样
		end
		positions[#positions + 1] = px
		positions[#positions + 1] = py
		maxAdd = maxAdd - 2
		return true
	end

	if atom.Type == "area" then
		local R = atom.Radius - atom.Padding
		if R <= 0 then return end
		local count = math.max(1, math.floor(math.pi * R * R / (spacing * spacing)))
		local angleOffset = rand() * 2 * math.pi
		for n = 1, count do
			local r = R * math.sqrt((n - 0.5) / count)
			local a = angleOffset + n * _SCOPE_PT_GOLDEN_ANGLE
			if not tryPush(atom.CenterX + math.cos(a) * r, atom.CenterY + math.sin(a) * r) then break end
		end
	elseif atom.Type == "fan" or atom.Type == "semicircle" then
		local R = atom.Radius - atom.Padding
		local halfRadian = atom.HalfRadian
		if R <= 0 or halfRadian <= 0 then return end
		local baseRadian = atom.Angle or 0
		-- 扇形面积 = halfRadian · R²
		local count = math.max(1, math.floor(halfRadian * R * R / (spacing * spacing)))
		local uOffset, vOffset = rand(), rand()
		for n = 1, count do
			local u = (_ScopePtHalton(n, 2) + uOffset) % 1
			local v = (_ScopePtHalton(n, 3) + vOffset) % 1
			local r = R * math.sqrt(u)
			local a = baseRadian + (v * 2 - 1) * halfRadian
			if not tryPush(atom.CenterX + math.cos(a) * r, atom.CenterY + math.sin(a) * r) then break end
		end
	elseif atom.Type == "line" then
		local W = atom.Width - 2 * atom.Padding
		local L = atom.Length - atom.Padding
		if W <= 0 or L <= 0 then return end
		-- 与 IsPointInSkillScope/QueryGrids 同语义: angle - π/2 让 ly+ 方向 = 攻击朝向
		local rad = (atom.Angle or 0) - math.pi / 2
		local cosR, sinR = math.cos(rad), math.sin(rad)
		local count = math.max(1, math.floor(W * L / (spacing * spacing)))
		local uOffset, vOffset = rand(), rand()
		for n = 1, count do
			local u = (_ScopePtHalton(n, 2) + uOffset) % 1
			local v = (_ScopePtHalton(n, 3) + vOffset) % 1
			local lx = (u - 0.5) * W
			local ly = v * L
			if not tryPush(atom.CenterX + lx * cosR - ly * sinR, atom.CenterY + lx * sinR + ly * cosR) then break end
		end
	end
end

-- 在 SkillScope 内采样均匀分布的 2D 点; 返回 { x1,y1, x2,y2, ... } 像素平铺数组 (或 nil)
-- opts:
--   Spacing  (px, 默认 64=1格) 目标点间距, 越大越稀; boids 同模型 collider 强制 ~50px 下限, 太密会浪费
--   MaxCount (默认 0=不限)      总点数上限
--   Padding  (px, 默认 0)       形状内缩, 让边界附近不出点
--   Seed     (默认 nil)         随机种子; 不填走全局 math.random 状态
function CSkillMgrBase:SampleSkillScopePoints(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter, opts)
	opts = opts or EMPTY_TABLE
	local spacing = opts.Spacing
	if not spacing or spacing <= 0 then spacing = _SCOPE_PT_DEFAULT_SPACING end
	local maxCount = opts.MaxCount or 0
	local padding = opts.Padding or 0

	-- 可选 seed: 局部 LCG, 不污染全局 math.random
	local rand
	if opts.Seed then
		local state = opts.Seed
		rand = function()
			state = (state * 1103515245 + 12345) % 0x80000000
			return state / 0x80000000
		end
	else
		rand = math.random
	end

	local atoms = {}
	self:_CollectScopePointAtoms(SkillProp, Sourcer, SkillContext, ScopeType, ScopeData, Targeter, padding, atoms)
	if #atoms == 0 then return nil end

	local needsFilter = _ScopePtHasIntersectOrExcept(ScopeType, ScopeData)
	local filterCtx = needsFilter and {
		Type = ScopeType, Data = ScopeData, SkillProp = SkillProp,
		Sourcer = Sourcer, SkillContext = SkillContext, Targeter = Targeter, Padding = padding,
	} or nil

	local positions = {}
	for _, atom in ipairs(atoms) do
		self:_SampleScopePointAtom(atom, spacing, rand, positions, maxCount, filterCtx)
		if maxCount > 0 and #positions >= maxCount * 2 then break end
	end
	return positions
end

SKILL_EFFECT_CHARACTER_EXTRA_DATA_SIZE = 2
function CSkillMgrBase:_GetSkillEffectedCharacterSet(SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext,
                                                     ScopeType, ScopeData, MaxNum, MaxPlayerNum, SelectPlayerFirst,
                                                     bIgnoreSkill, bIgnoreChemi, bIsExcept)
    MaxNum = math.min(MaxNum or self.DEFAULT_MAX_SKILL_TARGET_NUM, self.m_MAX_TARGET_NUM)
    MaxPlayerNum = math.min(MaxPlayerNum or self.DEFAULT_MAX_SKILL_PLAYER_TARGET_NUM, self.m_MAX_PLAYER_TARGET_NUM)
    bIsExcept = bIsExcept and true or false

    local CoreScene = Sourcer:GetCoreScene()
    local EffectedCharacters = nil
    local ExtraData = g_LuaPoolMgr:AllocTable(SKILL_EFFECT_CHARACTER_EXTRA_DATA_SIZE) --技能的来源坐标，单攻技能就是玩家位置，范围技能是范围的圆心
    local TotalN = 0
    local TotalPlayerN = 0
    local EffectChemiCharacters = nil

    local lv = SkillContext.Lv

    -- 根据开关和是否有 pitch 决定 Z 筛选策略
    -- 无pitch：引擎做 Z 完全筛选，不创建 skillZContext
    -- 有pitch或开关关：走旧逻辑，Lua 做 pitch 修正
    local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
    local zAbove, zBelow = -1, -1
    local skillZContext = nil

    if g_EngineZFilterEnabled and not hasPitch then
        -- 无 pitch：传真值给引擎，引擎做完全 Z 筛选
        -- 注意：引擎查询的 Z 上下范围参数为栅格单位（内部会再 *eGridSpan 转像素），不可再乘 pixel_per_grid
        zAbove = ScopeData.ZAbove or -1
        zBelow = ScopeData.ZBelow or -1
        -- skillZContext 保持 nil → IsTargetInRangeZ 直接 return true
    else
        -- 有 pitch 或开关关：走旧逻辑
        local sourceX, sourceY, sourceZ = Sourcer.m_engineObject:GetPixelPosv3()
        skillZContext = self:SkillZContext_Create(
            sourceX, sourceY, sourceZ,
            SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ,
            ScopeData.ZAbove and ScopeData.ZAbove * pixel_per_grid,
            ScopeData.ZBelow and ScopeData.ZBelow * pixel_per_grid,
            SkillProp.MaxPitch, SkillProp.MinPitch)
    end

    --单目标攻击
    if ScopeType == "none" then
        local sourceX, sourceY = Sourcer.m_engineObject:GetPixelPosv3()
        ExtraData.skillSourceX, ExtraData.skillSourceY = sourceX, sourceY

        if Targeter then
            EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
                { Targeter.m_engineObjectId }, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
                SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, nil, bIgnoreSkill, bIgnoreChemi)
        end

        EffectedCharacters = EffectedCharacters or g_LuaPoolMgr:AllocTable()
	--场景中所有玩家
    elseif ScopeType == "allplayersinscene" then
        local EffectedCharacterIdList = {}
        for player, _ in pairs(Sourcer.m_Scene.m_Players) do
            table.insert(EffectedCharacterIdList, player.m_engineObjectId)
        end

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, nil, bIgnoreSkill, bIgnoreChemi)
    --场景中所有假玩家
    elseif ScopeType == "allplayersinscenewithfake" then
        local EffectedCharacterIdList = {}
        for player, _ in pairs(Sourcer.m_Scene.m_Players) do
            table.insert(EffectedCharacterIdList, player.m_engineObjectId)
        end
        for player, _ in pairs(Sourcer.m_Scene.m_FakePlayers) do
            table.insert(EffectedCharacterIdList, player.m_engineObjectId)
        end

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, nil, bIgnoreSkill, bIgnoreChemi)
    --圆形范围
    elseif ScopeType == "area" then
        local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType,
            ScopeData)
        ExtraData.skillSourceX, ExtraData.skillSourceY = x, y
		if skillZContext then skillZContext.center = z end

        local EffectedCharacterIdList = CoreScene:QueryObjectsWithPixelInRoundvt(x, y, z, zAbove, zBelow,
            ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)), 0, 0, 0, bIsExcept)

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, skillZContext, bIgnoreSkill, bIgnoreChemi)

    --长方形范围
    elseif ScopeType == "line" then
        local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType,
            ScopeData)
        ExtraData.skillSourceX, ExtraData.skillSourceY = x, y
        if skillZContext then skillZContext.center = z end

        local EffectedCharacterIdList = CoreScene:QueryObjectsWithAngleInDirectionRectanglevt(x, y, z, angle,
            zAbove, zBelow, ScopeData.Width, ScopeData.Length * (self:GetScopeFactor(Sourcer, SkillProp.ID)),
            bIsExcept)

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, skillZContext, bIgnoreSkill, bIgnoreChemi)

    --半圆范围
    elseif ScopeType == "semicircle" then
        local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType,
            ScopeData)
        ExtraData.skillSourceX, ExtraData.skillSourceY = x, y
        if skillZContext then skillZContext.center = z end

        local EffectedCharacterIdList = CoreScene:QueryObjectsWithAngleInFanvt(x, y, z, angle,
            ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)), DegreeToRadian(90), zAbove,
            zBelow)

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, skillZContext, bIgnoreSkill, bIgnoreChemi)

    --扇形范围
    elseif ScopeType == "fan" then
        local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType,
            ScopeData)
        ExtraData.skillSourceX, ExtraData.skillSourceY = x, y
        if skillZContext then skillZContext.center = z end

        local EffectedCharacterIdList = CoreScene:QueryObjectsWithAngleInFanvt(x, y, z, angle,
            ScopeData.Randius * (self:GetScopeFactor(Sourcer, SkillProp.ID)), DegreeToRadian(ScopeData.Degree),
            zAbove, zBelow, bIsExcept)

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, skillZContext, bIgnoreSkill, bIgnoreChemi)

    --正三角形范围
    elseif ScopeType == "eqtri" then
        local x, y, z, angle = self:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType,
            ScopeData)
        ExtraData.skillSourceX, ExtraData.skillSourceY = x, y
        if skillZContext then skillZContext.center = z end

        local EffectedCharacterIdList = CoreScene:QueryObjectsWithAngleInEqTrivt(x, y, z, angle,
            ScopeData.Randius * self:GetScopeFactor(Sourcer, SkillProp.ID), zAbove, zBelow)

        EffectedCharacters, TotalN, TotalPlayerN, EffectChemiCharacters = self:GenerateValidCharacterSet(
            EffectedCharacterIdList, SkillProp, lv, EffectTargetCondition, Sourcer, MaxNum, MaxPlayerNum,
            SelectPlayerFirst, SkillContext.TargetId, SkillContext.IgnoreId, skillZContext, bIgnoreSkill, bIgnoreChemi)

    elseif ScopeType == "union" then
        g_LuaPoolMgr:ReleaseTable(ExtraData)
        EffectedCharacters, ExtraData, TotalN, TotalPlayerN, EffectChemiCharacters = self:_GetSkillEffectedCharacterSet(
            SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType1,
            ScopeData.SubScopeData1, MaxNum, MaxPlayerNum, SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, bIsExcept)
        if TotalN < MaxNum then
            local EffectedCharacters2, ExtraData2, _, _, EffectChemiCharacters2 = self:_GetSkillEffectedCharacterSet(
                SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType2,
                ScopeData.SubScopeData2, MaxNum, MaxPlayerNum, SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, bIsExcept)
            g_LuaPoolMgr:ReleaseTable(ExtraData2)
            for k, v in pairs(EffectedCharacters2) do
                if not EffectedCharacters[k] and (not k:IsPlayerOrFake() or TotalPlayerN < MaxPlayerNum) then
                    EffectedCharacters[k] = v

                    if k:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end

                    TotalN = TotalN + 1
                    if TotalN >= MaxNum then break end
                end
            end
            EffectChemiCharacters = EffectChemiCharacters or (EffectChemiCharacters2 and g_LuaPoolMgr:AllocTable())
            for k, v in pairs(EffectChemiCharacters2 or EMPTY_TABLE) do
                EffectChemiCharacters[k] = v
            end

            g_LuaPoolMgr:ReleaseTable(EffectedCharacters2)
            if EffectChemiCharacters2 then
                g_LuaPoolMgr:ReleaseTable(EffectChemiCharacters2)
            end
        end
    elseif ScopeType == "intersect" then
        local EffectedCharacters1, ExtraData1, _, _, EffectChemiCharacters1 = self:_GetSkillEffectedCharacterSet(
            SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType1,
            ScopeData.SubScopeData1, self.m_MAX_SKILL_TARGET_NUM_FOR_SET, self.m_MAX_SKILL_TARGET_NUM_FOR_SET,
            SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, bIsExcept)
        local EffectedCharacters2, ExtraData2, _, _, EffectChemiCharacters2 = self:_GetSkillEffectedCharacterSet(
            SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType2,
            ScopeData.SubScopeData2, self.m_MAX_SKILL_TARGET_NUM_FOR_SET, self.m_MAX_SKILL_TARGET_NUM_FOR_SET,
            SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, bIsExcept)

        EffectedCharacters = g_LuaPoolMgr:AllocTable()
        EffectChemiCharacters = (EffectChemiCharacters1 and EffectChemiCharacters2) and g_LuaPoolMgr:AllocTable() or nil
        g_LuaPoolMgr:ReleaseTable(ExtraData)
        ExtraData = ExtraData1

        for k, v in pairs(EffectedCharacters1) do
            if EffectedCharacters2[k] and (not k:IsPlayerOrFake() or TotalPlayerN < MaxPlayerNum) then
                EffectedCharacters[k] = v

                if k:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end

                TotalN = TotalN + 1
                if TotalN >= MaxNum then break end
            end
        end

        for k, v in pairs(EffectChemiCharacters1 or EMPTY_TABLE) do
            if EffectChemiCharacters2 and EffectChemiCharacters2[k] then
                EffectChemiCharacters[k] = v
            end
        end

        g_LuaPoolMgr:ReleaseTable(EffectedCharacters1)
        g_LuaPoolMgr:ReleaseTable(EffectedCharacters2)
        g_LuaPoolMgr:ReleaseTable(EffectChemiCharacters1)
        if EffectChemiCharacters2 then
            g_LuaPoolMgr:ReleaseTable(EffectChemiCharacters2)
        end
        g_LuaPoolMgr:ReleaseTable(ExtraData2)
    elseif ScopeType == "except" then
        local EffectedCharacters1, ExtraData1, _, _, EffectChemiCharacters1 = self:_GetSkillEffectedCharacterSet(
            SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType1,
            ScopeData.SubScopeData1, self.m_MAX_SKILL_TARGET_NUM_FOR_SET, self.m_MAX_SKILL_TARGET_NUM_FOR_SET,
            SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, bIsExcept)
        local EffectedCharacters2, ExtraData2, _, _, EffectChemiCharacters2 = self:_GetSkillEffectedCharacterSet(
            SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeData.SubScopeType2,
            ScopeData.SubScopeData2, self.m_MAX_SKILL_TARGET_NUM_FOR_SET, self.m_MAX_SKILL_TARGET_NUM_FOR_SET,
            SelectPlayerFirst, bIgnoreSkill, bIgnoreChemi, not bIsExcept)

        EffectedCharacters = g_LuaPoolMgr:AllocTable()
        EffectChemiCharacters = EffectChemiCharacters1
        g_LuaPoolMgr:ReleaseTable(ExtraData)
        ExtraData = ExtraData1

        for k, v in pairs(EffectedCharacters1) do
            if not EffectedCharacters2[k] and (not k:IsPlayerOrFake() or TotalPlayerN < MaxPlayerNum) then
                EffectedCharacters[k] = v

                if k:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end

                TotalN = TotalN + 1
                if TotalN >= MaxNum then break end
            end
        end

        if EffectChemiCharacters then
            for k, v in pairs(EffectChemiCharacters2 or EMPTY_TABLE) do
                EffectChemiCharacters[k] = nil
            end
        end

        g_LuaPoolMgr:ReleaseTable(EffectedCharacters1)
        g_LuaPoolMgr:ReleaseTable(EffectedCharacters2)
        if EffectChemiCharacters2 then
            g_LuaPoolMgr:ReleaseTable(EffectChemiCharacters2)
        end
        g_LuaPoolMgr:ReleaseTable(ExtraData2)
    else
        EffectedCharacters = g_LuaPoolMgr:AllocTable()
        EffectChemiCharacters = g_LuaPoolMgr:AllocTable()
        ExtraData.skillSourceX, ExtraData.skillSourceY = Sourcer.m_engineObject:GetPixelPosv()
        LogCallContext_lua()
    end

    return EffectedCharacters, ExtraData, TotalN, TotalPlayerN, EffectChemiCharacters
end

function CSkillMgrBase:IsSkillConnected(Attacker, Defender, SkillCls)
	local gp = Attacker:GetGameplay()
	if gp then
		local gpTemplateId = gp.m_TemplateId
		-- 技能穿墙白名单
		local skillPenetrationWhitelist = Gameplay_Gameplay[gpTemplateId] and Gameplay_Gameplay[gpTemplateId].SkillPenetrationWhitelist
		if skillPenetrationWhitelist and skillPenetrationWhitelist[SkillCls] then return true end
	end

	return IsSkillConnected(Attacker, Defender)
end

function CSkillMgrBase:IsValidSkillTarget(Attacker, Defender, EffectTarget, SkillCls, EffectTargetCondition, Lv, AttMode, SkillZContext)
	return self:IsTargetInRangeZ(Defender, SkillZContext)
		and self:CheckSkillValidTargetType(Attacker, Defender, EffectTarget, SkillCls, AttMode)
		and self:IsSkillConnected(Attacker, Defender, SkillCls) --技能穿墙判断
		and (not EffectTargetCondition or EffectTargetCondition(Attacker, Defender, Lv))   --特殊目标条件判断
end

function CSkillMgrBase:IsTargetInRangeZ(Target, SkillZContext)
    if not Target then return false end
    if not SkillZContext then return true end
    if SkillZContext.above < 0 and SkillZContext.below < 0 then return true end
	local dx, dy, dz = Target.m_engineObject:GetPixelPosv3()
	return self:SkillZContext_Check(SkillZContext, dx, dy, dz, dz + Target:GetAABBHeight())
end

local EID2OBJ = GetCharacterByEngineObjectGlobalId
function CSkillMgrBase:GenerateValidCharacterSet(EffectedCharacterIdList, SkillProp, Lv, EffectTargetCondition, Sourcer,
    MaxNum, MaxPlayerNum, SelectPlayerFirst, ChoosenTargetId, IgnoreId, SkillZContext, bIgnoreSkill, bIgnoreChemi)
    local ret = g_LuaPoolMgr:AllocTable()
    local num = 0
    local playerNum = 0
	local bCollectSkill = not bIgnoreSkill
	local bCollectChemi = not bIgnoreChemi

    -- 现在这里强制都把顺序打乱一下，防止技能不停的query到相同的玩家
    -- 以后如果性能有问题，可以考虑加列来配置是否随机
    ShuffleArray(EffectedCharacterIdList)
    local skillElement = bCollectChemi and GetSkillPropColRealV(Sourcer, SkillProp.ID, "Element", SkillProp.Element)
    local chemiRet = skillElement and g_LuaPoolMgr:AllocTable() or nil

	local EffectedCharacterIdListLen = #EffectedCharacterIdList

    local choosenFound = false
    local characters = {}
    for i = 1, EffectedCharacterIdListLen do
        characters[i] = EID2OBJ(EffectedCharacterIdList[i])
        if EffectedCharacterIdList[i] == ChoosenTargetId then
            choosenFound = true
        end
    end

    local skillEffectTarget = SkillProp.EffectTarget
    local skillId = SkillProp.ID
    local skillAttMode = SkillProp.AttMode

    local choosenTarget = EID2OBJ(ChoosenTargetId)
    local choosenMainBody = choosenTarget and choosenTarget:GetMainBodyOrSelf() or nil

    if choosenTarget then
        local found = choosenFound

        if found and skillElement and self:CheckValidChemiTargetType(Sourcer, choosenTarget, SkillZContext) then
            chemiRet[choosenTarget] = true
        end

        if found and IgnoreId ~= ChoosenTargetId and
            self:IsValidSkillTarget(Sourcer, choosenTarget, skillEffectTarget, skillId, EffectTargetCondition,
                Lv, skillAttMode, SkillZContext) then

            if choosenTarget.m_IsPlayer or choosenTarget.m_IsFakePlayer then
                if playerNum < MaxPlayerNum then
                    ret[choosenTarget] = true
                    playerNum = playerNum + 1
                    num = num + 1
                end
            else
                if num < MaxNum then
                    ret[choosenTarget] = true
                    num = num + 1
                end
            end
        end
    end

    if SelectPlayerFirst == 1 then
        -- 先选玩家
        if playerNum < MaxPlayerNum then
            for i = 1, EffectedCharacterIdListLen do
                local EffectedCharacterId = EffectedCharacterIdList[i]
                local EffectedCharacter = characters[i]
                if bCollectSkill and EffectedCharacter and IgnoreId ~= EffectedCharacterId and EffectedCharacter ~= choosenTarget and
                    (EffectedCharacter.m_IsPlayer or EffectedCharacter.m_IsFakePlayer) then
                    if self:IsValidSkillTarget(Sourcer, EffectedCharacter, skillEffectTarget, skillId,
                        EffectTargetCondition, Lv, skillAttMode, SkillZContext) then

                        ret[EffectedCharacter] = true

                        playerNum = playerNum + 1
                        if playerNum >= MaxPlayerNum then
                            break
                        end
                    end
                end
                if skillElement and self:CheckValidChemiTargetType(Sourcer, EffectedCharacter, SkillZContext) then
                    chemiRet[EffectedCharacter] = true
                end
            end
        end
        num = playerNum
        if num >= MaxNum then
            return ret, num, playerNum
        end
        -- 再选非玩家
        CLEAR_TABLE(self.m_TempMonsterPartIgnoreIdMap)
        CLEAR_TABLE(self.m_TempMonsterPartChemiIgnoreIdMap)
        for i = 1, EffectedCharacterIdListLen do
            local EffectedCharacterId = EffectedCharacterIdList[i]
            local EffectedCharacter = characters[i]
            local mainBody = EffectedCharacter and EffectedCharacter:GetMainBodyOrSelf() or nil
            if EffectedCharacter and IgnoreId ~= EffectedCharacterId and
                (not choosenTarget or mainBody ~= choosenMainBody) and
                not (EffectedCharacter.m_IsPlayer or EffectedCharacter.m_IsFakePlayer) then
                if bCollectSkill and not self.m_TempMonsterPartIgnoreIdMap[EffectedCharacterId] and
                    self:IsValidSkillTarget(Sourcer, EffectedCharacter, skillEffectTarget, skillId,
                        EffectTargetCondition, Lv, skillAttMode, SkillZContext) then
                    -- 如果存在ChoosenTarget, 并且ChoosenTarget在ret列表中, 则后续的部件跳过筛选
                    -- 如果目标是分部件怪物，则遍历后续所有的EffectedCharacterIdList
                    -- 获取所有部件，并计算并筛选出最近的那个目标
                    -- 记录已经遍历过的id放在ignore列表
                    local BestEffectedCharacter = EffectedCharacter
                    if EffectedCharacter:IsCombinedMonster() then
                        local minDistSqr = GetPixelDistance3Sqr(EffectedCharacter, Sourcer)
                        for j = i + 1, EffectedCharacterIdListLen do
                            local EffectedCharacterJId = EffectedCharacterIdList[j]
                            local EffectedCharacterJ = characters[j]
                            if EffectedCharacterJ and IgnoreId ~= EffectedCharacterJId then
                                local jMainBody = EffectedCharacterJ:GetMainBodyOrSelf()
                                if (not choosenTarget or jMainBody ~= choosenMainBody) and
                                    jMainBody == mainBody and
                                    self:IsValidSkillTarget(Sourcer, EffectedCharacterJ, skillEffectTarget, skillId,
                                        EffectTargetCondition, Lv, skillAttMode, SkillZContext) then
                                    local distSqr = GetPixelDistance3Sqr(EffectedCharacterJ, Sourcer)
                                    if distSqr < minDistSqr then
                                        minDistSqr = distSqr
                                        BestEffectedCharacter = EffectedCharacterJ
                                    end
                                    self.m_TempMonsterPartIgnoreIdMap[EffectedCharacterJId] = true
                                end
                            end
                        end
                    end
                    ret[BestEffectedCharacter] = true

                    num = num + 1
                    if num >= MaxNum then
                        break
                    end
                end
                if skillElement and not self.m_TempMonsterPartChemiIgnoreIdMap[EffectedCharacterId] and
                    self:CheckValidChemiTargetType(Sourcer, EffectedCharacter, SkillZContext) then
                    local BestEffectedCharacter = EffectedCharacter
                    if EffectedCharacter:IsCombinedMonster() then
                        local minDistSqr = GetPixelDistance3Sqr(EffectedCharacter, Sourcer)
                        for j = i + 1, EffectedCharacterIdListLen do
                            local EffectedCharacterJId = EffectedCharacterIdList[j]
                            local EffectedCharacterJ = characters[j]
                            if EffectedCharacterJ and IgnoreId ~= EffectedCharacterJId then
                                local jMainBody = EffectedCharacterJ:GetMainBodyOrSelf()
                                if (not choosenTarget or jMainBody ~= choosenMainBody)
                                and jMainBody == mainBody
                                and self:CheckValidChemiTargetType(Sourcer, EffectedCharacterJ, SkillZContext) then
                                    local distSqr = GetPixelDistance3Sqr(EffectedCharacterJ, Sourcer)
                                    if distSqr < minDistSqr then
                                        minDistSqr = distSqr
                                        BestEffectedCharacter = EffectedCharacterJ
                                    end
                                    self.m_TempMonsterPartChemiIgnoreIdMap[EffectedCharacterJId] = true
                                end
                            end
                        end
                    end
                    chemiRet[BestEffectedCharacter] = true
                end
            end
        end
    else
        if num < MaxNum then
            CLEAR_TABLE(self.m_TempMonsterPartIgnoreIdMap)
            CLEAR_TABLE(self.m_TempMonsterPartChemiIgnoreIdMap)
            for i = 1, EffectedCharacterIdListLen do
                local EffectedCharacterId = EffectedCharacterIdList[i]
                local EffectedCharacter = characters[i]
                local mainBody = EffectedCharacter and EffectedCharacter:GetMainBodyOrSelf() or nil

                if skillElement and not self.m_TempMonsterPartChemiIgnoreIdMap[EffectedCharacterId] and
                    self:CheckValidChemiTargetType(Sourcer, EffectedCharacter, SkillZContext) then
                    local BestEffectedCharacter = EffectedCharacter
                    if EffectedCharacter:IsCombinedMonster() then
                        local minDistSqr = GetPixelDistance3Sqr(EffectedCharacter, Sourcer)
                        for j = i + 1, EffectedCharacterIdListLen do
                            local EffectedCharacterJId = EffectedCharacterIdList[j]
                            local EffectedCharacterJ = characters[j]
                            if EffectedCharacterJ and IgnoreId ~= EffectedCharacterJId then
                                local jMainBody = EffectedCharacterJ:GetMainBodyOrSelf()
                                if (not choosenTarget or jMainBody ~= choosenMainBody)
                                and jMainBody == mainBody
                                and self:CheckValidChemiTargetType(Sourcer, EffectedCharacterJ, SkillZContext) then
                                    local distSqr = GetPixelDistance3Sqr(EffectedCharacterJ, Sourcer)
                                    if distSqr < minDistSqr then
                                        minDistSqr = distSqr
                                        BestEffectedCharacter = EffectedCharacterJ
                                    end
                                    self.m_TempMonsterPartChemiIgnoreIdMap[EffectedCharacterJId] = true
                                end
                            end
                        end
                    end
                    chemiRet[BestEffectedCharacter] = true
                end

                if bCollectSkill and EffectedCharacter and IgnoreId ~= EffectedCharacterId and
                    (not choosenTarget or mainBody ~= choosenMainBody) then
                    local bIsPlayer = EffectedCharacter.m_IsPlayer or EffectedCharacter.m_IsFakePlayer

                    if (not bIsPlayer or playerNum < MaxPlayerNum) -- 打击到的玩家总数限制没超
                    and not self.m_TempMonsterPartIgnoreIdMap[EffectedCharacterId] and
                        self:IsValidSkillTarget(Sourcer, EffectedCharacter, skillEffectTarget, skillId,
                            EffectTargetCondition, Lv, skillAttMode, SkillZContext) then
                        local BestEffectedCharacter = EffectedCharacter
                        if EffectedCharacter:IsCombinedMonster() then
                            local minDistSqr = GetPixelDistance3Sqr(EffectedCharacter, Sourcer)
                            for j = i + 1, EffectedCharacterIdListLen do
                                local EffectedCharacterJId = EffectedCharacterIdList[j]
                                local EffectedCharacterJ = characters[j]
                                if EffectedCharacterJ and IgnoreId ~= EffectedCharacterJId then
                                    local jMainBody = EffectedCharacterJ:GetMainBodyOrSelf()
                                    if (not choosenTarget or jMainBody ~= choosenMainBody)
                                    and jMainBody == mainBody and
                                        self:IsValidSkillTarget(Sourcer, EffectedCharacterJ, skillEffectTarget,
                                            skillId, EffectTargetCondition, Lv, skillAttMode, SkillZContext) then
                                        local distSqr = GetPixelDistance3Sqr(EffectedCharacterJ, Sourcer)
                                        if distSqr < minDistSqr then
                                            minDistSqr = distSqr
                                            BestEffectedCharacter = EffectedCharacterJ
                                        end
                                        self.m_TempMonsterPartIgnoreIdMap[EffectedCharacterJId] = true
                                    end
                                end
                            end
                        end
                        ret[BestEffectedCharacter] = true

                        if bIsPlayer then
                            playerNum = playerNum + 1
                        end

                        num = num + 1
                        if num >= MaxNum then
                            break
                        end
                    end
                end
            end
        end

    end
    return ret, num, playerNum, chemiRet
end


function CSkillMgrBase:_GetEmptySkillEffectedCharacterSet(Sourcer)
	local EffectedCharacters = g_LuaPoolMgr:AllocTable()
	local ExtraData = g_LuaPoolMgr:AllocTable(SKILL_EFFECT_CHARACTER_EXTRA_DATA_SIZE) --技能的来源坐标，单攻技能就是玩家位置，范围技能是范围的圆心
	local TotalN = 0
	if Sourcer.m_engineObject then
		ExtraData.skillSourceX, ExtraData.skillSourceY = Sourcer.m_engineObject:GetPixelPosv()
	end

	return EffectedCharacters, ExtraData ,TotalN
end

function CSkillMgrBase:GetSkillValidTarget(Sourcer, TargetId, SkillProp)
	local Targeter = nil
	local SkillTarget = SkillProp.Target
	if SkillTarget== "None" then
		return true, nil
	elseif SkillTarget == "Location" then
		return true, nil
	elseif SkillTarget == "Direction" then
		return true, nil
	else
		Targeter = GetCharacterByEngineObjectGlobalId(TargetId, true)
		if not Targeter or Targeter.m_IsPureClientNpc then	--PureClientNpc没有pk属性
			return false, nil
		end
		if Targeter.m_Scene ~= Sourcer.m_Scene then return false, nil end
		if not self:CheckSkillValidTargetType(Sourcer, Targeter, SkillTarget, SkillProp and SkillProp.ID, SkillProp and SkillProp.AttMode) then
			if SkillTarget == "Corpse(NotEnemy)" and Targeter:IsAlive() then
				return false, nil, "CAST_WITH_TARGET_ALIVE"
			else
				return false, nil
			end
		end

	end
	return true, Targeter
end

function CSkillMgrBase:CheckValidChemiTargetType(Sourcer, Targeter, SkillZContext)
	if not (Sourcer and Targeter) then
		return false
	end
	if Targeter.m_Scene ~= Sourcer.m_Scene then return false end

	local hasChemicalProp = Targeter:HasChemicalProp()
	if not hasChemicalProp then
		return false
	end

	if not self:IsTargetInRangeZ(Targeter, SkillZContext) then
		return false
	end

	if Targeter:IsFlag() then
		if not Sourcer:IsFriend(Targeter:GetOwner()) then
			return true
		end
		return false
	end
	return not Sourcer:IsFriend(Targeter)
end

function CSkillMgrBase:CheckSkillValidTargetType(Sourcer, Targeter, SkillEffect, SkillCls, AttMode)
	if not (Sourcer and Targeter and Sourcer:CanFight() and Targeter:CanFight()) then
		return false
	end

	if (not SkillCls) or (not self:IsPlatformWhite(SkillCls, Sourcer.m_MyPlatformId)) or 
	(not self:IsPlatformWhite(SkillCls, Targeter.m_MyPlatformId)) then
		if Sourcer.m_MyPlatformId then
			local platform = GetCharacterByEngineObjectGlobalId(Sourcer.m_MyPlatformId)
			if platform and platform:IsPlatformMoveEnabled() and (not self:IsCanUseSkillOnPlatformScene(platform:GetSceneTemplateId())) then
				local msg = platform:GetData("InvalidSkillMsg") or "SKILL_NO_ON_PLATFORM"
				return false, msg
			end
		end

		if Targeter.m_MyPlatformId then
			local platform = GetCharacterByEngineObjectGlobalId(Targeter.m_MyPlatformId)
			if platform and platform:IsPlatformMoveEnabled() and (not self:IsCanUseSkillOnPlatformScene(platform:GetSceneTemplateId())) then
				return false, "SKILL_TARGET_ON_MOVE_PLATFORM"
			end
		end
	end

	if not Targeter:CheckNotBehindSkillBlock(Sourcer) then
		return false
	end

	if not Sourcer:CheckInSameSkillDivision(Targeter) then
		return false
	end

	-- 护盾穿透
	local dpsSkillCls = SkillCls and GetSkillDpsStatIdBySkillCls(SkillCls)
	if dpsSkillCls and self:CanSkillPenetrateShield(dpsSkillCls) and Targeter.m_IsShield then
		return false
	end

	if SkillEffect == "None" then
		return true
	end

	local f = self.m_EffectCheckFuntionTable[SkillEffect]
	return f(Sourcer, Targeter)
end

function CSkillMgrBase:GetSkillEffectedCharacters(Sourcer, SkillContext, SkillProp, EffectTargetCondition, ScopeType, ScopeData, maxNum)
	local Ret, Targeter = self:GetSkillValidTarget(Sourcer, SkillContext.TargetId, SkillProp, SkillContext.TargetPart)
	if not Ret then
		return self:_GetEmptySkillEffectedCharacterSet(Sourcer)
	end

	local EffectedCharacters = nil
	local ExtraData = nil --技能的来源坐标，单攻技能就是玩家位置，范围技能是范围的圆心
	local TotalN = nil
	local EffectChemiCharacters = nil
	local TotalPlayerN = 0
	--对自已释放
	if SkillProp.EffectTarget == "Self" then
		EffectedCharacters, ExtraData, TotalN = self:_GetEmptySkillEffectedCharacterSet(Sourcer)
		EffectedCharacters[Sourcer] = true
		TotalN = TotalN + 1
		if Sourcer:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end

	--对主人释放
	elseif SkillProp.EffectTarget == "Owner" then
		EffectedCharacters, ExtraData, TotalN = self:_GetEmptySkillEffectedCharacterSet(Sourcer)
		local owner = Sourcer:GetOwner()
		if owner and owner ~= Sourcer then
			EffectedCharacters[owner] = true
			TotalN = TotalN + 1
			if owner:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end
		end
		
	elseif SkillProp.EffectTarget == "Catched" then
		EffectedCharacters, ExtraData, TotalN = self:_GetEmptySkillEffectedCharacterSet(Sourcer)
		if Sourcer.m_CatchedCharacters then
			for i=1, #Sourcer.m_CatchedCharacters do
				local DestCharacter = GetCharacterByEngineObjectGlobalId(Sourcer.m_CatchedCharacters[i])
				if DestCharacter then
					EffectedCharacters[DestCharacter] = true
					TotalN = TotalN + 1
					if DestCharacter:IsPlayerOrFake() then TotalPlayerN = TotalPlayerN + 1 end
				end
			end
		end
	else
		local maxPlayerTargets = self:GetSkillColMaxPlayerTargets(Sourcer, SkillProp)
		EffectedCharacters, ExtraData, TotalN, TotalPlayerN, EffectChemiCharacters = self:_GetSkillEffectedCharacterSet(SkillProp, EffectTargetCondition, Sourcer, Targeter, SkillContext, ScopeType, ScopeData, maxNum, maxPlayerTargets, SkillProp.SelectPlayerFirst)
	end

	return EffectedCharacters, ExtraData, TotalN, TotalPlayerN, EffectChemiCharacters
end

-- region 预命中
-- 为PreBeat功能提供的轻量目标收集，跳过怪物筛选/ShuffleArray/元素收集等不需要的逻辑

 -- 预命中专用日志开关，排查时调用 SetPreHitLogEnabled(true)
function PreHitLog(fmt, ...)
	-- PQLOGF("[PreHit][%s]" .. fmt, GetGlobalTime_ms(), ...)
end

-- 空间scope共用setup，将引擎查询结果填入外部传入的idSet
local function _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData, queryFunc)
	local x, y, z, angle = g_SkillMgr:GetSkillScopeBasePointAndAngle(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
	local arr = queryFunc(Sourcer:GetCoreScene(), x, y, z, angle, g_SkillMgr:GetScopeFactor(Sourcer, SkillProp.ID), ScopeData)
	for i = 1, #arr do idSet[arr[i]] = true end
	return x, y, z, angle
end

-- handler签名: (idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData, sourceX, sourceY, sourceZ)
-- 将命中ID写入外部传入的idSet，返回scope中心坐标(x,y,z)；返回nil表示不支持该scope类型
local _scopeQueryHandlers = {
	["none"] = function(idSet, _, Targeter, _, _, _, _, sourceX, sourceY, sourceZ)
		if Targeter then idSet[Targeter.m_engineObjectId] = true end
		return sourceX, sourceY, sourceZ, 0
	end,

	["allplayersinscene"] = function(idSet, Sourcer, _, _, _, _, _, sourceX, sourceY, sourceZ)
		local scene = Sourcer.m_Scene
		if scene then
			for player in pairs(scene.m_Players) do idSet[player.m_engineObjectId] = true end
		end
		return sourceX, sourceY, sourceZ, 0
	end,

	["allplayersinscenewithfake"] = function(idSet, Sourcer, _, _, _, _, _, sourceX, sourceY, sourceZ)
		local scene = Sourcer.m_Scene
		if scene then
			for player in pairs(scene.m_Players) do idSet[player.m_engineObjectId] = true end
			for player in pairs(scene.m_FakePlayers or EMPTY_TABLE) do idSet[player.m_engineObjectId] = true end
		end
		return sourceX, sourceY, sourceZ, 0
	end,

	["union"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, _, ScopeData)
		local set1, x1, y1, z1, angle1 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType1, ScopeData.SubScopeData1)
		if not set1 then return nil end
		local set2 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType2, ScopeData.SubScopeData2)
		if not set2 then g_LuaPoolMgr:ReleaseTable(set1); return nil end
		for id in pairs(set1) do idSet[id] = true end
		for id in pairs(set2) do idSet[id] = true end
		g_LuaPoolMgr:ReleaseTable(set1)
		g_LuaPoolMgr:ReleaseTable(set2)
		return x1, y1, z1, angle1
	end,

	["except"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, _, ScopeData)
		local set1, x1, y1, z1, angle1 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType1, ScopeData.SubScopeData1)
		if not set1 then return nil end
		local set2 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType2, ScopeData.SubScopeData2)
		if not set2 then g_LuaPoolMgr:ReleaseTable(set1); return nil end
		for id in pairs(set1) do
			if not set2[id] then idSet[id] = true end
		end
		g_LuaPoolMgr:ReleaseTable(set1)
		g_LuaPoolMgr:ReleaseTable(set2)
		return x1, y1, z1, angle1
	end,

	["intersect"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, _, ScopeData)
		local set1, x1, y1, z1, angle1 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType1, ScopeData.SubScopeData1)
		if not set1 then return nil end
		local set2 = g_SkillMgr:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeData.SubScopeType2, ScopeData.SubScopeData2)
		if not set2 then g_LuaPoolMgr:ReleaseTable(set1); return nil end
		for id in pairs(set1) do
			if set2[id] then idSet[id] = true end
		end
		g_LuaPoolMgr:ReleaseTable(set1)
		g_LuaPoolMgr:ReleaseTable(set2)
		return x1, y1, z1, angle1
	end,

	["area"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
		local zA, zB = -1, -1
		if g_EngineZFilterEnabled and not hasPitch then
			zA = ScopeData.ZAbove or -1
			zB = ScopeData.ZBelow or -1
		end
		return _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData,
			function(CoreScene, x, y, z, angle, scopeFactor, sd)
				return CoreScene:QueryObjectsWithPixelInRoundvt(x, y, z, zA, zB, sd.Randius * scopeFactor, 0, 0, 0, false)
			end)
	end,

	["line"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
		local zA, zB = -1, -1
		if g_EngineZFilterEnabled and not hasPitch then
			zA = ScopeData.ZAbove or -1
			zB = ScopeData.ZBelow or -1
		end
		return _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData,
			function(CoreScene, x, y, z, angle, scopeFactor, sd)
				return CoreScene:QueryObjectsWithAngleInDirectionRectanglevt(x, y, z, angle, zA, zB, sd.Width, sd.Length * scopeFactor, false)
			end)
	end,

	["fan"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
		local zA, zB = -1, -1
		if g_EngineZFilterEnabled and not hasPitch then
			zA = ScopeData.ZAbove or -1
			zB = ScopeData.ZBelow or -1
		end
		return _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData,
			function(CoreScene, x, y, z, angle, scopeFactor, sd)
				return CoreScene:QueryObjectsWithAngleInFanvt(x, y, z, angle, sd.Randius * scopeFactor, DegreeToRadian(sd.Degree), zA, zB, false)
			end)
	end,

	["semicircle"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
		local zA, zB = -1, -1
		if g_EngineZFilterEnabled and not hasPitch then
			zA = ScopeData.ZAbove or -1
			zB = ScopeData.ZBelow or -1
		end
		return _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData,
			function(CoreScene, x, y, z, angle, scopeFactor, sd)
				return CoreScene:QueryObjectsWithAngleInFanvt(x, y, z, angle, sd.Randius * scopeFactor, DegreeToRadian(90), zA, zB)
			end)
	end,

	["eqtri"] = function(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
		local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
		local zA, zB = -1, -1
		if g_EngineZFilterEnabled and not hasPitch then
			zA = ScopeData.ZAbove or -1
			zB = ScopeData.ZBelow or -1
		end
		return _queryWithScopeSetup(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData,
			function(CoreScene, x, y, z, angle, scopeFactor, sd)
				return CoreScene:QueryObjectsWithAngleInEqTrivt(x, y, z, angle, sd.Randius * scopeFactor, zA, zB)
			end)
	end,
}

-- 获取技能scope范围内的对象ID set（{[id]=true}，仅空间查询，不做目标筛选）
-- 返回: idSet(pool table), scopeX, scopeY, scopeZ；idSet为nil表示该scope类型不支持，调用方自行回退
-- 调用方负责释放返回的idSet（g_LuaPoolMgr:ReleaseTable）
function CSkillMgrBase:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)
	local sourceX, sourceY, sourceZ = Sourcer.m_engineObject:GetPixelPosv3()
	local handler = _scopeQueryHandlers[ScopeType]
	if not handler then
		PreHitLog("[skill] scope > unsupported type=%s objId=%s", ScopeType, Sourcer.m_engineObjectId)
		return nil, sourceX, sourceY, sourceZ, 0
	end
	local idSet = g_LuaPoolMgr:AllocTable()
	local x, y, z, angle = handler(idSet, Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData, sourceX, sourceY, sourceZ)
	if not x then
		g_LuaPoolMgr:ReleaseTable(idSet)
		return nil, sourceX, sourceY, sourceZ, 0
	end
	return idSet, x, y, z, angle
end

-- 从ID set中筛出有效玩家目标（PreBeat专用）
-- 相比IsValidSkillTarget去掉了IsSkillConnected穿墙判断（PreBeat为近似逻辑，可接受少量误差）
function CSkillMgrBase:_FilterPreHitPlayers(idSet, Sourcer, SkillProp, EffectTargetCondition, skillZContext, maxPlayerTargets, ignoreId, lv)
	local ret = g_LuaPoolMgr:AllocTable()
	if not idSet then return ret end
	local count = 0
	local effectTarget = SkillProp.EffectTarget
	local skillCls = SkillProp.ID
	local attMode = SkillProp.AttMode

	for id in pairs(idSet) do
		if count >= maxPlayerTargets then break end
		local char = EID2OBJ(id)
		if char and char.m_IsValid and char:IsPlayerOrFake() and char.m_engineObjectId ~= ignoreId
			and self:IsTargetInRangeZ(char, skillZContext)
			and self:CheckSkillValidTargetType(Sourcer, char, effectTarget, skillCls, attMode)
			and (not EffectTargetCondition or EffectTargetCondition(Sourcer, char, lv)) then
			ret[char] = true
			count = count + 1
		end
	end

	return ret
end

function CSkillMgrBase:_GetPreBeatEffectedPlayers(Sourcer, SkillContext, SkillProp, EffectTargetCondition, ScopeType, ScopeData, maxPlayerTargets)
	local Ret, Targeter = self:GetSkillValidTarget(Sourcer, SkillContext.TargetId, SkillProp)
	if not Ret then
		local EffectedCharacters = g_LuaPoolMgr:AllocTable()
		local sx, sy, sz = Sourcer.m_engineObject:GetPixelPosv3()
		return EffectedCharacters, sx, sy, sz, 0
	end

	local idSet, scopeX, scopeY, scopeZ, scopeAngle = self:_QuerySkillScopeObjectIds(Sourcer, Targeter, SkillContext, SkillProp, ScopeType, ScopeData)

	local hasPitch = SkillProp.MaxPitch ~= nil and SkillProp.MinPitch ~= nil
	local skillZContext = nil
	if not g_EngineZFilterEnabled or hasPitch then
		local sourceX, sourceY, sourceZ = Sourcer.m_engineObject:GetPixelPosv3()
		skillZContext = self:SkillZContext_Create(
			sourceX, sourceY, sourceZ,
			SkillContext.DestPosX, SkillContext.DestPosY, SkillContext.DestPosZ,
			ScopeData.ZAbove and ScopeData.ZAbove * pixel_per_grid,
			ScopeData.ZBelow and ScopeData.ZBelow * pixel_per_grid,
			SkillProp.MaxPitch, SkillProp.MinPitch)
		-- 与正式命中路径 _GetSkillEffectedCharacterSet 保持一致：用范围中心 Z 作为俯仰投影基准
		skillZContext.center = scopeZ
	end

	local EffectedCharacters = self:_FilterPreHitPlayers(
		idSet, Sourcer, SkillProp, EffectTargetCondition, skillZContext,
		maxPlayerTargets, SkillContext.IgnoreId, SkillContext.Lv)

	g_LuaPoolMgr:ReleaseTable(idSet)

	return EffectedCharacters, scopeX, scopeY, scopeZ, scopeAngle
end

-- endregion PreBeatEffectedPlayers

-- region PreHitScope helpers
-- 计算 scope 的 AABB 包围盒（pixel 坐标），返回 minX, minY, maxX, maxY；
-- 不支持的形状返回 nil（caller 应跳过 AABB 早排，直接精确测试）
local function _PreHitScopeBBox(sx, sy, angle, scopeType, scopeData)
	if scopeType == "area" or scopeType == "fan" or scopeType == "semicircle" then
		local r = (scopeData.Randius or 0) * 64
		return sx - r, sy - r, sx + r, sy + r
	elseif scopeType == "line" then
		local hl = (scopeData.Length or 0) * 64 * 0.5
		local hw = (scopeData.Width or 0) * 64 * 0.5
		local cx = sx + math.cos(angle) * hl
		local cy = sy + math.sin(angle) * hl
		local r = math.sqrt(hl * hl + hw * hw)
		return cx - r, cy - r, cx + r, cy + r
	elseif scopeType == "union" then
		local a1, b1, c1, d1 = _PreHitScopeBBox(sx, sy, angle, scopeData.SubScopeType1, scopeData.SubScopeData1)
		local a2, b2, c2, d2 = _PreHitScopeBBox(sx, sy, angle, scopeData.SubScopeType2, scopeData.SubScopeData2)
		if not a1 then return a2, b2, c2, d2 end
		if not a2 then return a1, b1, c1, d1 end
		return math.min(a1, a2), math.min(b1, b2), math.max(c1, c2), math.max(d1, d2)
	elseif scopeType == "intersect" or scopeType == "except" then
		-- intersect ⊆ sub1；except ⊆ sub1；用 sub1 包住即可（精确测试再筛）
		return _PreHitScopeBBox(sx, sy, angle, scopeData.SubScopeType1, scopeData.SubScopeData1)
	end
	return nil
end

function CSkillMgrBase:ComputePreHitScopeBBox(snap)
	if not snap then return nil end
	return _PreHitScopeBBox(snap.X, snap.Y, snap.Angle or 0, snap.ScopeType, snap.ScopeData)
end

-- endregion PreHitScope helpers

function CSkillMgrBase:GenerateOptimizeSkillInstanceId(SkillId, Count)
	return SkillId * 100 + Count
end

function CSkillMgrBase:GetSkillIdFromOptimizeSkillInstanceId(SkillInstanceId)
	return math.floor(SkillInstanceId / 100)
end

function CSkillMgrBase:GetSkillLearnedData(cls)
	return self.m_SkillUpData[1] and self.m_SkillUpData[1][cls]
end

function CSkillMgrBase:GetSkillJingjieData(cls)
	return self.m_SkillUpData[2] and self.m_SkillUpData[2][cls]
end

function CSkillMgrBase:GetSkillHuaJingData(cls)
	return self.m_SkillUpData[3] and self.m_SkillUpData[3][cls]
end

function CSkillMgrBase:GetSkillDengFengData(cls)
	return self.m_SkillUpData[4] and self.m_SkillUpData[4][cls]
end

function CSkillMgrBase:GetSkillAdvancedData(cls, advancedNum)
	return self.m_SkillUpData[advancedNum] and self.m_SkillUpData[advancedNum][cls]
end

function CSkillMgrBase:ParseSkillOrderDisData()
	self.m_SkillUpData = {} -- [1]=初传、[2]=进阶、[3]=化境、[4]=登峰
	for idx, v in bddpairs(FightProp_SkillLearnFightprop) do
		self.m_SkillUpData[v.Step + 1] = self.m_SkillUpData[v.Step + 1] or {}
		local tbl = {}
		for propName, row in bddpairs(FightProp_SkillFightpropDisp) do
			if v[propName] then
				table.insert(tbl, {row, v[propName]})
			elseif v.Buff and v.Buff == tonumber(propName) then
				table.insert(tbl, {row, v.Buff})
			end
		end
		if #tbl > 0 then
			for colName, value in bddpairs(v) do
				if string.find(colName, "^Skill%d") then
					if IdIsSkillCls(value) then
						self.m_SkillUpData[v.Step + 1][value] = tbl
					end
				end
			end
		end
	end
end

function CSkillMgrBase:CalcHitNumHurtDecay(num, decayNum, character)
	if not (decayNum and decayNum > 0 and num and num > 0) then
		return 1
	end
	local addNum = character and character:GetParam(EFightProp.HurtDeacyExTargets)
	if addNum then
		decayNum = decayNum + addNum
	end
	if decayNum <= 0 then 
		return 1
	end
	if num <= decayNum then
		return 1
	end

	return decayNum / num
end

local _AttModes = {"p", "m", "h", "c"}
local _AttMode2Event = {}
for k, v in ipairs(_AttModes) do
	_AttMode2Event[v] = v .. "Damage"
end

function CSkillMgrBase:IsImmunity(obj, AttMode)
	if obj and AttMode then
		return g_StatusMgr:CheckConflict(obj, EnumEvent[_AttMode2Event[AttMode] or (AttMode .. "Damage")])
	end
end

function CSkillMgrBase:IsImmunitySilence(obj, ImmunityStatus)
	if not obj or not ImmunityStatus then return end
	return obj:GetStatusAttribute(ImmunityStatus, "ImmunitySilence") == 1
end

function CSkillMgrBase:GetRealAttMode(AttMode, Attacker)
	if AttMode == 'b' then
		local realAttacker = GetRealAttacker(Attacker)
		if realAttacker and realAttacker:CanFight() then 
			return realAttacker:GetClassAttMode()
		end
	else
		return AttMode
	end
end

function CSkillMgrBase:LoadMainSkillInfo()
	local mainskill = SkillUI_MainSkill 
	self.m_MainSkillInfo = {}
	for _, class in pairs(EnumPlayerClass) do
		if mainskill[class] then
			local skillclsTbl = {}
			for _, v in bddipairs(mainskill[class].Skills or EMPTY_TABLE) do
				skillclsTbl[v] = true
			end
			for _, v in bddipairs(mainskill[class].JieKongSkills or EMPTY_TABLE) do
				skillclsTbl[v] = true
			end
			for _, v in bddipairs(mainskill[class].QTESkills or EMPTY_TABLE) do
				skillclsTbl[v] = true
			end
			for _, v in bddipairs(mainskill[class].PassiveQTESkills or EMPTY_TABLE) do
				skillclsTbl[v] = true
			end	
			for _, v in bddipairs(mainskill[class].DynQTESkills or EMPTY_TABLE) do
				skillclsTbl[v] = true
			end	
			
			self.m_MainSkillInfo[class] = skillclsTbl	
		end
	end
end

function CSkillMgrBase:GetCurBuildNameAndDesc(player)
	local index = self:GetCurSkillBuildId(player)
	local buildData = self:GetAllSkillBuild(player)
	local curbuildData = index and buildData and buildData[index]
	if not curbuildData then
		return
	end
	return curbuildData.name, curbuildData.desc
end

function CSkillMgrBase:GetCurBuildSkillMap(player)
	local index = self:GetCurSkillBuildId(player)
	local buildData = self:GetAllSkillBuild(player)
	local curbuildData = index and buildData and buildData[index]
	if not curbuildData then
		return
	end

	local skillTypes = EnumSkillBuildTypes

	local designData = SkillUI_MainSkill[ player:GetClass() ]
	-- 先设置上基础技能
	local skillclsTbl = {
		[ designData.Skills[1] ] = true,
		[ designData.JieKongSkills[1] ] = true,
	}
	-- 血河会有2个基础技能
	if designData.Skills[2] then
		skillclsTbl[designData.Skills[2]] = true
	end

	local qteskillcls = GetQTESkillCls(player)
	if qteskillcls then
		skillclsTbl[qteskillcls] = true
	end

	for _, skillType in ipairs(skillTypes) do
		if curbuildData[skillType] then
			for j = 1, EnumHotItemSkillTypeSize[skillType] do
				local skillcls = curbuildData[skillType][j]
				local realSkillCls = _DoGetSwitchGroupRealCls(player, skillcls) or skillcls

				if realSkillCls and Skill_Skill[ realSkillCls ] then
					skillclsTbl[ realSkillCls ] = true
				end
			end
		end
	end

	return skillclsTbl
end

function CSkillMgrBase:GetSkillInfoByCurBuild(player, cls)
	local index = self:GetCurSkillBuildId(player)
	local buildData = self:GetAllSkillBuild(player)	
	local curbuildData = index and buildData and buildData[index]
	if not curbuildData then
		return false
	end

	local skillCfg = Skill_Skill
	local skillTypes = EnumSkillBuildTypes
	for _, skillType in ipairs(skillTypes) do
		if curbuildData[skillType] then
			for j = 1, EnumHotItemSkillTypeSize[skillType] do
				local skillcls = curbuildData[skillType][j]
				if skillcls and skillCfg[ skillcls ] and skillcls == cls then
					return true,skillcls,skillType,j
				end
			end
		end
	end
	return false
end

-- begin：获取["ConsumeResource"]、["Targets"]、["MaxPlayerTargets"]、["Scope"]、["CD"]这些列的prop值时，需要调用以下函数才可以，不要裸调用
function CSkillMgrBase:GetSkillColMaxPlayerTargets(player, SkillProp)
	local ret = GetSkillPropColRealV(player, SkillProp.ID, "MaxPlayerTargets", SkillProp.MaxPlayerTargets) or 0
	return GetOptimizeMaxPlayerTargets(player and player.m_Scene, ret, SkillProp, player)
end

function CSkillMgrBase:GetScopeFactor(player, cls)
	if not player then return 1 end
	local range = 1 + (player:GetParam(EFightProp.Range) or 0)
	return GetSkillPropColRealV(player, cls, "Scope", range) or 0
end

function CSkillMgrBase:GetCNSkillMaxCount(player, cls)
	if not player then return end
	local skillProp = self:GetSkillProp(cls, player)
	local cnCountCfg = skillProp and skillProp.CNCount
	if not cnCountCfg then return end 
	local lv = 1
	local skillProp = player:IsPlayerOrFake() and player:SkillProp()
	if skillProp then
		local curSkillId = skillProp:GetSkillByCls(cls)
		lv = curSkillId and (curSkillId%100) or 1
	end

	local v
	if type(cnCountCfg) == "number" then -- ugc
		v = cnCountCfg
	else
		local func = AllFormulas.SimpleLvExp[cnCountCfg] or RETURN_0_FUNC
		v = func and func(lv) or 0
	end

	return GetSkillPropColRealV(player, cls, "CNCount", v) or 0
end

function CSkillMgrBase:GetCNSkillInterval(player, cls)
	if not player then return end
	local skillProp = self:GetSkillProp(cls, player)
	local cnIntervalCfg = skillProp and skillProp.CNInterval

	if not cnIntervalCfg then return end
	local numV = tonumber(cnIntervalCfg)
	if numV == -1 then return numV end
	
	local lv, SkillOrder = 1, 0
	local skillProp = player:IsPlayerOrFake() and player:SkillProp()
	if skillProp then
		local curSkillId = skillProp:GetSkillByCls(cls)
		lv = curSkillId and (curSkillId%100) or 1
		SkillOrder = GetSkillOrderById(player, cls * 100 + lv)
	end
	local v
	if type(cnIntervalCfg) == "number" then -- ugc
		v = cnIntervalCfg
	else
		local func = AllFormulas.SimpleLvExp[cnIntervalCfg] or RETURN_0_FUNC
		v = func and func(lv, SkillOrder) or 0
	end

	return GetSkillPropColRealV(player, cls, "CNInterval", v) or 0
end
-- end

function CSkillMgrBase:LoadIdentityMainSkill()
	self.m_IdentityMainSkilTbl = {}
	for id, info in bddpairs(SkillUI_LifeSkill) do
		self.m_IdentityMainSkilTbl[id] = true
	end
end

function CSkillMgrBase:IsIdentityMainSkill(skillCls)
	return self.m_IdentityMainSkilTbl[skillCls]
end

function CSkillMgrBase:GetOrigIdentitySkillTbl()
	return self.m_IdentityMainSkilTbl
end

function CSkillMgrBase:GetIdentitySkillTbl(player)
	local ret = {}
	for id, _ in pairs(self.m_IdentityMainSkilTbl) do 
		local skillId = player:GetSkillByCls(id)
		if skillId then 
			table.insert(ret, id)	
		end
	end

	return ret
end

function CSkillMgrBase:CheckHaveIdentitySkill(player)
	local ret = self:GetIdentitySkillTbl(player)
	return #ret ~= 0
end

-- 姿态切换是否解锁
function CSkillMgrBase:IsOccupationStatusUnlock(Character)
	if not (Character and Character:IsPlayerOrFake()) then return end
	local cfg = Skill_Settings.OCCUPATION_STATUS_UNLOCK_SKILL.tblVal or EMPTY_TABLE
	local cls = cfg and cfg[ Character:GetClass() ]
	local skillId = IdIsSkillCls(cls) and Character:GetSkillByCls(cls)
	return skillId
end

-- 技能是否是货币消耗类
function CSkillMgrBase:IsSkillConsumeMoney(skillCls)
	if not skillCls then return false end

	local skillProp = Skill_Skill[skillCls]
	if skillProp then
		local consumeTbl = g_SkillCondition:ParseConsumeResource(skillProp)
		for k, v in pairs(consumeTbl or EMPTY_TABLE) do
			if EnumConsumeResourceMoney[k] then return true end
		end
	end
	return false 
end

-- 吸收元素技能, 通过Context判断元素
function CSkillMgrBase:GetElementByPipetteElementContext(player, context)
	if not (player and context) then return end

	local mat, state, elmentName, elementId

	if context.Type == EnumPipetteElementMode.None then 
		if IsRunningServerCode() then
			-- 没有选择目标, 先看看自己身上有没有状态
			state = player.m_CurrChemistryState
			if not state then 
				-- 返回地面元素状态
				mat, state = player:GetCurrStandChemiInfo()
			end
		end

	elseif context.Type == EnumPipetteElementMode.EngineObj then
		local obj = EID2OBJ(context.Id)
		if obj then
			mat, state = obj:GetMaterialName(), obj:GetCurrChemistryState()
		end
		local tempId = obj:GetTemplateId()
		if tempId then
			elmentName = Chemistry_ChemicalState[tempId] and Chemistry_ChemicalState[tempId][state] and Chemistry_ChemicalState[tempId][state].OutElement
		end

	elseif context.Type == EnumPipetteElementMode.ArtObject then
		-- 看看能不能拿到这个物体
		local container, sceneId
		if IsRunningServerCode() then
			container = player.m_Scene:GetArtObjContainer()
			sceneId = player.m_Scene:GetTemplateId()
		else
			container = g_ArtObjContainer
			sceneId = g_SceneDesignID
		end

		local obj = container:GetObjByInstId(context.Id)
		local objData = g_ArtObjectsMgr:GetDataByInstId(context.Id, sceneId)
		local objTemplateId = objData[4]
		if objTemplateId then
			local objCategory = ArtObject_Object[objTemplateId] and ArtObject_Object[objTemplateId].Category
			mat = ArtObject_Category[objCategory] and ArtObject_Category[objCategory].Material
		end
		state = obj and obj:GetState() or (ArtObject_Object[objTemplateId] and ArtObject_Object[objTemplateId].InitState or "None")
	elseif context.Type == EnumPipetteElementMode.Enviroment then
		local pos = context.TargetPos
		local matId
		if IsRunningServerCode() then
			state, matId = player:GetChemiGridInfoByPos(pos.x, pos.y, pos.z)
			mat = g_ChemistryMgr:GetMaterialNameById(matId)
		else
			state, matId = g_ClientChemistryMgr:GetChemiGridInfoByPos(pos.x/pixel_per_grid, pos.y/pixel_per_grid, pos.z/pixel_per_grid)
			mat = g_ClientChemistryMgr:GetMaterialNameById(matId)
		end
	end

	elmentName = elmentName or g_ChemistryMgr:GetElementByMatAndState(mat, state)
	elementId = GameSetting_Common.ELEMENT_ABSORB_OUTCTRL.tblVal and GameSetting_Common.ELEMENT_ABSORB_OUTCTRL.tblVal[elmentName] or 0

	return elementId, elmentName
end


--- {{{ 进副本 每周限次数提示推荐套路

-- @param gpTagId:SkillUI表中buildtag的id
-- @Desc GamePlayRecSkillBuild Weekly 数据中 key为对应的goTagId value 为本周已经提示过的次数
function CSkillMgrBase:IsWeekRecBuildTimeOver(gpTagId, player)
	if not player then return true end
	local playData = player:GetUserWeeklyPlayDataTbl('GamePlayRecSkillBuild')
	local tipsCnt = playData[gpTagId] or 0
	local designCnt = SkillUI_BuildTag[gpTagId] and SkillUI_BuildTag[gpTagId].TipsCnt or -1
	if SkillUI_BuildTag[gpTagId] and SkillUI_BuildTag[gpTagId].ShowStatus == 0 then
		designCnt = -1
	end
	if tipsCnt < designCnt then
		return false, tipsCnt + 1
	end

	return true
end

function CSkillMgrBase:SetWeekRecBuildTimeDataTbl(player, gpTagId, cnt)
	local playData = player:GetUserWeeklyPlayDataTbl('GamePlayRecSkillBuild')
	playData[gpTagId] = cnt
end

function CSkillMgrBase:SetGameplayAutoSwitch(player, gamePlayID, curBuildId, buildData, skipCond)
	if not skipCond and self:GetSkillBuildAutoSwitch(player) ~= 1 then return end
	-- 进入副本，自动切换套路，仅在最开始的场景进行
	local designData = Gameplay_Gameplay[gamePlayID]
	if designData and designData.EntranceArgs then
		local iCurSceneID = player.m_Scene and player.m_Scene:GetTemplateId() or 0
		local iEntranceSceneID = tonumber(string.match(designData.EntranceArgs, "161%d%d%d%d%d"))
		local gp = player.GetGameplay and player:GetGameplay() or nil
		if iCurSceneID ~= iEntranceSceneID and not (gp and gp:GetSkillAutoSwitchSceneCheckSkip())  then
			return
		end
	end

	local preBuildID = curBuildId
	local collect    = {}
	local design 	 = SkillUI_BuildTag
	if not design then return end
	local iTargetTag = self:GetSkillBuildTagByGamePlayID(gamePlayID)
	if not iTargetTag then return end

	local func =  skipCond and pairs or ipairs 
	for k, v in func(buildData) do
		local tags = v.gpTag
		if skipCond then
			tags = v
		end
		for i, j in pairs(tags or EMPTY_TABLE) do
			if design[i] and design[i].ShowStatus == 1 and CheckDesignDataOpenDaysAndDate(design) then
				if i == iTargetTag then
					if collect[k] and collect[k].Priority > design[i].Priority then
						collect[k].ID = i
						collect[k].Priority = design[i].Priority
					else
						collect[k] = {}
						collect[k].ID = i
						collect[k].Priority = design[i].Priority
					end
				end
			end
		end
	end
	local buildId, temp, tagId
	if table.get_count(collect) > 0 then
		for k, v in pairs(collect) do
			if (not buildId) or ( v.Priority < temp.Priority or (v.Priority == temp.Priority and buildId > k) ) then 
				buildId = k
				temp = v
				tagId = v.ID
			end
		end
	end

	if not buildId then return end
	-- if preBuildID == buildId then return end
	PQLOG('SetGameplayAutoSwitch', preBuildID, buildId, gamePlayID)
	return buildId
end

--- 进副本 每周限次数提示推荐套路 }}}



function CSkillMgrBase:IsJuejiInWeakTransTime(skillCls)
	local beginTime = SkillUI_JueJiTransOrder[skillCls] and SkillUI_JueJiTransOrder[skillCls].WeakTransBeginTime
	local endTime = SkillUI_JueJiTransOrder[skillCls] and SkillUI_JueJiTransOrder[skillCls].WeakTransEndTime
	if not beginTime or not endTime then return end

	local curTime = GetGlobalTime()
	if curTime >= beginTime and curTime < endTime then
		return true
	end
	return false
end

-- 判断是否为探索（大荒）江湖技能
function CSkillMgrBase:IsDahuangExtraSkill(skillCls)
	local skillList=SkillUI_JianghuSkill[822101].Skills
	for i, cls in bddpairs(skillList or EMPTY_TABLE) do
		if skillCls == cls then return true end
	end
	return false
end

-- 判断是否为趣味江湖技能
function CSkillMgrBase:IsFunnySkill(skillCls)
	local skillList=SkillUI_JianghuSkill[822102].Skills
	for i, cls in bddpairs(skillList or EMPTY_TABLE) do
		if skillCls == cls then return true end
	end
	return false
end

function CSkillMgrBase:GetWakeUpPartnerSkillMainSkill(skillCls)
	for id, data in bddpairs(Buddy_BuddyInfo) do
		if data.JianghuSkill and data.JianghuSkill[2] and data.JianghuSkill[2] == skillCls then
			return data.JianghuSkill[1]
		end
	end
	return skillCls
end

function CSkillMgrBase:CheckSkillBuildLogInfoCanUse(player, gamePlayID, skillTbl, xinfaStr)
	local class = player and player:GetClass() or 1
	local iSkillStatus = player:GetClassState()
	local tblSkillBuildFilterConfig
	local CheckSkillUselessFunc = function(iSkills)
		if g_SkillMgr:IdIsDerivedSkillCls(iSkills) then
			iSkills = g_SkillMgr.m_SkillLvSourceTb[iSkills] or iSkills
		end
		if g_SkillMgr:IsDahuangExtraSkill(iSkills) or g_SkillMgr:IsFunnySkill(iSkills) then
			return true
		end
		return false
	end
	local GetTableFromString = function(str)
		local tbl = {}
		if str then
			local strTbl = string.split(str, ',')
			for k, v in pairs(strTbl) do
				local id = tonumber(v)
				if id then
					tbl[id] = true
				end
			end
		end
		return tbl
	end

	for k, v in bddipairs(SkillUI_SkillBuildFilterConfig) do
		if v.Class == class and v.StatusIdx == iSkillStatus then
			if string.find(v.GamePlay or "", gamePlayID) then
				tblSkillBuildFilterConfig = v
			end
		end
	end
	local tblFilterSkillCls
	local tblFilterXinFaType
	if tblSkillBuildFilterConfig then
		if tblSkillBuildFilterConfig.XinFaType then
			tblFilterXinFaType = GetTableFromString(tblSkillBuildFilterConfig.XinFaType)
		end
		if tblSkillBuildFilterConfig.Skill then
			tblFilterSkillCls = GetTableFromString(tblSkillBuildFilterConfig.Skill)
		end
	end
	local iLiuPaiCnt, iJiangHuSkillCnt = 0, 0
	for k, v in ipairs(skillTbl or EMPTY_TABLE) do
		if CheckSkillUselessFunc(v) then
			return false
		end
		if tblFilterSkillCls then
			if tblFilterSkillCls[v] then
				return false
			end
		end
		local iOriginCls = v > 0 and self:ConvertSkillIdToOrigin(v) or 0
		if Skill_Appear[iOriginCls] and Skill_Appear[iOriginCls].IsPetSkill == 1 then
			iOriginCls = BaseYuChongCls
		end
		local skillType = self:GetClassSkillType(iOriginCls)
		if skillType then
			if skillType == EnumClassSkillType.ProfessionalSkill then
				iLiuPaiCnt = iLiuPaiCnt + 1
			elseif skillType == EnumClassSkillType.JianghuSkill then
				iJiangHuSkillCnt = iJiangHuSkillCnt + 1
			end
		end
	end

	if (iJiangHuSkillCnt == 2 and iLiuPaiCnt == 5) or (iJiangHuSkillCnt == 3 and iLiuPaiCnt == 4) then
	else
		return false
	end
	local iXinFaCnt = 0
	local xinfa = string.split(xinfaStr or "", ',')
	for k, v in pairs(xinfa or EMPTY_TABLE) do
		local tpId = GetTemplateIdFromReadableString(v)
		if tpId > 0 then
			local spiritData = Item_Item[tpId]
			if spiritData and spiritData.XinfaID then
				iXinFaCnt = iXinFaCnt + 1
				local designData = XinFa_XinFa[spiritData.XinfaID]
				local xinfaType = designData and designData.XinfaType2
				local IllustrationTag = designData and designData.IllustrationTag or {}
				if tblFilterXinFaType and tblFilterXinFaType[xinfaType] then
					return false
				end
				if IsPVPGameplay(gamePlayID) then
					-- 带副本标签筛掉
					for i, j in bddipairs(IllustrationTag) do
						if j == 200 then
							return false
						end
					end
				end
				if IsPVEGameplay(gamePlayID) then
					-- 带竞技标签筛掉
					for i, j in bddipairs(IllustrationTag) do
						if j == 201 then
							return false
						end
					end
				end
			end
		end
	end

	if iXinFaCnt < 3 then
		return false
	end

	return true
end

function CSkillMgrBase:GetSkillBuildTagByGamePlayID(gamePlayID)
	local designData = Gameplay_Gameplay[gamePlayID]
	if designData and designData.GamePlaySkillBuildTag then
		return designData.GamePlaySkillBuildTag
	end
end

function CSkillMgrBase:CanJuejiTransOrder(player, fromCls, toCls)
	local beginTime = SkillUI_JueJiTransOrder[fromCls] and SkillUI_JueJiTransOrder[fromCls].WeakTransBeginTime
	local endTime = SkillUI_JueJiTransOrder[fromCls] and SkillUI_JueJiTransOrder[fromCls].WeakTransEndTime
	if not beginTime or not endTime then return false end

	local order = player:GetSkillOrder(fromCls)
	local toOrder = toCls and player:GetSkillOrder(toCls)

	local orderTimeTbl = player:GetUserPlayDataTbl("JueJiUpgradeSkillOrderTime")
	local canSend = 0
	for i = 1, order do
		local upTime = orderTimeTbl[fromCls] and orderTimeTbl[fromCls][i]
		if not upTime or upTime < beginTime then
			canSend = canSend + 1
		end
	end
	if not toOrder then
		return true, canSend, canSend
	end

	local toMaxOrder = CPropertySkill._GetMaxOrder(toCls)
	local canReceive = toMaxOrder - toOrder
	local canTrans = math.min(canSend, canReceive)
	return true, canTrans, canSend, canReceive
end

-- 是否为空战选点技能SkillProp
function IsAirLocationSkillProp(skillProp)
    return skillProp.EnableLocationInAir == 1
end

-- 是否为空战选点技能SkillCls
function IsAirLocationSkillCls(skillCls, Character)
	return IsAirLocationSkillProp(g_SkillMgr:GetSkillProp(skillCls, Character))
end

---@return integer|nil EnumSpecializedSkillType, type of target specialized skill
function CSkillMgrBase:IsSpecializedSkill(sid)
	if not sid then return end
	return SkillUI_SpecializedSkill[sid] and SkillUI_SpecializedSkill[sid].Category
end


function CSkillMgrBase:GetBigBuildGroupTagIDByGameplayId(iGameplayID)
	if not iGameplayID then return end

	if iGameplayID == EnumGameplay.LeiTai then
		return 2
	end

	if not self.m_GameplayIDToBigBuildGroupTagMap then
		self.m_GameplayIDToBigBuildGroupTagMap = {}
		for i,v in bddpairs(SkillUI_BigBuildTag or EMPTY_TABLE) do
			for _,id in bddpairs(v.GamePlay or EMPTY_TABLE) do
				self.m_GameplayIDToBigBuildGroupTagMap[id] = i
			end
		end
	end

	return self.m_GameplayIDToBigBuildGroupTagMap[iGameplayID]
end

function CSkillMgrBase:GetRankIDsByBigBuildGroupTagID(iTagID)
	if not iTagID then return "" end
	if not self.m_BigBuildGroupTagToRankIDsMap then
		self.m_BigBuildGroupTagToRankIDsMap = {}
		local func = function(i, v)
			if v.BigBuildGroupTag and v.BigBuildGroupTag > 0 then
				if CheckDesignDataOpenDaysAndDate(v, SERVER_GROUP_ID) then
					self.m_BigBuildGroupTagToRankIDsMap[v.BigBuildGroupTag] = self.m_BigBuildGroupTagToRankIDsMap[v.BigBuildGroupTag] or {}
					table.insert(self.m_BigBuildGroupTagToRankIDsMap[v.BigBuildGroupTag], i)
				end
			end
		end
		for i,v in bddpairs(Rank_GamePlay or EMPTY_TABLE) do
			func(i, v)
		end
		for i,v in bddpairs(Rank_Player or EMPTY_TABLE) do
			func(i, v)
		end
		for i,v in bddpairs(Rank_Guild or EMPTY_TABLE) do
			func(i, v)
		end
		for i, v in pairs(self.m_BigBuildGroupTagToRankIDsMap) do
			self.m_BigBuildGroupTagToRankIDsMap[i] = table.concat(v, ",")
		end
	end

	return self.m_BigBuildGroupTagToRankIDsMap[iTagID] or ""
end

-- 是否为摸金禁用技能
function CSkillMgrBase:IsMJForbidSkill(skillCls)
	local canUse = Skill_Skill[skillCls] and Skill_Skill[skillCls].CanUseInMJ
	return (not canUse)
end

-- 拿分支技能当前子技能列表，分支子技能也能查到
function CSkillMgrBase:GetSkillChangeSubSkills(player, iSkillCls, ExtraData)
	if not player then
		return
	end
	local listData = {}
	local designData = Skill_SkillChange[iSkillCls] and Skill_SkillChange[iSkillCls][1]
	if not designData then
		-- 查不到就转下主技能看看有没有
		local tempData = Skill_SkillChange_Rev2[iSkillCls]
		if tempData then
			designData = tempData
			iSkillCls = tempData.ID
		end
	end
	if designData and designData['AppearChange'] and designData['AppearChange'] == 1 then
		local idx = designData.ID2
		local showF = Skill_SkillChange_f[iSkillCls] and Skill_SkillChange_f[iSkillCls][idx] and Skill_SkillChange_f[iSkillCls][idx].ShowCondition
		if showF then
			if not bServer then
				local state = player:GetClassState()
				local state = TryGetFixOccupationStatusInMoJinPanel(g_MainPlayer, state)
				ExtraData = ExtraData or {}
				ExtraData.ClassState = state
			end
			local skillStr = showF(player, player, ExtraData or EMPTY_TABLE, EMPTY_TABLE, EMPTY_TABLE)
			if skillStr then
				for num_str in string.gmatch(skillStr, "([^;]+)") do
					local cls = tonumber(num_str)
					table.insert(listData, cls)
				end
			end
			return listData
		else
			for k, v in bddipairs(designData.Skills) do
				table.insert(listData, v)
			end
			return listData
		end
	end
end

function CSkillMgrBase:GetSkillPropData(SkillCls, Field, Character, bNotMainSkill)
	local skillProp = self:GetSkillProp(SkillCls,Character)
	local val = skillProp[Field]
	local val2 = GetSkillPropColRealV(Character, SkillCls, Field, val, bNotMainSkill)
	return val2
end

--region ugc skill
function CSkillMgrBase:GetSkillProp(SkillCls, Character)
	if IdIsUGCSkillCls(SkillCls) then
		local skillData = g_UGCLevelMgr:GetSkillById(Character, SkillCls)
		if skillData and Character then
			g_UGCLevelMgr:CheckProperty(skillData, Character)
		end
		return skillData and skillData.SkillProp or Skill_Skill[SkillCls] or Skill_Skill[993001]
	end
	return Skill_Skill[SkillCls]
end

-- 下面的接口相较于IdIsCNSkill考虑了ugc的情况
function IsCNSkillId(SkillId, Player)
	local cls = GetSkillClass(SkillId)
	return IsCNSkillCls(cls, Player)
end

function IsCNSkillCls(SkillCls, Player)
	local designdata = g_SkillMgr:GetSkillProp(SkillCls, Player)
	return designdata and designdata.CNCount ~= nil and designdata.CNInterval ~= nil
end

function IsManualCNSkillId(SkillId, Player)
	local cls = GetSkillClass(SkillId)
	return IsManualCNSkillCls(cls, Player)
end

function IsManualCNSkillCls(SkillCls, Player)
	local designdata = g_SkillMgr:GetSkillProp(SkillCls, Player)
    return designdata and designdata.CNCount ~= nil and tonumber(designdata.CNInterval) == -1
end

--endregion ugc skill

-- 查主技能对于index的分支技能
function CSkillMgrBase:GetSkillDerivedChangeCls(iSkillCls, iIndex)
	if not iSkillCls or not iIndex then
		return iSkillCls
	end
	local designData  = Skill_SkillChange_Rev2[iSkillCls]
	if designData and designData['AppearChange'] then
		if designData.Skills and designData.Skills[iIndex] then
			return designData.Skills[iIndex]
		end
	end
	return iSkillCls
end

function CSkillMgrBase:CheckClassCanSwitchQTE(iClass)
	if not iClass then
		return false
	end

	local moJinCheckRet = CheckMoJinSwitchQTE(iClass)
	if not moJinCheckRet then return false end

	return SkillUI_Setting.CLASS_QTE_SWITCH_MAP.TblVal[iClass]
end

function CSkillMgrBase:CheckClassCanSwitchJieKong(iClass)
	if not iClass then
		return false
	end
	return SkillUI_Setting.CLASS_JIEKONG_SWITCH_MAP.TblVal[iClass]
end

function CSkillMgrBase:GetSkillStatusRealCls(iSkillCls, iStatus, iClass)
	-- 不是流派技能不需要处理技能姿态
	if not IdIsLiuPaiSkill(iSkillCls) then
		return iSkillCls
	end
	if not IsSuWenLikeClass(iClass) then
		return iSkillCls
	end
    if not IsStatusSwitchGroupSkill(iSkillCls) then
        return iSkillCls
    end
	local tblInfo = Skill_SkillChange_Rev2[iSkillCls]
	if tblInfo and tblInfo['AppearChange'] == 0 then
		local iIndex = iStatus + 1
		local iRealSkillCls = tblInfo and tblInfo.Skills and tblInfo.Skills[iIndex] or iSkillCls
		return iRealSkillCls
	end
	return iSkillCls
end

-- 拿分支技能的下标
function CSkillMgrBase:GetSkillDerivedChangeIndex(iRealSkillCls)
	if not iRealSkillCls then
		return
	end
	if Skill_SkillChange_Rev_Sub2MainNIdx[iRealSkillCls] then
		return Skill_SkillChange_Rev_Sub2MainNIdx[iRealSkillCls][2]
	end
end

function CSkillMgrBase:ClientSkillContainsFeatures(cls, featureIds, checkType)
	local info =  Skill_Appear[cls]
	local skillFeatureStr = info and info.SkillFeature
	if type(featureIds) == "number" then
		return self:SingleClientSkillContainsFeature(skillFeatureStr, featureIds)
	end
	checkType = checkType or EnumContainSkillFeature.eAnyOne
	if checkType == EnumContainSkillFeature.eAnyOne then
		for _, featureId in ipairs(featureIds) do
			if self:SingleClientSkillContainsFeature(skillFeatureStr, featureId) then
				return true
			end
		end
		return false
	elseif checkType == EnumContainSkillFeature.eAll then
		for _, featureId in ipairs(featureIds) do
			if not self:SingleClientSkillContainsFeature(skillFeatureStr, featureId) then
				return false
			end
		end
		return true
	end
end

function CSkillMgrBase:SingleClientSkillContainsFeature(skillFeatureStr, featureId)
	if skillFeatureStr then
		local featureTbl = self.m_SkillFeatureName2Id
		for w in string.gmatch(skillFeatureStr, "([^;]+)") do
			local wNum = tonumber(w)
			if type(wNum) == "number"  then
				if featureId == wNum then
					return true
				end
			else
				local fid = featureTbl[w]
				if fid == featureId then
					return true
				end
			end
		end
	end
	return false
end

function CSkillMgrBase:SkillContainsFeature(cls, featureId)
	if bServer then
		return self.m_SkillFeatureId2True[cls] and self.m_SkillFeatureId2True[cls][featureId]
	else
		return self:ClientSkillContainsFeatures(cls, featureId)
	end
end

local shield_penetration_skill_feature = Skill_Settings.SHIELD_PENETRATION_SKILL_FEATURE.numVal
function CSkillMgrBase:CanSkillPenetrateShield(cls)
	return self:SkillContainsFeature(cls, shield_penetration_skill_feature)
end

-- 技能是否不作用于盾（AttMode=h/穿透/CanBlock不可格挡），选盾层与拆分钩子共用（#1341992），条件单点维护
function CSkillMgrBase:IsSkillIgnoreShield(designData, defender, shield, dpsStatCls)
	if not designData then return false end
	if designData.AttMode == "h" then return true end
	if dpsStatCls and self:CanSkillPenetrateShield(dpsStatCls) then return true end
	local canBlock = designData.CanBlock
	if shield and canBlock and canBlock > 0 and shield ~= defender:GetCreatedShield() then return true end
	return false
end

-- 统一盾选取判定（#1341992）：五条命中路径（主路径/tick/弹道/光环/旗子）共用。
-- AttMode=h/穿透技能/CanBlock不可格挡技能/承伤盾 → 不挡（返回nil）；否则返回格挡盾
-- skillId：技能实例id（主/tick/弹道传入；光环/旗子传nil跳过穿透判定），内部取DPS统计cls判穿透
function CSkillMgrBase:GetBlockingShield(defender, attacker, designData, skillId)
	if not designData then return end
	local shield = defender:GetShield(attacker)
	if not shield then return end
	local dpsCls = skillId and GetRealSkillClsBySourceId(skillId)
	if self:IsSkillIgnoreShield(designData, defender, shield, dpsCls) then return end
	-- 承伤比例的盾不格挡（#1341992）：伤害命中受击者，由拆分钩子按比例转移
	if shield:IsShareHurtEnabled() then return end
	return shield
end

-- 查询技能能不能升阶
function CSkillMgrBase:CheckSkillCanUpOrder(iSkillCls)
	if not iSkillCls then return false end
	local designData = SkillUI_LearnUpgrade[iSkillCls]
	if not designData then return false end
	if designData.ClassItem then
		return true
	end
	return false
end

function CCharacter:IsStealPassiveSkillSlotUnlock(slotIdx)
	if slotIdx > EnumHotItemSkillTypeSize[EnumSkillType2HotSlot.StealPassiveSkill] then 
		return false
	end	
	local year = GetCurGameVersionYear()
	local row = SkillUI_StealSkillSlot[year] and SkillUI_StealSkillSlot[year][slotIdx]
	if not row then
		return false
	end
	if row.IsAutoUnlock == 1 then
		return true	-- 自动解锁了
	end
	if row.OpenSeasonAutoUnlock and CheckDesignDataOpenDaysAndDate(row, self:GetServerId(), nil, "AutoUnlock") then
		return true
	end
	if IsRunningServerCode() then
		local data = self:PlayProp():GetUserPlayData("StealPassiveSkillUnlockSlot")
		return data and data[slotIdx] == 1
	else
		if g_GacRemoteBuildMgr:CheckIsInEditing() then
			--local src = g_GacRemoteBuildMgr:GetTezhiEditData("StealUnlockedSlot")
			--return src[slotIdx]
			return
		end
		local data = self:PlayProp():GetUserPlayData("StealPassiveSkillUnlockSlot")
		return data and data[slotIdx] == 1
	end
end

if IsRunningServerCode() then
	function CCharacter:IsStealMasterySkill(skillCls)
		return g_StealSkillMgr:IsStealMasterySkill(self, skillCls)
	end
	function CCharacter:IsFixSelfPassiveSkill(skillCls)
		return g_StealSkillMgr:IsFixSelfPassiveSkill(self, skillCls)
	end
	function CCharacter:GetStealSkillClass(skillCls)
		return g_StealSkillMgr:GetStealSkillClass(skillCls)
	end
else
	function CCharacter:IsStealMasterySkill(skillCls)
		return g_SkillTheifMgr:IsJTPassiveSkill(skillCls)
	end
	function CCharacter:IsFixSelfPassiveSkill(skillCls)
		return g_SkillTheifMgr:IsDefaultPassiveSkill(skillCls)
	end
	function CCharacter:GetStealSkillClass(skillCls)
		return g_SkillTheifMgr:GetStealSkillClass(skillCls)
	end
end

local _StealSkillBuildArgs = {}
function CSkillMgrBase:CanBuildToStealPassiveSkillGuide(player, slotIdx, skillCls, stealSpSel)
	if not player then return false, -1 end
	if not player:IsStealPassiveSkillSlotUnlock(slotIdx) then return false, -2 end

	local classSkillType, classSkillSubType = self:GetClassSkillType(skillCls)
	if not (classSkillType and (classSkillType == EnumClassSkillType.JianghuPassiveSkill or classSkillType == EnumClassSkillType.StealPassiveSkill))
	and not self:IsSpecializedSkill(skillCls) then
		return false, -3
	end
	local serverId = player:GetServerId()
	local skillClass = player:GetStealSkillClass(skillCls)
	if skillClass then
		if skillClass == player:GetClass() then
			return false, -4 --当前职业的偷师技不能装
		end
		local row = SkillUI_StealSkill[skillClass]
		if not (row and CheckDesignDataOpenDaysAndDate(row, serverId)) then
			return false, -5 --偷师技能的赛季检查不通过
		end
	end
	_StealSkillBuildArgs.SlotIdx = slotIdx
	_StealSkillBuildArgs.ClassSkillType = classSkillType
	_StealSkillBuildArgs.ClassSkillSubType = classSkillSubType
	_StealSkillBuildArgs.SkillCls = skillCls
	_StealSkillBuildArgs.StealSpSel = stealSpSel
	_StealSkillBuildArgs.IsDefensivePassiveSkill = self:IsDefensivePassiveSkill(skillCls)
	local year = GetCurGameVersionYear(serverId)
	local yearDesign = SkillUI_StealSkillSlot[year]
	local formulaTbl = AllFormulas.SkillUI_StealSkillSlotBCond or EMPTY_TABLE

	local condIds = yearDesign[0] and yearDesign[0].BuildCondIds
	for k, v in bddpairs(condIds or EMPTY_TABLE) do
		local condFunc = formulaTbl[v] and formulaTbl[v].Cond
		if condFunc then
			local bPassed, msg = condFunc(player, player, _StealSkillBuildArgs)
			if not bPassed then
				return false, -6, msg
			end
		end
	end
	condIds = yearDesign[slotIdx] and yearDesign[slotIdx].BuildCondIds
	for k, v in bddpairs(condIds or EMPTY_TABLE) do
		local condFunc = formulaTbl[v] and formulaTbl[v].Cond
		if condFunc then
			local bPassed, msg = condFunc(player, player, _StealSkillBuildArgs)
			if not bPassed then
				return false, -7, msg
			end
		end
	end
	condIds = yearDesign[slotIdx] and yearDesign[slotIdx].MutualBuildCondIds
	table.clear(TEMP_TABLE)
	for k, v in bddpairs(condIds or EMPTY_TABLE) do
		local condFunc = formulaTbl[v] and formulaTbl[v].Cond
		if condFunc then
			local bPassed, msg = condFunc(player, player, _StealSkillBuildArgs)
			if not bPassed then
				return false, -8, msg
			end
		end
		TEMP_TABLE[v] = true
	end
	for k, v in bddpairs(yearDesign) do
		if k ~= slotIdx and v.MutualBuildCondIds then
			for _, condId in bddpairs(v.MutualBuildCondIds) do
				local condFunc = (not TEMP_TABLE[condId]) and formulaTbl[condId] and formulaTbl[condId].Cond
				if condFunc then
					local bPassed, msg = condFunc(player, player, _StealSkillBuildArgs)
					if bPassed then
						return false, -9, msg
					end
				end
			end
		end
	end
	return true
end

local _defensivePassiveSkillFeature = Skill_Settings.DEFENSIVE_PASSIVE_SKILL_FEATURE.numVal
function CSkillMgrBase:IsDefensivePassiveSkill(SkillCls)
	if bServer then
		local skillFeatureSet = self.m_SkillFeatureId2True[SkillCls]
		return _defensivePassiveSkillFeature and skillFeatureSet and skillFeatureSet[_defensivePassiveSkillFeature] or false
	else
		return self:ClientSkillContainsFeatures(SkillCls, _defensivePassiveSkillFeature)
	end
end

-- 把非0的超过最大尺寸的删了
function CSkillMgrBase:AdjustLogSkillList(list, iMaxCount)
	if not list then
		return
	end
	local iListCount = #list
	if iMaxCount > 0 and iListCount > 0 then
		for i = iListCount, 1, -1 do
			if list[i] then
				if i > iMaxCount then
					list[i] = nil
				else
					if not IdIsSkillCls(list[i]) then
						table.remove(list, i)
					end
				end
			end
		end
	end
end


function CSkillMgrBase:CheckIsSeasonDefaultTezhi(skillCls)
	local mainSkillCls = Skill_SkillChange_Rev_Sub2MainNIdx[skillCls] and Skill_SkillChange_Rev_Sub2MainNIdx[skillCls][1] or skillCls
	local ds = SkillUI_Setting.SEASON_TEZHI_EX_LIST.TblVal
	if ds and ds[mainSkillCls] then
		return true
	else
		return false
	end
end

function CSkillMgrBase:GetSeasonDefualtTezhi()
	local list = {}
	local ds = SkillUI_Setting.SEASON_TEZHI_EX_LIST.TblVal
    if ds and bddnext(ds) then
        for k,v in bddpairs(ds) do
            table.insert(list, k)
        end
    end
	return list
end

function CSkillMgrBase:AddRealSeasonDefualtTezhiToList(player,list)
	if not player or not list then
		return
	end
	local ds = SkillUI_Setting.SEASON_TEZHI_EX_LIST.TblVal
    if ds and bddnext(ds) then
        for k,v in bddpairs(ds) do
			if IsSkillLearned(player, k) then
				local iRealSkillCls = g_SkillMgr:GetSkillDerivedChangeCls(k, player:ItemProp():GetSwitchSkill_At(k) or 1)
				if not table.find(list, iRealSkillCls) then
					table.insert(list, iRealSkillCls)
				end
			end
        end
    end
	
end


-- 检查技能套路数据中 ProfessionalSkill/JianghuSkill/UniqueSkill 三个字段是否超出正常槽位数量
-- 用 pairs 遍历所有 key，检出下标超出 normalSize 的异常位并清理
-- @param buildData table 技能套路数据（会被原地修改）
-- @return boolean 是否有数据被修正
function CSkillMgrBase:CheckAndTrimSkillGuideSlots(buildData)
    if not buildData then return false end

    local checkSkillTypes = {
        EnumSkillType2HotSlot.ProfessionalSkill,
        EnumSkillType2HotSlot.JianghuSkill,
        EnumSkillType2HotSlot.UniqueSkill,
    }

    local hasFix = false

    for _, skillType in ipairs(checkSkillTypes) do
        local normalSize = EnumHotItemSkillTypeSize[skillType]
        if normalSize then
            local slotArr = buildData[skillType]
            if slotArr and type(slotArr) == "table" then
                -- 用 pairs 遍历，避免 # 遇到 hole 返回值不准确，漏掉正常下标外的脏数据
                for i, skillId in pairs(slotArr) do
                    if type(i) == "number" and i > normalSize then
                        if skillId and skillId ~= 0 then
                            hasFix = true
                            LogCallContext_lua()
                        end
                        slotArr[i] = nil
                    end
                end
            end
        end
    end

    return hasFix
end

function CSkillMgrBase:CheckSkillCanUseInMoJin(player, skillCls)
	if not IsPlayerInMoJinPlay(player) then
		return
	end
	local design = Skill_Skill[skillCls]
	if not design or not design.CanUseInMJ then
		return
	end
	local tuoKaSkillCls = MoJinPlay_Setting.MOJIN_TUOKA_SKILLCLS.TblVal[1]
	if tuoKaSkillCls and table.find(tuoKaSkillCls, skillCls) then
		return true
	end
	local skillchangeInfo = Skill_SkillChange_Rev[skillCls]
	local groupId = skillCls
	if skillchangeInfo then
		groupId = skillchangeInfo[1]
	end
	local tp, _, cls = self:GetClassSkillType(groupId)
	if not tp then
		return true
	end

	if tp == EnumSkillType2HotSlot.JianghuSkill
		or tp == EnumSkillType2HotSlot.UniqueSkill then
		return true
	end

	local mainClass = player:GetClass()
	local gameplayClass = GetMojinGamePlayerClass(player)

	if mainClass ~= gameplayClass then -- 搜打撤切职业
		local cls, idx = GetMojinSkillSkillChangeRealSkill(player, groupId)
		local bLearned = IsMojinOtherClassLearnedChangeSkill(player, cls, gameplayClass, idx)
		if bLearned then
			return true
		end		
	else
		if tp == EnumSkillType2HotSlot.ProfessionalSkill then
			if GetMojinGamePlayerClass(player) == cls then
				return true
			end
		end		
	end


	if bServer then
		if g_StealSkillMgr:IsStealActiveSkill(player, skillCls) then 
			return true
		end

		local joiner = player:GetGameplay():GetJoiner(player:GetPlayerId())
		if joiner and joiner.m_StatusInfo["IsSkillFix"] then
			if tp == EnumSkillType2HotSlot.ProfessionalSkill then
				return true
			end
		end
	end
end

function CSkillMgrBase:GetPassiveQTESkillCls(iClass)
    local designData = SkillUI_MainSkill[iClass]
    if not designData then return 0 end
    return designData.PassiveQTESkills and designData.PassiveQTESkills[1] or 0
end

function CSkillMgrBase:UxDataTable2Num(tbl)
    for k, v in pairs(tbl or EMPTY_TABLE) do
        local num = tonumber(v)
        tbl[k] = num
    end
end

function CSkillMgrBase:SetSkillDebug(enable)
	self._m_Debug = enable
end

function CSkillMgrBase:ParsePuGongList()
	self.m_PuGongList = {}
	for class, _ in bddpairs(Class_Class)do
		for _, skillCls in bddpairs(table.safe_get(SkillUI_MainSkill, class, "Skills") or EMPTY_TABLE) do
			self.m_PuGongList[skillCls] = true
		end
	end
end

function CSkillMgrBase:IsPuGongSkillCls(skillCls)
	return self.m_PuGongList[skillCls]
end

function IsSuWenLikeClass(iClass)
    return iClass == EnumPlayerClass.eSuWen or iClass == EnumPlayerClass.eHongYin
end

-- 是否是双姿态切换技能组
function IsStatusSwitchGroupSkill(skillGroupId)
    local tblInfo = Skill_SkillChange_Rev2[skillGroupId]
    skillGroupId = tblInfo and tblInfo.ID or skillGroupId
    local suwenGidTbl = GameSetting_Common.SuWenStatusSwitch_GroupId.tblVal
    local hongyinGidTbl = GameSetting_Common.HongYinStatusSwitch_GroupId.tblVal
    if (suwenGidTbl and suwenGidTbl[skillGroupId]) or (hongyinGidTbl and hongyinGidTbl[skillGroupId]) then
        return true
    end
    return false
end

function GetSkillClsById(skillId)
    if IdIsSkillCls(skillId) then
        return skillId
    end
    if IdIsSkill(skillId) then
        return math.floor(skillId/100)
    end
end

function CSkillMgrBase:IsSkillSpeedInfluenced(SkillCls, Character)
	local skillProp = self:GetSkillProp(SkillCls, Character)
	local speedInfluenced = skillProp and skillProp.SpeedInfluenced
	return speedInfluenced ~= 1
end


function CSkillMgrBase:GetSkillMaxSpeed(SkillCls, Character)
	local skillProp = self:GetSkillProp(SkillCls, Character)
	return skillProp.MaxSpeed
end
