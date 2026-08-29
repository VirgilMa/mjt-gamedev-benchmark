local sqrt = math.sqrt
local atan = math.atan
local atan2 = math.atan2
local ceil = math.ceil
local rad = math.rad
local cos = math.cos
local sin = math.sin
local Bullet_Bullet_f = AllFormulas.Bullet_Bullet
local IsNanOrInf = IsNanOrInf


local function SHARE_IMP_TO_SERVER_BULLET_ALL(name) --导出Share上接口的宏
	CServerBullet[name] = function(self, ...) return CServerBulletShare[name](self.m_Share, ...) end
	CServerBulletOpt[name] = function(self, ...) return CServerBulletShare[name](self.m_Share, ...) end
end

function GetBulletObjById(id, isOpt)
	if isOpt then 
		return g_BulletObjectMgr:GetOptBulletByUId(id)
	else
		return GetObjectByGlobalId(id)
	end
end

function CServerBulletShare:Ctor(bullet)
	self.m_Bullet = bullet
	self.m_LastHitTimeTb = {}
	self.m_HitedObjectCount = 0
	self.m_HitedPlayerCount = 0
end

function CServerBulletShare:OnReturn()
	table.clear(self.m_LastHitTimeTb)
	self.m_HitedObjectCount = 0
	self.m_HitedPlayerCount = 0
end
--------------------------------------------------------------------------------

function CServerBullet:Ctor()
	self:InitEngineObjectArgs(EServerObjectType.eSOT_Bullet, EObjectBlockFlag.eOBF_BlockTypeNone, EnumAoiGroup.Monster)
	self:SetCharacterType(EnumCharacterType.Bullet)

	self.m_SkillWallData = nil
	self.m_AutoDestroyTime = nil
	self.m_Level = nil
	self.m_SkillEnabled = true
	self.m_State = CSimpleMemState:new()
	self.m_CanBulletMove = true 
	self.m_TimesHurtMul = nil
	self.m_TimesHurtAdj = nil
	self.m_HitEnabled = true

	self.m_Share = CServerBulletShare:new(self)
	self.m_CurMoveFrame = 0
end

local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local MaxLifeTime = 300 * 30
local MaxEyeSight = 10
local s_ClientHitZombieTtlMs = 500  -- ClientHit 子弹销毁后的僵尸等待期(ms)，用于接收迟到的命中 RPC

function CServerBullet:InitBullet(BulletResData, lv, bx, by, bz, Degree, Sourcer, UseOtherBulletClientResource, ugcBulletData)
	if not BulletResData then 
		LogCallContext_lua()
		return false
	end
	local NPT_TemplateId = BulletResData.ID	-- 看着采样那边需要
	CServerCharacter.Init(self)
	
	--LOG_PRINT(DEBUG,"InitBullet", BulletResData.ID, lv, bx, by, bz)
	
	self.m_Level = lv
	
	self:InitBulletMoveData(BulletResData, bx, by, bz, ugcBulletData, Sourcer)
	self.m_BulletMoveData.m_Status = 1

	self._m_TemplateId_For_Debug = BulletResData.ID
	self.m_BulletMoveData.m_UseOtherBulletClientResource = UseOtherBulletClientResource
	self.m_BulletMoveData.m_OwnerId = Sourcer and Sourcer.m_engineObjectId

	local rootOwner = Sourcer and Sourcer:GetOwner() or Sourcer
	self.m_BulletMoveData.m_RootOwnerId = rootOwner and rootOwner.m_engineObjectId
	self.m_BulletMoveData.m_RootOwnerCharacterType = rootOwner and rootOwner.m_CharacterType

	self:InitSummonObjAppearance(self:GetOwner(), EnumSummonObjType.eBullet)

	local flowchartName = self:GetData("FlowchartName")
	if flowchartName then
		flowchart.init(self, EFlowClass.ServerBullet)
		for _, name in bddipairs(flowchartName) do
			flowchart.load(self,"BulletAI." .. name)
		end
		flowchart.start(self)
	end
	        
    if ugcBulletData then
        self.m_AutoDestroyTime = ugcBulletData[EnumUGCBulletName2PropId["AutoDestroy"]] == 0 and -1 or 0
    else
        self.m_AutoDestroyTime = BulletResData.AutoDestroy		-- -1表示不销毁
    end
	
	local bulletId = self.m_BulletMoveData.m_BulletDataId
	self.m_BornTime = g_App:GetFrameTime()
	self.m_BeforDestroyActionFunc = Bullet_Bullet_f[bulletId] and Bullet_Bullet_f[bulletId].BeforeDestroyAction
	self.m_HitActionFunc = Bullet_Bullet_f[bulletId] and Bullet_Bullet_f[bulletId].HitAction
	self.m_IsNoAoiHitQuery = BulletResData.NoAoiHit and BulletResData.OnlyHitTarget ~= 1 and (ugcBulletData ~= nil or BulletResData.OnHitSkill ~= 0 or BulletResData.FlowchartName or BulletResData.HitReport)

	return true
end

function CServerBullet:InitBulletEngineObject(BulletResData)	--Init时需要已经加入场景
	if not BulletResData or not self.m_engineObject then
		LogCallContext_lua()
		return false
	end

	-- 继承 owner 位面到引擎(不走status): 引擎对象已创建, owner 在位面时子弹跨位面不可见
	self:InheritDivisionFromOwner()

	if BulletResData.ObjIgnoreQuery == 1 and IsOptimizeOpen("ObjIgnoreQuery", self.m_Scene) then
		self.m_engineObject:SetServerObjectFlag(EServerObjectFlag.eSOF_IgnoreQuery, 1)
	end

	local owner = self:BulletGetOwner()
    local lifeTime = self:GetBulletData("LifeTime")
	if lifeTime and lifeTime > 0 then
        lifeTime = lifeTime and lifeTime / 30
		--嘉熠需求：有流程图或者时间长于100帧的子弹，不会受到range属性影响
		if owner and IsClassObject(owner, CServerFightableCharacter) and not BulletResData.FlowchartName and BulletResData.LifeTime <= 100 then
			lifeTime = lifeTime * (1 + owner:GetParam(EFightProp.Range))
		end
		self:SetDieTime(lifeTime)	--策划数据中的LifeTime单位为帧
	end
	
	self:BeginOnSummonSkill()
	return true
end

function CServerBullet:GetAppearUD()
	local appearProp = self:AppearanceProp()
	if (not self.m_AppearUD) and appearProp then
		self.m_AppearUD = appearProp:SaveToString()
	end
	return self.m_AppearUD 
end

function CServerBullet:OnEnterViewAoiOfPlayer(player)
	-- 子弹位面可见性已由引擎过滤(InitBulletEngineObject 继承 owner 位面), 无需此处再拦
	CServerCharacter.OnEnterViewAoiOfPlayer(self, player)
end

g_BulletTrafficOptSwitch = true
local BulletSyncExtraData = {}
function CServerBullet:CreateObjectForConnection(RPCAddress)
	local moveData = self.m_BulletMoveData
	if moveData.m_NewBorn ~= true then
		moveData.m_NewBorn = g_App:GetFrameTime() - self.m_BornTime
	end
	
	table.clear(BulletSyncExtraData)
    local fxId = self.m_UgcBulletData and self.m_UgcBulletData[EnumUGCBulletName2PropId["FxID"]]
    if self.m_UgcBulletData then
        BulletSyncExtraData.UgcBulletData = {}
        BulletSyncExtraData.UgcBulletData.FxID = UGCLevel_Fx[fxId] and UGCLevel_Fx[fxId].RefID
        BulletSyncExtraData.UgcBulletData.FxScale = self.m_UgcBulletData[EnumUGCBulletName2PropId["BulletScale"]]
    end
	BulletSyncExtraData.arv = self.m_AppearReplaceValue
	local appearUD = self:GetAppearUD()
	if appearUD then 
		BulletSyncExtraData.appearUD = appearUD
	end
	if self:StatusProp() then 
		BulletSyncExtraData.statusString = self:StatusProp():SaveToStringForOther()
	end
	if self.m_FruitId then
		BulletSyncExtraData.FruitId = self.m_FruitId
		BulletSyncExtraData.FruitData = self.m_FruitData
	end
	
	local freqMP, noFreqMP, specMP = self:GetBulletMoveDataMsgPack()
	if g_BulletTrafficOptSwitch then
		if not self.m_RefreshedMoveDataFlag then
			specMP = NIL_USER_DATA -- 对于延迟子弹，在RefreshBulletMoveData之前specMP没必要发送
		end
	end

	Gas2Gac:InitBullet(
		RPCAddress,
		self.m_engineObjectId,
		freqMP, noFreqMP, specMP,
		moveData.m_RootOwnerId or 0,
		moveData.m_BulletDataId or 0,
		self.m_UseWeaponCharDef_WeaponId or 0,
		self.m_UseWeaponCharDef_Index or 0,
		self.m_ReplaceTexPath or "",
		self.m_ReplaceRendererIdx or 0,
        next(BulletSyncExtraData) and msgpack.pack(BulletSyncExtraData) or EMPTY_TBL_UD
	)
end

function CServerBullet:RefreshBulletMoveData(RpcAddress)
	self.m_RefreshedMoveDataFlag = true
	CServerCharacter.RefreshBulletMoveData(self, RpcAddress)
end

function CServerBullet:GetBulletAttachToPlayerId(owner)
	local bulletAttachType = self:GetData("BulletAttachType")
	local bulletAttachEnabled = bulletAttachType == 1 or (bulletAttachType == 2 and self:IsOptimizeOpen("SimpleSkill"))
	if not bulletAttachEnabled then return end

	if self.m_AttachToPlayerId then
		return self.m_AttachToPlayerId
	end
	if owner and owner:IsPlayerOrFake() then
		return owner:GetPlayerId()
	end
end

function CServerBullet:OnMoveBegan()
	CServerCharacter.OnMoveBegan(self)
	self.m_IsTargetReached = nil
end

