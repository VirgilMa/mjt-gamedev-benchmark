local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID

--子弹应该不需要基类的各种行为
function CClientBullet:OnPreDetachEngineObject()
	if not OPTIMIZE_MODE_EX_BULLET then
        CFollowerCharacter.OnPreDetachEngineObject(self)
		return
	end
	if self.m_HasHeadInfo then
        self:DestroyHeadInfo()
    end
end

function CClientBullet:_DestroyBeforeRemoveCharacter()
	if not OPTIMIZE_MODE_EX_BULLET then
		CClientCharacter._DestroyBeforeRemoveCharacter(self)
		return
	end
	local id = self:GetEngineObjectGlobalId()
	if g_Client_SceneSyncObj[id] then
		g_Client_SceneSyncObj[id] = nil
	end
	self:ChameleonCleanUp()
end

function CClientBullet:DestroyRenderObject(bCachedDestroy)
	if not OPTIMIZE_MODE_EX_BULLET then
		CClientCharacter.DestroyRenderObject(self, bCachedDestroy)
		return
	end
	local ro = self.m_RenderObject
	if not ro then 
		return
	end
	if self:IsHitPosCorrect() then
		return
	end
	self:DestroyHeadInfo()
	if g_SceneLoadingMgr:IsRODelayDestroy() then
		g_SceneLoadingMgr:AddDelayDestroyRO(ro)
	elseif g_ClientFashionMgr:CheckObjIsPerformDelayDestroyRo(self) then
		local delay = g_ClientFashionMgr:GetPerformDelayDestroyROTime(self) or 0
		g_ClientFashionMgr:AddPerformDelayDestroyRO(ro, delay)
	else
		ro:DestroyForBullet()
	end
	self:SetCurrDynWeaponName(nil)
	self.m_RenderObject = nil
end

