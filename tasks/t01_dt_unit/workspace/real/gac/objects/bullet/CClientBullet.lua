local cEffectMgr = CS.Pangu.AppFacade.cEffectMgr
local vector3 =  CS.UnityEngine.Vector3
local quaternion = CS.UnityEngine.Quaternion
local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local band = bit.band

--==============================================================================================
function CClientBullet:Ctor()
	self.m_EffectList = self.m_EffectList or {}
end



function CClientBullet:Init(engineObject)
	if not OPTIMIZE_MODE_EX_BULLET then
		CFollowerCharacter.Init(self, engineObject, EnumCharacterType.Bullet)
		return
	end
	if self.m_State then
		self.m_State:Init(self)
	end
	self:SetCharacterType(EnumCharacterType.Bullet)
	self:SetEngineObject(engineObject)
	self:_InitEngineObjectHandler(engineObject)
	g_CharacterMgr:AddCharacter(self)
    local basicProp = self:BasicProp()
    if basicProp then
        basicProp:Attach(self)
    end
    local appearanceProp = self:AppearanceProp()
    if appearanceProp then
        appearanceProp:Attach(self)
    end
    self.m_HasHeadInfo = self:GetData("NeedHeadInfo") ~= nil
	if self.m_HasHeadInfo then
		self:InitHUDProperties()
	end
	self.m_DesignDataInteractCache = self:GetData("TerrainInteract")
end

function CClientBullet:Destroy()
	if self.m_Destroying then LogCallContext_lua() return end
	self.m_Destroying = true
	self:DoDestroyCallback()
	CClientBullet._Destroy(self)
end

function CClientBullet:SafeCall_Destroy()
	self:CheckAbsorbEffect()
	if OPTIMIZE_MODE_EX_BULLET then
		local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
		if renderObject then
			renderObject:RemovePositionTerrainInteractPointEx(self.m_engineObjectId)
		end
	else
		self:TryRemovePositionTerrainInteractPoint()
	end
	self:TryRemoveLongYinQJBulletHudInteractive()
	TrySubBulletCreateCnt(self)

	self:RemoveAllEffects(false)
	self:StopUpdateSelfByOwner()

	g_ClientFashionMgr:UnregisterSummonWearingFashion(self.m_engineObjectId)
end

function CClientBullet:_Destroy()
	SAFE_CALL(CClientBullet.SafeCall_Destroy, self)
	
	CFollowerCharacter._Destroy(self)
	g_ObjPoolMgr:ReturnObj(self)
end


function CClientBullet:SetCharacterType(t)
	self.m_CharacterType = t
	self.m_IsBullet = true
end

function CClientBullet:GetBulletId()
	return self.m_BulletMoveData and self.m_BulletMoveData.m_BulletDataId
end

OverrideCharacterDef_Idx2Key = {
	[1] = "OverrideCharacterDef1",
	[2] = "OverrideCharacterDef2",
	[3] = "OverrideCharacterDef3",
}

function CClientBullet:GetData(name)
	-- Style CharMod
	if name == "CharacterDef" and self.m_StyleCharMod then
		return self.m_StyleCharMod
	end

    local bulletId = self.m_SourceTemplateId
    local ugcOverrideValue
    if IdIsUGCBulletCls(bulletId) then
        if self.m_UgcFxScale and name == "FxScale" then
            ugcOverrideValue = self.m_UgcFxScale
        elseif self.m_UgcFxID and name == "FxID" then
            ugcOverrideValue = self.m_UgcFxID
        else
            local bulletData = g_UGCLevelMgr.m_LevelData and g_UGCLevelMgr.m_LevelData.Bullet
            local bullet = bulletData and bulletData:GetBullets_At(bulletId)
            ugcOverrideValue = bullet and bullet:GetExtraData(name)
        end
    end
	local BulletDataId = self.m_BulletMoveData.m_BulletDataId
	local BulletSetting = Bullet_Appear[BulletDataId]
	local BulletSettingValue = BulletSetting and BulletSetting[name]

	if name == "CharacterDef" and BulletSettingValue then
		local overrideCharacterDef = table.safe_get(FashionClothes_Fashion, self.m_UseWeaponCharDef_WeaponId,
			self.m_UseWeaponCharDef_Index and OverrideCharacterDef_Idx2Key[self.m_UseWeaponCharDef_Index])
		if overrideCharacterDef then return overrideCharacterDef end

		local replacePath = GetSkillAttachReplacePath(GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId), BulletSetting.NodeID)
		if replacePath then return replacePath end

		local appearReplaceKey = BulletSetting["BulletAppearReplaceKey"]
		if appearReplaceKey and self.m_AppearReplaceValue then
			local t1 = Bullet_BulletAppearReplaceValue[appearReplaceKey]
			local row = t1 and t1[self.m_AppearReplaceValue]
			local charDef = row and row.CharacterDef
			if charDef then return charDef end
		end
	end

	return ugcOverrideValue or BulletSettingValue or (Bullet_Bullet[BulletDataId] and Bullet_Bullet[BulletDataId][name])
end

function IsNoCreateHudBullet(RootOwnerId, BulletId)
	local bulletData = Bullet_Bullet[BulletId]
	if not bulletData or ((not bulletData.HudNoCreate) and (not bulletData.NoModelNoCreate) and (not bulletData.HudNoCreate_NoEnemy) ) then
		return false
	end

	-- 保持跟原逻辑一致，只要下来了都走这个逻辑
	local owner = GetCharacterByEngineObjectGlobalId(RootOwnerId, true)
	if owner and owner.m_IsSimpleHUD and g_MainPlayer and not g_MainPlayer:IsEnemy(owner) then
		return true
	end

	if owner and owner.m_IsSimpleHUD and bulletData.HudNoCreate then
		return true
	end

	if (not owner or owner.m_IsSimpleHUD) and bulletData.NoModelNoCreate then
		return true
	end
	
	return false
end

local function GetClientCreateNumControlData(bulletId)
	local design = Bullet_Bullet[bulletId]
	if not design then return end
	local row
	if IsOptimizeOpen("OptBulletClientCreate") then
		row = design.ClientCreateNumControlInOpt or design.ClientCreateNumControl
	else
		row = design.ClientCreateNumControl
	end
	if row then
		return row, design.ClientCreateNumControlGroupId
	end
end

function _CheckBulletCreateByNumControl(bulletId, owner, config, groupId)
	if not config then return true end

	local row = config[1]
	if not IsRunOnPC() then
		row = config[2] or row
	end

	bulletId = groupId or bulletId

	local enemyMaxCnt, noEnemyMaxCnt = row[1], row[2]
	if owner and g_MainPlayer:IsEnemy(owner) then
		if (g_CreateEnemyBullet2Cnt[bulletId] or 0) >= enemyMaxCnt then
			return false --小于敌方显示数量上限才可以显示
		end
	else
		if (g_CreateNoEnemyBullet2Cnt[bulletId] or 0) >= noEnemyMaxCnt then
			return false --小于非敌方显示数量上限才可以显示
		end
	end
	return true
end

function IsNeedCreateBullet(RootOwnerId, BulletId)
	if g_BattleReplayMgr:IsReplaying() then
		return true
	end

	if not g_MainPlayer then return false end 
	local noNeedCreate = IsNoCreateHudBullet(RootOwnerId, BulletId)
	if noNeedCreate then
		return false
	end

	if RootOwnerId ~= g_MainPlayer.m_engineObjectId then -- 主角的不受限
		local bulletData = Bullet_Bullet[BulletId]
		if not bulletData then return false end
		local numControlData, groupId = GetClientCreateNumControlData(BulletId)
		if numControlData then
			local owner = GetCharacterByEngineObjectGlobalId(RootOwnerId) or g_WaitingSyncMgr:GetWaitingSyncObject(RootOwnerId)
			if not _CheckBulletCreateByNumControl(BulletId, owner, numControlData, groupId) then
				return false
			end
		end
		-- PVE副本中，沉浸模式下部分技能的召唤物不创建
		if bulletData.HideInImmersion and g_MainPlayer:GetImmersionModeSetting("MainSwitch", EnumGameplayMode.PVE) == 1 then
			return false
		end
	end

	return true
end