function CServerBullet:OnMoveEnded(MoveArg, bStopAll, StopReason)
	self:SendFCMoveEndEvent()
	self:CheckGenCGScope(true, self:GetPixelPosition())
	CServerCharacter.OnMoveEnded(self, MoveArg, bStopAll, StopReason)

    if self.m_UgcBulletData and IdIsUGCBulletCls(self.m_SourceTemplateId) then
        local gp = self:GetGameplay()
        local bulletRuntime = gp and gp.m_BulletRuntime
        if bulletRuntime then
            bulletRuntime:OnMoveEnd(self)
        end
    end

	self:TryDoOnMoveEndAction()

	if not self.m_Destroying then
		self:AutoDestroy()
	end
end

function CServerBullet:OnMoveStopped(fStopDist, fSpeedX, fSpeedY, nPixelPosX, nPixelPosY, nPixelPosZ)
	CServerCharacter.OnMoveStopped(self, fStopDist, fSpeedX, fSpeedY, nPixelPosX, nPixelPosY, nPixelPosZ)

	self.m_Share:TryDoCollisionBarrierAction()
end

SHARE_IMP_TO_SERVER_BULLET_ALL("TryDoOnMoveEndAction")
function CServerBulletShare:TryDoOnMoveEndAction()
	if self.m_Bullet.m_Destroying then return end
	local templateId = self:GetTemplateId()
	local onMoveEndAction = Bullet_Bullet_f[templateId] and Bullet_Bullet_f[templateId].OnMoveEndAction
	if onMoveEndAction then 
		g_ActionMgr:DoAction(self.m_Bullet, nil, {ProfileId = templateId}, onMoveEndAction)
	end
end

function CServerBulletShare:TryDoCollisionBarrierAction()
	local templateId = self:GetTemplateId()
	local collisionBarrierAction = Bullet_Bullet_f[templateId] and Bullet_Bullet_f[templateId].CollisionBarrierAction
	if collisionBarrierAction then 
		g_ActionMgr:DoAction(self.m_Bullet, nil, {ProfileId = templateId}, collisionBarrierAction)
	end
end

function CServerBullet:OnEnterCallbackRegion(RegionId)
	if not self:CanTriggerRegion(RegionId) then return end
	self:OnFlowchartEvent("EnterRegionId", RegionId)
end

function CServerBullet:SetDieTime(DieTime)
	self.m_Share:SetDieTime(DieTime)
	CServerCharacter.SetDieTime(self, DieTime)
end

function CServerBulletShare:SetDieTime(DieTime)
	if not DieTime then return end
	if self.m_Bullet.m_Destroying then return end
	DieTime = math.max(0.001, DieTime)

	if DieTime > MaxLifeTime then
		DieTime = MaxLifeTime
	end
	
	local isOpt = self.m_Bullet.m_IsOptBullet
	local id = isOpt and self.m_Bullet:GetUId() or self.m_Bullet.m_engineObjectId
	local f = function()
		local bullet = GetBulletObjById(id, isOpt)
		if bullet then
			bullet:Die()
		end
	end
	
	self.m_LiftTime = DieTime
	local dieTimeMs = DieTime * 1000 * self.m_Bullet:GetTimeScaleRev()
	RegisterObjTickWithDuration(self.m_Bullet, "Die", f, dieTimeMs, dieTimeMs)
end

function CServerBullet:SetLifeTime(Time)
	local RestTime = Time / 30 - (g_App:GetFrameTime() - self.m_BornTime) * 0.001
	self:UnRegisterTick("Die")
	self:SetDieTime(RestTime)
end

function CServerBullet:SetMaxDist(Dist)
	self:UpdateProperties({m_MaxDistance = Dist})
end

function CServerBullet:AppearanceProp()
	return self.m_PropertyAppearance
end

function CServerBullet:Die()
	Gas2Gac:BulletDie(self:GetSyncAndSelfIS(), self.m_engineObjectId)
	self:Destroy()
end
function CServerBullet:OnAboutToInsertToScene(Scene)
	CServerCharacter.OnAboutToInsertToScene(self, Scene)

	self.m_engineObject:AddAoiOptFlag(EServerAoiOptFlag.eSAO_LeaveSceneAoiOpt)

	self:CreateAOITriggers(self:GetData("MultiEyeSight"))
	self:FaceToDirection(self.m_InitDegree)
	
	self.m_engineObject:SetKeenness(20000)
	
	local owner = self:BulletGetOwner()
	if owner and owner:IsMonsterOrNpc() and owner:IsSceneSync() then
		self:SetSceneSync()
	end

	if self:GetData("OnlyHitPlayerOpt") then
		self.m_engineObject:SetAoiType(1)
	end

	if self.m_BulletMoveData then
		rawset(self.m_BulletMoveData, "m_EngineObjectId", self.m_engineObjectId)
	end

	if self._m_MoveOnAboutToInsertToScene then

		local moveArgs = self._m_MoveOnAboutToInsertToScene
		self._m_MoveOnAboutToInsertToScene = nil

		self:InitBulletEngineObject(self:GetData())
		self:StartBulletTrajectoryMove(moveArgs)
	end

	local attachToPlayerId = self:GetBulletAttachToPlayerId(owner)
	if attachToPlayerId then
		self.m_engineObject:EnableAttachPlayerSync()
		self.m_engineObject:SetAttachToPlayerId(attachToPlayerId, EMPTY_TABLE)
		self.m_AttachToPlayerId = nil
	end

	-- enable hit
	local hitEnableTime = self:GetData("HitEnableTime")
	if hitEnableTime and hitEnableTime > 0 then
		self.m_HitEnabled = false
		local engineObjectId = self.m_engineObjectId
		self:RegisterTickWithDuration("BulletHitEnable", function()
			local bullet = GetCharacterByEngineObjectGlobalId(engineObjectId)
			if bullet then
				bullet.m_HitEnabled = true
			end
		end, hitEnableTime * 1000, hitEnableTime * 1000)
	end
end

function CServerBullet:OnAfterInsertToScene(Scene)
	CServerCharacter.OnAfterInsertToScene(self, Scene)
	if not (self.m_BulletDelayMoveTime and self.m_BulletDelayMoveTime > 0) then
		self.m_BulletMoveData.m_Status = nil -- 创建子弹且非延迟移动且插入场景后，更新成运动状态
	end
end

function CServerBullet:GetName()
	return self:GetData("Name") or ""
end

function CServerBullet:DebugInfo()
	if not self.m_engineObject then 
		return tostring(self)
	end
	local x, y, z = self.m_engineObject:GetPixelPosv3()
	local gx, gy, gz = self.m_engineObject:GetGridPosv3()
	return string.format("Bullet %d %s at (%d,%d,%d) [%d,%d,%d]", self:GetTemplateId(), self:GetName(), x, y, z, gx, gy, gz)
end

function CServerBullet:CreateAOITriggers( multiEyeSight)
	if self.m_AOITriggers then
		self:RemoveAOITriggers()
	end
	
	if self:GetData("OnlyHitTarget") == 1 and self:GetData("FlowchartName") == nil or self:GetData("NoAoiHit") then
		self:SetEyeSight(0)
		self.m_DamageEyeSight = tonumber(multiEyeSight)
		if not self.m_DamageEyeSight then LogCallContext_lua() end
		return
	end
	
	if multiEyeSight then	
		local eyeSightTb = {}
		local eyeSightOne = nil
		local eyeSightCount = 0
		for eyeSight in string.gmatch(multiEyeSight, "[^;]+") do
			eyeSight = tonumber(eyeSight)
			if eyeSight > MaxEyeSight then eyeSight = MaxEyeSight end
			if eyeSight < 0 then eyeSight = 0 end
			
			if not eyeSightOne then eyeSightOne = eyeSight end
			eyeSightTb[eyeSight] = 1
			eyeSightCount = eyeSightCount + 1
		end
		
		if eyeSightCount == 0 then return end
		
		self.m_DamageEyeSight = eyeSightOne
		if not self.m_DamageEyeSight then LogCallContext_lua() end
		
		if eyeSightCount == 1 then
			self:SetEyeSight(eyeSightOne)

			local za, zb = self:GetZAboveBelow()
			-- AOI 预筛 eyeSightZ 为对称半径，非对称 HitZPair 取大值宽进，精筛仍由 IsTargetInZRange 把关
			self:SetEyeSightZ(math.max(za, zb))
		else
			self.m_AOITriggers = {}
			for eyeSight,_ in pairs(eyeSightTb) do
				if eyeSight ~= 0 then
					local trigger = CAOITrigger:new(EnumAoiTriggerType.eBullet)
					local function EnterCallBack(character,target,eyeSight)
						if not target:IsBullet() and not target:IsPhysics() then
							--LOG_PRINT(DEBUG,character.m_engineObjectId, "ISawInViewAoi", target.m_engineObjectId, eyeSight)
							if target.TryBodyAbsorbBullet and target:TryBodyAbsorbBullet(character) then
								return
							end
							character:OnFlowchartEvent("HitTarget", target)
						end
					end
					trigger:SetCallBack(self,EnterCallBack)
					trigger:Init(self, eyeSight)
					--LOG_PRINT(DEBUG,"AddTrigger",  trigger.m_engineObjectId)
					self.m_AOITriggers[eyeSight] = trigger
				end
			end
		end
	end
end



function CServerBullet:GetRreallyHitTarget(target)
	
	if not (target and self.m_XXLYAttachMentId) then
		return target 
	end 

	local ret = CServerCharacter.GetRreallyHitTarget(target,self.m_XXLYAttachMentId,self:BulletGetOwner())
	return ret 
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetData")
function CServerBulletShare:GetData(name)
	local bullet = self.m_Bullet
	local bulletMoveData = bullet and bullet.m_BulletMoveData
	local BulletDataId = bulletMoveData and bulletMoveData.m_BulletDataId
	if not BulletDataId then return end

    if bullet.m_UgcBulletData and IdIsUGCBulletCls(BulletDataId) then
        local gp = bullet:GetGameplay()
        local UgcOverrideData = gp and gp:GetBulletOverrideData(bullet, nil, name)
		if UgcOverrideData then
			return UgcOverrideData
		end
    end

	local BulletSetting = Bullet_Bullet[BulletDataId]
	local BulletSettingOverride = bullet.m_BulletResDataOverride
	
	if not name then
		return BulletSetting
	else
		return BulletSettingOverride and BulletSettingOverride[name] or BulletSetting and BulletSetting[name]
	end
end