function CClientBullet:_OnResLoaded_(bCachedLoaded)
	self.m_bResLoaded = true
	self.m_bResLoading = false
	if not bCachedLoaded then
		self:InitOriginType()
	end
	self:CheckHideForBornAni(bCachedLoaded)
	self:OnDynEquipChanged()
	--self:SetWeaponOriginType()
	if not bCachedLoaded then
		self:InitLayer()
		self:GetRenderObject():CreateAABB(false)
		self:OnLoadPreAnimationClip()
	end

	if self.m_engineObject then
		local dir = -self.m_engineObject:GetDirectionDegree() + 90
		self.m_RenderObject:Set360DegreeDirection(dir)

		if g_Open3DRotate then
			local directionX = self.m_engineObject:GetDirectionDegreeX()
			local directionY = self.m_engineObject:GetDirectionDegreeY()
			if directionX ~= 0 or directionY ~= 0 then
				self.m_RenderObject:SetRotationByEulerAngle(directionX, dir, directionY)
			end
		end
	end

	self:RefreshROPosition(bCachedLoaded, bCachedLoaded)
	--[ToDelete]: 子弹应该不需要性别？
	self:SetAnimatorFloatParam("gender", self:GetGender())

	local RO = self:GetRenderObject()
	local bHasAnimatorController = nil
	if RO then
        --[ToCheck]: 大部分时候应该不需要头顶？
        if self.m_HasHeadInfo then
            RO:ClearBoneIndexDic() -- 临时修复, 221再放到C#里面
            self.m_HeadBoneIndex = RO:GetBoneIndexByName("Bip001 Head")
            self.m_HeadHeight = RO:GetBoneDefaultPositionLocalByIndex(self.m_HeadBoneIndex).y
            self:ResetHUDDuringQingGongObResLoaded()
        end

		--Npc互撞相关
		-- local templateId = self:GetTemplateId()
		-- local Pushable = self:IsMonsterOrNpc() and Monster_Or_Npc[templateId] and Monster_Or_Npc[templateId].Pushable;
		-- local EnablePhysicsCollision = self:IsMonsterOrNpc() and Monster_Or_Npc[templateId] and  (Monster_Or_Npc[templateId].EnablePhysicsCollision == 1);
		-- if Pushable or EnablePhysicsCollision  then
			-- local PushNpc = CS.Leihuo.NpcPushMgr.Instance
			-- if PushNpc ~= nil and templateId and self:IsROVisible() then
			-- 	PushNpc:RegisterProxy(templateId,RO,1)
			-- end
		-- end

		--[ToDelete]: 子弹应该不需要判断水下状态？
		if self:IsUnderOcean() then
			self:SetAniValue_Int("UnderOcean", 1)
		end

		bHasAnimatorController = RO:HasAnimatorController()
		if not bHasAnimatorController then
			self.m_NoHasAnimator = true
		end
		if self.m_BulletMoveData then
			local dirX, dirY, dirZ = self:GetBulletInitLookDir()
			RO:SetRotation(dirX, dirY, dirZ)
		end

		local characterDef = self.m_CharacterDefineId and Character_Define[self.m_CharacterDefineId]
		local characterDefSwimmingDepth = characterDef and characterDef.SwimmingDepth

		self:SetSwimmRoDepth(false)

		if self:GetData("IsAlwaysVisible") == 1 or (characterDef and characterDef.WithColliderBlockCamera == 1) then
			RO.bAlwaysVisible = true
		else
			RO.bAlwaysVisible = false
		end

		local dontHideWhenCameraInside = self:GetData("DontHideWhenCameraInside") or characterDef and characterDef.DontHideWhenCameraInside

		if dontHideWhenCameraInside == 1 then
			RO.bHideWhenCameraInside = false
		else
			RO.bHideWhenCameraInside = true
		end

		if self:GetData("IgnoreCamera") then
			RO:MaskColliderIgnoreCamera()
		end

		if not self:GetData("Scale") then
			local scale = self:GetCurScale()
			RO:SetScale(scale, scale, scale)
		end
		self:OnResLoaded_SlowScale()
		if self:IsOpenPhyMove() then
			self.m_PhyMove = RO:GetPhyMove()
			if self.m_PhyMove then
				self.m_FrameRaycastInfo = self.m_PhyMove:GetFrameRaycastInfo()
			end
		end

		--[ToDelete]: 这个对于子弹应该也是不需要的？
		-- 我在剧组模式，则判断下动骨
		-- if g_ScreenPlayMgr:IsMainPlayerInScreenPlayMode() then
		-- 	local playerId = self:GetPlayerId()
		-- 	if g_ScreenPlayMgr:IsInMyScreenPlayGroup(playerId) then
		-- 		RO:EnableDynamicBoneForce(true,true)
		-- 	else
		-- 		RO:EnableDynamicBoneForce(false,true)
		-- 	end
		-- end

		-- 如果有未能应用的外观切换
		-- 这里把切场景时更了的数据应用到appear上
		if self.m_CachedNewAp then
			local newAp = CPropertyAppearance_Player:new()
			newAp:Clone(self:AppearanceProp())
			newAp:CloneFashionDataOnly(self.m_CachedNewAp)
			self:UpdateAppearance(newAp, self.m_CachedIgnoreEquip)
		end
	else
		self.m_NoHasAnimator = true
	end

	MsgHub_GacCharacterResLoaded:Emit(self, bCachedLoaded)
    
	if self.m_HasHeadInfo then
		self:CreateHeadInfo()
	end
	self:ProcessBornAni(bHasAnimatorController)
	self:RefreshROVisible()

	MsgHub_GacCharacterResLoadedAndROVisibleRefreshed:Emit(self)

    --[ToCheck]: 子弹应该不需要头顶？
    if self.m_HasHeadInfo then
        self:UpdateNameColor()
    end
	self:OnResLoadedAniVal(bHasAnimatorController)
	self:OnResLoadedHkEvent()
	self:OnResLoadedAniState()
	self:OnResLoadedSceneText()
	if self:IsPlayerOrFake() then
		self:ClassOpWhenResLoaded()
	end

	self:ProssBornInWangQi()

	local appearanceProp = self:AppearanceProp()
	if appearanceProp and self:NeedRefreshElement() then
		g_DispElementClientMgr:RefreshAllElement(self)
	end

	if self:NeedSceneSync() then
		g_Client_SceneSyncObj[self:GetEngineObjectGlobalId()] = true
	end
	self:ClearFightParamDelayTbl()
    --[Todo]: 这里里面的IsRoVisible和上面的RefreshROVisible里面的重复了？
	self:UpdateBlockEngineObject()
    --[ToCheck]: 子弹应该不需要头顶？
    if self.m_HasHeadInfo then
	    self:UpdateBlockHUD()
    end
	self:OnResLoadedCheckExploreEffect()
	self:OnResloadedCheckAttach()

	self:BindHangupAudios()

	if not bCachedLoaded then
		self:OnResLoadedInitRagdoll()
		self:TryEnableAnimatorSkipFrame()
		self:TryEnableAnimatorMainCameraCulling()
		self:CheckClearShowDamageNumberHeight()
	end

	self:OnResLoadedEnterStatus()

	if type(self.m_OnResLoadedFunc) == 'function' then
        self.m_OnResLoadedFunc(self)
    end

	if self:GetData("DisableMainCameraCulling") == 1 and RO then
		--print("33333333333____________")
		RO:SetMainCameraCulling(false)
	end

	if self:GetData("DisableInterpolate") == 1 and RO then
		--print("33333333333____________")
		if (GetPlatformType() ~= EnumPlatformType.eIOS) then
			--print("1111111111 ", self:GetName())
			RO:EnableInterpolate(false)
		end
	end

    --[ToDelete]: 子弹应该不需要SmartKey？
	-- if g_CharacterResLoadedSmartKeyOpt then
	-- 	-- 角色加载完成后，重新触发一次
	-- 	self:RealUpdateSmartKey(self.m_SmartKey, true)
	-- end

	-- g_SmartKeyMgr:AddSmartKeyAll(self.m_SmartKey)
	g_GameplayMgr:TryAddPreviewMirror(self)
	g_ClientZXDLiuPaiPlayMgr:TryInitTrackObj(self)

	local obj = GetObjectByGlobalId(self.m_engineObjectId)
	if obj and obj.RefreshROPartVisible then
		obj:RefreshROPartVisible()
	end

	-- 大航海灰色区域
	g_ClientDaHangHaiMgr:TrySetGrayAreaObj(self)

	self:CheckHavokPathAniEvent()

	if self.m_bNoCheckCanReach then
		self:SetNoCheckCanReach(self.m_bNoCheckCanReach)
	end
    if self.m_HasHeadInfo then
	    self:ResetHUDAfterQingGongObResLoaded()
    end
	self:OnResLoaded_SyncAnimationBlackWhiteListToRO()

	self:OnResLoaded_CloneTarget()
	
	if self.m_IsValid then
		MsgHub_GacCharacterResLoadedDone:Emit(self)
	end
