function CSkillObject:Ctor()
	self.m_State = CSimpleMemState:new()
	self.m_IsValid = true
end

function CSkillObject:IsFlowchartControllable(obj)
	if obj and obj.m_IsValid then
		return true
	end
	return false
end

function CSkillObject:CreateAOITrigger(size, skillId, offset, eyeSightZ, duration, MaxTarget, MaxPlayer, NeedQueryTick, IsObjIgnoreQuery, clientHitType)
    -- LOG_PRINT(DEBUG,"CreateAOITrigger", g_App:GetFrameTime(), size, skillId, offset, eyeSightZ, duration)
    self:RemoveAOITrigger()

    local owner = self.m_Owner
    clientHitType = EnumAoiTriggerClientHitType.None

    if g_AoiTriggerClientHitEnabled then
        if clientHitType and SEnumAoiTriggerClientHitType[clientHitType] then
            clientHitType = clientHitType
        elseif owner.m_IsPlayer then
            clientHitType = EnumAoiTriggerClientHitType.Player
        end
    end

    local trigger = CAOITrigger:new(EnumAoiTriggerType.eSkillObj, self:GetSkillCls(), owner, duration, clientHitType)
    self.m_AOITriggerHitTb = {}

    local maxT = MaxTarget
    local maxP = MaxPlayer
    if (not maxT or not maxP) and skillId then
        local skillCls, lv = GetSkillClsLv(skillId)
        local skillObj = g_SkillMgr:GetSkillObj(skillCls)
        local skillProp = skillObj.m_SkillProp
        maxT = maxT or g_SkillMgr:GetSkillColTargets(owner, skillObj, lv)
        maxP = maxP or g_SkillMgr:GetSkillColMaxPlayerTargets(owner, skillProp)
    end
    maxT = maxT or 0
    maxP = maxP or 0
    local function EnterCallBack(self, target)
        -- LOG_PRINT(DEBUG,owner, "AOI Hit", target)
        if not target:CanFight() then return end
        if not owner or target == owner then return end
        if clientHitType ~= EnumAoiTriggerClientHitType.None and target:IsPlayer() and not self.m_AOITrigger:CheckEnterObjValid(target) then
            return
        end
        if self.m_AOITriggerInvalidTime then
            local s1 = self.m_AOITriggerInvalidTime and g_App:GetGlobalTime() >= self.m_AOITriggerInvalidTime and "timeout" or "intime"
        end
        if self.m_AOITriggerInvalidTime and g_App:GetGlobalTime() >= self.m_AOITriggerInvalidTime and not self.m_AOITrigger:CheckEnterObjValid(target) then
            self.m_TimeoutEnterObjId = self.m_TimeoutEnterObjId or {}
            self.m_TimeoutEnterObjId[target.m_engineObjectId] = true
            return
        end
        if self.m_AOITriggerHitTb[target.m_engineObjectId] then return end
        self.m_AOITriggerHitTb[target.m_engineObjectId] = true

        if EFlowEvent["ISawInViewAoi"] then
            self:OnFlowchartEvent("ISawInViewAoi", target)
        end

        if not self.m_AOITrigger:CheckMaxTargetCount(maxT, maxP) then return end

        if skillId and target:IsAlive() then
            local skillCls, lv = GetSkillClsLv(skillId)
            local skillObj = g_SkillMgr:GetSkillObj(skillCls)
            local skillProp = skillObj.m_SkillProp
            local category = g_SkillMgr:GetSkillPropData(skillCls, "Category", owner, true)
            local pendingClientHitResult = trigger and trigger.m_PendingClientHitResult
            if category == 2 then
                if g_SkillMgr:IsValidSkillTarget(owner, target, skillProp.EffectTarget, skillProp.ID, skillObj.m_EffectTargetCondition, lv, skillProp.AttMode) then
                    self.m_AOITrigger:UpdateTargetCount(target)
                    g_SkillMgr:CastingSkill(
                        self.m_Owner, target, {
                            SkillId = skillId,
                            Cls = skillCls,
                            Lv = lv,
                            SourceId = self:GetSkillId(),
                            TargetId = target:GetEngineObjectGlobalId(),
                            ClientHitResult = pendingClientHitResult,
                        }
                    )
                end
            else
                self.m_AOITrigger:UpdateTargetCount(target)
                owner:DoCastSkill(skillId, target, nil, nil, nil, nil, self:GetSkillId())
            end
        end
    end
    local function LeaveCallBack(self, target)
        if self.m_AOITriggerInvalidTime then
            local s1 = self.m_AOITriggerInvalidTime and g_App:GetGlobalTime() >= self.m_AOITriggerInvalidTime and "timeout" or "intime"
        end
        if self.m_AOITriggerInvalidTime and g_App:GetGlobalTime() >= self.m_AOITriggerInvalidTime and not self.m_AOITrigger:CheckEnterObjValid(target) then
            return
        end
        if EFlowEvent["ISawLeftViewAoi"] then
            self:OnFlowchartEvent("ISawLeftViewAoi", target)
        end
    end
    trigger:SetCallBack(self, EnterCallBack, LeaveCallBack)
    trigger:Init(owner, size, offset, eyeSightZ, NeedQueryTick, nil, IsObjIgnoreQuery, skillId and GetSkillClass(skillId) or 0)
    self.m_AOITrigger = trigger

    self:TrySkillAoiTriggerDraw(owner, size, offset, eyeSightZ, duration)

    if duration then
        assert(duration > 0)
        self.m_AOITriggerInvalidTime = g_App:GetGlobalTime() + duration * 1000
    end