SHARE_IMP_TO_SERVER_BULLET_ALL("SetResDataOverride")
function CServerBulletShare:SetResDataOverride(key, value)
    local bullet = self.m_Bullet
    local bulletSettingOverride = bullet.m_BulletResDataOverride
    if not bulletSettingOverride then
        bulletSettingOverride = {}
        bullet.m_BulletResDataOverride = bulletSettingOverride
    end
	bulletSettingOverride[key] = value
end

SHARE_IMP_TO_SERVER_BULLET_ALL("BeginOnSummonSkill")
function CServerBulletShare:BeginOnSummonSkill()
	local onSummonSkill = self:GetData("OnSummonSkill")
	if not onSummonSkill then return end
	
	local startTime = 0
	local isOpt = self.m_Bullet.m_IsOptBullet
	local id = isOpt and self.m_Bullet:GetUId() or self.m_Bullet.m_engineObjectId
	for s in string.gmatch(onSummonSkill, "[^;]+") do
		local waitTime, skill = string.match(s, "([%d.]+),([%d]+)")
		startTime = startTime + waitTime
			
		if startTime > 0 then
			RegisterTickWithDuration(
			function() 
				local bullet = GetBulletObjById(id, isOpt) 
				if bullet then 
					bullet:DoCastSkill(skill*100 + bullet:GetLevel()) 
				end
			end,
			startTime * 1000,
			startTime * 1000)
		elseif startTime == 0 then
			self:DoCastSkill(skill*100 + self:GetLevel()) 
		end
	end
end

-- 检查是否命中风墙，若命中风墙，则执行风墙的entercallback
function CServerBullet:HitAbsorbAOITrigger(ObjIdList, PreX, PreY)
    self.m_PreX, self.m_PreY = PreX, PreY
    for k, v in pairs(ObjIdList) do
        local t = GetCharacterByEngineObjectGlobalId(v)
        if self:IsValid() and t and (t.m_TriggerType == EnumAoiTriggerType.eAbsorbWall or t.m_TriggerType == EnumAoiTriggerType.eForceField)
            and t.m_EnterAoiCallback then
            t.m_EnterAoiCallback(t.m_CallbackCharacter, self, t.m_engineObject:GetEyeSight(), unpack(t.m_CallbackArgs))
        end
    end
    self.m_PreX, self.m_PreY = nil, nil
end

function CServerBullet:OnBulletMove(PreX, PreY, PreZ, NowX, NowY, NowZ)
	self.m_CurMoveFrame = self.m_CurMoveFrame + 1
	local NPT_bulletId = self:GetId()

	-- 不合法位置跳过
    if IsNanOrInf(NowX) or IsNanOrInf(NowY) or IsNanOrInf(NowZ) then
		return
    end

    if not self.m_UgcBulletData then
        local element = self:GetElement()
        if element then
            g_ChemistryMgr:OnBulletMove(self, NPT_bulletId, PreX, PreY, PreZ, NowX, NowY, 2 * self:GetDamageEyeSight() * 64, element, self:GetData("ElementLv"))
        end
    end

	if self.m_IsNoAoiHitQuery then
        if self.m_UgcBulletData and IdIsUGCBulletCls(self.m_SourceTemplateId) then
            if NowZ ~= NowZ then
                NowZ = PreZ
            end
            local distance = GetPixelPosDistance3(PreX, PreY, PreZ, NowX, NowY, NowZ) / 64
            if distance ~= distance then
                distance = 0.5
            end
            local dirx, diry, dirz = NormalizeVectorXYZ(NowX - PreX, NowY - PreY, NowZ - PreZ)
            if dirx ~= dirx or diry ~= diry or dirz ~= dirz then
                dirx, diry, dirz = self:GetFaceDirectionXYZ()
            end
            local directionZ, directionX, directionY = self.m_engineObject:GetDirectionDegree(), self.m_engineObject:GetDirectionDegreeX(), self.m_engineObject:GetDirectionDegreeY()
            local handler = self.m_Scene.m_CoreScene:GetPhysicsSceneHandle()
            local hitx = self.m_UgcBulletData and GetUgcBulletDataReal("MultiEyeSight", self.m_UgcBulletData[EnumUGCBulletName2PropId["MultiEyeSight"]]) or 0.5
            local hity = 0.5
            local hitz = self.m_UgcBulletData and GetUgcBulletDataReal("HitZ", self.m_UgcBulletData[EnumUGCBulletName2PropId["HitZ"]]) or 0.5
            local rx, ry, rz, rw = ConvertToPxRotation(directionY, EngineDirectionToUnityDirection(directionZ), -directionX)

            local infoLength = 10
            local targetList = {}
            local layerMask = bit.lshift(1, 5) - 1
            local infos = PhysicsManager.Inst():BoxCastNoBlock(handler, 1000,  PreX/64, PreZ/64, PreY/64, hitx, hitz, hity, dirx, dirz, diry, rx, ry, rz, rw, distance, layerMask, true)
            if #infos > 0 then
                for i = 1, #infos, infoLength do
                    local eId =infos[i+7]
                    table.insert(targetList, eId)
                end
            end
            if #targetList > 0 then
                self:HitTargetsNextFrame(targetList, PreX, PreY)
            end
            return
        end

		local angle = atan2(NowY - PreY, NowX - PreX)
		local length = ceil(sqrt((NowY - PreY)^2 + (NowX - PreX)^2) / 64)
		if g_OpenSuperProfileId then
			g_SceneQueryId = NPT_bulletId
			g_SceneQueryTime = g_App:GetFrameTime()
			g_ServerProfileMgr:AddQueryProfileCount(g_SceneQueryId)
		end

		-- 处理垂直下落的子弹
		if length == 0 then
			local width = self:GetDamageEyeSight()
			local dx = width * math.cos(angle) * pixel_per_grid
			local dy = width * math.sin(angle) * pixel_per_grid
			PreX = PreX - dx
			PreY = PreY - dy
			length = length + 2 * width
		end

		local za, zb = -1, -1
		if g_EngineZFilterEnabled then
			za, zb = self:GetZAboveBelow()  -- 栅格单位，引擎查询直接接受
		end
		local EffectedCharacterIdList = self.m_Scene.m_CoreScene:QueryObjectsWithAngleInDirectionRectanglevt(PreX, PreY,
			PreZ, angle, za, zb, 2 * self:GetDamageEyeSight(), length)
		g_SceneQueryId = 0
		self:HitTargetsNextFrame(EffectedCharacterIdList, PreX, PreY)
	end

	self:CheckGenCGScope(nil, NowX, NowY, NowZ)
end

function CServerBullet:OnBulletMoveHitTargets(ids)
	self:HitTargetsNextFrame(ids)
end

SHARE_IMP_TO_SERVER_BULLET_ALL("ClearHitInterval")
function CServerBulletShare:ClearHitInterval()
	table.clear(self.m_LastHitTimeTb)
end

function CServerBullet:IsValid()
	return self.m_IsValid and not self.m_Destroying 
end

function CServerBulletShare:GetPixelPosition()
	return self.m_Bullet:GetPixelPosition()
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetZAboveBelow")
-- 返回格子单位的 Z 上下范围（-1 表示不限制）。引擎查询的 gridZAbove/gridZBelow 直接接受该单位。
function CServerBulletShare:GetZAboveBelow()
    local za, zb = self.m_ZAbove, self.m_ZBelow
    if not za or not zb then
        local ZAboveBelow = g_BulletObjectMgr.m_BulletDesignId2ZAboveBelow[self:GetTemplateId()]
        za, zb = ZAboveBelow[1], ZAboveBelow[2]
        if self.m_Bullet.m_UgcBulletData and IdIsUGCBulletCls(self.m_Bullet.m_SourceTemplateId) then
            local hitZ = GetUgcBulletDataReal("HitZ", self.m_Bullet.m_UgcBulletData[EnumUGCBulletName2PropId["HitZ"]])
            za, zb = hitZ / 2, hitZ / 2
        end
        self.m_ZAbove, self.m_ZBelow = za, zb
    end
    return za, zb
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetZAboveBelowPixel")
-- 返回像素单位的 Z 上下范围（-1 表示不限制），供与像素坐标比较使用；缓存于 m_ZAbovePixel/m_ZBelowPixel
function CServerBulletShare:GetZAboveBelowPixel()
    local za, zb = self.m_ZAbovePixel, self.m_ZBelowPixel
    if not za or not zb then
        local gza, gzb = self:GetZAboveBelow()
        za = gza >= 0 and gza * pixel_per_grid or gza
        zb = gzb >= 0 and gzb * pixel_per_grid or gzb
        self.m_ZAbovePixel, self.m_ZBelowPixel = za, zb
    end
    return za, zb
end

SHARE_IMP_TO_SERVER_BULLET_ALL("IsTargetInZRange")
function CServerBulletShare:IsTargetInZRange(Target)
	local bulletZAbove, bulletZBelow = self:GetZAboveBelowPixel()
	if bulletZAbove == -1 and bulletZBelow == -1 then return true end
	local _, _, bulletZ = self:GetPixelPosition()
	local tarZBelow = Target.m_engineObject:GetPixelZ()
	local tarZAbove = tarZBelow + Target:GetAABBHeight()
	if bulletZAbove >= 0 and bulletZ + bulletZAbove < tarZBelow then
		return false
	elseif bulletZBelow >= 0 and bulletZ - bulletZBelow > tarZAbove then
		return false
	end

	return true
end

function CServerBullet:TryOnElement(owner, Target)
	local element = self:GetElement()
	if element and owner and g_SkillMgr:CheckValidChemiTargetType(owner, Target)  then
		Target:OnElement(owner, element, self:GetData("ElementLv"))
	end
end

function CServerBullet:HitReport(Target)
	local HitReport = self:GetData("HitReport")
	if HitReport ~= nil then
		local owner = self:BulletGetOwner()
		if Target and Target:CanFight() and owner:IsEnemy(Target) then
			if owner and owner:IsPlayerOrFake() then
				Gas2Gac:BulletHitTarget(owner.m_Conn, self.m_engineObjectId, Target.m_engineObjectId)
			end
		end
	end
end