function Gas2Gac:InitBullet(PipeId, uCharacterGlobalID, FreqDataString, NoFreqDataString, SpecDataString, RootOwnerId,
							BulletId, UseWeaponCharDef_WeaponId, UseWeaponCharDef_Index, ReplaceTexPath,
							ReplaceRendererIdx, extraDataUD)
	local isNeedCreate = IsNeedCreateBullet(RootOwnerId, BulletId)
	if not isNeedCreate then
		if OPTIMIZE_STATISTIC_ENABLE then
			g_ClientProfilerMgr:RecordRpcCall("InitBullet", false)
		end
		return
	end

	local engineObject = CCoreObjectClient_CCoreObjectClient(g_CoreScene, uCharacterGlobalID)
	-- LOG_PRINT(DEBUG,"InitBullet", uCharacterGlobalID, engineObject, RootOwnerId, BulletId)
	if not engineObject then
		if OPTIMIZE_STATISTIC_ENABLE then
			g_ClientProfilerMgr:RecordRpcCall("InitBullet", false)
		end
		return
	end

	if OPTIMIZE_STATISTIC_ENABLE then
		g_ClientProfilerMgr:RecordRpcCall("InitBullet", true)
	end

	local bullet = g_ObjPoolMgr:GetObj(CClientBullet)
	NewBulletMoveDataToObj(bullet, FreqDataString, NoFreqDataString, SpecDataString)

	bullet.m_ClientBornTime = GetProcessTime()
	bullet:Init(engineObject)
	if not bullet.m_RenderObjectLuaType then
		bullet.m_RenderObjectLuaType = EObj_Lua_Type.OLT_CLIENT_BULLET
	end
	bullet.m_NeedCreate = true
	if not g_ClientOptimizeMgr:IsNeedCreateBullet(bullet, bullet.m_BulletMoveData) then
		bullet.m_NeedCreate = false
	end

	bullet.m_RootOwnerId = bullet.m_BulletMoveData.m_RootOwnerId
	bullet.m_RootOwnerCharacterType = bullet.m_BulletMoveData.m_RootOwnerCharacterType
	if UseWeaponCharDef_WeaponId ~= 0 and UseWeaponCharDef_Index ~= 0 then
		bullet.m_UseWeaponCharDef_WeaponId = UseWeaponCharDef_WeaponId
		bullet.m_UseWeaponCharDef_Index = UseWeaponCharDef_Index
	end
	bullet.m_ReplaceTexPath = ReplaceTexPath
	bullet.m_ReplaceRendererIdx = ReplaceRendererIdx

	local bulletId = bullet.m_BulletMoveData.m_BulletDataId
	local bulletAppearDesign = Bullet_Appear[bulletId]
	bullet.m_BulletMoveIs2DDir = bulletAppearDesign and bulletAppearDesign.Is2DDir

    local extraData = msgpack.unpack(extraDataUD)
    bullet.m_UgcFxID = extraData.UgcBulletData and  extraData.UgcBulletData["FxID"] or nil
    bullet.m_UgcFxScale = extraData.UgcBulletData and  extraData.UgcBulletData["FxScale"] or nil
	bullet.m_AppearReplaceValue = extraData and extraData.arv
	bullet.m_FruitId = extraData.FruitId
	bullet.m_FruitData = extraData.FruitData


    if IdIsUGCBulletCls(bulletId) and UGCLevel_Setting.UGC_BULLET_CREATE_CLIENT_ASYNC.NumVal and   g_UGCLevelMgr:GetSupervisor() then
        g_UGCLevelMgr:AddBulletToRanderList(bullet)
    else
        if g_SceneLoaded then
            bullet:InitRenderObject()
        end

        bullet:OnLuaObjectCreated()
        bullet:TryCreateLongYinQJBulletHudInteractive()
        TryAddBulletCreateCnt(bullet)
    end

	if extraData and extraData.appearUD then
		bullet.m_PropertyAppearance = CPropertyAppearance_NonPlayer.ClearOrNew(bullet.m_PropertyAppearance)
		bullet.m_PropertyAppearance:LoadFromString(extraData.appearUD)
	end

	local statusString = extraData and extraData.statusString
	if statusString and not IsNilUserData(statusString) and bullet:CheckCreateStatusProp() then 
		g_StatusMgr:SyncStatus(bullet, statusString)
	end
	bullet.m_bAllPropLoaded = true
end

function Gas2Gac:ChangeBulletAppear(PipeId, uCharacterGlobalID, Id)
	local ClientBulletFxObject = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if OPTIMIZE_STATISTIC_ENABLE then
		g_ClientProfilerMgr:RecordRpcCall("ChangeBulletAppear", ClientBulletFxObject ~= nil)
	end
	if ClientBulletFxObject then
		ClientBulletFxObject.m_BulletMoveData.m_BulletDataId = Id
		ClientBulletFxObject.m_BulletMoveData.m_UseOtherBulletClientResource = Id
		if g_SceneLoaded then
			ClientBulletFxObject:InitRenderObject()
			g_RecordReplayMgr:OnObjEvent(RREventType.BulletChangeAppear, ClientBulletFxObject, Id)
		end
	end
end

function CClientBullet:CheckAbsorbEffect()
	if type(self.m_BulletMoveData.m_AbsorbedBy) == "table" then
		local wallOwner = GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_AbsorbedBy[2])
		if wallOwner and IsNeedPlayEffect(wallOwner) then
			local effectId =  tonumber(GameSetting_Client["BULLET_ABSORBED_EFFECT_ID"].value)
			local x, y, z = self.m_engineObject:GetPixelPosv3()
			wallOwner:PlayEffectAtPos(effectId, x, y, z, 0) 
		end
	end
end

function CClientBullet:ProcessMoveStateBegan()
	if not self:IsRequireRenderObject() then
		return
	end
	CFollowerCharacter.ProcessMoveStateBegan(self)
end

function Gas2Gac:ShowBulletDestroyFx(PipeId, uCharacterGlobalID)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end

	local path = bullet:GetData("OnDestroyAreName")
	if path then
		bullet:ShowBulletEffect(nil, path)
	end
end

function Gas2Gac:BulletDie(PipeId, uCharacterGlobalID)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end

	local path = bullet:GetData("OnDieAreName")
	if path then
		bullet:ShowBulletEffect(nil, path)
	end
end

local PropertyTbl = {}
function Gas2Gac:UpdateBulletProperty(PipeId, uCharacterGlobalID, DataString)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end
	
	msgpack.unpack(DataString, nil, PropertyTbl)
	local bulletData = bullet.m_BulletMoveData
	for k, v in pairs(PropertyTbl) do
		local strKey = EnumUpdateBulletPropertyMappingReverse[k]
		local key = strKey or k
		bulletData[key] = v
		bullet:OnPropertyUpdated(key, v)
	end
	table.clear(PropertyTbl)
end

function Gas2Gac:BulletShowFx(PipeId, uCharacterGlobalID)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end
	bullet:FxVisiable(true)
end

function Gas2Gac:BulletHideFx(PipeId, uCharacterGlobalID)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end
	bullet:FxVisiable(false)
end

function CClientBullet:GetOwner()
	return self.m_BulletMoveData.m_OwnerId and GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_OwnerId)
end



function Gas2Gac:BulletDestroyRemain(PipeId, uCharacterGlobalID, TargetId, Degree, Yaw)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then
		return
	end
	LOG_PRINT(DEBUG,"TODO Gas2Gac:BulletDestroyRemain")
end

function Gas2Gac:ClearMyRemainDestroyedBullet(PipeId, uCharacterGlobalID, bulletId)	
	local obj = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not obj then return end
	
	obj:ClearMyRemainDestroyBullet(bulletId)
end

function Gas2Gac:ReplayBulletFX(PipeId, uCharacterGlobalID, fLocalTime)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then 
		return 
	end
	LOG_PRINT(DEBUG,"TODO Gas2Gac:ReplayBulletFX")
end

function CClientBullet:GetLayer()
	return LayerDefine.LAYER_IGNORE_RAYCAST
end

function CClientBullet:IsMainPlayerJianQiBullet()
	return IdIsLongYinJianqiBulletId(self:GetBulletId()) and g_MainPlayer and self:GetOwner() == g_MainPlayer
end

function CClientBullet:IsMainPlayerBullet()
	return g_MainPlayer and self:GetOwner() == g_MainPlayer
end

function CClientBullet:CreateHeadInfo()
	-- 大部分Bullet没有头顶
	if not self:GetData("NeedHeadInfo") then return end
	CClientCharacter.CreateHeadInfo(self)

	local designData = Bullet_Bullet[self:GetBulletId()]
	local tabOffset = designData.HudOffsetParam
	if tabOffset then
		local hudWnd = self:GetHudWnd()
		  if hudWnd then
			  hudWnd:SetPosOffset(tabOffset[1] or 0, tabOffset[2] or 0, tabOffset[3] or 0)
		  end
	end
end

function CClientBullet:DestroyHeadInfo()
	-- 大部分Bullet没有头顶
	if not self:GetData("NeedHeadInfo") then return end
	CClientCharacter.DestroyHeadInfo(self)
end

---{{{龙吟惊雷气剑辅助施法处理 Begin
local LongYinJingLeiSkillCls = 917110
function CClientBullet:TryCreateLongYinQJBulletHudInteractive()
	if not self:IsMainPlayerJianQiBullet() then return end 
	if not g_Store.MainSkillDefaultView:__GetBtnNameBySkillCls(LongYinJingLeiSkillCls) then return end 
	local settingVal = g_MainPlayer:GetCharacterSetting(EnumCharacterSettings.LongYinQJSetting)
	if settingVal ~= 1 and settingVal ~= 2 then return end 
	if not (g_HudInteractive and g_HudInteractive:IsValid()) then return end 
	local skillId = g_MainPlayer:GetSkillByCls(LongYinJingLeiSkillCls)
	if not skillId then return end 
	
	local item = g_HudInteractive:GetHUDItem("HudLongyinskillItem")
	self.m_LongYinQJItem = item
	item.m_QJBulletEngineId = self.m_engineObjectId
	item:SafeCall("UpdatePos")
	item:SafeCall("UpdateStatus")
end

function CClientBullet:TryRemoveLongYinQJBulletHudInteractive()
	if self.m_LongYinQJItem and g_HudInteractive then 
		g_HudInteractive:ReturnHUDItem(self.m_LongYinQJItem)
	end
end
---}}}龙吟惊雷气剑辅助施法处理 End