end

function CSkillObject:TrySkillAoiTriggerDraw(owner, size, offset, eyeSightZ, duration)
	if not SAConfig.InnerServer or not owner then
		return
	end

	if not g_SkillMgr.m_SkillHitDebugDrawPlayerSet or not next(g_SkillMgr.m_SkillHitDebugDrawPlayerSet) then
		return
	end
	
	local x, y, z = owner.m_engineObject:GetPixelPosv3()
	local offsetX = offset and offset.x or 0
	local offsetY = offset and offset.y or 0
	local skillID = self:GetSkillId()
	local templateId = self:GetSkillCls()
	local ownerEngineId = owner.m_engineObjectId
	local conn = owner.m_Conn

	if not conn then
		conn = g_ServerPlayerMgr:GetIS()
	end

	-- Ensure all parameters are valid numbers
	if type(ownerEngineId) ~= "number" then ownerEngineId = 0 end
	if type(skillID) ~= "number" then skillID = 0 end
	if type(templateId) ~= "number" then templateId = 0 end
	if type(x) ~= "number" then x = 0 end
	if type(y) ~= "number" then y = 0 end
	if type(z) ~= "number" then z = 0 end
	if type(size) ~= "number" then size = 0 end
	if type(offsetX) ~= "number" then offsetX = 0 end
	if type(offsetY) ~= "number" then offsetY = 0 end
	if type(eyeSightZ) ~= "number" then eyeSightZ = 0 end
	if type(duration) ~= "number" then duration = 0 end
	
	Gas2Gac:TrySkillAoiTriggerDraw(conn or 0, ownerEngineId, skillID, templateId, x, y, z, size, offsetX, offsetY, eyeSightZ, duration)
end

function CSkillObject:RemoveAOITrigger()
	-- LOG_PRINT(DEBUG,"RemoveAOITrigger",CSkillObject._n)
	local trigger = self.m_AOITrigger
	if not trigger then return end
	self.m_AOITrigger = nil
	self.m_AOITriggerInvalidTime = nil
	trigger:Destroy()
end