function CServerBullet:TryBulletHitDebugDraw()
	if not SAConfig.InnerServer then 
		return 
	end

	if not g_SkillMgr.m_SkillHitDebugDrawPlayerSet or not next(g_SkillMgr.m_SkillHitDebugDrawPlayerSet) then 
		return 
	end
	
	local owner = self:BulletGetOwner()
	if not owner then 
		return 
	end
	
	if not self.m_engineObject then
		return
	end

	local bulletId = self.m_engineObjectId
	local templateId = self.m_SourceTemplateId
	local moveData = self.m_BulletMoveData
	local radius = self.m_DamageEyeSight
	
	local bulletZAbove, bulletZBelow = 0, 0
	local hitZPair = self:GetData("HitZPair")
	if hitZPair then
		bulletZAbove, bulletZBelow = hitZPair[1], hitZPair[2]
	else
		local zBias = self:GetData("HitZ")
		if zBias and zBias > 0 then
			bulletZAbove, bulletZBelow = zBias, zBias
		end
	end
	
	local conn = owner.m_Conn

	if not conn then
		conn = self:GetSyncAndSelfIS()
	end
	
	Gas2Gac:BulletMoveDebugDraw(conn, true, bulletId, templateId, moveData.m_Data_Freq.m_CurX, moveData.m_Data_Freq.m_CurY, moveData.m_Data_Freq.m_CurZ, radius, bulletZAbove, bulletZBelow)
end

function CServerBullet:TryHitPosCorrect(targetId)
	if self:IsValid() and self:GetData("IsOpenHitPosCorrect") == 1 then 
		Gas2Gac:BulletHitPosCorrect(self:GetSyncAndSelfIS(), self.m_engineObjectId, targetId)
	end
end

function CServerBulletShare:TryHitPosCorrect(...)
	return self.m_Bullet:TryHitPosCorrect(...)
end

function CServerBulletShare:Destroy(...)
	return self.m_Bullet:Destroy(...)
end

function CServerBullet:HitTarget(Target, fromClientRpc)
	if not self.m_HitEnabled then return end
	if Target.m_IsAOITrigger then
		return
	end
	if not Target.m_IsValid then
		return
	end
	if Target.m_Scene ~= self.m_Scene then return end

	-- 客户端命中模式：真实玩家目标由客户端上报，服务器物理命中跳过
	-- fromClientRpc=true 时来自 Gac2Gas_BulletHit，不受此限制
	if not fromClientRpc and g_BulletClientHitEnabled and self:GetData("ClientHit") == 1 and Target:IsPlayer() then
		return
	end

	-- 内网绘制bullet的碰撞盒轨迹
	--self:TryBulletMoveDebugDraw()
	
	local skipZCheck = self.m_UgcBulletData or fromClientRpc or (g_EngineZFilterEnabled and self.m_IsNoAoiHitQuery)
	if not skipZCheck and (not self:IsTargetInZRange(Target)) then
		return
	end
	
	local owner = self:BulletGetOwner()
	self:TryOnElement(owner, Target)
	if owner and Target:CanFight() and not owner:CheckInSameSkillDivision(Target) then
		return
	end
	if not Target.m_IsValid then
		return --TryOnElement可能会导致Target失效
	end

	local targetId = Target.m_engineObjectId
	local now = g_App:GetFrameTime()
	local share = self.m_Share
	if share.m_LastHitTimeTb[targetId] and now - share.m_LastHitTimeTb[targetId] < 1000 then
		return
	end

	if Target.TryBodyAbsorbBullet and Target:TryBodyAbsorbBullet(self) then
		return
	end

	local maxPlayers = self:GetData("MaxPlayerTargets") or 0
	if not self:GetData("FlowchartName") and not self.m_HitActionFunc then
		maxPlayers = GetOptimizeMaxPlayerTargets(self.m_Scene, maxPlayers, self:GetData(), owner)
	end
	if maxPlayers > 0 and share.m_HitedPlayerCount >= maxPlayers then
		return
	end
	local maxTargets = self:GetData("Targets") or 0
	if maxTargets > 0 and share.m_HitedObjectCount >= maxTargets then
		return
	end
	if GetObjTick(self, "OnHitDestroy") then 
		return --命中后延迟销毁不再计算命中
	end
	self:OnFlowchartEvent("HitTarget", Target)
	
    if self.m_UgcBulletData and IdIsUGCBulletCls(self.m_SourceTemplateId) then
        local gp = self:GetGameplay()
        local bulletRuntime = gp and gp.m_BulletRuntime
        if bulletRuntime then
            bulletRuntime:OnHitTarget(self, Target)
        end
    end

	-- 射中反馈
	self:HitReport(Target)
	
	share.m_LastHitTimeTb[targetId] = now
	if self.m_ShareHitTimeTb then
		for _, v in pairs(self.m_ShareHitTimeTb) do
			local bullet = GetCharacterByEngineObjectGlobalId(v)
			if bullet then
				bullet.m_Share.m_LastHitTimeTb[targetId] = now
			end
		end
	end
	
	if Target.RmChasedByBullet then
		Target:RmChasedByBullet(self)
	end
	local onHitSkill = self:GetData("OnHitSkill") or 0
	local skillId = onHitSkill * 100 + self:GetLevel()
	if onHitSkill ~= 0 and (onHitSkill == -1 or (Target and Target:CanFight() and self:GetOwner()~=nil 
	and g_SkillMgr:CheckSkillValidTargetTypeForBullet(self:GetOwner(), Target, skillId))) then

		-- 执行命中action
		if self.m_HitActionFunc then
			g_ActionMgr:DoAction(self, Target, {ProfileId = self:GetTemplateId()}, self.m_HitActionFunc)
		end

		if not self.m_IsValid then
			return -- hitaction可能导致bullet自己被销毁
		end

		-- 内网绘制bullet击中目标这一刻的碰撞盒
		self:TryBulletHitDebugDraw()

		if Target:IsPlayerOrFake() then
			share.m_HitedPlayerCount = share.m_HitedPlayerCount + 1
		end
		share.m_HitedObjectCount = share.m_HitedObjectCount + 1	

		if onHitSkill ~= -1 then
			self:DoCastSkill(onHitSkill * 100 + self:GetLevel(), Target)
		end
		
		self:OnHitDestroy(targetId)
		
	end
end

SHARE_IMP_TO_SERVER_BULLET_ALL("OnHitDestroy")
function CServerBulletShare:OnHitDestroy(targetId)
	local bullet = self.m_Bullet
	if not bullet:IsValid() then return end 

	local onHitDestroy = self:GetData("OnHitDestroy")
	if onHitDestroy == 0 then
		self:TryHitPosCorrect(targetId)
		self:Destroy(targetId)
	elseif onHitDestroy > 0 then
		local isOpt = bullet.m_IsOptBullet
		local id = isOpt and bullet:GetUId() or bullet.m_engineObjectId
		RegisterObjTickWithDuration(bullet, "OnHitDestroy",
			function()
				local b = GetBulletObjById(id, isOpt) 
				if b then 
					b:TryHitPosCorrect(targetId)
					b:Destroy(targetId) 
				end
			end,
			onHitDestroy * 1000,
			onHitDestroy * 1000)
	end
end

function CServerBullet:TargetReached()
	local target = GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_TargeterEngineObjectId)
	if not target then return end

	self.m_IsTargetReached = true
	self:HitTargetNextFrame(target)
end

function CServerBullet:HitTargetsNextFrame(objIdList, PreX, PreY)
	if not (objIdList and next(objIdList)) then return end
	if GetObjTick(self, "AutoDestroy") then return end --移动停止后延迟销毁不再计算命中

	local id = self.m_engineObjectId
	RegisterTickWithDuration(function()
		local bullet = GetBulletObjById(id)
		if not bullet then return end 
		local NPT_bulletId = bullet:GetId()
		bullet:HitAbsorbAOITrigger(objIdList, PreX, PreY) -- 命中风墙需要提前判断，避免伤害先触发了
		for k, v in pairs(objIdList) do
            if id ~= v then
                local bullet = GetBulletObjById(id)
                if not bullet then return end
                local t = GetCharacterByEngineObjectGlobalId(v)
                if t then
                    bullet:HitTarget(t)
                else
                    local ugcTarget = GetUGCObjectByGlobalId(v)
                    if ugcTarget then
                        local gp = bullet:GetGameplay()
                        local bulletRuntime = gp and gp.m_BulletRuntime
                        if bulletRuntime then
                            bulletRuntime:OnHitUGCTarget(bullet, GetUGCObjectByGlobalId(v))
                        end
                    end
                end
            end
		end
	end, 1,	1)
end

function CServerBullet:HitTargetNextFrame(Target)
	if GetObjTick(self, "AutoDestroy") then return end --移动停止后延迟销毁不再计算命中

	local id = self.m_engineObjectId
	local tid = Target.m_engineObjectId

	-- 不在一个场景内提前报错 @virgilma
	if self.m_Scene ~= Target.m_Scene then LogCallContext_lua() end
	
	RegisterTickWithDuration(function()
		local bullet = GetBulletObjById(id)
		if not bullet then return end
		local t = GetCharacterByEngineObjectGlobalId(tid)
		if not t then return end

		bullet:HitTarget(t)	
	end, 1, 1)
end

function CServerBullet:ISawInViewAoi(engineId)
	local targetObj = GetCharacterByEngineObjectGlobalId(engineId)
	if not targetObj then return end
	
	if self:GetData("OnlyHitTarget") == 1 then
		return
	end
	if GetObjTick(self, "AutoDestroy") then return end --移动停止后延迟销毁不再计算命中

	self:HitTarget(targetObj)
end

function CServerBullet:GetDamageEyeSight()
	return self.m_DamageEyeSight or 0
end

function CServerBullet:RemoveAOITriggers()
	local triggers = self.m_AOITriggers
	if not triggers then return end
	self.m_AOITriggers = nil
	for k,trigger in pairs(triggers) do
		trigger:Destroy()
	end
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetId")
function CServerBulletShare:GetId()
	local bulletData = self.m_Bullet.m_BulletMoveData
	return bulletData and bulletData.m_BulletDataId
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetTemplateId")
function CServerBulletShare:GetTemplateId()
	return self:GetId()
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetLevel")
function CServerBulletShare:GetLevel()
	return self.m_Bullet.m_Level or 1
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetBulletId")
function CServerBulletShare:GetBulletId()
	return self:GetId() * 100 + self:GetLevel()
end