end

--子弹不需要武器？
function CClientBullet:OnDynEquipChanged()
	if not OPTIMIZE_MODE_EX_BULLET then
		CFollowerCharacter.OnDynEquipChanged(self)
	end
end

function CClientBullet:RefreshROPosition(bForce, bIgnorePosCheck)
	if not OPTIMIZE_MODE_EX_BULLET then
		CClientCharacter.RefreshROPosition(self, bForce, bIgnorePosCheck)
		return
	end
	if not self.m_IsValid then
		return
	end
	local engineObj = self.m_engineObject
	if not bForce and engineObj:IsMoving() and not engineObj:IsTurning() then
		return
	end
	-- 追飞翼/传送状态下，暂时屏蔽
	local statusCache = self.m_StatusCache
	if statusCache and (statusCache[EPropStatus.OnFly] or statusCache[EPropStatus.Teleporting] or statusCache[EPropStatus.BezierMove]) then
		return
	end
	-- 旋转偏移情况下屏蔽
	if self:NeedChangeRotate2YOffset() and (not self:HasStatus("MagneticSlave")) then
		return
	end

	local ro = self:GetRenderObject()
	if not ro then 
		return 
	end
	-- local pos = ro:GetPosition()
	local posX, posY, posZ = ro:GetPosition_opt()
	local x, y, z = engineObj:GetPixelPosv3f()
	local ux = x / pixel_per_grid
	local uy = z / pixel_per_grid
	local uz = y / pixel_per_grid
	local isOnDynamicGrid_NoObject = engineObj:IsOnDynamicGrid_NoObject()

	if (posX == ux and posZ == uz) or bIgnorePosCheck then
		-- 物理挂接模式这里也无视DynamicGrid
		if self:IsOpenPhyMove() and self:IsInUltraHandDirectSet() then
			isOnDynamicGrid_NoObject = true
		end
		ux, uy, uz = self:ChangeMagneticMove(ux, uy, uz)
		ro:SetPosition2(ux, uy, uz, engineObj:GetGravityRatio() ~= 0, eSetPositionType.eSPT_DirectSet, isOnDynamicGrid_NoObject)
	end
end


