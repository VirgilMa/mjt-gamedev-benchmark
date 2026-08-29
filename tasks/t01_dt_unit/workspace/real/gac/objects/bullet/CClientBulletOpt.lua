local cEffectMgr = CS.Pangu.AppFacade.cEffectMgr
local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local GameManager = CS.Pangu.AppFacade.gameManager
local Quaternion = CS.UnityEngine.Quaternion
local MaxLifeTime = 300 * 30
local OPT_BULLET_AI_LOAD_RETRY_COUNT = 3
local OPT_BULLET_AI_LOAD_RETRY_INTERVAL = 33
--==============================================================================================

function CClientBulletOpt:Ctor()
	self.m_EffectList = self.m_EffectList or {}
	self.m_BulletMoveData = self.m_BulletMoveData or CBulletMoveDataOpt:new()
end

function CClientBulletOpt:Destroy()
	if self.m_Destroying then LogCallContext_lua() return end
	self.m_Destroying = true
	-- print("CClientBulletOpt:Destroy", self, g_App:GetGlobalTime())

	CClientBulletOpt._Destroy(self)
end

function CClientBulletOpt:SafeCall_Destroy()

	-- 保底：当optbullet销毁时，如果当前镜头正在追踪这个bullet的RO，恢复到主角镜头
	if self.m_EnableRestoreCameraOnDestroy and self.m_RenderObject and g_CameraMgr:GetTmpCameraData("TargetRenderObject") == self.m_RenderObject then
		g_CameraMgr:RestoreMainCameraTarget(0)
	end

	self:TryRemovePositionTerrainInteractPoint()
	UnRegisterObjTick(self, "MoveTick")
	UnRegisterObjTick(self, "Die")
	UnRegisterObjTick(self, "DelayLoadAI")
	self:RemoveAllEffects(false)

	local bulletId = self:GetBulletId()
	local func = table.safe_get(AllFormulas, "Bullet_Bullet", bulletId, "BeforeDestroyActionClient")
	if func then
		g_ActionMgr:DoAction(self, nil, nil, func)
	end

	self:UnloadClientAI()

	TrySubBulletCreateCnt(self)
end

function CClientBulletOpt:_Destroy()
	SAFE_CALL(CClientBulletOpt.SafeCall_Destroy, self)

	CClientCharacter._Destroy(self)
	g_BulletObjectMgr:RemoveOptBullet(self)
	g_ObjPoolMgr:ReturnObj(self)
end

function CClientBulletOpt:GetUId()
	return self.m_UId
end

function CClientBulletOpt:GetBulletId()
	return self.m_BulletMoveData.m_BulletDataId
end

function CClientBulletOpt:GetSourceTemplateId()
	return self.m_BulletMoveData.m_BulletDataId
end

function CClientBulletOpt:GetData(name)
	-- Style CharMod
	if name == "CharacterDef" and self.m_StyleCharMod then
		return self.m_StyleCharMod
	end

	local BulletDataId = self.m_BulletMoveData.m_BulletDataId
	local BulletSetting = Bullet_Appear[BulletDataId]
	if name == "CharacterDef" and BulletSetting then
		local appearReplaceKey = BulletSetting.BulletAppearReplaceKey
		if appearReplaceKey and self.m_AppearReplaceValue then
			local t1 = Bullet_BulletAppearReplaceValue[appearReplaceKey]
			local row = t1 and t1[self.m_AppearReplaceValue]
			local charDef = row and row.CharacterDef
			if charDef then return charDef end
		end
		if BulletSetting.CharacterDef then
			local replacePath = GetSkillAttachReplacePath(GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId), BulletSetting.NodeID)
			if replacePath then return replacePath end
		end
	end
	return BulletSetting and BulletSetting[name] or (Bullet_Bullet[BulletDataId] and Bullet_Bullet[BulletDataId][name])
end

function Gas2Gac:RefreshBulletOptMoveData(PipeId, UId, RootOwnerId, BulletId, freqMP, noFreqMP, specMP, DirX, DirY, DirZ, LifeTime)
	-- print("RefreshBulletOptMoveData", UId, RootOwnerId, BulletId, freqMP, noFreqMP, specMP, DirX, DirY, DirZ, LifeTime)
	local isNeedCreate = IsNeedCreateBullet(RootOwnerId, BulletId)
	if OPTIMIZE_STATISTIC_ENABLE then
		g_ClientProfilerMgr:RecordRpcCall("RefreshBulletOptMoveData", isNeedCreate)
	end
	if not isNeedCreate then
		return
	end

	local bullet = g_ObjPoolMgr:GetObj(CClientBulletOpt)
	local moveData = bullet.m_BulletMoveData
	msgpack.unpack(freqMP, CBulletData_Freq, moveData)
	msgpack.unpack(noFreqMP, CBulletData_NoFreq, moveData)
	local spCls = BulletTrajectoryClassTb[moveData.m_Trajectory]
	if spCls then
		msgpack.unpack(specMP, spCls, moveData)
	end

	moveData.m_RootOwnerId = RootOwnerId
	moveData.m_BulletDataId = BulletId
	if not moveData.m_OwnerId then
		moveData.m_OwnerId = RootOwnerId
	end

	bullet:Init(UId, DirX, DirY, DirZ, LifeTime)
	bullet:StartLuaMove(UId)

	TryAddBulletCreateCnt(bullet) 