SHARE_IMP_TO_SERVER_BULLET_ALL("AutoDestroy")
function CServerBulletShare:AutoDestroy()
	local bullet = self.m_Bullet
	local destroyTime = bullet.m_AutoDestroyTime
	if destroyTime == -1 then return end

	local isOpt = bullet.m_IsOptBullet	
	if destroyTime == 0 then
		-- 普通子弹由于TargetReached和移动停止时在同一帧且TargetReached会早于移动停止销毁，因此这里需要同步延迟1帧
		if not isOpt and bullet.m_IsTargetReached then
			destroyTime = 0.001
		else
			bullet:Destroy()
			return
		end
	end
	
	local id = isOpt and bullet:GetUId() or bullet.m_engineObjectId
	RegisterObjTickWithDuration(bullet, "AutoDestroy",
		function() 
			local bullet = GetBulletObjById(id, isOpt) 
			if bullet then 
				bullet:Destroy() 
			end
		end,
		destroyTime * 1000,
		destroyTime * 1000)
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetOwner")
function CServerBulletShare:GetOwner()
	local bullet = self.m_Bullet
	return bullet.m_OwnerId and GetCharacterByEngineObjectGlobalId(bullet.m_OwnerId)
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetRealOwner")
function CServerBulletShare:GetRealOwner()
	local bullet = self.m_Bullet
	return bullet.m_OwnerId and GetCharacterByEngineObjectGlobalId(bullet.m_OwnerId)
end

function CServerBullet:EnterClientHitZombieState(TargetId)
	self.m_ClientHitZombie = true
	self:SetVisible(false)  -- 通知客户端隐藏子弹，服务器仍存活等待迟到的命中 RPC
	local id = self.m_engineObjectId
	RegisterObjTickWithDuration(self, "ClientHitZombieDestroy",
		function()
			local b = GetBulletObjById(id)
			if b then b:Destroy(TargetId) end
		end,
		s_ClientHitZombieTtlMs,
		s_ClientHitZombieTtlMs)
end

function CServerBullet:Destroy(TargetId)
	if self.m_Destroying then
		return
	end

	-- ClientHit 子弹：进入僵尸等待期，延迟实际销毁以处理迟到的命中 RPC
	if g_BulletClientHitEnabled and not self.m_ClientHitZombie and self:GetData("ClientHit") == 1 then
		self:EnterClientHitZombieState(TargetId)
		return
	end

	self.m_Destroying = true
	CServerBullet._Destroy(self, TargetId)
end

function CServerBullet:SafeCall_Destroy(TargetId)
	if TargetId and self:GetData("HitRemain") then
		Gas2Gac:BulletDestroyRemain(self:GetSyncAndSelfIS(), self.m_engineObjectId, TargetId, self.m_engineObject:GetDirectionDegree(), self.m_engineObject:GetDirectionDegreeX())
	end

	if self.m_BeforDestroyActionFunc then
		g_ActionMgr:DoAction(self, GetCharacterByEngineObjectGlobalId(TargetId), {ProfileId = self:GetTemplateId()}, self.m_BeforDestroyActionFunc)
	end
	
	local target = self:GetTargetObject()
    if target and target.RmChasedByBullet then
        target:RmChasedByBullet(self)
    end
	
	local owner = self:GetOwner()
	if owner then
		local OwnerBullets = owner.m_MyBullets
		OwnerBullets[self.m_engineObjectId] = nil
	end
	
	if self.m_MyHelpAOITrigger then
		self.m_MyHelpAOITrigger:Destroy()
		self.m_MyHelpAOITrigger = nil
	end
	
	self:RemoveAOITriggers()
	UnRegisterObjTickAll(self)
end

function CServerBullet:_Destroy(TargetId)
	SAFE_CALL(CServerBullet.SafeCall_Destroy, self, TargetId)
	
	CServerCharacter._Destroy(self)
end

function CServerBullet:CreateHelpLineAOITrigger(eyesight, length)
	local selfPosX, selfPosY = self.m_engineObject:GetPixelPosv()
	
	if length == 0 then return end
	
	self.m_engineObject:SetEyeSight(0)
	
	if self.m_MyHelpAOITrigger then
		self.m_MyHelpAOITrigger:Destroy()
	end
	
	self.m_MyHelpAOITrigger = CAOITriggerGroup:new(EnumAoiTriggerType.HelpLine)
	self.m_MyHelpAOITrigger:SetOwner(self)
	
	local step = 0
	
	if length % 2 == 0 then
		step = -0.5 * EnumGlobalConstants.PIXEL_PER_GRID
	else
		self.m_MyHelpAOITrigger:AddAOITrigger(eyesight, {x = 0,y = 0})
	end
	
	local count = math.floor(length / 2)
	for i = 1, count do
		local _step = EnumGlobalConstants.PIXEL_PER_GRID *  i + step
		
		self.m_MyHelpAOITrigger:AddAOITrigger(eyesight, {x = _step,y = 0})
		self.m_MyHelpAOITrigger:AddAOITrigger(eyesight, {x = -_step,y = 0})
	end

	self:TryHelpLineAOITriggerDraw(length, eyesight)
end

function CServerBullet:TryHelpLineAOITriggerDraw(length, eyesight)
	if not SAConfig.InnerServer then
		return
	end

	if not g_SkillMgr.m_SkillHitDebugDrawPlayerSet or not next(g_SkillMgr.m_SkillHitDebugDrawPlayerSet) then
		return
	end
	
	local x, y, z = self.m_engineObject:GetPixelPosv3()
	local bulletId = self.m_engineObjectId
	local templateId = self.m_SourceTemplateId
	local owner = self:BulletGetOwner()
	local ownerEngineId = owner and owner.m_engineObjectId
	local conn = owner and owner.m_Conn

	Gas2Gac:TryBulletAoiTriggerDraw(conn, ownerEngineId, bulletId, templateId, x, y, z, eyesight, length)
end

function CServerBullet:CreateCircleAOITrigger(radius)
	if radius == 0 then return end
	self.m_engineObject:SetEyeSight(0)
	if self.m_MyHelpAOITrigger then
		self.m_MyHelpAOITrigger:Destroy()
	end	
	self.m_MyHelpAOITrigger = CAOITriggerGroup:new(EnumAoiTriggerType.Circle)
	self.m_MyHelpAOITrigger:SetOwner(self)
	self.m_MyHelpAOITrigger:AddAOITrigger(radius, {x = 0,y = 0})
end

function CServerBullet:DoAbsorbedAction(absorbFormulaId, wallOwnerId)
	if not absorbFormulaId then return end 
	local func = GetFormulaFunc('Formula', absorbFormulaId, 'Formula')
	if not func then return end
	local wallowner = EID2OBJ(wallOwnerId)
	if not wallowner then return end

	func(wallowner, self)
end

function CServerBullet:AbsorbedByWall(dieTime, wallOwnerId, absorbFormulaId)
	if dieTime == 0 then
		self:DoAbsorbedAction(absorbFormulaId, wallOwnerId)
		self:UpdateProperty("m_AbsorbedBy", {EnumBulletAbosrbedBy.eWall, wallOwnerId})
		self:Destroy()
		return
	end
	
	if GetObjTick(self, "AbsorbedByWall") then return end
	-- 这里算一下被墙吸收的子弹
	local wallowner = GetCharacterByEngineObjectGlobalId(wallOwnerId)
	if wallowner and IsClassObject(wallowner, CServerFightableCharacter) then
		wallowner.m_WallAbsorbCnt = (wallowner.m_WallAbsorbCnt or 0) + 1
	end

	self:DisableCastSkill()
	
	local id = self.m_engineObjectId
	RegisterObjTickWithDuration(self, "AbsorbedByWall",
		function()
			local bullet = GetCharacterByEngineObjectGlobalId(id)
			if not bullet then return end
			bullet:DoAbsorbedAction(absorbFormulaId, wallOwnerId)
			bullet:UpdateProperty("m_AbsorbedBy", {EnumBulletAbosrbedBy.eWall, wallOwnerId})
			bullet:Destroy()
		end,
		dieTime * 1000,
		dieTime * 1000
	)

end

function CServerBullet:DisableCastSkill()
	self.m_SkillEnabled = false
end

function CServerBullet:SetExtraBuff(BuffId)
	self.m_ExtraAddBuff = BuffId
end

---@class CServerBullet
---@field BulletGetOwner func
SHARE_IMP_TO_SERVER_BULLET_ALL("BulletGetOwner")
function CServerBulletShare:BulletGetOwner()
	local owner = self:GetOwner()
	while owner and owner:IsBullet() do
		owner = owner:GetOwner()
	end
	
	return owner
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetHitNumHurtDecay")
function CServerBulletShare:GetHitNumHurtDecay(owner, TargetObj)
	if not TargetObj then return end 
	local mixHurtTargets = self:GetData("MixHurtTargets")
	local hitNumHurtDecay = 1
	if mixHurtTargets then
		local decay2Target = g_SkillMgr:CalcHitNumHurtDecay(self.m_HitedObjectCount, mixHurtTargets, owner)
		if decay2Target < 1 then
			hitNumHurtDecay = self:GetData("HitNumHurtDecay")
		end
	end
	return hitNumHurtDecay
end

SHARE_IMP_TO_SERVER_BULLET_ALL("DoCastSkillByOwner")
function CServerBulletShare:DoCastSkillByOwner(SkillId,TargetObj,X,Y,Z,Delay,SourceId)
	local bullet = self.m_Bullet
	if not bullet.m_SkillEnabled then return end
	if not SkillId then return end
	local owner = self:BulletGetOwner()
	if not ( owner and owner.m_engineObject) then return end

	owner:DoCastSkill(SkillId,TargetObj,X,Y,Z,Delay,SourceId, bullet.m_TimesHurtMul, bullet.m_TimesHurtAdj)
end