function CClientBullet:_IsROVisible_()
	-- if not OPTIMIZE_MODE_EX then
	-- 	return CClientCharacter.IsROVisible(self)
	-- end
	--[ToDelete]: 子弹应该不需要检查探索？
	if not self:CheckExploreMapStatus() then
		return false --对应的探索地图没有外放则探索内容不显示
	end

	--[ToDelete]: 子弹应该不需要检查探索？
	if self:IsExploreHide() then
		return false
	end

	--[ToDelete]: 子弹应该不需要节日活动显隐？
	-- 节日活动显隐[CustomData]
	-- local festivalId = self:GetCustomDataInPublicMap("FestivalId")
	-- if festivalId and not g_AutoSyncKVMgr:GetMapValue("Festival", festivalId) then
	-- 	return false
	-- end

	--[ToDelete]: 这个感觉子弹也不太需要？
	if not self:IsROVisible_Sinking() then
		return false
	end

	-- 门客剧组请求隐藏
	-- if self:IsUgcNpc() and g_MainPlayer and self:GetUgcOwnerId() == g_MainPlayer:GetPlayerId() and g_ScreenPlayMgr:IsHideMainPlayer() then
	-- 	return false
	-- end

	--[ToDelete]: 子弹应该不需要
	-- 大航海港口隐藏
	-- if not g_ClientDaHangHaiMgr:IsObjVisible(self) then
	-- 	return false
	-- end

	--[ToDelete]: 子弹应该不需要
	-- if g_ClientNpcPerformMgr:CheckNpcHide(self) then
	-- 	return false
	-- end

	--[ToDelete]: 子弹应该不需要
	-- if g_ClientHuaCheMgr:CheckNpcHide(self) then
	-- 	return false
	-- end

	if g_MoJinMgr:IsHideEscapePointByEngineId(self.m_engineObjectId) then
		return false
	end

	--[ToDelete]: 子弹应该不需要
	-- if g_ClientGGDMgr:IsCharacterNeedHide(self) then
	-- 	return false
	-- end

	local prop = self:StatusProp()
	if prop then
		if g_MainPlayer and (not g_MainPlayer:CheckSkillDivisionVisible(self)) then
			return false
		end

		if prop:GetStatus(EPropStatus.MirorFantasy_Object) == 1 and self:GetMirorEffectId() == 0 then
			return self:IsROVisible_MirorFantasy_Object()
		end

		return prop:GetStatus( EPropStatus.HideCharacter ) ~= 1
	end

	return true
end

function CClientBullet:SetROVisible(bVisible)
	if not OPTIMIZE_MODE_EX_BULLET then
		CClientCharacter.SetROVisible(self, bVisible)
		return
	end
	if not self.m_bResLoaded then 
		return 
	end

	-- 门客剧组请求隐藏
	-- if self:IsUgcNpc() and g_MainPlayer and self:GetUgcOwnerId() == g_MainPlayer:GetPlayerId() and g_ScreenPlayMgr:IsHideMainPlayer() then
	-- 	bVisible = false
	-- end

	if self.m_bIsROVisible == bVisible then
		return
	end

	self.m_bIsROVisible = bVisible

	local ro = self:GetRenderObject()
	-- if ro and ro:GetGameObject() then
	ro:SetVisible(bVisible)
	-- end

    --[ToDelete]: 子弹应该不需要选中框处理？
	-- if g_MainPlayer and g_AttachPanel and g_AttachPanel:IsValid() then
	-- 	if not bVisible then
	-- 		--清除选中框
	-- 		if self == g_MainPlayer:GetTarget() then
	-- 			local selectItem = g_AttachPanel:GetAttachItem(EnumUIAttachItemType.Select, "TargetSelect")
	-- 			if selectItem and not IsCSharpNull(selectItem.m_Widget) then
	-- 				selectItem.m_Widget.visibility = SGUI_Hidden
	-- 			end
	-- 		end
	-- 	else
	-- 		--重新选中选中框
	-- 		if g_MainPlayer:HasStatus("BezierSplineMove") then return end

	-- 		if self.m_engineObjectId == g_MainPlayer.m_LastManualTargetId then
	-- 			if not IsClassObject(self, CClientFarmAnimal) then
	-- 				if self == g_MainPlayer:GetTarget() then
	-- 					local selectItem = g_AttachPanel:GetAttachItem(EnumUIAttachItemType.Select, "TargetSelect")
	-- 					if selectItem and not IsCSharpNull(selectItem.m_Widget) then
	-- 						selectItem.m_Widget.visibility = SGUI_Visible
	-- 					end
	-- 				elseif not g_ClientDaHangHaiMgr:IsInDaHangHaiMode() then
	-- 					g_MainPlayer:RequestSetTarget(self, true)
	-- 				end
	-- 			end
	-- 		end
	-- 	end
	-- end

	self:OnRefreshROVisible(bVisible)
end