end

function CClientBulletOpt:Init(UId, DirX, DirY, DirZ, LifeTime)
	-- print("CClientBulletOpt:Init", UId, g_App:GetGlobalTime(), DirX, DirY, DirZ, LifeTime)
	self.m_UId = UId
	local bulletData = self.m_BulletMoveData
	local bulletDesign = Bullet_Bullet[bulletData.m_BulletDataId]
	local bulletAppearDesign = Bullet_Appear[bulletData.m_BulletDataId]
	self.m_BulletMoveIs2DDir = bulletAppearDesign and bulletAppearDesign.Is2DDir
	self.m_BulletMoveIsIgnoreUpdateMoveDir = bulletDesign and bulletDesign.IgnoreUpdateMoveDir == 1
	self.m_OldX, self.m_OldY, self.m_OldZ = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
	g_BulletObjectMgr:AddOptBullet(self)

	self.m_ClientBornTime = GetProcessTime()
	self:SetDieTime(LifeTime)

	self.m_NeedCreate = true
	if not g_ClientOptimizeMgr:IsNeedCreateBullet(self, self.m_BulletMoveData) then
		self.m_NeedCreate = false
	end

	self.m_RootOwnerId = bulletData.m_RootOwnerId
	self.m_RootOwnerCharacterType = bulletData.m_RootOwnerCharacterType

	-- 计算外观替换值，与服务端 SetAppearReplaceValue 逻辑保持一致
	local bulletAppearReplaceKey = bulletAppearDesign and bulletAppearDesign.BulletAppearReplaceKey
	if bulletAppearReplaceKey then
		local keyDef = AllFormulas.Bullet_BulletAppearReplaceKeyDefine[bulletAppearReplaceKey]
		local func = keyDef and keyDef.GetValueExpression
		if func then
			self.m_AppearReplaceValue = func(GetCharacterByEngineObjectGlobalId(bulletData.m_RootOwnerId))
		end
	end

	if g_SceneLoaded then
		self:InitRenderObject()
	end

	--设置运动初始朝向
	if not (bulletDesign and bulletDesign.IgnoreInitUpdateMoveDir == 1) then
		if self.m_BulletMoveIs2DDir == 1 then 
			self:SetBulletRotation(DirX, 0, DirY)
		else
			self:SetBulletRotation(DirX, DirZ, DirY)
		end
	end
	self.m_NeedAfterGacCoreUpdate = true

	local ai = self:GetData("ClientFlowchartName")
	self:InitClientAI(ai)
	self:LoadClientAI(OPT_BULLET_AI_LOAD_RETRY_COUNT)
	self.m_DesignDataInteractCache = self:GetData("TerrainInteract")
end

function CClientBulletOpt:IsPureClientBullet()
	return g_BulletObjectMgr:IsPureClientBullet(self)
end

-- 读取纯客户端子弹的自定义数据（服务端创建时通过 CreateSomeBullet.CustomData 带入，随
-- RefreshBulletOptMoveData 同步到客户端并保存到 m_BulletMoveData.m_CustomData）。
-- 传入 key 时一次只能读取该 key 对应的一个值；key 不存在或没有自定义数据时返回 nil。
function CClientBulletOpt:GetCustomDataClientBullet(key)
	if not key then
		return nil
	end
	local moveData = self.m_BulletMoveData
	local customData = moveData and moveData.m_CustomData
	if customData == nil then
		return nil
	end
	return customData[key]
end

function CClientBulletOpt:SetDieTime(DieTime)
	DieTime = math.max(0.001, DieTime)

	if DieTime > MaxLifeTime then
		DieTime = MaxLifeTime
	end

	local uid = self:GetUId()
	local f = function()
		local bullet = g_BulletObjectMgr:GetOptBulletByUId(uid)
		if bullet then
			bullet:Destroy()
		end
	end

	RegisterObjTickWithDuration(self, "Die",f, DieTime, DieTime)
end

-- 纯客户端子弹轨迹切换 start
local BULLET_RES_DATA_OVERRIDE_KEY_TO_TYPE = {
	["Acceleration"] = "number",
	["Speed"] = "number",
	["Trajectory"] = "table",
	["CrossBuilding"] = "number",
}