SHARE_IMP_TO_SERVER_BULLET_ALL("DoCastSkill")
function CServerBulletShare:DoCastSkill(SkillId,TargetObj,X,Y,Z)
	local bullet = self.m_Bullet
	if not bullet.m_SkillEnabled then return end
	if not SkillId then return end
	--LOG_PRINT(DEBUG,"CServerBullet:DoCastSkill", SkillId, TargetObj and TargetObj.m_engineObjectId, X,Y,Z)
	local owner = self:BulletGetOwner()
	if not ( owner and owner.m_engineObject) then return end
	
	if not (X and Y and Z) then
		X,Y,Z = bullet:GetPixelPosition()
	end
	
	local hitNumHurtDecay = self:GetHitNumHurtDecay(owner, TargetObj)

	local isOpt = bullet.m_IsOptBullet
	local attackerId = not isOpt and bullet.m_engineObjectId
	local cls, lv = GetSkillClsLv(SkillId)
	local SkillContext = {
		SkillId = SkillId,
		Cls = cls,
		Lv = lv,
		TargetId = TargetObj and TargetObj.m_engineObjectId,
		DestPosX = X,
		DestPosY = Y,
		DestPosZ = Z,
		HurtDefendersCount = 0,
		KillDefendersCount = 0,
		AttackerId = attackerId,
		ExtraAddBuff = bullet.m_ExtraAddBuff,
		TimesHurtMul = bullet.m_TimesHurtMul,
		TimesHurtAdj = bullet.m_TimesHurtAdj,
		HitNumHurtDecay = hitNumHurtDecay,
		IsFromBullet = true,
		ClientHitResult = bullet.m_PendingClientHitResult,
		BulletPosX = X,
		BulletPosY = Y,
		BulletPosZ = Z,
	}

	g_SkillMgr:UseSkillAction(owner, SkillContext)
end

function CServerBullet:ModifySpeed(fSpeed)
	if not self:GetData("NoAoiHit") then
		fSpeed = math.min(fSpeed, MAX_BULLET_AOI_HIT_SPEED)
	end
	
	self:UpdateProperty("m_BulletSpeed", fSpeed)
end

function CServerBullet:SetEyeSight(sight)
	if self.m_engineObject then
		self.m_engineObject:SetEyeSight(sight)
	end
end

function CServerBullet:IntZSpeed(zSpeed, fSpeedRatio)
	if not self.m_engineObject or not zSpeed then return end
	
	if self.m_engineObject:IsMoving() then
		self:EnginStopMoving()
	end
	
	local fSpeed = self:GetBulletMoveSpeed()
	local dir = self.m_engineObject:GetDirectionDegree() /180 * math.pi
	if not fSpeed or not dir then return end
	
	fSpeedRatio = fSpeedRatio or 1
	fSpeed = fSpeed * fSpeedRatio
	
	self.m_engineObject:IntSpeedVector(fSpeed*math.cos(dir),fSpeed*math.sin(dir),zSpeed * EnumGlobalConstants.PIXEL_PER_GRID)
end

function CServerBullet:SetOwner(character)
	if character and not IsClassObject(character, CServerFightableCharacter) then return end
	local oldOwner = self:GetOwner()
	self.m_OwnerId = character and character.m_engineObjectId
	MsgHub_CharacterSetOwner:Emit(self)

	if oldOwner and self.m_engineObjectId then
	     oldOwner.m_MyBullets[self.m_engineObjectId] = nil
	end
	if character and self.m_engineObjectId then
		character:AddBullet(self.m_engineObjectId)
	end

	if character then
		self.m_OwnerCharacterType = character.m_CharacterType
		self.m_OwnerTemplateId = character:GetTemplateId()
		if (self.m_OwnerTemplateId or 0) == 0 then
			local basicProp = character:BasicProp()
			if basicProp and basicProp.GetId then
				self.m_OwnerTemplateId = basicProp:GetId()
			end
		end
	end
end

function CServerBullet:GetTargetObject()
	return GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_TargeterEngineObjectId)
end

function CServerBullet:GetZDirection()
	return XYDirToDegreeDir(self.m_BulletMoveData.m_BulletSpeed, self.m_BulletMoveData.m_VectorZ)
end

function CServerBullet:GetFaceDirectionXYZ()
	local yaw, pitch = self.m_engineObject:GetDirectionDegree(), self.m_engineObject:GetDirectionDegreeX()
	yaw, pitch = rad(yaw), rad(pitch)
	return cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), -sin(pitch)
end

local function IsBulletPropertyValueLuaObject(value)
	return type(value) == "table" and rawget(value, "__class") ~= nil
end

function CServerBullet:UpdateProperty(key, value)
	if IsBulletPropertyValueLuaObject(value) then
		LogCallContext_lua()
		return
	end

	local BulletData = self.m_BulletMoveData
	local old = BulletData[key]
	if old == value then return end

	BulletData[key] = value

	table.clear(TEMP_TABLE)

	local newKey = GetBulletPropertyIdByName(key) or key
	TEMP_TABLE[newKey] = value
	Gas2Gac:UpdateBulletProperty(self:GetSyncAndSelfIS(), self.m_engineObjectId, msgpack.pack(TEMP_TABLE))
	table.clear(TEMP_TABLE)
end

function CServerBullet:UpdateProperties(newData)
	local BulletData = self.m_BulletMoveData
	for k, v in pairs(newData) do
		if IsBulletPropertyValueLuaObject(v) then
			LogCallContext_lua()
			return
		end
		BulletData[k] = v
	end

	table.clear(TEMP_TABLE)
	for k, v in pairs(newData) do
		local newKey = GetBulletPropertyIdByName(k) or k
		TEMP_TABLE[newKey] = v
	end

	Gas2Gac:UpdateBulletProperty(self:GetSyncAndSelfIS(), self.m_engineObjectId, msgpack.pack(TEMP_TABLE))
	table.clear(TEMP_TABLE)
end

--参数格式: key, val, key, val, key, val
function CServerBullet:UpdatePropertiesEx(...)
	table.clear(TEMP_TABLE)
	local BulletData = self.m_BulletMoveData
	local num = select("#", ...)
	assert(num % 2 == 0)
	for i = 1, num, 2 do
		local k = select(i, ...)
		local v = select(i + 1, ...)
		if v then 
			if IsBulletPropertyValueLuaObject(v) then
				LogCallContext_lua()
				return
			end
			local newKey = GetBulletPropertyIdByName(k) or k
			BulletData[k] = v
			TEMP_TABLE[newKey] = v
		end
	end
	Gas2Gac:UpdateBulletProperty(self:GetSyncAndSelfIS(), self.m_engineObjectId, msgpack.pack(TEMP_TABLE))
	table.clear(TEMP_TABLE)
end

function CServerBullet:MarkBulletForeverMove(flag)
	if flag then
		self.m_BulletForeverMove = true
	else
		self.m_BulletForeverMove = nil
	end
end

function CServerBullet:StartDirTrackTarget(engineObjectId)
	self:UpdateProperty("m_DirTrackTargetId", engineObjectId)
end

function CServerBullet:StopDirTrackTarget()
	self:UpdateProperty("m_DirTrackTargetId", 0)
end

function CServerBullet:UpdateDirZDegree(dirzdegree)
	local dirz = math.sin(math.rad(dirzdegree))
	self:UpdateDirZ(dirz)
end

function CServerBullet:UpdateDirZ(dirz)
	self:UpdateProperty("m_DirZ", dirz)
end

function CServerBullet:ModifyDirection(dir)
	local bulletType = self.m_BulletMoveData.m_Trajectory
	if bulletType ~= EnumBulletTracjectory.Direction then --目前只支持Direction子弹
		return
	end
	dir = DegreeToRadian(dir)
	local BulletData = self.m_BulletMoveData
	BulletData.m_MoveVectorX = math.cos(dir) 
	BulletData.m_MoveVectorY = math.sin(dir) 
	BulletData.m_MoveVectorZ = 0

	table.clear(TEMP_TABLE)
	TEMP_TABLE["m_MoveVectorX"] = BulletData.m_MoveVectorX
	TEMP_TABLE["m_MoveVectorY"] = BulletData.m_MoveVectorY
	TEMP_TABLE["m_MoveVectorZ"] = BulletData.m_MoveVectorZ
	Gas2Gac:UpdateBulletProperty(self:GetSyncAndSelfIS(), self.m_engineObjectId, msgpack.pack(TEMP_TABLE))
	table.clear(TEMP_TABLE)
end

function CServerBullet:ModifyBulletRotationByDir(dir)
	local rad = DegreeToRadian(dir)
	local dirZ = self.m_BulletMoveData and self.m_BulletMoveData.m_DirZ or 0
	local dxy = sqrt(1 - dirZ * dirZ)
	self:ModifyBulletRotation(cos(rad) * dxy, sin(rad) * dxy, dirZ)
end

function CServerBullet:ModifyBulletRotation(x, y, z)
	assert(x and y and z)
	Gas2Gac:UpdateBulletRotation(self:GetSyncAndSelfIS(), self.m_engineObjectId, x, y, z)
end

function CServerBullet:ShowFx()
	Gas2Gac:BulletShowFx(self:GetSyncAndSelfIS(), self.m_engineObjectId)
end

function CServerBullet:HideFx()
	Gas2Gac:BulletHideFx(self:GetSyncAndSelfIS(), self.m_engineObjectId)
end

--p点绕着op点顺时针选择angle角度
local function _Rotate(opx, opy, px, py, angle)
	local angle = DegreeToRadian(angle)
	local nx = px - opx
	local ny = py - opy

	local ansx = nx * math.cos(-angle) - ny * math.sin(-angle)
	local ansy = ny * math.cos(-angle) + nx * math.sin(-angle)

	return ansx + opx, ansy + opy
end

function CServerBullet:ReflectByMonster(monster)
	
	local bulletType = self.m_BulletMoveData.m_Trajectory
	if bulletType ~= EnumBulletTracjectory.Direction then
		return
	end
	
	local bx, by = self.m_BulletMoveData.m_CurX, self.m_BulletMoveData.m_CurY
	local tx, ty = self.m_BulletMoveData.m_DestX, self.m_BulletMoveData.m_DestY
	local mx, my = monster.m_engineObject:GetPixelPosv()

	--子弹已经到终点，就算了
	if bx == tx and by == ty then
		return
	end

	local rotateAngle = 0
	if bx == mx and by == my then --如果直接击中怪物中心点，则直接反弹
		rotateAngle = 180
	else
		local angle1 = VectorToDirection2(bx, by, mx, my)
		local angle2 = VectorToDirection2(bx, by, tx, ty)
		local dist = (angle1 - angle2 + 360) % 360

		if dist <= 180 then
			rotateAngle = (90 - dist) * 2
		else
			rotateAngle = (360 - dist + 90) * 2
		end
	end

	local ansx, ansy = _Rotate(bx, by, tx, ty, rotateAngle)
	
	self.m_BulletMoveData.m_DestX = ansx
	self.m_BulletMoveData.m_DestY = ansy

	Gas2Gac:RefreshBulletMoveTargetPos(self:GetSyncAndSelfIS(), self.m_engineObjectId, self.m_BulletMoveData.m_DestX, self.m_BulletMoveData.m_DestY, self.m_BulletMoveData.m_DestZ)