function CClientBullet:OnRefreshROVisible(bVisible)
	if not OPTIMIZE_MODE_EX_BULLET then
		CClientCharacter.OnRefreshROVisible(self, bVisible)
		return
	end
    --[ToDelete]: 子弹应该不需要HUD和SmartKey？
    -- self:RefreshHudWndVisible()
	-- self:RealUpdateSmartKey(self.m_SmartKey, true)

    --[ToCheck]: 子弹应该需要FollowSound吗？
	-- if bVisible then
		-- self:PlayFollowSound()
	-- else
		-- local notStop = false
		-- if self.m_IsNpc then
		-- 	local npcTemplateId = self:GetTemplateId()
		-- 	local designData = npcTemplateId and Monster_Or_Npc[npcTemplateId] or ClientNpc_ClientNpc[npcTemplateId]
		-- 	local showHideCloseSound = designData.showHideCloseSound
		-- 	notStop = (showHideCloseSound and showHideCloseSound == 1) and true or false
		-- 	g_ExploreCharacterHeadEffectMgr:TryDestroyDaHangHaiMachineItem(self)
		-- 	g_ExploreCharacterHeadEffectMgr:TryDestroyExploreDrawMachineItem(self)
		-- 	-- LOG_PRINT(DEBUG, 'cy === stopfollowsound', npcTemplateId, showHideCloseSound)
		-- end

		-- if not notStop then
		-- self:StopFollowSound()
		-- end
	-- end
end


function CClientBullet:AniEvent(EventName, ElapseSeconds, bIgnoreHideWeapon, bForceSyncTimeWhenLoaded, bPauseAnimation, skillId, bIgnoreAttachment)
	if not OPTIMIZE_MODE_EX_BULLET then
		return CClientCharacter.AniEvent(self, EventName, ElapseSeconds, bIgnoreHideWeapon, bForceSyncTimeWhenLoaded, bPauseAnimation, skillId, bIgnoreAttachment)
	end
	if self.m_IgnoreToOriginAniEvent and self.m_IgnoreToOriginAniEvent ~= EventName then
		self.m_IgnoreToOriginAniEvent = nil
	end
	if self:CheckAniConflict(EventName) then 
		return 
	end
	if self:TryUGCAniEvent(EventName) then 
		return 
	end
	-- 不能加在Status的黑名单，因为黑名单清除比OnLeave方法更晚，会导致OnLeave的to_Origin无法触发
	if EventName == "to_Origin" and self:HasStatus("SeatToLocalFrame") then
		return
	end
	
	if self.m_bResLoaded then
		if self.m_RenderObject then
			if skillId then -- 由技能触发的动画状态机
				g_SkillProfileMgr:AddSkillProfileData(skillId, "OnCast_AniEvent_Recover")
			end
			FireAnimatonEventWithCache(self.m_RenderObject, EventName, ElapseSeconds, bIgnoreHideWeapon, bForceSyncTimeWhenLoaded, bIgnoreAttachment)
			if bPauseAnimation ~= nil then
				self:StepAnimationLocalTimeAndPause(ElapseSeconds, bPauseAnimation)
			end
			self:CheckAniEventRefCallFunc(EventName)
		end
	elseif EventName ~= "to_Origin" then --to_Origin 不用在这边发,资源加载好会发
		self.m_WaitingHkEvent = self.m_WaitingHkEvent or {}
		table.insert(self.m_WaitingHkEvent, {EventName, ElapseSeconds, bForceSyncTimeWhenLoaded, GetProcessTime_lua(), bPauseAnimation})
	end
	g_RecordReplayMgr:OnObjHkEvent(self, EventName, ElapseSeconds)
	return true
end


function CClientBullet:SetAniValue_Int(Name, Value)
	if not OPTIMIZE_MODE_EX_BULLET then
		return CClientCharacter.SetAniValue_Int(self, Name, Value)
	end
	if Name == "Skin_Run" and g_StatusMgr:HasStatus_Unsafe(self, EPropStatus.Transform) then
		return
	end
	if not self:CanSetAniVal_Int(Name, Value) then
		return
	end
	if Value == 1 or Value == 0 then
		local valueMap = Animator_ValueMap[Name]
		if valueMap then
			Name = valueMap.MapName
			Value = Value == 1 and valueMap.Value or 0
		end
	end

	if self.m_RenderObject then
		local bSync2Child = Animator_AnimatorVar2ChildBlackList[Name] == nil
		if self:ForbidbSync2ChildCondition(Name, Value) then
   			bSync2Child = false
		end
		self:SetAnimatorIntParam(Name, Value, bSync2Child)
		g_RecordReplayMgr:OnObjSetAniVal(self, RRAniValType.Int, Name, Value)
	else
		self:SetAnimatorFloatParam(Name, Value)
	end
end