local PureClientBulletTrajectoryChangeMap = {
	['BezierCurveTarget'] = true,
	['BezierCurvePos'] = true,
}

local function _CheckBulletResDataOverrideValid(BulletResDataOverride)
	if not BulletResDataOverride then return true end
	for k, v in pairs(BulletResDataOverride) do
		local reqType = BULLET_RES_DATA_OVERRIDE_KEY_TO_TYPE[k]
		if not reqType then
			BulletResDataOverride[k] = nil
		else
			local curType = type(v)
			if reqType ~= curType then
				PQERRF("BulletResDataOverride: type of key \"%s\" is %s, required is %s", k, curType, reqType)
				return false
			end
		end
	end
	return true
end

function CClientBulletOpt:InitMoveDataByBulletId(BulletId, bAttachToLocalFrame, BulletResDataOverride)
	if not (BulletId and self:IsPureClientBullet() and self:IsValid() and _CheckBulletResDataOverrideValid(BulletResDataOverride)) then
		LogCallContext_lua()
		return false
	end

	local bulletData = self.m_BulletMoveData
	if not bulletData then
		return false
	end

	local BulletResData = Bullet_Bullet[math.floor(BulletId / 100)]
	if not BulletResData then
		LogCallContext_lua()
		return false
	end
	local trajectory = BulletResDataOverride and BulletResDataOverride.Trajectory or BulletResData.Trajectory
	if not PureClientBulletTrajectoryChangeMap[trajectory[1]] then
		LogCallContext_lua()
		return false
	end

	local x, y, z = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
	local ownerId = bulletData.m_OwnerId
	local rootOwnerId = bulletData.m_RootOwnerId
	local rootOwnerCharacterType = bulletData.m_RootOwnerCharacterType
	local useOtherBulletClientResource = bulletData.m_UseOtherBulletClientResource

	self:InitBulletMoveData(BulletResData, x, y, z, BulletResDataOverride)

	bulletData.m_OwnerId = ownerId
	bulletData.m_RootOwnerId = rootOwnerId
	bulletData.m_RootOwnerCharacterType = rootOwnerCharacterType
	bulletData.m_UseOtherBulletClientResource = useOtherBulletClientResource
	if bAttachToLocalFrame then 
		self.m_BulletMoveData.m_Status = 2 
	end
	return true
end

function CClientBulletOpt:InitBulletMoveData(BulletResData, bx, by, bz, BulletResDataOverride)
	local bulletData = self.m_BulletMoveData
	ClearAllClassData(bulletData)
	bulletData:Ctor()
	return self:_InitBulletMoveData(BulletResData, bx, by, bz, BulletResDataOverride)
end

function CClientBulletOpt:_InitBulletMoveData(BulletResData, bx, by, bz, BulletResDataOverride)
	self.m_BulletMoveData.m_BulletDataId = BulletResData.ID
	self.m_BulletMoveData.m_BulletSpeed = BulletResDataOverride and BulletResDataOverride.Speed or BulletResData.Speed
	if not BulletResData.NoAoiHit then
		self.m_BulletMoveData.m_BulletSpeed = math.min(self.m_BulletMoveData.m_BulletSpeed, MAX_BULLET_AOI_HIT_SPEED)
	end
	self.m_BulletMoveData.m_CurX = bx
	self.m_BulletMoveData.m_CurY = by
	self.m_BulletMoveData.m_CurZ = bz

	local trajectory = BulletResDataOverride and BulletResDataOverride.Trajectory or BulletResData.Trajectory
	ClientBulletTrajectoryImp:SetBulletMoveTrajectory(self, trajectory[1])

	self.m_BulletMoveData.m_TrajectoryArgs = trajectory[2]	
	if #trajectory > 2 then --多于一个的参数		
		local t = {}
		for i = 2, #trajectory do  			
			table.insert(t, trajectory[i])
		end
		self.m_BulletMoveData.m_TrajectoryArgs = t
	end
	local delayMoveTime = BulletResDataOverride and BulletResDataOverride.DelayMoveTime or BulletResData.DelayMoveTime
	if delayMoveTime and delayMoveTime > 0 then
		self.m_BulletDelayMoveTime = delayMoveTime
	end
end

-- 纯客户端子弹轨迹切换 end

function CClientBulletOpt:StartLuaMove()
	if self:IsPureClientBullet() then
		local delayMoveTime = self:GetData("DelayMoveTime")
		if delayMoveTime and delayMoveTime > 0 then
			UnRegisterObjTick(self, "DelayMoveTick")
			RegisterObjTickWithDuration(self, "DelayMoveTick", CClientBulletOpt._StartLuaMove, delayMoveTime * 1000, delayMoveTime * 1000, self)
			return
		end
	end
	return self:_StartLuaMove()