end

function CServerBullet:StartBaFangJue(TargetPos, SideSpeed, SideAngle)
	--LOG_PRINT(DEBUG,"StartBaFangJue", SideSpeed, SideAngle)
	
	if not TargetPos or not SideSpeed then return end
	
	BulletTrajectoryImp:SetBulletMoveTrajectory(self, "BaFangJue")
	
	local BulletData = self.m_BulletMoveData
	
	local tx, ty, tz = TargetPos.x, TargetPos.y, TargetPos.z
	local bx, by, bz = self.m_engineObject:GetPixelPosv3()
	
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = bx, by, bz
	
	if math.abs(SideAngle) == 90 then
		local t = Dist_XYZ2(bx, by, bz, tx, ty, tz) / self:GetBulletMoveSpeed() / 2
		BulletData.m_SideA1 = SideSpeed  / t
		BulletData.m_SideA2 = SideSpeed / t 
		BulletData.m_SideSpeed = SideSpeed
		BulletData.m_SideSpeedDir = DegreeToRadian(VectorToDirection2(bx, by, tx, ty) + SideAngle)
	end
	
	BulletData.m_TargetPos = TargetPos

	self:RefreshBulletMoveData()
	self:StartLuaMove()
end

local BulletFindChaseTarget_ChooseCri = function(dist, angle, maxScore)	--用来评判选怪攻击的评分函数
	local score = 1 / ( dist + angle / 15)
	if maxScore and score < 1 / maxScore then return -1 end
	return score
end

function CServerBullet:BulletFindChaseTarget( Radius,func,ChooseMaxScore)--格子半径
	--LOG_PRINT(DEBUG,"BulletFindChaseTarget", Radius,func,ChooseMaxScore)
	
	local owner = self:GetOwner()
	if not owner then return end
	local Scene = self.m_Scene.m_CoreScene
	local selfX, selfY, selfZ = self.m_engineObject:GetPixelPosv3()
	local Targets = Scene:QueryObjectsWithAngleInFanvt(selfX, selfY, selfZ,
		DegreeToRadian(self.m_engineObject:GetDirectionDegree()), Radius, DegreeToRadian(90), 5, 5)
	
	if #Targets == 0 then return end

	
	local selfGridX, selfGridY, selfGridZ = GetGridByPixel2(selfX, selfY, selfZ)
	local ChooseCri = func or BulletFindChaseTarget_ChooseCri
	
	local ansTarget
	local ansScore = -1
	
	for i = 1, #Targets do
		local Target = GetCharacterByEngineObjectGlobalId(Targets[i])
		if Target and Target:IsAlive() and self:IsEnemy(Target) and not owner:IsInvisbleObject(Target) then
			local tx, ty, tz = Target.m_engineObject:GetPixelPosv3()
			local tgx, tgy, tgz = GetGridByPixel2(tx, ty, tz)
			
			local Dist = Dist_XYZ2(selfGridX, selfGridY, selfGridZ, tgx, tgy, tgz)
			local Angle = VectorToDirection2(selfX, selfY, tx, ty)
			local DiffAngle = math.abs(Angle - self.m_engineObject:GetDirectionDegree())
			DiffAngle = DiffAngle % 360
			if DiffAngle > 180 then
				DiffAngle = 360 - DiffAngle
			end
			local Score = ChooseCri(Dist, DiffAngle, ChooseMaxScore)
			if Score > ansScore then
				ansTarget = Target.m_engineObjectId
				ansScore = Score
			end
		end
	end
	return ansTarget
end

function ServerActionImp.SetTornadoData(Attacker, Defender, SourceInfo, ActionContext, args)
	
end

function ServerActionImp.SetWindWallData(Attacker, Defender, SourceInfo, ActionContext, args)
	
end

function CServerBullet:IsEnemy(Target)
	local o = GetRealOwner(self)
	if not IsClassObject(o,CServerFightableCharacter) then  return false end
	return o and o:IsEnemy(Target)
end

function CServerBullet:IsFriend(Target)
	local o = GetRealOwner(self)
	if not IsClassObject(o,CServerFightableCharacter) then  return false end
	return o and o:IsFriend(Target)
end

function CServerBullet:ReplayBulletFX(fLocalTime)
	Gas2Gac:ReplayBulletFX(self:GetSyncAndSelfIS(), self.m_engineObjectId, fLocalTime)
end

function CServerBullet:FlowchartCalcReflect()
    local t = self.m_State:GetV("WallIds")
    t = t or {  }
    local x2, y2 = self:GetPixelPosition()
    local dir2 = self.m_BulletMoveData.m_MoveDir
    if not dir2 then
        return 
    end

    local nearest_dist, nearest_id = 256, nil
    for id, _ in pairs(t) do
        local wall = GetObjectByGlobalId(id)
        if wall then
            local x1, y1 = wall:GetPixelPosition()
            local dir1 = wall.m_State:GetV("Dir")
            local l1, l2 = RayIntercept2D(x1, y1, dir1, x2, y2, dir2)
            if l2 > 0 and l2 < nearest_dist and math.abs(l1) < wall.m_State:GetV("HalfLen") then
                nearest_dist = l2
                nearest_id = id
            end

        else
            t[id] = nil
        end

    end
    if nearest_id then
        self.m_State:SetV("WallRefId", nearest_id)
        self.m_State:SetV("AboutToRef", true)
    end
	return math.max(nearest_dist / self.m_BulletMoveData.m_BulletSpeed - 0.02, 0)
end

--移植bullet ai中的羽碎弹弹弹ai(包括168，169,303,305)
function CServerBullet:YuSuiTanTanTan(ret, hitted)
	local nJumpLeft = self.m_State:GetV("nJumpLeft") - 1
	if nJumpLeft <= 0 then
		self:Destroy()
		return 
	else
		self.m_State:SetV("nJumpLeft", nJumpLeft)
	end
	local owner = self:BulletGetOwner()
	local chars, nohit, nobuff = {  }, {  }, {  }
	for v, _ in pairs(ret) do
		if not g_SkillMgr:IsImmunity(v, "m") then
			table.insert(chars, v)
			if not hitted[v:GetEngineObjectGlobalId()] then
				table.insert(nohit, v)
			end

			if v:HaveBuffsFromObj(owner, 641639) == 0 then
				table.insert(nobuff, v)
			end
		end
	end

	if #nobuff > 0 then
		local nextTar = listrand(unpack(nobuff))
		local x, y, z = nextTar:GetPixelPosition()
		self:StartChaseTarget(nextTar, nil, 64)
		--self:ReplayBulletFX(0.5)
	elseif #nohit > 0 then
		local nextTar = listrand(unpack(nohit))
		local x, y, z = nextTar:GetPixelPosition()
		self:StartChaseTarget(nextTar, nil, 64)
		--self:ReplayBulletFX(0.5)
	elseif #chars > 0 then
		local nextTar = listrand(unpack(chars))
		local x, y, z = nextTar:GetPixelPosition()
		self:StartChaseTarget(nextTar, nil, 64)
		--self:ReplayBulletFX(0.5)
	else
		self:Destroy()
	end
end

function CServerBullet:FlowchartOnTargetReachedYuSui1(querySkillCls1, hitSkillCls2)	
	local owner = self:BulletGetOwner()
	if not owner then return end
	local cls1 = IdIsSkillCls(querySkillCls1) and querySkillCls1 or 915143
	local cls2 = IdIsSkillCls(hitSkillCls2) and hitSkillCls2 or 931070
	local ret, extraData = g_SkillMgr:QuerySkillEffectedCharacters(owner, nil,  cls1 * 100 + self:GetLevel(), self:GetPixelPosition())
	local tar = GetObjectByGlobalId(self.m_BulletMoveData.m_TargeterEngineObjectId)
	local last = GetObjectByGlobalId(self.m_State:GetV("LastTar"))
	local hitted = self.m_State:GetV("Hitted")
	local hitNum = self.m_State:GetV("HitPlayerNum")
	self.m_State:SetV("LastTar", self.m_BulletMoveData.m_TargeterEngineObjectId)
	if tar then
		self:DoCastSkill(cls2 * 100 + self:GetLevel(), tar)
		if not self:IsValid() then 
			g_LuaPoolMgr:ReleaseTable(ret)
			g_LuaPoolMgr:ReleaseTable(extraData)
			return
		end
		ret[tar] = nil
		if not hitted[self.m_BulletMoveData.m_TargeterEngineObjectId] then
			if tar:IsPlayerOrFake() then
				self.m_State:SetV("HitPlayerNum", hitNum + 1)
			end
		end

		hitted[self.m_BulletMoveData.m_TargeterEngineObjectId] = true
	end
	self:YuSuiTanTanTan(ret, hitted)

	g_LuaPoolMgr:ReleaseTable(ret)
	g_LuaPoolMgr:ReleaseTable(extraData)
end

function CServerBullet:FlowchartOnTargetReachedYuSui2()
	local owner = self:BulletGetOwner()
	if not owner then return end
	local ret, extraData = g_SkillMgr:QuerySkillEffectedCharacters(owner, nil, 915965 * 100 + self:GetLevel(), self:GetPixelPosition())
	local tar = GetObjectByGlobalId(self.m_BulletMoveData.m_TargeterEngineObjectId)
	local last = GetObjectByGlobalId(self.m_State:GetV("LastTar"))
	local hitted = self.m_State:GetV("Hitted")
	self.m_State:SetV("LastTar", self.m_BulletMoveData.m_TargeterEngineObjectId)
	if tar then
		self:DoCastSkill(931236 * 100 + self:GetLevel(), tar)
		if not self:IsValid() then 
			g_LuaPoolMgr:ReleaseTable(ret)
			g_LuaPoolMgr:ReleaseTable(extraData)
			return
		end
		ret[tar] = nil
		hitted[self.m_BulletMoveData.m_TargeterEngineObjectId] = true
	end
	self:YuSuiTanTanTan(ret, hitted)

	g_LuaPoolMgr:ReleaseTable(ret)
	g_LuaPoolMgr:ReleaseTable(extraData)