function TryAddBulletCreateCnt(self) 
	if not g_MainPlayer then return end 
	local moveData = self.m_BulletMoveData
	if moveData.m_OwnerId == g_MainPlayer.m_engineObjectId then return end 

	local bulletId = self:GetSourceTemplateId() -- 这里需要用m_SourceTemplateId，m_BulletMoveData的BulletId可能中间切换
	local row, groupId = GetClientCreateNumControlData(bulletId)
	if not row then return end

	local owner = GetCharacterByEngineObjectGlobalId(moveData.m_OwnerId) or g_WaitingSyncMgr:GetWaitingSyncObject(moveData.m_OwnerId)
	bulletId = groupId or bulletId -- 有组id用组id
	if owner and g_MainPlayer:IsEnemy(owner) then 
		g_CreateEnemyBullet2Cnt[bulletId] = (g_CreateEnemyBullet2Cnt[bulletId] or 0) + 1
		self.m_IsEnemyBullet = 1
	else
		g_CreateNoEnemyBullet2Cnt[bulletId] = (g_CreateNoEnemyBullet2Cnt[bulletId] or 0) + 1
		self.m_IsEnemyBullet = 2
	end
end

function TrySubBulletCreateCnt(self)
	local bulletId = self:GetSourceTemplateId() -- 这里需要用m_SourceTemplateId，m_BulletMoveData的BulletId可能中间切换
	local row, groupId = GetClientCreateNumControlData(bulletId)
	bulletId = groupId or bulletId -- 有组id用组id

	if self.m_IsEnemyBullet == 1 then 
		local cnt = g_CreateEnemyBullet2Cnt[bulletId] - 1
		if cnt < 0 then cnt = 0 end

		g_CreateEnemyBullet2Cnt[bulletId] = cnt
	elseif self.m_IsEnemyBullet == 2 then
		local cnt = g_CreateNoEnemyBullet2Cnt[bulletId] - 1
		if cnt < 0 then cnt = 0 end

		g_CreateNoEnemyBullet2Cnt[bulletId] = cnt
	end
end

-- Style 预处理CharMod和Effect，主要是GetData里面会取Charmod
function LoadBulletStyle(bullet)
	local BulletDataId = bullet.m_BulletMoveData.m_BulletDataId
	local BulletSetting = Bullet_Appear[BulletDataId]
	local rootOwner = GetCharacterByEngineObjectGlobalId(bullet.m_RootOwnerId)
	if BulletSetting and rootOwner then 
		bullet.m_StyleEffect, bullet.m_StyleCharMod = EffectUtils_TryGetStyleAllPaths(rootOwner, BulletSetting.StyleSkillId, BulletSetting.StyleSkillFxId, BulletSetting.StyleSkillCharModId)
		-- print("Bullet 皮肤路径", rootOwner, BulletSetting.StyleSkillId, BulletSetting.StyleSkillFxId, BulletSetting.StyleSkillCharModId, BulletDataId)
		-- print("Bullet 皮肤路径", bullet.m_StyleEffect, bullet.m_StyleCharMod)
		-- print("Bullet CharacterDef", BulletSetting.CharacterDef)
	end
end

-- 特效不用ro
function CClientBullet:IsRequireRenderObject()
	return self:GetData("CharacterDef") or self:GetData("EnableFxAction")
end

function CClientBullet:CreateFruitBulletRO()
	if self.m_FruitBulletPlantObj then return end
	if not self.m_FruitId then return end
	local fruitData = self.m_FruitData
	if not fruitData or IsNilUserData(fruitData) then
		print("[PlantFarm][WARN] CreateFruitBulletRO no FruitData, bulletId=" .. tostring(self.m_engineObjectId))
		return
	end

	local fruitItem = CPlantItem:new()
	fruitItem:LoadFromString(fruitData)
	local templateId = fruitItem:GetTemplateId()
	if not templateId or templateId == 0 then
		print("[PlantFarm][WARN] CreateFruitBulletRO invalid FruitData, bulletId=" .. tostring(self.m_engineObjectId))
		return
	end

	local isMysterySeed = PlantingConfigHelper.IsMysterySeedItemId(templateId)
	local fruitTemplateId
	if isMysterySeed then
		fruitTemplateId = PlantingConfigHelper.GetSeedIdByItemId(templateId)
	else
		fruitTemplateId = EnumPlantingItem2Fruit[templateId]
	end
	if not fruitTemplateId then
		print("[PlantFarm][WARN] CreateFruitBulletRO no fruit template, templateId=" .. tostring(templateId))
		return
	end

	local bulletEngineId = self.m_engineObjectId
	local onResLoaded = function(plantObj, ro)
		local bullet = GetCharacterByEngineObjectGlobalId(bulletEngineId)
		if not bullet or bullet.m_Destroying or not ro then
			if ro and ro.Destroy then
				ro:Destroy()
			end
			return
		end

		if bullet.m_RenderObject and bullet.m_RenderObject ~= ro then
			bullet:DestroyRenderObject()
		end

		ro:SetLayer(LayerDefine.LAYER_NPC)
		bullet.m_RenderObject = ro
		bullet.m_FruitBulletPlantObj = plantObj
		bullet:OnFruitBulletROLoaded()
	end

	local plantObj = CClientPlantingRO:new()
	plantObj:Init(fruitTemplateId)
	plantObj:SetPropFromPlantItemExtra(fruitItem:GetExtraData())
	plantObj:SetResLoadCallback(onResLoaded)
	self.m_FruitBulletPlantObj = plantObj
	if isMysterySeed then
		local assetPath = PlantingConfigHelper.GetFruitHandHeldAssetPath(templateId)
		plantObj:LoadResource(assetPath)
	else
		plantObj:LoadResource()
	end
end

function CClientBullet:OnFruitBulletROLoaded()
	self.m_bResLoaded = true
	self.m_bResLoading = false
	if self.m_RenderObject then
		self:InitLayer()
		self.m_RenderObject:SetLayer(LayerDefine.LAYER_NPC)
		if self.m_RenderObject.CreateAABB then
			self.m_RenderObject:CreateAABB(false)
		end
		if self.m_engineObject then
			local dir = -self.m_engineObject:GetDirectionDegree() + 90
			self.m_RenderObject:Set360DegreeDirection(dir)
			if g_Open3DRotate then
				local directionX = self.m_engineObject:GetDirectionDegreeX()
				local directionY = self.m_engineObject:GetDirectionDegreeY()
				if directionX ~= 0 or directionY ~= 0 then
					if self.m_RenderObject.SetRotationByEulerAngle then
						self.m_RenderObject:SetRotationByEulerAngle(directionX, dir, directionY)
					else
						self.m_RenderObject:SetRotationByQuat(CS.UnityEngine.Quaternion.Euler(directionX, dir, directionY))
					end
				end
			end
		end
		self:RefreshROPosition(true, true)
		self:RefreshROVisible()
	end
	self:CheckAndFollowOwnerVisible()
	self:CheckAndFollowOwnerGuajie()
end

function CClientBullet:OnResLoaded()
	if OPTIMIZE_MODE_EX_BULLET then
		self:_OnResLoaded_()
	else
		CFollowerCharacter.OnResLoaded(self)
	end
	
	local moveData = self.m_BulletMoveData
	if moveData.m_DirZ then 
		self:RefreshBulletRotationByDirZ(moveData.m_DirZ, self:GetData("Is2DDir") == 1)
	end

	if self.m_RenderObject then
		local bulletScale = self:GetData("BulletScale")
		if bulletScale then
			self.m_RenderObject:SetScale(bulletScale, bulletScale, bulletScale)
		end

		self:ProcessSummonAccessories()
	end

	self:CheckAndFollowOwnerVisible()
	self:CheckAndFollowOwnerGuajie()

	-- 潮光的海豚隐显处理
	if self:GetTemplateId() == 800371 then
		local pet = {
			EngineId = self:GetEngineObjectGlobalId(),
			OwnerId = self.m_OwnerId,
		}
		g_OtherPlayer_Pet[pet.EngineId] = pet

		-- ro类型调整为pet，适配全局屏蔽逻辑
		if self.m_RenderObject then
			self.m_RenderObject:SetObjLuaType(EObj_Lua_Type.OLT_PET)
		end
	
		self:StartUpdateSelfByOwner()
	end
	
	local bulletData = self.m_BulletMoveData
	self:RefreshReplaceClassByCharacterDef(bulletData and bulletData.m_ReplaceClassByCharacterDef)
	self:CheckAndApplyBulletDyeColor()
end

function CClientBullet:InitRenderObject()
	self:InitRenderObject_OnSceneLoaded()
end