function CSkillObject:DoCastSkill(id,target,x,y,z,delay,sourceId)
	local timesHurtMul,timesHurtAdj
	if self.m_SourceInfoExtra then
		timesHurtMul,timesHurtAdj = self.m_SourceInfoExtra["TimesHurtMul"], self.m_SourceInfoExtra["TimesHurtAdj"]
	end
	self.m_Owner:DoCastSkill(id,target,x,y,z,delay,sourceId,timesHurtMul,timesHurtAdj)
end

function CSkillObject:Destroy()
	self.m_IsValid = false
	
	self:RemoveAOITrigger()
	self:RemoveStepTick()

	flowchart.deinit(self)
end

function CSkillObject:RemoveStepTick()
	if self.m_StepTick then
		UnRegisterTick(self.m_StepTick)
		self.m_StepTick = nil
	end
end

function CSkillObject:GetSkillCls()
	return self.m_SkillCls
end

function CSkillObject:GetSkillId()
	return self.m_Owner:IsPlayerOrFake() and self.m_Owner:GetSkillByCls(self:GetSkillCls()) or self:GetSkillCls() * 100 + 1
end

function CSkillObject:EnterExtraSkillState()
	self.m_IsInExtraSkill = true
end

function CSkillObject:LeaveExtraSkillState()
	self.m_IsInExtraSkill = false
end

function CSkillObject:IsInExtraSkillState()
	return self.m_IsInExtraSkill
end

function CSkillObject:SetStep(value, skillSourceId, bSetBrotherSkillCD, Interval, bExtraSkill)
	if self.m_Step == value then
		return false
	end

--	local stepSkillCls = g_SkillMgr:GetStepSkillCls(self.m_Owner, self:GetSkillCls(), value)
--	local stepSkillObj =  Skill_Skill[stepSkillCls]
--	if stepSkillObj and stepSkillObj.ComboSkillLearnLevel and self.m_Owner:GetGrade() < stepSkillObj.ComboSkillLearnLevel then
--		return false
--	end
	
	local oldStep = self.m_Step
	
	self.m_Step = value
	self.m_StepIntTotalT = value ~= 0 and type(Interval) == "number" and Interval * 1000 or -1
	self.m_StepIntTime = g_App:GetGlobalTime()

	local bOnStepEnd = false

	if value ~= 0 then
		if self.m_IsInExtraSkill then
			-- do nothing
		else
			if bExtraSkill then
				bOnStepEnd = true -- 后置，避免cd先展示出来
				self.m_IsInExtraSkill = true
			end
		end
	else -- value == 0
		if self.m_IsInExtraSkill then
			self.m_IsInExtraSkill = false
		else
			self:OnStepEnd(oldStep, skillSourceId, bSetBrotherSkillCD) --先进cd再切段
		end
	end

	if self.m_Owner.m_IsPlayer then
		Gas2Gac:SyncMainPlayerStepSkill(self.m_Owner.m_Conn or 0, self:GetSkillCls(), self.m_Step, self.m_StepIntTime,
			self.m_StepIntTotalT, self.m_IsInExtraSkill)
	end

	if bOnStepEnd then
		self:OnStepEnd(oldStep, skillSourceId, bSetBrotherSkillCD) --先切段再进cd
	end

	return true
end

function CSkillObject:OnStepEnd(oldStep, skillSourceId, bSetBrotherSkillCD)
	local skillCls = self:GetSkillCls()
	local skillId = self.m_Owner:IsPlayerOrFake() and self.m_Owner:GetSkillByCls(skillCls) or skillCls * 100 + 1

	if not skillSourceId then
		skillSourceId = g_SkillMgr:GetStepSkillId(self.m_Owner, skillId, oldStep)
	end

	g_SkillMgr:SetSkillCooldownByID(self.m_Owner, skillSourceId, skillCls, nil, true)
	g_SkillMgr:DoSkillEndAction(self.m_Owner, skillId)

	if bSetBrotherSkillCD then
		g_ActionMgr:DoAction(self.m_Owner, nil, nil, "SetBrotherSkillCD", { SkillId = skillSourceId })
	end

	local owner = self.m_Owner
	if owner:IsPlayerOrFake() then
		owner:OccupationFunc("OnResetSkillStep")
	end