end

function CClientBulletOpt:_StartLuaMove()
	local rate = GameManager:GetTargetFrameRate()
	local interval = EnumGlobalConstants.MoveCyc_Client
	if rate > 0 then 
		interval = math.max(1000 / rate, interval)
	end

	UnRegisterObjTick(self, "MoveTick")
	RegisterObjTick(self, "MoveTick", CClientBulletOpt.OnMoveTick, interval, self, interval)
end

function CClientBulletOpt:OnMoveTick(interval)
	self:GetLuaNextMove(interval)
end

function CClientBulletOpt:GetLuaNextMove(deltaTime)
	local bulletData = self.m_BulletMoveData

	self.m_OldX, self.m_OldY, self.m_OldZ = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
	GetLuaNextMove(bulletData, self, deltaTime)

	if self.m_BulletMoveNextMoveStop then
		self:OnFlowchartEvent("MoveEnded")
		UnRegisterObjTick(self, "MoveTick")
	end
end

function CClientBulletOpt:AfterGacCoreUpdate()
	local bulletData = self.m_BulletMoveData
	local x, y, z = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
	local diffX = x - self.m_OldX 
	local diffY = y - self.m_OldY 
	local diffZ = z - self.m_OldZ 
	if abs(diffX) > 1 or abs(diffY) > 1 or abs(diffZ) > 1 then 
		self.m_NeedAfterGacCoreUpdate = true
	end

	if self.m_NeedAfterGacCoreUpdate then 
		--刷新子弹运动对象朝向, 子弹可能没有ro, 也需要调用
		if bulletData and not self.m_BulletMoveIsIgnoreUpdateMoveDir then 
			if self.m_BulletMoveIs2DDir == 1 then 
				self:SetBulletRotation(diffX, 0, diffY)
			else
				self:SetBulletRotation(diffX, diffZ, diffY)
			end
		end
		
		local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
		local ux, uy, uz = x / pixel_per_grid, y / pixel_per_grid, z / pixel_per_grid
		local uid = self:GetUId()
		renderObject:ResetEffectPosition(nil, ux, uz, uy, uid)

		local fxId = self.m_FxId
		if fxId then
			local hash = uid
			local fxData = Fx_TargetFx[fxId]
			while fxData and fxData.ExtraFx do
				hash = hash + fxData.ExtraFx
				renderObject:ResetEffectPosition(nil, ux, uz, uy, hash)
				fxData = Fx_TargetFx[fxData.ExtraFx]
			end
		end
		self:TryAddOrUpdatePositionTerrainInteractPoint(ux, uy, uz)

		if self.m_RenderObject then
			if OPTIMIZE_MOVE then
				self.m_RenderObject:SetPosition2_V2(ux, uz, uy, true, 0, false, nil, false, false, 0, true, not g_WaterMgr:IsSceneUnityPosAbsolutelyNoWater_Cache(ux, uy))
			else
				self.m_RenderObject:SetPosition2(ux, uz, uy)
			end
		end
	end
	self.m_NeedAfterGacCoreUpdate = false
	self:HitClientNpcCheck(self.m_OldX, self.m_OldY, self.m_OldZ, x, y, z)
end

function CClientBulletOpt:GetPixelPosition()
	local bulletData = self.m_BulletMoveData
	return bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
end

function CClientBulletOpt:GetOwner()
	return self.m_BulletMoveData.m_OwnerId and GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_OwnerId)
end

function CClientBulletOpt:GetLayer()
	return LayerDefine.LAYER_IGNORE_RAYCAST
end

function CClientBulletOpt:RefreshROPosition(bForce, bIgnorePosCheck)
	if not self:IsValid() then
		return
	end
	self.m_NeedAfterGacCoreUpdate = true
end

-- 特效不用ro
function CClientBulletOpt:IsRequireRenderObject()
	return self:GetData("CharacterDef") or self:GetData("EnableFxAction")
end

function CClientBulletOpt:InitRenderObject()
	self:InitRenderObject_OnSceneLoaded()
end