function CClientBullet:InitRenderObject_OnSceneLoaded()
	if not self.m_NeedCreate then
		return
	end

	LoadBulletStyle(self)

	if self:IsRequireRenderObject() then
		CFollowerCharacter.InitRenderObject(self)
	end

	-- ro
	local bulletScale = self:GetData("BulletScale")
	if self.m_RenderObject and bulletScale then
		self.m_RenderObject:SetScale(bulletScale, bulletScale, bulletScale)
	end

	-- StartTime
	local fStartTime = type(self.m_BulletMoveData.m_NewBorn) == "number" and self.m_BulletMoveData.m_NewBorn or 0
	fStartTime = (fStartTime + GetProcessTime() - self.m_ClientBornTime) / 1000

	local fScaleX, fScaleY, fScaleZ

	-- 玄机刀片替换
	local weaponPath
	if self.m_UseWeaponCharDef_WeaponId and self.m_UseWeaponCharDef_WeaponId ~= 0 and self.m_UseWeaponCharDef_Index == 1 then
		weaponPath = table.safe_get(FashionClothes_Fashion, self.m_UseWeaponCharDef_WeaponId, "OverrideCharacterDef1")
		-- print("玄机武器刀片", weaponPath)
	end

	local fxId = self:GetData("FxID")
	local fxScale = self:GetData("FxScale")
	local path = self:GetData("AreName")
	self.m_FxId = nil
	if fxId then
		local fxData = Fx_TargetFx[fxId]
        if fxScale then
            fScaleX, fScaleY, fScaleZ = fxScale, fxScale, fxScale
		elseif fxData.Scale then
            fScaleX, fScaleY, fScaleZ = fxData.Scale[1], fxData.Scale[2], fxData.Scale[3]
        end
		fStartTime = fStartTime + (fxData.StartTime or 0)

		if self:GetData("FxUseOffset") then
			local pos = fxData.Position
			if pos then
				self.m_FxOffsetX, self.m_FxOffsetY, self.m_FxOffsetZ = pos[1] * pixel_per_grid, pos[3] * pixel_per_grid, pos[2] * pixel_per_grid
			end
		end

		local fHue, fSat, fBright, fWeight, effectClipTag = fxData.FxEffectHue, fxData.FxSaturate, fxData.FxBright, fxData.FxWeight, 0

		local rootOwner = GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId)

		local stylePath = self.m_StyleEffect
		if not stylePath then
			stylePath, fHue, fSat, fBright, fWeight, effectClipTag = EffectUtils_ApplyLogicReplace(rootOwner, nil, nil, fxId, fxData.FxName, fxData.LogicReplaceRule, fHue, fSat, fBright, fWeight, effectClipTag)
		end

		self:ShowBulletEffect(self.m_engineObjectId, GetTargetFxPath(GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId), fxId), stylePath, fScaleX, fScaleY, fScaleZ, fStartTime, fHue, fSat, fBright, fWeight, self.m_ReplaceTexPath, self.m_ReplaceRendererIdx, weaponPath, effectClipTag)

		if fxData.ExtraFx then
			self.m_FxId = fxId
			self:_PlayBulletExtraFx(fxData.ExtraFx, self.m_engineObjectId, self.m_StyleEffect, fxScale, fStartTime, rootOwner)
		end
	elseif path then
		if bulletScale then fScaleX, fScaleY, fScaleZ = bulletScale, bulletScale, bulletScale end
		
		self:ShowBulletEffect(self.m_engineObjectId, path, self.m_StyleEffect, fScaleX, fScaleY, fScaleZ, fStartTime, nil, nil, nil, nil, self.m_ReplaceTexPath, self.m_ReplaceRendererIdx, weaponPath)
	end

	self:CheckAndFollowOwnerVisible()
	self:CheckAndFollowOwnerGuajie()
	self:UpdateEffectVisible()
	self:CreateFruitBulletRO()
end

function CClientBullet:CheckAndFollowOwnerVisible()
	local sceneId = g_SceneDesignID
	local designData = Gameplay_CharacterVisibleInMap[sceneId] --目前只限定在某些副本生效
	if designData and designData.ClientVisibleFormula then 
		local owner = self.m_RootOwnerId and GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId)
		if owner then
			self:SetROVisible(owner:IsROVisible())
			self:FxVisiable(owner:IsROVisible())
		end
	end
end

function CClientBullet:CheckAndFollowOwnerGuajie()
	local owner = GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId)
	if not owner then return end
	if g_StatusMgr:GetStatus(owner, EPropStatus.HavokGuaJieMulti) == 1 then
		local Id2GuajieId = g_StatusMgr:GetAttribute(owner, EPropStatus.HavokGuaJieMulti, "Id2GuajieId")
		for id, guajieId in Id2GuajieId:Pairs() do
			if id == self.m_engineObjectId then
				owner:OnEnter_HavokGuaJieMulti()
				return
			end
		end
	end
end

function CClientBullet:RegisterBulletEffect(nLogicHash)
	if not nLogicHash then nLogicHash = cEffectMgr:GenerateRuntimeGuid() end

	table.insert(self.m_EffectList, nLogicHash)

	return nLogicHash
end

function CClientBullet:GetBulletEffectOffset()
    local x, y, z = self.m_FxOffsetX, self.m_FxOffsetY, self.m_FxOffsetZ
    if x and y and z then
        local dir = self.m_engineObject:GetDirectionDegree()
        x, y = XYRotateDegree(x, y, dir)
        return x, y, z
    end
end

function CClientBullet:ShowBulletEffect(nLogicHash, path, stylePath, fScaleX, fScaleY, fScaleZ, fStartTime, fHue, fSaturate, fBright, fWeight, replaceTex, replaceRendererIdx, weaponPath, effectClipTag)
	if not path then return end

	nLogicHash = self:RegisterBulletEffect(nLogicHash)

	-- print(self, self.m_BulletMoveData.m_OwnerId, self.m_BulletMoveData.m_RootOwnerId, self.m_BulletMoveData.m_RootOwnerCharacterType)
	local player = GetCharacterByEngineObjectGlobalId(self.m_RootOwnerId)
	local playerType = EffectUtils_GetPlayerTypeRootOwner(self.m_RootOwnerId, self.m_RootOwnerCharacterType)
	local x, y, z = self.m_engineObject:GetPixelPosv3()
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	replaceTex = replaceTex ~= "" and replaceTex or nil
	local ox, oy, oz = self:GetBulletEffectOffset()
	if ox and oy and oz then
		x, y, z = x + ox, y + oy, z + oz
	end
	
	renderObject:PlayBulletEffect(nLogicHash, path, player and player:GetRenderObject(), playerType,
		x/64, z/64, y/64, fScaleX or 1, fScaleY or 1, fScaleZ or 1, fHue or -1, fSaturate or 1, fBright or 1, fWeight or 1, fStartTime or 0, stylePath, replaceTex, replaceRendererIdx, weaponPath, effectClipTag)

	if HasFeature("Common_411") then
		local timeScale = self:GetTimeScale()
		if timeScale ~= 1 then
			renderObject:SetEffectSpeed(nil, self:GetTimeScale(), nLogicHash)
		end
	end
end

function CClientBullet:_PlayBulletExtraFx(fxId, parentHash, stylePath, bulletFxScale, baseStartTime, rootOwner)
	local fxData = Fx_TargetFx[fxId]
	if not fxData then return end

	local path = GetTargetFxPath(rootOwner, fxId)
	if not path then return end

	local extraHash = parentHash + fxId
	local fScaleX, fScaleY, fScaleZ
	if bulletFxScale then
		fScaleX, fScaleY, fScaleZ = bulletFxScale, bulletFxScale, bulletFxScale
	elseif fxData.Scale then
		fScaleX, fScaleY, fScaleZ = fxData.Scale[1], fxData.Scale[2], fxData.Scale[3]
	end

	self:ShowBulletEffect(extraHash, path, stylePath,
		fScaleX, fScaleY, fScaleZ,
		(baseStartTime or 0) + (fxData.StartTime or 0),
		fxData.FxEffectHue, fxData.FxSaturate, fxData.FxBright, fxData.FxWeight)

	if fxData.ExtraFx then
		self:_PlayBulletExtraFx(fxData.ExtraFx, extraHash, stylePath, bulletFxScale, baseStartTime, rootOwner)
	end
end

function CClientBullet:RemoveAllEffects(ignoreLoop)
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	local forceRemoveLoopEffect = ignoreLoop or false
	for k,v in ipairs(self.m_EffectList) do
		renderObject:RemoveEffect(nil, forceRemoveLoopEffect, v)
	end
	table.clear(self.m_EffectList)
end