end

function CSkillObject:OnStepEnd4UGC(oldStep, skillSourceId, bSetBrotherSkillCD, cdType)
	local skillCls = self:GetSkillCls()
	local skillId = self.m_Owner:IsPlayerOrFake() and self.m_Owner:GetSkillByCls(skillCls) or skillCls * 100 + 1

	if not skillSourceId then
		skillSourceId = g_SkillMgr:GetStepSkillId(self.m_Owner, skillId, oldStep)
	end

	if cdType == 1 then
		g_SkillMgr:SetSkillCooldownByID(self.m_Owner, skillSourceId * 100 + 1, skillCls, nil, true)
	end
	g_SkillMgr:DoSkillEndAction(self.m_Owner, skillId)

	if bSetBrotherSkillCD then
		g_ActionMgr:DoAction(self.m_Owner, nil, nil, "SetBrotherSkillCD", { SkillId = skillSourceId })
	end

	local owner = self.m_Owner
	if owner:IsPlayerOrFake() then
		owner:OccupationFunc("OnResetSkillStep")
	end
end


function CSkillObject:AddSkillStep(Interval, MaxStep, SourceId, MiniCoolDown, bSetBrotherSkillCD, bExtraSkill)
	self:SetSkillStep(Interval, (self.m_Step + 1) % MaxStep, SourceId, MiniCoolDown, bSetBrotherSkillCD, bExtraSkill)
end

function CSkillObject:SetSkillStep(Interval, Step, SourceId, MiniCoolDown, bSetBrotherSkillCD, bExtraSkill)
	local owner = self.m_Owner
	local skillCls = self:GetSkillCls()

	if not g_SkillMgr:IsMainSkillCls(skillCls) then
		return
	end

	local oriInterval = Interval
	Interval = type(oriInterval) == "number" and
		oriInterval / owner:GetAttackSpeedForSkill(skillCls, owner:GetInHitRecoverSkillContext(skillCls) or EMPTY_TABLE) or
		oriInterval
	if not self:SetStep(Step, SourceId, bSetBrotherSkillCD, Interval, bExtraSkill) then
		return
	end

	if oriInterval and oriInterval > 0 and self.m_Step ~= 0 then
		self:RemoveStepTick()
		self.m_SourceId, self.m_bSetBrotherSkillCD = SourceId, bSetBrotherSkillCD
		local intervalMs = (Interval * 1000 + 100) * owner:GetTimeScaleRev()
		self.m_StepTick = RegisterTickWithDuration(self.ClearSkillStep, intervalMs, intervalMs, self, SourceId, bSetBrotherSkillCD)
	end

	if MiniCoolDown then
		local skillCls = self:GetSkillCls()
		local cdSkillCls = self:IsInExtraSkillState() and g_SkillMgr:GetStepSkillCls(nil, skillCls, Step) or skillCls
		g_SkillMgr:SetSkillCoolDownTimeWithSync(owner, cdSkillCls, MiniCoolDown)
	end
end