function CClientBulletOpt:InitRenderObject_OnSceneLoaded()
	-- print("优化模式")
	LoadBulletStyle(self)

	if self:IsRequireRenderObject() then
		CClientCharacter.InitRenderObject(self)
	end
	
	-- ro
	local bulletScale = self:GetData("BulletScale")
	if self.m_RenderObject and bulletScale then
		self.m_RenderObject:SetScale(bulletScale, bulletScale, bulletScale)
	end

	local fStartTime = type(self.m_BulletMoveData.m_NewBorn) == "number" and self.m_BulletMoveData.m_NewBorn or 0
	fStartTime = (fStartTime + GetProcessTime() - self.m_ClientBornTime) / 1000

	local fScaleX, fScaleY, fScaleZ
	local fxId = self:GetData("FxID")
	local path = self:GetData("AreName")
	self.m_FxId = nil
	if fxId then
		local fxData = Fx_TargetFx[fxId]
		if fxData.Scale then fScaleX, fScaleY, fScaleZ = fxData.Scale[1], fxData.Scale[2], fxData.Scale[3] end
		fStartTime = fStartTime + (fxData.StartTime or 0)

		local fxPath = GetTargetFxPath(GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId), fxId)
		local styleEffect = self.m_StyleEffect
		local fHue, fSat, fBright, fWeight, effectClipTag = fxData.FxEffectHue, fxData.FxSaturate, fxData.FxBright, fxData.FxWeight, 0

		local bulletDataId = self.m_BulletMoveData.m_BulletDataId
		local bulletAppear = Bullet_Appear[bulletDataId]
		local rootOwner = GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId)
		if not styleEffect then
			styleEffect, fHue, fSat, fBright, fWeight, effectClipTag = EffectUtils_ApplyLogicReplace(rootOwner, nil, nil, fxId, fxPath, fxData.LogicReplaceRule, fHue, fSat, fBright, fWeight, effectClipTag)
		end

		self:ShowBulletEffect(self:GetUId(), fxPath, styleEffect, fScaleX, fScaleY, fScaleZ, fStartTime, fHue, fSat, fBright, fWeight, self.m_ReplaceTexPath, self.m_ReplaceRendererIdx, nil, effectClipTag)

		if fxData.ExtraFx then
			self.m_FxId = fxId
			self:_PlayBulletExtraFx(fxData.ExtraFx, self:GetUId(), styleEffect, fStartTime, rootOwner)
		end
	elseif path then
		if bulletScale then fScaleX, fScaleY, fScaleZ = bulletScale, bulletScale, bulletScale end

		self:ShowBulletEffect(self:GetUId(), path, self.m_StyleEffect, fScaleX, fScaleY, fScaleZ, fStartTime)
	end

	self:UpdateEffectVisible()
end

function CClientBulletOpt:RegisterBulletEffect(nLogicHash)
	if not nLogicHash then nLogicHash = cEffectMgr:GenerateRuntimeGuid() end

	table.insert(self.m_EffectList, nLogicHash)

	return nLogicHash
end

function CClientBulletOpt:ShowBulletEffect(nLogicHash, path, stylePath, fScaleX, fScaleY, fScaleZ, fStartTime, fHue, fSaturate, fBright, fWeight, replaceTex, replaceRendererIdx, weaponPath, effectClipTag)
	if not path then return end

	nLogicHash = self:RegisterBulletEffect(nLogicHash)

	local bulletData = self.m_BulletMoveData
	local rootOwnerId = bulletData.m_RootOwnerId
	local rootOwnerCharacterType = bulletData.m_RootOwnerCharacterType
	local player = GetCharacterByEngineObjectGlobalId(rootOwnerId)
	local playerType = EffectUtils_GetPlayerTypeRootOwner(rootOwnerId, rootOwnerCharacterType)
	local x, y, z = self:GetPixelPosition()
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()

	renderObject:PlayBulletEffect(nLogicHash, path, player and player:GetRenderObject(), playerType,
		x/64, z/64, y/64, fScaleX or 1, fScaleY or 1, fScaleZ or 1, fHue or -1, fSaturate or 1, fBright or 1, fWeight or 1, fStartTime or 0, stylePath, replaceTex, replaceRendererIdx, weaponPath, effectClipTag)
end

function CClientBulletOpt:_PlayBulletExtraFx(fxId, parentHash, stylePath, baseStartTime, rootOwner)
	local fxData = Fx_TargetFx[fxId]
	if not fxData then return end

	local path = GetTargetFxPath(rootOwner, fxId)
	if not path then return end

	local extraHash = parentHash + fxId
	local fScaleX, fScaleY, fScaleZ
	if fxData.Scale then
		fScaleX, fScaleY, fScaleZ = fxData.Scale[1], fxData.Scale[2], fxData.Scale[3]
	end

	local fHue, fSat, fBright, fWeight, effectClipTag = fxData.FxEffectHue, fxData.FxSaturate, fxData.FxBright, fxData.FxWeight, 0
	if not stylePath then
		stylePath, fHue, fSat, fBright, fWeight, effectClipTag = EffectUtils_ApplyLogicReplace(rootOwner, nil, nil, fxId, fxData.FxName, fxData.LogicReplaceRule, fHue, fSat, fBright, fWeight, effectClipTag)
	end

	self:ShowBulletEffect(extraHash, path, stylePath,
		fScaleX, fScaleY, fScaleZ,
		(baseStartTime or 0) + (fxData.StartTime or 0),
		fHue, fSat, fBright, fWeight, nil, nil, nil, effectClipTag)

	if fxData.ExtraFx then
		self:_PlayBulletExtraFx(fxData.ExtraFx, extraHash, stylePath, baseStartTime, rootOwner)
	end