function CClientBullet:FxVisiable(bVisiable)
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()

	renderObject:SetEffectVisible(nil, bVisiable, self.m_engineObjectId)

	local fxId = self.m_FxId
	if fxId then
		local hash = self.m_engineObjectId
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			renderObject:SetEffectVisible(nil, bVisiable, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
end

function CClientBullet:LateOnChangePosition(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	self:DoPositionChangeCallback(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	if not self.m_NeedCreate then
		if g_MainPlayer and GetPixelDistance(g_MainPlayer, self) < g_OptCreateBulletDist * pixel_per_grid then
			self.m_NeedCreate = true
			self:InitRenderObject()
		else
			return
		end
	end

	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	local ox, oy, oz = self:GetBulletEffectOffset()
	local ex, ey, ez = X + (ox or 0), Y + (oy or 0), Z + (oz or 0)
	renderObject:ResetEffectPosition(nil, ex / pixel_per_grid, ez / pixel_per_grid, ey / pixel_per_grid, self.m_engineObjectId)

	local fxId = self.m_FxId
	if fxId then
		local hash = self.m_engineObjectId
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			renderObject:ResetEffectPosition(nil, ex / pixel_per_grid, ez / pixel_per_grid, ey / pixel_per_grid, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
	self:TryAddOrUpdatePositionTerrainInteractPoint(ex / pixel_per_grid, ez / pixel_per_grid, ey / pixel_per_grid)	

	CClientBullet._LateOnChangePosition(self, OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	self:HitClientNpcCheck(OldX, OldY, OldZ, X, Y, Z)
	self:BulletHitCheck(OldX, OldY, OldZ, X, Y, Z)
end

function CClientBullet:_LateOnChangePosition_UpdateRotation(OldX, OldY, OldZ, X, Y, Z, bulletData)
    if not bulletData then return end
    if self.m_BulletMoveIsIgnoreUpdateMoveDir then return end

    -- 服务器一次性校准 dir 后，跳过紧随其后的这次位移驱动覆盖；之后恢复正常逻辑
    if self.m_BulletDirSkipNextRotation then
        self.m_BulletDirSkipNextRotation = nil
        return
    end

    local diffX = X - OldX
    local diffY = Y - OldY
    local diffZ = Z - OldZ
    if abs(diffX) > 1 or abs(diffY) > 1 or abs(diffZ) > 1 then
        self:UpdateBulletMovePhysics(OldX, OldY, OldZ, X, Y, Z)
    end

    local trackTargetId = bulletData and bulletData.m_DirTrackTargetId
    if trackTargetId then
        local target = GetCharacterByEngineObjectGlobalId(trackTargetId)
        if target then
            local tx, ty, _tz = target.m_engineObject:GetPixelPosv3()
            local yaw = math.atan2(ty - Y, tx - X)
			-- 不track俯仰角，保持dirz的俯仰角
            local dirZ = bulletData.m_DirZ or 0
            local dxy = math.sqrt(1 - dirZ * dirZ)
            local dx = math.cos(yaw) * dxy
            local dy = dirZ
            local dz = math.sin(yaw) * dxy
            self:SetBulletRotation(dx, dy, dz)
            return
        end
    end

    if abs(diffX) > 1 or abs(diffY) > 1 or abs(diffZ) > 1 then
        if self.m_BulletMoveIs2DDir == 1 then
            self:SetBulletRotation(diffX, 0, diffY)
        elseif self.m_BulletMoveIs2DDir == 2 then
            local yaw = math.atan2(diffY, diffX)
            local dirZ = bulletData.m_DirZ or 0
            local dxy = math.sqrt(1 - dirZ * dirZ)
            local dx = math.cos(yaw) * dxy
            local dy = dirZ
            local dz = math.sin(yaw) * dxy
            self:SetBulletRotation(dx, dy, dz)
        else
            self:SetBulletRotation(diffX, diffZ, diffY)
        end
    end
end

g_LateOnChangePositionOpt_Bullet = true
function CClientBullet:_LateOnChangePosition(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	if not g_LateOnChangePositionOpt_Bullet then
		CClientCharacter.LateOnChangePosition(self, OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
		return
	end

	self:OnSmartKeyPositionChange(X, Y, Z)

	--刷新子弹运动对象朝向, 子弹可能没有ro, 也需要调用
	local bulletData = self.m_BulletMoveData
	self:_LateOnChangePosition_UpdateRotation(OldX, OldY, OldZ, X, Y, Z, bulletData)

	if not self.m_RenderObject then
        return 
	end
	if self:PositionRelyOnAttach() then 
		return 
	end
	local bWaterMove = false
	if self.m_IsWalkOnWater or self.m_IsWaterRide or self.m_IsWaterCarrier then
		bWaterMove = true
	end

	-- if (not g_LateOnChangePositionOpt) or (self:IsMainPlayerBullet()) then
	if (not g_LateOnChangePositionOpt) or (not g_MainPlayer.m_IsFighting) then
		--非主角的子弹为ture时走原有逻辑
		self:_LateOnChangePosition_Default(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling, bWaterMove)
	else
		--否则走战斗简化逻辑
		self:_LateOnChangePosition_Fighting(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	end
end

function CClientBullet:_LateOnChangePosition_Fighting(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, isFlying, isFalling)
	self.m_RenderObject:UpdateMoveStat(isFalling, isFlying, false, false, false, 0)
	local ux, uy, uz = X / pixel_per_grid, Z / pixel_per_grid, Y / pixel_per_grid
	if OPTIMIZE_MODE_EX_BULLET then
		if IsMicroPipelineEnabledByLuaTaskId(EMicroPipelineLuaTaskId.BATCH_WATER_QUERY, self) then
			-- MicroPipeline Task 化路径：写入 g_BatchPosResult，由 Worker 预计算 bCheckWater
			local idx = g_BatchPosResultCount + 1
			local item = g_BatchPosResult[idx]
			if not item then
				item = table.new(0, 10)
				g_BatchPosResult[idx] = item
			end
			item.ro                  = self.m_RenderObject
			item.ux                  = ux
			item.uy                  = uy
			item.uz                  = uz
			item.bOnCollide          = not (isFalling or isFlying)
			item.isBullet            = true
			item.bCheckWater         = false  -- Worker 覆写
			item.precomputedWaterY   = 1000001  -- Worker 覆写
			item.precomputedMaxWaterDepth = 0   -- Worker 覆写
			g_BatchPosResultCount = idx
		else
			self.m_RenderObject:SetPosition2_V2(ux, uy, uz, not (isFalling or isFlying), SPType, bOnDynamicGrid_NoObject, nil, true, self.m_MyPlatformId and true or false, 0, true, not g_WaterMgr:IsSceneUnityPosAbsolutelyNoWater_Cache(ux, uz))
		end
	else
		self.m_RenderObject:SetPosition2(ux, uy, uz, not (isFalling or isFlying), SPType, bOnDynamicGrid_NoObject, nil, true, self.m_MyPlatformId and true or false)
	end
end

function CClientBullet:SetBulletRotation(dx, dy, dz)
	if OPTIMIZE_MODE_EX_BULLET then
		self:SetBulletRotation_New(dx, dy, dz)
		return
	end
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	renderObject:ResetEffectLookRotation(nil, dx, dy, dz, self.m_engineObjectId)

	local fxId = self.m_FxId
	if fxId then
		local hash = self.m_engineObjectId
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			renderObject:ResetEffectLookRotation(nil, dx, dy, dz, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end

	if self.m_RenderObject then
		CClientCharacter.SetBulletRotation(self, dx, dy, dz)
	end
end

function CClientBullet:SetBulletRotation_New(dx, dy, dz)
	local effectRo = g_ClientEffectMgr:GetEffectRenderObject()
	effectRo:ResetEffectLookRotation(nil, dx, dy, dz, self.m_engineObjectId)

	local fxId = self.m_FxId
	if fxId then
		local hash = self.m_engineObjectId
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			effectRo:ResetEffectLookRotation(nil, dx, dy, dz, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
	local bulletData = self.m_BulletMoveData
	local selfRo = self.m_RenderObject
	if not selfRo then
		return
	end
	if bulletData and bulletData.m_RotX and bulletData.m_RotY and bulletData.m_RotZ then
		if g_StatusMgr:HasStatus_Unsafe(self, EPropStatus.BezierSplineMove) then
			selfRo:SetRotationByEulerAngle(bulletData.m_RotX, bulletData.m_RotY, bulletData.m_RotZ)
		end
	elseif dx and dy and dz then
		selfRo:SetRotationDiffWithNoParent(dx, dy, dz)
	end
end

function Gas2Gac:BindExistEffect(PipeId, BulletID, PlayerID, LogicName, BindEffectBullet)
	local bullet = GetCharacterByEngineObjectGlobalId(BulletID)
	if bullet then
		local nLogicHash = bullet.m_engineObjectId

		if BindEffectBullet then
			local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
			cEffectMgr:BulletBindExistEffect(nLogicHash, renderObject, PlayerID..LogicName)
			bullet:RegisterBulletEffect(nLogicHash)
		else
			local obj = GetCharacterByEngineObjectGlobalId(PlayerID)
			local renderObject = obj:GetRenderObject()
			if renderObject then
				cEffectMgr:BulletBindExistEffect(nLogicHash, renderObject, LogicName)
				bullet:RegisterBulletEffect(nLogicHash)
			end
		end
	end
end

function CClientBullet:IsHitPosCorrect()
	return self.m_IsHitPosCorrect
end

function Gas2Gac:BulletHitPosCorrect(PipeId, uCharacterGlobalID, TargetId)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then return end
	local target = GetCharacterByEngineObjectGlobalId(TargetId)
	if not (target and target.m_bResLoaded) then return end
	local targetRo = target:GetRenderObject()
	if not targetRo then return end 
	local r = targetRo:GetBoxColliderRadius4Bullet() * pixel_per_grid
	if r <= 0 then 
		return 
	end
	local tb = bullet._m_ChangePositionTbl
	if not (tb.OldX and tb.X and bullet.m_BulletMoveData) then 
		return 
	end

	local tx, ty = target.m_engineObject:GetPixelPosv()
	local bx, by = tb.X, tb.Y
	local btx, bty = bx - tx, by - ty
	local dist = math.sqrt(btx * btx + bty * bty)
	if math.abs(dist) < 1 then
		return
	end
	local nx, ny = btx / dist * r + tx, bty / dist * r + ty
	local ox, oy = tb.OldX, tb.OldY
	local box, boy = bx - ox, by - oy
	local nox, noy = nx - ox, ny - oy
	local b = math.sqrt((box * box + boy * boy) * (nox * nox + noy * noy))
	if b < 0.0001 then 
		return 
	end
	local a = box * nox + boy * noy
	local deg = math.deg(math.acos(a / b))
	local maxDeg = GameSetting_Client.BULLET_HIT_POS_CORRECT_MAX_DEGREE.numVal
	if deg > maxDeg then 
		return
	end
	
	bullet.m_IsHitPosCorrect = true
	local ro = bullet:GetRenderObject()
	local effectList = bullet.m_EffectList
	bullet.m_EffectList = {}
	
	bullet:LateOnChangePosition(nx, ny, bullet.m_BulletMoveData.m_CurZ, nx, ny, bullet.m_BulletMoveData.m_CurZ, 0, false, false, false)
	RegisterTickWithDuration(function() 
		if ro then
			if g_SceneLoadingMgr:IsRODelayDestroy() then
				g_SceneLoadingMgr:AddDelayDestroyRO(ro)
			else
				ro:Destroy()	
			end
		end
		local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
		for k,v in pairs(effectList or EMPTY_TABLE)  do
			renderObject:RemoveEffect(nil, false, v)
		end
	end, 100, 100)
end

--这边定义不需要清的数据,
local __no_clear_keys = 
{
	["m_EngineObjHandler"] = true,
	["m_RenderObjectLuaType"] = true,
	["m_NameColor"] = true,
}
function CClientBullet:OnReturnToPool(...)
	if self.m_BulletMoveData then
		NewBulletMoveDataToObj(self)
	end
	if false then
		--可以如下调用PrintClassInstanceKVBeforeReturnToPool()查看OnReturnToPoolDefault中
		---即将要被清的key,value以及不会被清的key，value
		PrintClassInstanceKVBeforeReturnToPool(self, __no_clear_keys)
	end

	OnReturnToPoolDefault(self, __no_clear_keys, ...)
	--额外需要清的数据写这里，比如Ctor里初始化的某些key确定后面用不到了，需要置nil
end

function CClientBullet:OnReuseFromPool()
	OnReuseFromPoolDefault(self)
	--额外的一些初始化逻辑写这里
end

function Gas2Gac:BulletHitTarget(PipeId, uCharacterGlobalID, TargetId)
	local bullet = GetCharacterByEngineObjectGlobalId(uCharacterGlobalID)
	if not bullet then return end

	local target = GetCharacterByEngineObjectGlobalId(TargetId)
	if not target then return end

	MsgHub_GacBulletHitTarget:Emit(bullet, target)
end


function Gas2Gac:BulletMoveDebugDraw(PipeId, bIfHit, BulletId, TemplateId, CurPosX, CurPosY, CurPosZ, Radius, BulletZAbove, BulletZBelow)
	local bulletId = BulletId
	local templateId = TemplateId
	local curPos = CS.UnityEngine.Vector3(CurPosX / EnumGlobalConstants.PIXEL_PER_GRID, CurPosZ / EnumGlobalConstants.PIXEL_PER_GRID, CurPosY / EnumGlobalConstants.PIXEL_PER_GRID)
	local radius = Radius 
	local yBiasAbove = BulletZAbove 
	local yBiasBelow = BulletZBelow
	local bulletObj = GetCharacterByEngineObjectGlobalId(bulletId)

	local owner = bulletObj:GetOwner()
	local ownerName = owner and owner:GetName() or "nil"
	local ownerRenderObj = owner and owner:GetRenderObject()
	local ownerRenderObjTransform = ownerRenderObj and ownerRenderObj.transform
	
	local selfName = bulletObj:GetName()

	CS.SkillScopeExpressionEditor.DebugDrawReachTunnel.RequestBulletMoveDraw(bIfHit, bulletId, templateId, selfName, ownerName, curPos, ownerRenderObjTransform, radius, yBiasAbove, yBiasBelow)
	
end

-- {{{ 服务器子弹解挂资源对象

function CClientBullet:TryDetachBulletEffect()
	local ret = nil

	for k,v in ipairs(self.m_EffectList) do
		if v == self.m_engineObjectId then
			ret = k
			break
		end				
	end

	if ret then 
		table.remove(self.m_EffectList, ret)
	end
end

function Gas2Gac:TakeplateClientBulletTaiji(PipeId, BulletId, OwnerId, Dx, Dy, Dz, LifeTime, RotSpeed)
	local bullet = GetCharacterByEngineObjectGlobalId(BulletId)
	local owner = GetCharacterByEngineObjectGlobalId(OwnerId)
	local ro = owner and owner:GetRenderObject()
	if bullet and ro then 
		bullet:TryDetachBulletEffect()
		cEffectMgr:CreateClientBulletTaiji(ro, BulletId, Dx, math.clamp(Dz, -0.3, 0.3), Dy, LifeTime, RotSpeed)
	end
end

-- }}} 服务器子弹解挂资源对象

function CClientBullet:UpdateOceanLegoWalkStatus()
end

function CClientBullet:CheckExplorePuzzleTag()
end

function CClientBullet:OnLuaObjectCreated()
	CFollowerCharacter.OnLuaObjectCreated(self)

	local moveData = self.m_BulletMoveData
	if moveData.m_Status == 1 then
		self:AdjustBulletMoveInitPos(moveData, self:GetData("BulletLocal"))
	end
	if moveData.m_DirZ then 
		self:RefreshBulletRotationByDirZ(moveData.m_DirZ, self:GetData("Is2DDir") == 1)
	end
	local bulletDesign = Bullet_Bullet[moveData.m_BulletDataId]
	self.m_BulletMoveIsIgnoreUpdateMoveDir = nil
	if bulletDesign and bulletDesign.IgnoreUpdateMoveDir == 1 then 
		self.m_BulletMoveIsIgnoreUpdateMoveDir = true
	end

	if bulletDesign and bulletDesign.CollisionBuildingFixOff then
		self.m_BulletCollisionFixOff = bulletDesign.CollisionBuildingFixOff * 64
	else
		self.m_BulletCollisionFixOff = nil
	end
end

function CClientBullet:GetTemplateId()
	return self:GetBulletId()
end

function CClientBullet:HitClientNpcCheck(_, _, _, x, y, z)
	if not self:IsMainPlayerBullet() then
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

--region 怪物子弹客户端命中

local __CLIENT_BULLET_HIT_LOG_ENABLED = IsInnerClient()
local function __LogClientBulletHit(step, bullet, fmt, ...)
	if not __CLIENT_BULLET_HIT_LOG_ENABLED then return end
	if not bullet or bullet:GetData("ClientHit") ~= 1 then return end
	local bulletId = bullet:GetBulletId()
	local owner = bullet:GetOwner()
	local ownerName = owner and owner:GetName() or "Unknown"
	local msg = string.format("[ClientBulletHit-%s] Bullet[%d] Owner[%s]" .. (fmt and (" " .. fmt) or ""),
		step, bulletId, ownerName, ...)
	print(msg)
end

function CClientBullet:BulletHitCheck(oldX, oldY, oldZ, x, y, z)
	if not g_BulletClientHitEnabled then
		return
	end
	if self:GetData("ClientHit") ~= 1 then
		return
	end

	-- 只处理怪物子弹，owner 不存在或非怪物则跳过
	local owner = self:GetOwner()
	if owner and not owner.m_IsMonster then
		return
	end

	if not g_MainPlayer or not g_MainPlayer.m_IsValid or not g_MainPlayer.m_engineObject then
		return
	end

	local targetId = g_MainPlayer.m_engineObjectId
	local now = g_App:GetFrameTime()

	-- CD 与服务器 m_LastHitTimeTb 保持一致，均为 1000ms
	if self.m_ReportedClientHitTargets then
		local lastHitTime = self.m_ReportedClientHitTargets[targetId]
		if lastHitTime and now - lastHitTime < 1000 then
			return
		end
	end

	-- 用引擎矩形查询检测子弹路径上的对象（正确处理 Z 轴和碰撞体形状）
	local dx, dy = x - oldX, y - oldY
	local lenSq = dx * dx + dy * dy
	if lenSq < 1 then return end
	local len = math.sqrt(lenSq)
	local hitRadius = self:GetData("HitRadius") or 64

	-- 将 mainplayer 投影到子弹路径坐标系，判断是否在矩形范围内
	local mx, my = g_MainPlayer.m_engineObject:GetPixelPosv()
	local pmx, pmy = mx - oldX, my - oldY
	local forward = (pmx * dx + pmy * dy) / len   -- 沿路径方向的投影
	local side = math.abs((-pmx * dy + pmy * dx) / len)  -- 垂直路径方向的偏移
	if forward >= 0 and forward <= len and side <= hitRadius then
		__LogClientBulletHit("Detect", self, "Target[%d] Pos=(%.0f,%.0f,%.0f)", targetId, x, y, z)
		self:DoReportBulletHit(targetId, x, y, z)
	end
end

local _BulletClientHitSkillContext = {}
function CClientBullet:DoReportBulletHit(targetId, hitX, hitY, hitZ)
	if not self.m_ReportedClientHitTargets then
		self.m_ReportedClientHitTargets = {}
	end
	self.m_ReportedClientHitTargets[targetId] = g_App:GetFrameTime()

	local owner = self:GetOwner()
	local target = GetCharacterByEngineObjectGlobalId(targetId)
	local missRet
	if owner and target then
		local bulletId = self:GetBulletId()
		local bulletData = Bullet_Bullet[bulletId]
		local onHitSkill = bulletData and bulletData.OnHitSkill or 0
		if onHitSkill > 0 then
			_BulletClientHitSkillContext.Cls = onHitSkill
			_BulletClientHitSkillContext.Id = onHitSkill * 100 + 1
			missRet = g_SkillMgr:_ClientSkillHit_CalcMiss(owner, target, _BulletClientHitSkillContext)
		end
	end

	local extraArgs = {
		targetId = targetId,
		hitX = hitX,
		hitY = hitY,
		hitZ = hitZ,
		ClientHitResult = missRet,
	}
	__LogClientBulletHit("Report", self, "->Gac2Gas:BulletHit Target[%d] missRet<%s>", targetId, missRet or "nil")
	Gac2Gas:BulletHit(g_Conn, self.m_engineObjectId, msgpack.pack(extraArgs))
	-- 立即在本地触发命中事件，驱动客户端命中特效（不等待服务器 BulletHitTarget 回包）
	-- 记录已本地触发，防止服务器回包时重复播放

	if target then
		MsgHub_GacBulletHitTarget:Emit(self, target)
	end

	self:DoClientHitAction(target, hitX, hitY, hitZ)

	if self:GetData("OnHitDestroy") == 0 then
		self:Destroy()
	end
end

local _DoClientHitActionSourceInfo = {}
function CClientBullet:DoClientHitAction(target, hitX, hitY, hitZ)
	local bulletId = self:GetBulletId()
	local func = GetFormulaFunc("Bullet_Bullet", bulletId, "ClientHitAction")
	local owner = self:GetOwner()
	if func then
		_DoClientHitActionSourceInfo.Bullet = self
		_DoClientHitActionSourceInfo.HitX = hitX
		_DoClientHitActionSourceInfo.HitY = hitY
		_DoClientHitActionSourceInfo.HitZ = hitZ
		g_ActionMgr:DoActionReturnCtx(owner, target, _DoClientHitActionSourceInfo, func)
	end
end

--endregion 怪物子弹客户端命中

function CClientBullet:DoHitClientNpc(npcId, npcEngineId)
	if IsLanDuWaterBullet(self:GetBulletId()) then
		local npc = GetObjectByGlobalId(npcEngineId)
		if not npc then
			return
		end
		if table.safe_get(self.m_BulletMoveData, "m_TargeterEngineObjectId") == self.m_BulletMoveData.m_OwnerId then
			npc:FlowchartCustomEvent("OnBulletHitClientNpc_ComeBack", self:GetTemplateId(), self.m_engineObjectId, self.m_BulletMoveData.m_OwnerId)
		else
			npc:FlowchartCustomEvent("OnBulletHitClientNpc", self:GetTemplateId(), self.m_engineObjectId, self.m_BulletMoveData.m_OwnerId)
		end
		--npc:SetROVisible(false)
		if self:GetData("MultiHitClientNpc") ~= 1 then
			npc.m_ExtraData.IsHit = true
		end
		local guid = npc:GetGUID()
		local data = PublicMap_ext_PureClientNpc[guid]
		if not data then
			return
		end
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
		if hitCount <= 1 then
			extraArgs.isStart = true
		end
		if self:GetData("MultiHitClientNpc") ~= 1 then
			self.m_IsHitClientNpc = true
		end
		Gac2Gas:BulletHitClientNpc(g_Conn, self.m_engineObjectId, msgpack.pack(extraArgs))
		local hideNpc = self:GetData("HitHideClientNpc")
		if hideNpc and hideNpc[npcId] then
			npc:SetROVisible(false)
		end
		return
	end
end

function Gas2Gac:UpdateBulletRotation(_, engineId, x, y, z)
	local bullet = GetCharacterByEngineObjectGlobalId(engineId)
	if not bullet then return end
	local moveData = bullet.m_BulletMoveData
	local dirTrackTargetId = moveData and moveData.m_DirTrackTargetId
	if dirTrackTargetId and dirTrackTargetId ~= 0 or bullet.m_BulletMoveIs2DDir == 2 then
		return
	end
	bullet:SetBulletRotation(x, z, y)
	-- 服务器一次性校准：标记下一次 _LateOnChangePosition_UpdateRotation 跳过位移驱动覆盖
	bullet.m_BulletDirSkipNextRotation = true
end

function Gas2Gac:BulletRemoveAllEffects(PipeId, EngineObjectId, IgnoreLoop)
	local bullet = EID2OBJ(EngineObjectId)
	if not bullet or not bullet.m_IsBullet then return end
	bullet:RemoveAllEffects(IgnoreLoop)
end

function CClientBullet:BulletEffectScale(ScaleX, ScaleY, ScaleZ)
	local ro = g_ClientEffectMgr:GetEffectRenderObject()
	ro:ResetEffectScale(nil, ScaleX, ScaleY, ScaleZ, self.m_engineObjectId)

	local fxId = self.m_FxId
	if fxId then
		local hash = self.m_engineObjectId
		local fxData = Fx_TargetFx[fxId]
		while fxData and fxData.ExtraFx do
			hash = hash + fxData.ExtraFx
			ro:ResetEffectScale(nil, ScaleX, ScaleY, ScaleZ, hash)
			fxData = Fx_TargetFx[fxData.ExtraFx]
		end
	end
end

function Gas2Gac:BulletSetEffectScale(PipeId, Id, ScaleX, ScaleY, ScaleZ)
	local bullet = EID2OBJ(Id) or g_BulletObjectMgr:GetOptBulletByUId(Id)
	if bullet then
		bullet:BulletEffectScale(ScaleX, ScaleY, ScaleZ)
	end
end


function CClientBullet:StartUpdateSelfByOwner()
	self:StopUpdateSelfByOwner()

	local engineId = self:GetEngineObjectGlobalId()
	local ownerId = self.m_BulletMoveData and self.m_BulletMoveData.m_OwnerId or 0
	if ownerId == 0 then return end

	self:RegisterTick("HideByOwnerTick", function() 
		self:OnUpdateSelfByOwner(engineId, ownerId)
	end, 2000)
end

function CClientBullet:StopUpdateSelfByOwner()
	self:UnRegisterTick("HideByOwnerTick")
end

function CClientBullet:OnUpdateSelfByOwner(engineId, ownerId)
	local monster = GetObjectByGlobalId(engineId)
	if not monster then return end

	local owner = GetObjectByGlobalId(ownerId)
	if owner and g_OtherPlayer_Pet_Hide[engineId] then
		monster:ShowMonsterPet(true, engineId, ownerId)
	elseif not owner and not g_OtherPlayer_Pet_Hide[engineId] then
		monster:ShowMonsterPet(false, engineId, ownerId)
	end
end

function CClientBullet:ShowMonsterPet(bShow, engineId, ownerId)
	local pet = nil
	if not bShow then
		pet = {
			EngineId = engineId,
			OwnerId = ownerId,
		}
	end

	g_OtherPlayer_Pet_Hide[engineId] = pet
	self:RefreshROVisible()
end

function CClientBullet:IsROVisible()
	if OPTIMIZE_MODE_EX_BULLET then
		if not self:_IsROVisible_() then
			return false
		end
	else
		if not CClientCharacter.IsROVisible(self) then
			return false
		end
	end

	if self:IsROVisibleIndImmersionMode() == false then
		return false
	end

	local engineId = self:GetEngineObjectGlobalId()
	if g_OtherPlayer_Pet_Hide[engineId] then
		return false
	end

	local bulletData = self.m_BulletMoveData
	if bulletData.m_IsInvisible then
		return false
	end

	if g_MainPlayer and g_MainPlayer:HasStatus("TakePhoto") then
		local master = self:GetOwner()
		if master and master:IsPlayer() then
			return g_TakingPhotoMgr:IsLiupaiSummonPetShow(master, self)
		end
	end

	return true
end

function CClientBullet:OnPropertyUpdated(key, val)
	if key == "m_IsInvisible" then
		self:RefreshROVisible()
	elseif key == "m_ReplaceClassByCharacterDef" then
		self:RefreshReplaceClassByCharacterDef(val)
	elseif key == "m_TimeScale" then
		self:RefreshTimeScale(val)
	end
end

function CClientBullet:RefreshTimeScale(timeScale)
	local effectRO = g_ClientEffectMgr:GetEffectRenderObject()
	if not HasFeature("Common_411") then return end
	for k, nLogicHash in ipairs(self.m_EffectList) do
		effectRO:SetEffectSpeed(nil, nLogicHash, timeScale)
	end
end

function CClientBullet:RefreshReplaceClassByCharacterDef(tbl)
	if not tbl then return end
	if not self.m_bResLoaded then return end
	local ro = self:GetRenderObject()
	if not ro then return end
	for k, v in pairs(tbl) do
		local prefab = table.safe_get(Character_Define, v, "Prefab")
		if prefab then
			ro:ReplaceClassByCharModeFile(nil, prefab, k)
		end
	end
end

--region 召唤物穿戴配饰

function CClientBullet:ProcessSummonAccessories()
	if not self.m_bResLoaded then return end

	local ro = self:GetRenderObject()
	if not ro then return end

	local appear = self:AppearanceProp()
	if not appear then return end

	local summonId
	local bulletId = self.m_BulletMoveData.m_BulletDataId
	if bulletId == 812350 then
		summonId = 105	-- 鸿音小鹿
	elseif bulletId == 812353 then
		summonId = 106	-- 鸿音小鹿2
	else
		summonId = 102	-- 潮光海豚
	end

	g_ClientFashionMgr:PutOffSummonFashion(ro, EnumPetFashionClothBoundType.Head)
	g_ClientFashionMgr:PutOffSummonFashion(ro, EnumPetFashionClothBoundType.Back)
	g_ClientFashionMgr:UnregisterSummonWearingFashion(self.m_engineObjectId)

	if self:ShouldBlockSummonAccessories() then
		return
	end

	local bOwnerIsMainPlayer = g_MainPlayer and self:GetOwner() == g_MainPlayer

	for fashionId, colorId in appear:AccessoriesData_Pairs() do
		g_ClientFashionMgr:PutOnSummonFashion(ro, summonId, fashionId, colorId)
		if not bOwnerIsMainPlayer then
			g_ClientFashionMgr:RegisterSummonWearingFashion(self.m_engineObjectId)
		end
	end
end

function CClientBullet:IsModelOptOpen()
	local owner = self:GetOwner()
	local isModelOptOpenScene = g_ClientOptimizeMgr:IsModelOptOpen(g_SceneDesignID)
	return owner and owner:IsModelOptOpen() or isModelOptOpenScene
end

function CClientBullet:ShouldBlockSummonAccessories()
	local owner = self:GetOwner()
	if g_MainPlayer and owner == g_MainPlayer then
		return false
	end
	if g_ClientFashionMgr:IsSummonFashionLimitReached() then
		return true
	end
	if self:IsModelOptOpen() then
		return true
	end
	if owner then
		if g_ClientOtherPlayerMgr:IsOtherPlayerAppearBlocked(owner, EnumOtherPlayerAppearBlock.BlockFollowPet) then
			return true
		end
	else
		-- owner may not be loaded yet; fall back to global block bits
		local blockBits = g_ClientOtherPlayerMgr.m_OtherPlayerAppearBlockBits or 0
		if band(blockBits, EnumOtherPlayerAppearBlock.BlockFollowPet) ~= 0 then
			return true
		end
	end
	return false
end
--endregion

function CClientBullet:UpdateAppearBlockBits(changedBits)
	local owner = self:GetOwner()
	if not g_ClientOtherPlayerMgr:IsObjSupportAppearBlock(owner) then
		return
	end

	if band(changedBits, EnumOtherPlayerAppearBlock.PetResChanged) ~= 0 then
		local ro = self:GetRenderObject()
		if ro then
			ro:ResetGameObject()
			self:LoadResourceWithTransformCheck()
		end
	end
end

--region 子弹监听回调

function CClientBullet:RegisterPositionChangeCallback(key, callback)
	if not self.m_PositionChangeCallback then
		self.m_PositionChangeCallback = {}
	end
	self.m_PositionChangeCallback[key] = callback
end

function CClientBullet:UnRegisterPositionChangeCallback(key)
	if not self.m_PositionChangeCallback then
		return
	end
	self.m_PositionChangeCallback[key] = nil
end

function CClientBullet:DoPositionChangeCallback(OldX, OldY, OldZ, X, Y, Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	if not self.m_PositionChangeCallback then return end
	if not next(self.m_PositionChangeCallback) then
		self.m_PositionChangeCallback = nil
		return 
	end
	for k,v in pairs(self.m_PositionChangeCallback) do
		SAFE_CALL(v, OldX, OldY, OldZ, X , Y , Z, SPType, bOnDynamicGrid_NoObject, IsFlying, IsFalling)
	end
end


function CClientBullet:RegisterDestroyCallback(key, callback)
	if not self.m_DestroyCallback then
		self.m_DestroyCallback = {}
	end
	self.m_DestroyCallback[key] = callback
end

function CClientBullet:DoDestroyCallback()
	self.m_PositionChangeCallback = nil
	if not self.m_DestroyCallback then return end
	if not next(self.m_DestroyCallback) then
		self.m_DestroyCallback = nil
		return 
	end
	for k,v in pairs(self.m_DestroyCallback) do
		SAFE_CALL(v)
	end
	self.m_DestroyCallback = nil
end



--endregion

local _TerrainMgr = CS.Pangu.AppFacade.terrainMgr
function CClientBullet:TryAddOrUpdatePositionTerrainInteractPoint(posX, posY, posZ)
	self.m_DesignDataInteractCache = self:GetData("TerrainInteract")
	if not self.m_DesignDataInteractCache then 
		return 
	end
	if not _TerrainMgr:HasTerrainInteract() then 
		return
	end
	if not HasFeature("SnowInteractPositionAndBone_411") then 
		return 
	end
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	if not renderObject then 
		return 
	end
	local designDataInteract = self.m_DesignDataInteractCache
	local scaleX = designDataInteract.Scale[1] or 1
	local scaleY = designDataInteract.Scale[2] or 1
	local scaleZ = designDataInteract.Scale[3] or 1	

	local offsetX = designDataInteract.Offset and designDataInteract.Offset[1] or 0
	local offsetY = designDataInteract.Offset and designDataInteract.Offset[2] or 0
	local offsetZ = designDataInteract.Offset and designDataInteract.Offset[3] or 0
	renderObject:AddOrUpdatePositionTerrainInteractPoint(self.m_engineObjectId, posX+offsetX, posY+offsetY, posZ+offsetZ, scaleX, scaleY, scaleZ)
end

function CClientBullet:TryRemovePositionTerrainInteractPoint()
	if not _TerrainMgr:HasTerrainInteract() then 
		return 
	end
	if not HasFeature("SnowInteractPositionAndBone_411") then 
		return 
	end
	local renderObject = g_ClientEffectMgr:GetEffectRenderObject()
	if not renderObject then 
		return 
	end
	renderObject:RemovePositionTerrainInteractPoint(self.m_engineObjectId)
end

function CClientBullet:GetBlockObjectType()
	local flag = EnumBlockEngineObjectType.Bullet
	if g_MainPlayer and self:GetOwner() == g_MainPlayer then
		flag = bit.bor(flag, EnumBlockEngineObjectType.MainPlayerBullet)
	end
	return flag
end

function CClientBullet:OnEffectVisibleChanged(bVisible)
	self:FxVisiable(bVisible)
end

function CClientBullet:GetTimeScale()
	local timeScale = self.m_BulletMoveData.m_TimeScale
	if not timeScale then return 1 end 
	return Clamp(timeScale, 0.1, 10)
end

function CClientBullet:GetTimeScaleRev()
	return 1 / CClientBullet:GetTimeScale()
end

function CClientBullet:ModifySpeed(fSpeed)
	self:UpdateProperty("m_BulletSpeed", fSpeed)
end

function CClientBullet:UpdateProperty(key, value)
	local BulletData = self.m_BulletMoveData
	local old = BulletData[key]
	if old == value then return end
	BulletData[key] = value
end

-- CClientBullet 重写 RODirectionChangeCheck
function CClientBullet:RODirectionChangeCheck()
    local moveData = self.m_BulletMoveData
	local dirTrackTargetId = moveData and moveData.m_DirTrackTargetId
    if dirTrackTargetId and dirTrackTargetId ~= 0 then
		return true
    end
    if self.m_BulletMoveIs2DDir == 2 then
        return true
    end
    return CClientCharacter.RODirectionChangeCheck(self)
end

function CClientBullet:OnAfterHavokGuaJieMulti()
	-- 存在一种情况，宠物先加载完成了，然后刷新了一次ROVisible
	-- 然后玩家才加载完成，去执行Attach操作，但C#端会强行把宠物的ROVisible刷新成true
	-- 导致本来应该隐藏的宠物被强制显示出来了
	self:RefreshROVisible()
end

--region 染色Appear

function CClientBullet:CheckAndApplyBulletDyeColor()
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