function CSkillObject:SetStep4UGC(value, skillSourceId, bSetBrotherSkillCD, Interval, bExtraSkill, cdType)
	cdType = cdType or 1
	if self.m_Step == value then
		return false
	end
	
	local oldStep = self.m_Step
	
	self.m_Step = value
	self.m_StepIntTotalT = value ~= 0 and type(Interval) == "number" and Interval * 1000 or -1
	self.m_StepIntTime = g_App:GetGlobalTime()

	local bOnStepEnd = false

	if value ~= 0 then
		if self.m_IsInExtraSkill then
			-- do nothing
		else
			if bExtraSkill then
				bOnStepEnd = true -- 后置，避免cd先展示出来
				self.m_IsInExtraSkill = true
			end
		end
		if value == 1 and cdType == 2 then
			print("CSkillObject:SetStep4UGC set cd on step 1")
			g_SkillMgr:SetSkillCooldownByID(self.m_Owner, skillSourceId * 100 + 1, self:GetSkillCls(), nil, true)
		end
	else -- value == 0
		if self.m_IsInExtraSkill then
			self.m_IsInExtraSkill = false
		else
			self:OnStepEnd4UGC(oldStep, skillSourceId, bSetBrotherSkillCD, cdType) --先进cd再切段
		end
	end

	if self.m_Owner.m_IsPlayer then
		Gas2Gac:SyncMainPlayerStepSkill(self.m_Owner.m_Conn or 0, self:GetSkillCls(), self.m_Step, self.m_StepIntTime,
			self.m_StepIntTotalT, self.m_IsInExtraSkill)
	end

	if bOnStepEnd then
		self:OnStepEnd4UGC(oldStep, skillSourceId, bSetBrotherSkillCD, cdType) --先切段再进cd
	end

	return true
end

function CSkillObject:SetSkillStep4UGC(Interval, Step, SourceId, MiniCoolDown, CDType)
	local owner = self.m_Owner
	local skillCls = self:GetSkillCls()

	local oriInterval = Interval
	Interval = oriInterval / owner:GetAttackSpeedForSkill(skillCls, owner:GetInHitRecoverSkillContext(skillCls) or EMPTY_TABLE)
	if not self:SetStep4UGC(Step, SourceId, false, Interval, false, CDType) then
		return
	end

	if oriInterval and oriInterval > 0 and self.m_Step ~= 0 then
		self:RemoveStepTick()
		self.m_SourceId = SourceId
		self.m_StepTick = RegisterTickWithDuration(self.ClearSkillStep4UGC, Interval * 1000 + 100, Interval * 1000 + 100, self, SourceId, false, CDType)
	end

	-- if MiniCoolDown then
	-- 	local skillCls = self:GetSkillCls()
	-- 	local cdSkillCls = skillCls
	-- 	g_SkillMgr:SetSkillCoolDownTimeWithSync(owner, cdSkillCls, MiniCoolDown)
	-- end
end

function CSkillObject:ClearSkillStep4UGC(SourceId, bSetBrotherSkillCD, CDType)
	local owner = self.m_Owner
	
	if owner.m_engineObject and g_StatusMgr:GetStatus(owner, EPropStatus.HitRecoverCombo) == 1 then
		local currComboSkillCls = owner:OccupationFunc("GetCurrComboSkillCls")
		if currComboSkillCls then
			local selfSkillCls = self:GetSkillCls()
			local ret = self.m_Owner:OccupationFunc("TryClearRecoverComboStatus", nil, 0)	
			if not ret then
				g_StatusMgr:SetAttributeWithSync(owner, EPropStatus.HitRecoverCombo, {HasStepSkill = 0})
			end
		end		
	end
	
	if self.m_Owner:IsPlayerOrFake() then
		local skillCls = self:GetSkillCls()
		local skillId =  self.m_Owner:GetSkillByCls(skillCls) or skillCls * 100 + 1
		self.m_Owner:OccupationFunc("OnLeaveSkillStep", skillId)			
	end
	self:SetStep4UGC(0, SourceId, bSetBrotherSkillCD, -1, CDType)
	g_UGCLevelMgr:OnSkillStepEnd(self.m_Owner, self:GetSkillCls())
end

function CSkillObject:ExtendSkillStepTime(Interval)
	if not g_SkillMgr:IsMainSkillCls(self:GetSkillCls()) then
		LogCallContext_lua()
		return
	end
	
	if not self.m_StepTick then
		return
	end
	
	local duration = Interval * 1000 
	self:RemoveStepTick()
	self.m_StepTick = RegisterTickWithDuration(self.ClearSkillStep, duration + 100, duration + 100, self, self.m_SourceId, self.m_bSetBrotherSkillCD)
	self.m_StepIntTotalT = duration
	self.m_StepIntTime = g_App:GetGlobalTime()
	if self.m_Owner.m_IsPlayer then
		Gas2Gac:SyncMainPlayerStepSkill(self.m_Owner.m_Conn or 0, self:GetSkillCls(), self.m_Step, self.m_StepIntTime, self.m_StepIntTotalT)
	end