end

function CClientBulletOpt:RemoveAllEffects(ignoreLoop)
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	local forceRemoveLoopEffect = ignoreLoop or false
	for k,v in ipairs(self.m_EffectList) do
		renderObject:RemoveEffect(nil, forceRemoveLoopEffect, v)
	end
	table.clear(self.m_EffectList)
end

-- dx, dy, dz是unity坐标系的朝向增量
function CClientBulletOpt:SetBulletRotation(dx, dy, dz)
	self.m_Degree = XYDirToDegreeDir(dx, dz)

	if self.m_RenderObject then
		self.m_RenderObject:SetRotation(dx, dy, dz)
	else
		local uid = self:GetUId()
		local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
		renderObject:ResetEffectLookRotation(nil, dx, dy, dz, uid)

		local fxId = self.m_FxId
		if fxId then
			local hash = uid
			local fxData = Fx_TargetFx[fxId]
			while fxData and fxData.ExtraFx do
				hash = hash + fxData.ExtraFx
				renderObject:ResetEffectLookRotation(nil, dx, dy, dz, hash)
				fxData = Fx_TargetFx[fxData.ExtraFx]
			end
		end
	end
end

function CClientBulletOpt:GetTemplateId()
	return self:GetBulletId()
end

function Gas2Gac:DestroyServerBulletOpt(_, uid)
	local bullet = g_BulletObjectMgr:GetOptBulletByUId(uid)
	if bullet then 
		bullet:Destroy()
	end
end

function Gas2Gac:DestroyPureClientBullet(_, rootOwnerId, bulletId)
	local bulletMgr = g_BulletObjectMgr
	local toDestroy = {}
	for uid, bullet in pairs(bulletMgr.m_UId2OptBullet) do
		if bullet:IsPureClientBullet() and bullet.m_RootOwnerId == rootOwnerId and bullet:GetBulletId() == bulletId then
			table.insert(toDestroy, uid)
		end
	end
	for _, uid in ipairs(toDestroy) do
		local bullet = bulletMgr:GetOptBulletByUId(uid)
		if bullet then
			bullet:Destroy()
		end
	end
end

function CClientBulletOpt:GetFaceDirection()
	return self.m_Degree
end

--这边定义不需要清的数据,
local __no_clear_keys = 
{
}
function CClientBulletOpt:OnReturnToPool(...)
	if false then
		--可以如下调用PrintClassInstanceKVBeforeReturnToPool()查看OnReturnToPoolDefault中
		---即将要被清的key,value以及不会被清的key，value
		PrintClassInstanceKVBeforeReturnToPool(self, __no_clear_keys)
	end

	OnReturnToPoolDefault(self, __no_clear_keys, ...)
	--额外需要清的数据写这里，比如Ctor里初始化的某些key确定后面用不到了，需要置nil
	ClearAllClassData(self.m_BulletMoveData)
end

function CClientBulletOpt:OnReuseFromPool()
	OnReuseFromPoolDefault(self)
	--额外的一些初始化逻辑写这里
	self.m_BulletMoveData:Ctor()
end