end

--移植bullet ai中的羽碎弹弹弹ai(包括168，169,303,305) end

function CServerBullet:BindExistEffect(PlayerID, FxLogicName, BindEffectBullet)
	if PlayerID and FxLogicName then 
		Gas2Gac:BindExistEffect(self:GetSyncAndSelfIS(), self.m_engineObjectId, PlayerID, FxLogicName, BindEffectBullet or false)
	end
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetHitedObjectCount")
function CServerBulletShare:GetHitedObjectCount()
	return self.m_HitedObjectCount or 0, self.m_HitedPlayerCount or 0
end

SHARE_IMP_TO_SERVER_BULLET_ALL("SetEffectScale")
function CServerBulletShare:SetEffectScale(scaleX, scaleY, scaleZ)
	local bullet = self.m_Bullet

	-- get logic id
	local isOpt = bullet.m_IsOptBullet
	local id = isOpt and bullet:GetUId() or bullet.m_engineObjectId
	local is = bullet:GetSyncAndSelfIS()
	if not is then return end

	-- set effect scale
	scaleY = scaleY or scaleX
	scaleZ = scaleZ or scaleX
	Gas2Gac:BulletSetEffectScale(bullet:GetSyncAndSelfIS(), id, scaleX, scaleY, scaleZ)
end

function CServerBullet:RemoveAllEffects(IgnoreLoop)
	Gas2Gac:BulletRemoveAllEffects(self:GetSyncAndSelfIS(), self.m_engineObjectId, IgnoreLoop)
end

function CServerBullet:GenCGScope(calcFrameCnt, fakeEyeSight)
	local owner = self:BulletGetOwner()
	if not (owner and owner:IsCGScopeOpened()) then return end
	calcFrameCnt = calcFrameCnt or 5
	fakeEyeSight = fakeEyeSight or 0
	local x, y, z = self:GetPixelPosition()
	self.m_GenCGScope = {frame = calcFrameCnt, lastX = x, lastY = y, lastZ = z, eyeSight = fakeEyeSight}
end

function CServerBullet:CheckGenCGScope(force, x, y, z)
	if not self.m_GenCGScope then return end
	if (self.m_CurMoveFrame % self.m_GenCGScope.frame) ~= 0 and not force then return end 
	local owner = self:BulletGetOwner()
	if not (owner and owner:IsCGScopeOpened()) then return end

	local tbl = self.m_GenCGScope
	local angle = math.atan2(y - tbl.lastY, x - tbl.lastX)
	local length = math.ceil(math.sqrt((y - tbl.lastY)^2 + (x - tbl.lastX)^2) / 64)
	local width = tbl.eyeSight > 0 and (2 * tbl.eyeSight) or 1
	local gridList = self.m_Scene.m_CoreScene:QueryGridsWithAngleInDirectionRectanglevt(tbl.lastX, tbl.lastY, tbl.lastZ, angle, -1, -1, width, length)
	owner:AddBulletScope(gridList, z)

	tbl.lastX, tbl.lastY, tbl.lastZ = x, y, z
end

function CServerBullet:GetHitRotationZ(force, x, y, z)
	local px, py, pz = self:GetPixelPosition()
	if not px or not py or not pz then
		return 0
	end
	local minZ, maxZ
	local gridX, gridY, gridZ = GetGridByPixel2(px, py, pz)
	for x = -1, 1 do
		for y = -1, 1 do
			gridZ = self.m_Scene.m_CoreScene:GetNearestStandGridPixelZByPixel(px + x * EnumGlobalConstants.PIXEL_PER_GRID, py + y * EnumGlobalConstants.PIXEL_PER_GRID, pz)
			if not minZ then
				minZ = gridZ
			else
				minZ = math.min(minZ, gridZ)
			end
			if not maxZ then
				maxZ = gridZ
			else
				maxZ = math.max(maxZ, gridZ)
			end
		end
	end
	if not minZ or not maxZ then
		return 0
	end
	return 90 * math.min((maxZ - minZ), 3 * EnumGlobalConstants.PIXEL_PER_GRID) / (3 * EnumGlobalConstants.PIXEL_PER_GRID)
end

--region 击中客户端NPC

Gac2GasDefine["BulletHitClientNpc"] =
{
	Desc = "子弹击中客户端NPC",
	Category = "子弹",
	Committer = "pizhanhe",
	Args =
	{
		{Name = "bulletEngineId", Comment= "子弹引擎Id"},
		{Name = "extraUD", Comment= "额外参数"},
	}
}
function CServerPlayer:Gac2Gas_BulletHitClientNpc(bulletEngineId, extraUD)
	local extraArgs = msgpack.unpack(extraUD)
	local isOpt = extraArgs.isOpt
	local bullet = isOpt and g_BulletObjectMgr:GetOptBulletByUId(bulletEngineId) or GetBulletObjById(bulletEngineId)
	if not bullet or bullet:GetOwner() ~= self then
		return
	end
	local hitNpcIdTbl = bullet:GetData("HitClientNpc")
	if not hitNpcIdTbl then
		return
	end
	local bulletId = bullet:GetId()
	if IsLanDuWaterBullet(bulletId) then
		local exploreNpcGUID = extraArgs.exploreNpcGuid
		local npc = exploreNpcGUID and g_CharacterMgr:GetObjectByGUID(exploreNpcGUID)
		if npc and npc:IsInViewAoiOf(self) then
			if extraArgs.isStart then
				npc:FlowchartCustomEvent("OnBulletHitClientClusterStart", bulletId, bullet.m_engineObjectId, self)
			end

			npc:FlowchartCustomEvent("OnBulletHitClientCluster", bulletId, bullet.m_engineObjectId, self:GetPlayerId())
		end
	end
	if bullet:GetData("NoDestroyAfterHitClientNpc") ~= 1 then
		bullet:Destroy()
	end
end

--endregion 击中客户端NPC

--region 怪物子弹客户端命中上报

local __SERVER_BULLET_HIT_LOG_ENABLED = IsInner()
local function __LogServerBulletHit(step, bulletEngineId, player, fmt, ...)
	if not __SERVER_BULLET_HIT_LOG_ENABLED then return end
	local playerName = player and player:GetName() or "Unknown"
	local msg = string.format("[ServerBulletHit-%s] Bullet[%d] Player[%s]" .. (fmt and (" " .. fmt) or ""),
		step, bulletEngineId, playerName, ...)
	print(msg)
end

Gac2GasDefine["BulletHit"] =
{
	Desc = "怪物子弹客户端命中上报",
	Category = "子弹",
	Args =
	{
		{Name = "bulletEngineId", Comment= "子弹引擎Id"},
		{Name = "extraUD", Comment= "额外参数(targetId, hitX, hitY, hitZ)"},
	}
}
function CServerPlayer:Gac2Gas_BulletHit(bulletEngineId, extraUD)
	if not g_BulletClientHitEnabled then
		return
	end
	local bullet = GetBulletObjById(bulletEngineId) or g_BulletObjectMgr:GetOptBulletByUId(bulletEngineId)
	if not bullet then
		return
	end
	if bullet:GetData("ClientHit") ~= 1 then
		return
	end
	local extraArgs = msgpack.unpack(extraUD)
	if not extraArgs then
		return
	end
	local targetId = extraArgs.targetId
	local target = GetCharacterByEngineObjectGlobalId(targetId)
	if not target or not target:IsAlive() then
		return
	end
	if not target:IsPlayer() then
		return -- 只允许对真实玩家的命中
	end
	__LogServerBulletHit("Recv", bulletEngineId, self, "Target[%d]", targetId)
	-- CD 校验：与服务器 m_LastHitTimeTb 一致，提前拦截重复 RPC
	local share = bullet.m_Share
	if share then
		local now = g_App:GetFrameTime()
		if share.m_LastHitTimeTb[targetId] and now - share.m_LastHitTimeTb[targetId] < 1000 then
			return
		end
	end
	if not bullet.m_engineObject or not target.m_engineObject then
		return
	end
	__LogServerBulletHit("Apply", bulletEngineId, self, "Target[%d]", targetId)
	bullet.m_PendingClientHitResult = extraArgs.ClientHitResult
	bullet:HitTarget(target, true)  -- fromClientRpc=true，绕过服务器物理命中的跳过检查
	bullet.m_PendingClientHitResult = nil
end

--endregion 怪物子弹客户端命中上报

function CServerBullet:SetVisible(bVisible)
	self:UpdateProperty("m_IsInvisible", not bVisible)
end

function CServerBullet:SetReplaceClassByCharacterDef(ClassNameToCharacterDef)
	self:UpdateProperty("m_ReplaceClassByCharacterDef", ClassNameToCharacterDef)
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetTimeScale")
function CServerBulletShare:GetTimeScale()
	return self.m_Bullet.m_BulletMoveData.m_TimeScale or 1
end

SHARE_IMP_TO_SERVER_BULLET_ALL("GetTimeScaleRev")
function CServerBulletShare:GetTimeScaleRev()
	local scale = self.m_Bullet.m_BulletMoveData.m_TimeScale
	return scale and 1 / scale or 1
end

-- 强制同步服务器子弹位置
function CServerBullet:ForceSyncServerPosition()
	-- 由于网络原因，客户端子弹的运动停止位置与服务器的停止位置很可能不一样。但是为了客户端不突变与既有配置的稳定，又不能直接修改
	-- CRpc_Gas2GacOC_Stop_Follower_Lua的handler。因此给一个接口手动同步服务器位置给客户端，供策划调用。

	-- 当前的实现方式比较丑陋，由于直接设置位置没有变化不会同步，因此需要轻微变化位置来同步，后续有需求可以完善成更合理的方案。

    local x, y, z = self.m_engineObject:GetPixelPosv3()
    self.m_engineObject:SetPixelPosv3(x + 1, y, z)
    self.m_engineObject:SetPixelPosv3(x, y, z)
end