end

function CSkillObject:GetSkillStep()
	local owner = self.m_Owner
	return self.m_Step or 0
end
function CSkillObject:GetSkillStepDetail()
	local owner = self.m_Owner
	return self.m_Step or 0, self.m_StepIntTime or -1, self.m_StepIntTotalT or -1
end

function CSkillObject:ClearMemberVar(skillCls, ...)
	local skillObj = self
	if skillCls ~= nil then
		skillObj = self.m_Owner:LuaDataProp():GetSkillBehavior(skillCls*100, self.m_Owner)
		if not skillObj then
			return
		end
	end
	
	local args = {...}
	if #args ~= 0 then
		for i,name in ipairs(args) do
			skillObj.m_State:SetData(name,nil)
		end
	else
		skillObj.m_State:ClearData()
	end
end

function CSkillObject:GetSkillVar(skillCls, VarName)
	local skillObj = self
	if skillCls ~= nil then
		skillObj = self.m_Owner:LuaDataProp():GetSkillBehavior(skillCls*100, self.m_Owner)
		if not skillObj then
			return 
		end
	end
	
	return skillObj.m_State:GetData(VarName)
end

function CSkillObject:ClearSkillStep(SourceId, bSetBrotherSkillCD)
	local owner = self.m_Owner
	if not g_SkillMgr:IsMainSkillCls(self:GetSkillCls()) then
		LogCallContext_lua()
		return
	end
	
	if owner.m_engineObject and g_StatusMgr:GetStatus(owner, EPropStatus.HitRecoverCombo) == 1 then
		local currComboSkillCls = owner:OccupationFunc("GetCurrComboSkillCls")
		if currComboSkillCls then
			local selfSkillCls = self:GetSkillCls()
			local ret = self.m_Owner:OccupationFunc("TryClearRecoverComboStatus", nil, 0)	
			if not ret then
				g_StatusMgr:SetAttributeWithSync(owner, EPropStatus.HitRecoverCombo, {HasStepSkill = 0})
			end
		end		
	end
	
	if self.m_Owner:IsPlayerOrFake() then
		local skillCls = self:GetSkillCls()
		local skillId =  self.m_Owner:GetSkillByCls(skillCls) or skillCls * 100 + 1
		self.m_Owner:OccupationFunc("OnLeaveSkillStep", skillId)			
	end
	self:SetStep(0, SourceId, bSetBrotherSkillCD, -1)
end

function CSkillObject:GetOwner()
	return self.m_Owner
end

function CSkillObject:AddOb()
	self.m_Owner:AddEventObserver(self)
end

function CSkillObject:RmOb()
	self.m_Owner:RemoveEventObserver(self)
end

function CSkillObject:DoNewAction(Defender, ActionName, Args)
	local skillId = self:GetSkillId()
	if self.m_SourceInfoExtra then
		self.m_SourceInfoExtra["id"] = skillId
	end
	g_ActionMgr:DoAction(self.m_Owner, Defender, self.m_SourceInfoExtra or {id = skillId}, ActionName, Args or {})
end

function CSkillObject:OnFlowchartEvent(eventName, ...)
	local eventId = eventName and EFlowEvent[eventName]
	if not eventId then
		LogCallContext_lua()
		return
	end
	local res = flowchart.event(self,eventId, ...)
	if res == EnumFlowchartEventRes.ePause then
		LogCallContext_lua()
	end
end


function CSkillObject:SetSourceInfoExtraArgs(k, v)
	self.m_SourceInfoExtra = self.m_SourceInfoExtra or {}
	self.m_SourceInfoExtra[k] = v
end