function CClientBulletOpt:BulletEffectScale(ScaleX, ScaleY, ScaleZ)
	local uid = self:GetUId()
	local ro = g_ClientEffectMgr:GetEffectRenderObject()
	ro:ResetEffectScale(nil, ScaleX, ScaleY, ScaleZ, uid)

	local fxId = self.m_FxId
	if fxId then
		local hash = uid
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			ro:ResetEffectScale(nil, ScaleX, ScaleY, ScaleZ, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
end

function CClientBulletOpt:HitClientNpcCheck(_, _, _, x, y, z)
	if not (g_MainPlayer and self:GetOwner() == g_MainPlayer) then
		return
	end
	local hitNpcIdTbl = self:GetData("HitClientNpc")
	if not hitNpcIdTbl then
		return
	end
	if self.m_IsHitClientNpc then
		return
	end
	for npcId, hitDis in bddpairs(hitNpcIdTbl) do
		local allObjects = g_CharacterMgr:GetObjsByTemplateId(npcId)
		if allObjects then
			for _, obj in pairs(allObjects) do
				if not obj.m_ExtraData.IsHit then
					local oX, oY, oZ = obj:GetPixelPosition()
					local dis = (x - oX) ^ 2 + (y - oY) ^ 2 + (z - oZ) ^ 2
					if dis <= hitDis ^ 2 then
						self:DoHitClientNpc(obj:GetTemplateId(), obj.m_engineObjectId)
						return
					end
				end
			end
		end
	end
end

function CClientBulletOpt:DoHitClientNpc(npcId, npcEngineId)
	if IsLanDuWaterBullet(self:GetBulletId()) then
		local npc = GetObjectByGlobalId(npcEngineId)
		if not npc then
			return
		end
		npc:FlowchartCustomEvent("OnBulletHitClientNpc", self:GetTemplateId(), self.m_engineObjectId, self.m_BulletMoveData.m_OwnerId)
		--npc:SetROVisible(false)
		npc.m_ExtraData.IsHit = true
		local guid = npc:GetGUID()
		local data = PublicMap_ext_PureClientNpc[guid]
		if not data then return end
		local clusterName = data.ClusterName
		local hitCount = 0
		local sceneData = PublicMap_ext_PublicMap[g_SceneDesignID]
		local pureClientNpc =  sceneData.PureClientNpc
		if pureClientNpc then
			for _, v in bddipairs(pureClientNpc) do
				if v.ClusterName and v.ClusterName == clusterName then
					local tmpObj = g_CharacterMgr:GetObjectByGUID(v.GUID)
					if not tmpObj or tmpObj.m_ExtraData.IsHit == true then
						hitCount = hitCount + 1
					end
				end
			end
		end
		local extraArgs = {}
		local exploreNpcGuid = nil
		local summonObjId = GameSetting_Client.LANDU_WATER_BULLET_CLUSTER_2_SUMMONID.tblVal[clusterName]
		local summonObjects = summonObjId and g_CharacterMgr:GetObjsByTemplateId(summonObjId)
		for _, obj in pairs(summonObjects or EMPTY_TABLE) do
			if obj.m_ExtraData.ServerExtra.m_SummonCustomData.cluster == clusterName then
				exploreNpcGuid = obj.m_ExtraData.ServerExtra.m_EventDupId
				break
			end
		end
		extraArgs.exploreNpcGuid = exploreNpcGuid
		extraArgs.isOpt = true
		if hitCount <= 1 then
			extraArgs.isStart = true
		end
		self.m_IsHitClientNpc = true
		Gac2Gas:BulletHitClientNpc(g_Conn, self:GetUId(), msgpack.pack(extraArgs))
		local hideNpc = self:GetData("HitHideClientNpc")
		if hideNpc and hideNpc[npcId] then
			npc:SetROVisible(false)
		end
		return
	end
end

local _TerrainMgr = CS.Pangu.AppFacade.terrainMgr
function CClientBulletOpt:TryAddOrUpdatePositionTerrainInteractPoint(posX, posY, posZ)
	self.m_DesignDataInteractCache = self:GetData("TerrainInteract")
	if not self.m_DesignDataInteractCache then return end

	if not _TerrainMgr:HasTerrainInteract() then return end
	if not HasFeature("SnowInteractPositionAndBone_411") then return end

	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	if not renderObject then return end
	
	local designDataInteract = self.m_DesignDataInteractCache
	local scaleX = designDataInteract.Scale[1] or 1
	local scaleY = designDataInteract.Scale[2] or 1
	local scaleZ = designDataInteract.Scale[3] or 1

	local offsetX = designDataInteract.Offset and designDataInteract.Offset[1] or 0
	local offsetY = designDataInteract.Offset and designDataInteract.Offset[2] or 0
	local offsetZ = designDataInteract.Offset and designDataInteract.Offset[3] or 0	
	local uuid = self:GetUId()
	renderObject:AddOrUpdatePositionTerrainInteractPoint(uuid, posX+offsetX, posY+offsetY, posZ+offsetZ, scaleX, scaleY, scaleZ)
end

function CClientBulletOpt:TryRemovePositionTerrainInteractPoint()
	if not _TerrainMgr:HasTerrainInteract() then return end
	if not HasFeature("SnowInteractPositionAndBone_411") then return end

	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	if not renderObject then return end
	local uuid = self:GetUId()
	renderObject:RemovePositionTerrainInteractPoint(uuid)
end
	
function CClientBulletOpt:InitClientAI(aiList)
	self.m_AINameList = aiList
end

function CClientBulletOpt:DelayLoadClientAI(retryCount)
	if not retryCount or retryCount <= 0 then return end
	local uid = self:GetUId()
	local f = function()
		local bullet = g_BulletObjectMgr:GetOptBulletByUId(uid)
		if bullet and not bullet.m_IsAILoaded then
			bullet:LoadClientAI(retryCount)
		end
	end
	RegisterObjTickWithDuration(self, "DelayLoadAI", f, OPT_BULLET_AI_LOAD_RETRY_INTERVAL, OPT_BULLET_AI_LOAD_RETRY_INTERVAL)
end

function CClientBulletOpt:LoadClientAI(retryCount)
	local flowcharts = self.m_AINameList

	if not flowcharts or not bddnext(flowcharts) then
		return
	end

	if self.m_IsAILoaded then
		PQLOGF("[CClientBulletOpt] LoadClientAI already loaded for bulletUId<%s>", self:GetUId())
		return
	end

	flowchart.init(self, EFlowClass.ClientCharacter)
	self.m_ClientAIList = self.m_ClientAIList or {}

	local ok = 0
	for _k, v in bddipairs(flowcharts) do
		local name = "ClientBulletOptAI." .. v
		local ret = flowchart.load(self, name)
		if ret then
			ok = ok + 1
			self.m_ClientAIList[name] = true
		end
	end

	if ok > 0 then
		self.m_IsAILoaded = true
		flowchart.start(self)
	elseif (retryCount or 0) > 1 then
		self:DelayLoadClientAI(retryCount - 1)
	else
		PQLOGF("[CClientBulletOpt] LoadClientAI retry exhausted bulletUId<%s> templateId<%s>", self:GetUId(), self:GetTemplateId())
	end
end

function CClientBulletOpt:UnloadClientAI()
	UnRegisterObjTick(self, "DelayLoadAI")
	if self.m_IsAILoaded then
		self.m_IsAILoaded = nil
		self.m_ClientAIList = nil
		flowchart.deinit(self)
	end
end

function CClientBulletOpt:OnResLoaded()
	CFollowerCharacter.OnResLoaded(self)

	if self.m_RenderObject then
		local bulletScale = self:GetData("BulletScale")
		if bulletScale then
			self.m_RenderObject:SetScale(bulletScale, bulletScale, bulletScale)
		end
	end
	self:CheckAndApplyBulletDyeColor()
end

function CClientBulletOpt:CreateHeadInfo()
end

function CClientBulletOpt:GetPixelPositionTable()
    local bulletData = self.m_BulletMoveData
    local x, y, z = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
    return {x = x, y = y, z = z}
end

function CClientBulletOpt:GetBlockObjectType()
	local flag = EnumBlockEngineObjectType.Bullet
	if g_MainPlayer and self:GetOwner() == g_MainPlayer then
		flag = bit.bor(flag, EnumBlockEngineObjectType.MainPlayerBullet)
	end
	return flag
end

function CClientBulletOpt:FxVisiable(bVisible)
	local uid = self:GetUId()
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	renderObject:SetEffectVisible(nil, bVisible, uid)

	local fxId = self.m_FxId
	if fxId then
		local hash = uid
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			renderObject:SetEffectVisible(nil, bVisible, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
end

function CClientBulletOpt:OnEffectVisibleChanged(bVisible)
	self:FxVisiable(bVisible)
end

function CClientBulletOpt:GetBulletInitRotation()
	return self.m_Degree and Quaternion.Euler(0, self.m_Degree, 0) or CClientCharacter.GetBulletInitRotation(self)
end

function CClientBulletOpt:ModifySpeed(fSpeed)
	self:UpdateProperty("m_BulletSpeed", fSpeed)
end

function CClientBulletOpt:UpdateProperty(key, value)
	local BulletData = self.m_BulletMoveData
	local old = BulletData[key]
	if old == value then return end
	BulletData[key] = value
end

function CClientBulletOpt:FaceToTarget(TargetObj, adjustAngle)
	if TargetObj and TargetObj.m_engineObject then
		if adjustAngle then
			PQLOG("FaceToTarget adjustAngle not impl")
			LogCallContext_lua()
		end

		local tx, ty, tz = TargetObj.m_engineObject:GetPixelPosv3()
		local bulletData = self.m_BulletMoveData
		local sx, sy, sz = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
		local dx, dy, dz = tx - sx, ty - sy, tz - sz
		self:SetBulletRotation(dx, dz, dy)
	end
end

function CClientBulletOpt:FaceToDirection(direction, adjustAngle)
	local finalAngle =( direction + (adjustAngle or 0)) % 360
	local rad = math.rad(finalAngle)
	local dx = math.cos(rad)
	local dz = math.sin(rad)
	self:SetBulletRotation(dx, 0, dz)
end

--region 染色Appear

function CClientBulletOpt:CheckAndApplyBulletDyeColor()
	local dyeColorSource = self:GetData("DyeColorSource")
	if not dyeColorSource or #dyeColorSource < 1 or not EnumBulletDyeColorSourceKey[dyeColorSource[1]] then return end

	local dyeRule = self:GetData("DyeColorRule")
	if not dyeRule then return end

	local dyeColor = g_ClientFashionMgr:TryGetBulletDyeColor(self, dyeColorSource)
	if not dyeColor then return end

	for i, rule in bddipairs(dyeRule) do
		g_ClientFashionMgr:Common_ApplyPiecePropertyBlock(self, nil, dyeColor, rule)
	end
end

--endregion