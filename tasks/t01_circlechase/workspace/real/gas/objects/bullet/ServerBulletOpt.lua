local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local MaxLifeTime = 300 * 30
local MaxEyeSight = 10
local atan2 = math.atan2
local ceil = math.ceil
local sqrt = math.sqrt
local max = math.max
local min = math.min
local floor = math.floor
local Bullet_Bullet_f = AllFormulas.Bullet_Bullet
--==============================================================================================

function CServerBulletOpt:Ctor()
	self.m_AutoDestroyTime = nil
	self.m_Level = nil
	self.m_TimesHurtMul = nil
	self.m_TimesHurtAdj = nil
	self.m_SkillEnabled = true

	self.m_BulletMoveData = self.m_BulletMoveData or CBulletMoveDataOpt:new()
	self.m_Share = self.m_Share or CServerBulletShare:new(self)
	self.m_State = CSimpleMemState:new()
end

function CServerBulletOpt:DelayDestroy(DelayTime)
	if self.m_Destroying then
		return
	end

	if not DelayTime or DelayTime <= 0 then
		DelayTime = 1
	else
		DelayTime = DelayTime * 1000
	end

	local uid = self:GetUId()
	local func = function()
		local bullet = g_BulletObjectMgr:GetOptBulletByUId(uid)
		if bullet then
			bullet:Destroy()
		end
	end

	RegisterObjTickWithDuration(self, "DelayDestroy", func, DelayTime, DelayTime)
	return true
end

function CServerBulletOpt:Destroy(TargetId, isFromLifeOver)
	if self.m_Destroying then
		return
	end
	
	self.m_Destroying = true
	SAFE_CALL(CServerBulletOpt.SafeCall_Destroy, self, TargetId, isFromLifeOver)

	g_BulletObjectMgr:RemoveOptBullet(self)
	g_ObjPoolMgr:ReturnObj(self)
end

function CServerBulletOpt:GetBulletOptSyncIS(owner)
	if not owner then return end

	local bulletAttachType = self:GetData("BulletAttachType")
	local bulletAttachEnabled = bulletAttachType == 1 or (bulletAttachType == 2 and owner:IsOptimizeOpen("SimpleSkill"))
	if bulletAttachEnabled then
		local attachToPlayerId = self.m_AttachToPlayerId
		if attachToPlayerId then
			local attachPlayer = GetPlayerOrFakeById(attachToPlayerId)
			if attachPlayer and attachPlayer.m_Conn then
				return attachPlayer.m_Conn
			end
		end
		if owner:IsPlayerOrFake() then
			return owner.m_Conn
		end
	end
	return owner:GetSyncAndSelfIS()
end

function CServerBulletOpt:SafeCall_Destroy(TargetId, isFromLifeOver)
	self:RemoveDelayBulletMoveTick()
	UnRegisterObjTickAll(self)

	local target = self:GetTargetObject()
    if target and target.RmChasedByBullet then
        target:RmChasedByBullet(self)
    end

	if not self:IsPureClientBullet() then
		local owner = self:GetOwner()
		if owner then
			owner.m_MyOptBullets[self:GetUId()] = nil
			if not isFromLifeOver then 
				Gas2Gac:DestroyServerBulletOpt(self:GetBulletOptSyncIS(owner), self:GetUId())
			end
		end
		
		if self.m_BeforDestroyActionFunc then
			g_ActionMgr:DoAction(self, TargetId and GetCharacterByEngineObjectGlobalId(TargetId), {ProfileId = self:GetTemplateId()}, self.m_BeforDestroyActionFunc)
		end
	end
end

function CServerBulletOpt:InitBullet(designData, lv, x, y, z, dirx, diry, dirZ, owner)
	-- LOG_PRINT(DEBUG,"CServerBulletOpt:InitBullet", designData.ID, lv, x, y, z)
	self.m_IsOptBullet = true

	CServerCharacter._InitBulletMoveData(self, designData, x, y, z)

	local tempalteId = designData.ID
	self.m_Level = lv
	self._m_TemplateId_For_Debug = tempalteId
	self.m_BulletMoveData.m_OwnerId = owner and owner.m_engineObjectId

	local rootOwner = owner and owner:GetOwner() or owner
	self.m_BulletMoveData.m_RootOwnerId = rootOwner and rootOwner.m_engineObjectId
	self.m_BulletMoveData.m_RootOwnerCharacterType = rootOwner and rootOwner.m_CharacterType
	self.m_DirX, self.m_DirY, self.m_DirZ = dirx, diry, dirZ
	self.m_AutoDestroyTime = designData.AutoDestroy		-- -1表示不销毁
	self.m_BeforDestroyActionFunc = Bullet_Bullet_f[tempalteId] and Bullet_Bullet_f[tempalteId].BeforeDestroyAction
	self.m_DamageEyeSight = tonumber(designData.MultiEyeSight) or 0
	self.m_OnHitSkill = designData.OnHitSkill
	self.m_HitActionFunc = Bullet_Bullet_f[tempalteId] and Bullet_Bullet_f[tempalteId].HitAction
	self.m_OptFloorHit = self:GetData("OptFloorHit") == 1

	if designData.IsPureClientBullet == 1 then
		-- 纯客户端子弹
		self.m_UId = -1
		self.m_BulletDelayMoveTime = nil -- 服务器这边不需要延迟，这个可以去掉
	else
		g_BulletObjectMgr:AddOptBullet(self)
	end
	
	local lifeTime = designData.LifeTime and designData.LifeTime / 30
	if lifeTime then
		if owner and IsClassObject(owner, CServerFightableCharacter) then
			lifeTime = lifeTime * (1 + owner:GetParam(EFightProp.Range))
		end
	end
	lifeTime = lifeTime or 30 --必须要有存在时间，没有给个默认
	self:SetDieTime(lifeTime)	--策划数据中的LifeTime单位为帧

	self:BeginOnSummonSkill()
	self:SetOwner(owner)

	return true
end

function CServerBulletOpt:GetUId()
	return self.m_UId
end

function CServerBulletOpt:IsPureClientBullet()
	return self.m_UId < 0
end

function CServerBulletOpt:SetDieTime(DieTime)
	if self:IsPureClientBullet() then
		DieTime = min(max(0.001, DieTime), MaxLifeTime)
		self.m_Share.m_LiftTime = DieTime
	else
		return self.m_Share:SetDieTime(DieTime)
	end
end

function CServerBulletOpt:Die()
	self:Destroy()
end

function CServerBulletOpt:GetPixelPosition()
	local bulletData = self.m_BulletMoveData
	return bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
end

function CServerBulletOpt:RemoveDelayBulletMoveTick()
	SafeUnRegisterTick(self, "m_DelayBulletMoveTick")
end

function CServerBulletOpt:GetBulletMoveTrajectory()
	return self.m_BulletMoveData.m_Trajectory, self.m_BulletMoveData.m_TrajectoryArgs
end

function CServerBulletOpt:GetBulletMoveDataMsgPack()
	local data = self.m_BulletMoveData
	local spCls = BulletTrajectoryClassTb[data.m_Trajectory]
	return msgpack.pack_object_for_sync(data, CBulletData_Freq), msgpack.pack_object_for_sync(data, CBulletData_NoFreq), spCls and msgpack.pack_object_for_sync(data, spCls) or NIL_USER_DATA
end

function CServerBulletOpt:RefreshBulletMoveData()
	local bulletData = self.m_BulletMoveData
	if not bulletData then return end
	local owner = self:GetOwner()
	if not owner then return end 

	local rootOwnerId = bulletData.m_RootOwnerId
	local ownerId = bulletData.m_OwnerId
	local bulletDataId = bulletData.m_BulletDataId
		-- 同步优化
	if rootOwnerId == bulletData.m_OwnerId then
		bulletData.m_OwnerId = nil
	end
	bulletData.m_RootOwnerId = nil
	bulletData.m_BulletDataId = nil
	local freqMP, noFreqMP, specMP = self:GetBulletMoveDataMsgPack()
	bulletData.m_OwnerId = ownerId
	bulletData.m_RootOwnerId = rootOwnerId
	bulletData.m_BulletDataId = bulletDataId

	local is = self:GetBulletOptSyncIS(owner)
	local lifeTime = (self.m_Share.m_LiftTime - (self.m_BulletDelayMoveTime or 0)) * 1000
	Gas2Gac:RefreshBulletOptMoveData(is, self.m_UId, rootOwnerId, self:GetId(), freqMP, noFreqMP, specMP, self.m_DirX or 0, self.m_DirY or 0, self.m_DirZ or 0, floor(lifeTime))
end

function CServerBulletOpt:GetBulletMoveSideSpeed()
	return self:GetBulletMoveSpeed() * 1
end

function CServerBulletOpt:GetBulletMoveSpeed()
	return self.m_BulletMoveData.m_BulletSpeed or 0 
end

function CServerBulletOpt:GetFaceDirection()
	return XYDirToDegreeDir(self.m_DirX, self.m_DirY)
end

function CServerBulletOpt:GetFaceDirectionXYZ()
	return self.m_DirX, self.m_DirY, self.m_DirZ
end

function CServerBulletOpt:StartBulletTrajectoryMove(MoveArgs)
	local delayTime = self.m_BulletDelayMoveTime
	local BulletData = self.m_BulletMoveData
	
	BulletData.m_DestOffsetX, BulletData.m_DestOffsetY, BulletData.m_DestOffsetZ = MoveArgs.DestOffsetX, MoveArgs.DestOffsetY, MoveArgs.DestOffsetZ

	if delayTime then
		local uid = self.m_UId
		self.m_DelayBulletMoveTick = RegisterTickWithDuration(function() 
			local self = g_BulletObjectMgr:GetOptBulletByUId(uid)
			if self then
				local bRet = BulletTrajectoryImp:_StartBulletTrajectoryMove(self, MoveArgs)
				if not bRet then 
					PQERR("StartBulletTrajectoryMove fail1", BulletData.m_BulletDataId)
					self:Destroy()
					return 
				end
			end
		end, delayTime * 1000, delayTime * 1000)
	else
		local bRet = BulletTrajectoryImp:_StartBulletTrajectoryMove(self, MoveArgs)
		if not bRet then 
			PQERR("StartBulletTrajectoryMove fail2", BulletData.m_BulletDataId)
			if self:IsPureClientBullet() then
				-- 纯客户端子弹这里可以直接销毁
				self:Destroy()
			else
				--这里延迟下销毁, 防止创建流程还没跑完就进行了销毁
				local uid = self.m_UId
				RegisterTickWithDuration(function() 
					local self = g_BulletObjectMgr:GetOptBulletByUId(uid)
					if self then
						self:Destroy()
					end
				end, 1, 1)
			end
			return
		end
	end
end

function CServerBulletOpt:StartLuaMove()
	if self:IsPureClientBullet() then
		-- 纯客户端子弹的此时CServerBulletOpt可以干掉了，信息都同步给客户端了
		self:Destroy()
	else
		local trajectory = self:GetBulletMoveTrajectory()
		local interval = OPT_BULLET_MOVE_TICK_INTERVAL[trajectory] or OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL
	
		UnRegisterObjTick(self, "MoveTick")
		RegisterObjTick(self, "MoveTick", CServerBulletOpt.OnMoveTick, interval, self, interval)
	end
end

function CServerBulletOpt:OnMoveTick(interval)
	local uid = self:GetUId()
	local isContinue = self:GetLuaNextMove(interval)
	if not isContinue then
		if GetBulletObjById(uid, true) then 
			self:DoTargetReached()
		end
		if GetBulletObjById(uid, true) then 
			UnRegisterObjTick(self, "MoveTick")
			self:AutoDestroy()
		end
	end
end

function CServerBulletOpt:GetLuaNextMove(interval)
	local uid = self:GetUId()
	local bulletData = self.m_BulletMoveData
	local preX, preY, preZ = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
	GetLuaNextMove(bulletData, self, interval)
	local curX, curY, curZ = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ

	if not self:CheckCrossBuilding(preX, preY, preZ, curX, curY, curZ) then 
		curX, curY, curZ = preX, preY, preZ
		bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ = preX, preY, preZ -- 遇到障碍了，不能穿，要把坐标修正回来
		self.m_Share:TryDoCollisionBarrierAction()
		self.m_BulletMoveStopMoving = true
	end

	local bStopMoving = self.m_BulletMoveStopMoving or false
	if bStopMoving then
		self.m_BulletMoveStopMoving = false

		-- 旧的轨迹不是None时，执行OnMoveEnd，已经destroy就不执行了
		if GetBulletObjById(uid, true) and bulletData.m_Trajectory ~= EnumBulletTracjectory.None then
			self:TryDoOnMoveEndAction()
		end

		bulletData.m_Trajectory = EnumBulletTracjectory.None
	else
		self:OnBulletMove(preX, preY, preZ, curX, curY, curZ)
	end

	return not bStopMoving, curX, curY, curZ, nil
end

-- TODO: 如果性能可以接受，全改成PreciseGround的也行
function CServerBulletOpt:CheckCrossBuilding(PreX, PreY, PreZ, NowX, NowY, NowZ)
	if self.m_OptFloorHit then
		return self:CheckCrossBuildingPreciseGround(PreX, PreY, PreZ, NowX, NowY, NowZ)
	else
		return self:CheckCrossBuildingOri(PreX, PreY, PreZ, NowX, NowY, NowZ)
	end
end

function CServerBulletOpt:CheckCrossBuildingOri(PreX, PreY, PreZ, NowX, NowY, NowZ)
	local owner = self:GetOwner()
	if not owner then return false end 
	
	local coreScene = owner.m_Scene.m_CoreScene
	if self:GetData("CrossBuilding") == 0 then 
		local oldGridPosX, oldGridPosY = GetGridByPixel2(PreX, PreY)
		local newGridPosX, newGridPosY = GetGridByPixel2(NowX, NowY)
		if not (newGridPosX == oldGridPosX and newGridPosY == oldGridPosY) then 
			local gridTbl = coreScene:GetPixelLine(PreX, PreY, PreZ, NowX, NowY, NowZ, false, false)
			for i = 1, #gridTbl, 3 do
				local gridX, gridY, gridZ = GetGridByPixel2(gridTbl[i], gridTbl[i + 1], gridTbl[i + 2])
				local barrierType = coreScene:GetBarrierv3(gridX, gridY, gridZ)
				if barrierType > EBarrierType.eBT_MidBarrier then
					return false
				end
			end
		end
	end
	return true
end

-- 增强了地面检测，子弹穿过地面时会检测下一个格子是否为高障
function CServerBulletOpt:CheckCrossBuildingPreciseGround(PreX, PreY, PreZ, NowX, NowY, NowZ)
    local owner = self:GetOwner()
    if not owner then return false end

    local dpx = NowX - PreX
    local dpy = NowY - PreY
    local dpz = NowZ - PreZ

    local coreScene = owner.m_Scene.m_CoreScene
    if self:GetData("CrossBuilding") ~= 0 then return true end

    local gridTbl = coreScene:GetPixelLine(PreX, PreY, PreZ, NowX, NowY, NowZ, false, false)
    for i = 1, #gridTbl, 3 do
        local gridPixelX = gridTbl[i]
        local gridPixelY = gridTbl[i + 1]
        local gridPixelZ = gridTbl[i + 2]
        for j = 1, 4 do -- instead of while, 4 grids are enough
            local gridX, gridY, gridZ = GetGridByPixel2(gridPixelX, gridPixelY, gridPixelZ)
            local belowPixelZ = coreScene:GetNearestBelowGridPixelZByPixel(gridPixelX, gridPixelY, gridPixelZ)
            local barrierType = coreScene:GetBarrierv3Pixel(gridX, gridY, gridPixelZ)

            if barrierType > EBarrierType.eBT_MidBarrier then
                return false
            end
			
			if belowPixelZ < NowZ then
				break
			end

            local ratio = (belowPixelZ - PreZ) / dpz
            local nextPixelX = PreX + dpx * ratio
            local nextPixelY = PreY + dpy * ratio
            local nextGridX = floor(nextPixelX / 64)
            local nextGridY = floor(nextPixelY / 64)

            if nextGridX == gridX and nextGridY == gridY then
                local nextPixelZ = coreScene:GetNearestBelowGridPixelZByPixel(gridPixelX, gridPixelY, belowPixelZ - 1)
                if nextPixelZ == belowPixelZ then
                    break
                end
                gridPixelZ = nextPixelZ
            else
                break
            end
        end
    end
    return true
end

function CServerBulletOpt:OnBulletMove(PreX, PreY, PreZ, NowX, NowY, NowZ)
	local owner = self:GetOwner()
	if not owner then return end 
	local coreScene = owner.m_Scene.m_CoreScene
	
	local diffX, diffY, diffZ = NowX - PreX, NowY - PreY, NowZ - PreZ
	self.m_DirX, self.m_DirY, self.m_DirZ = NormalizeVectorXYZ(diffX, diffY, diffZ)

	local onHitSkill = self.m_OnHitSkill
	if (onHitSkill > 0 or self.m_HitActionFunc) and self:GetData("OnlyHitTarget") ~= 1 then 
		local angle = atan2(diffY, diffX)
		local length = ceil(sqrt((diffY)^2 + (diffX)^2) / 64)
		if g_OpenSuperProfileId then
			g_SceneQueryId =  self:GetId()
			g_SceneQueryTime = g_App:GetFrameTime()
			g_ServerProfileMgr:AddQueryProfileCount(g_SceneQueryId)
		end

		local za, zb = -1, -1
		if g_EngineZFilterEnabled then
			za, zb = self:GetZAboveBelow()
		end

		local EffectedCharacterIdList = coreScene:QueryObjectsWithAngleInDirectionRectanglevt(PreX, PreY, PreZ, angle, za, zb, 2 * self:GetDamageEyeSight(), length)
		g_SceneQueryId = 0
		if next(EffectedCharacterIdList) then 
			self:HitTargets4Opt(EffectedCharacterIdList)
		end
	end
end

function CServerBulletOpt:HitTargets4Opt(EffectedCharacterIdList)
	local owner = self:BulletGetOwner()
	if not owner then return end 
	
	local hitAction = self.m_HitActionFunc
	if hitAction then
		for k, eid in ipairs(EffectedCharacterIdList) do
			local target = EID2OBJ(eid)
			if target and target.m_IsValid then
				g_ActionMgr:DoAction(self, target, {ProfileId = self:GetTemplateId()}, hitAction)
			end
		end
	end

	local onHitSkill = self.m_OnHitSkill
	if onHitSkill and onHitSkill > 0 then
		local lv = self:GetLevel()
		local skillId = onHitSkill * 100 + lv
		local skillObj = g_SkillMgr.m_Skills[onHitSkill]
		local maxTarget = g_SkillMgr:GetSkillColTargets(owner, skillObj, lv)
		local maxPlayerTarget = g_SkillMgr:GetSkillColMaxPlayerTargets(owner, skillObj.m_SkillProp)
		local effectedCharacters, totalN, totalPlayerN, chemiRet = g_SkillMgr:GenerateValidCharacterSetForCircleSkill(skillId, EffectedCharacterIdList, owner, maxTarget, maxPlayerTarget)	
		local shield, lastShield, defender
		local uid = self:GetUId()
		for effectedCharacter, _ in pairs(effectedCharacters) do
			shield = g_SkillMgr:GetBlockingShield(effectedCharacter, owner, skillObj.m_SkillProp, skillId) or (effectedCharacter.m_IsShield and effectedCharacter)
			defender = shield or effectedCharacter
			
			if defender.m_IsValid and (not shield or shield ~= lastShield) then
				self:HitTarget4Opt(owner, defender, skillId)
				if not GetBulletObjById(uid, true) then 
					break
				end
				if defender.m_IsShield then 
					lastShield = defender 
				end
			end
		end
		g_LuaPoolMgr:ReleaseTable(effectedCharacters)
		if chemiRet then
			g_LuaPoolMgr:ReleaseTable(chemiRet)
		end
	end
end

function CServerBulletOpt:HitTarget4Opt(owner, target, skillId, isTargetReached)
	if not target.m_IsValid then
		return
	end

	local targetId = target.m_engineObjectId
	local now = g_App:GetFrameTime()
	local share = self.m_Share
	if share.m_LastHitTimeTb[targetId] and now - share.m_LastHitTimeTb[targetId] < 1000 then
		return
	end

	if GetObjTick(self, "OnHitDestroy") then 
		return --命中后延迟销毁不再计算命中
	end
	local maxPlayers = self:GetData("MaxPlayerTargets") or 0
	if not self:GetData("FlowchartName") and not self.m_HitActionFunc then
		maxPlayers = GetOptimizeMaxPlayerTargets(owner.m_Scene, maxPlayers, self:GetData(), owner)
	end
	if maxPlayers > 0 and share.m_HitedPlayerCount >= maxPlayers then
		return
	end
	local maxTargets = self:GetData("Targets") or 0
	if maxTargets > 0 and share.m_HitedObjectCount >= maxTargets then
		return
	end

	-- 引擎 query 路径已由引擎过滤，跳过 Lua 判定；isTargetReached 路径(DoTargetReached)未经引擎 query，必须走 Lua Z 校验
	local skipZCheck = g_EngineZFilterEnabled and not isTargetReached
	if not skipZCheck and not self:IsTargetInZRange(target) then
		return
	end

	share.m_LastHitTimeTb[targetId] = now
	
	if target:IsPlayerOrFake() then
		share.m_HitedPlayerCount = share.m_HitedPlayerCount + 1
	end
	share.m_HitedObjectCount = share.m_HitedObjectCount + 1	
	
	local uid = self:GetUId()
	if isTargetReached then
		self:DoCastSkill(skillId, target)
	else
		self:DoCastSkill4Opt(owner, target, skillId)
	end

	if GetBulletObjById(uid, true) then 
		self:OnHitDestroy(targetId)
	end
end

function CServerBulletOpt:DoCastSkill4Opt(owner, target, skillId)
	local hitNumHurtDecay = self:GetHitNumHurtDecay(owner, target)
	local cls, lv = GetSkillClsLv(skillId)
	local x, y, z = self:GetPixelPosition()
	g_SkillMgr:CastingSkill(owner, target, 
		{
			SkillId = skillId,
			Cls = cls,
			Lv = lv,
			TargetId = target and target.m_engineObjectId,
			DestPosX = x,
			DestPosY = y,
			DestPosZ = z,
			HurtDefendersCount = 0,
			KillDefendersCount = 0,
			HitNumHurtDecay = hitNumHurtDecay,
			IsFromBullet = true,
		}
	)
end

-- 优化子弹这边IsValid接口没什么用，最好用GetBulletObjById接口来判断，因为优化子弹回收到池子后，字段被销毁且不允许访问
function CServerBulletOpt:IsValid()
	return not self.m_Destroying 
end

function CServerBulletOpt:OnFlowchartEvent() end
function CServerBulletOpt:TryHitPosCorrect() end
function CServerBulletOpt:TargetReached()
	self.m_IsTargetReached = true
end

function CServerBulletOpt:DoTargetReached()
	if not self.m_IsTargetReached then return end
	local id = self.m_BulletMoveData.m_TargeterEngineObjectId
	if not id then return end
	local t = GetCharacterByEngineObjectGlobalId(id)
	if not t then return end 
	local hitAction = self.m_HitActionFunc
	if hitAction then
		g_ActionMgr:DoAction(self, t, {ProfileId = self:GetTemplateId()}, hitAction)
	end
	local onHitSkill = self.m_OnHitSkill
	if onHitSkill <= 0 then return end

	local owner = self:BulletGetOwner()
	if owner then 
		local skillId = onHitSkill * 100 + self:GetLevel()
		self:HitTarget4Opt(owner, t, skillId, true)	
	end 
end

function CServerBulletOpt:GetDamageEyeSight()
	return self.m_DamageEyeSight
end

function CServerBulletOpt:SetOwner(owner)
	self.m_OwnerId = owner.m_engineObjectId

	if self:IsPureClientBullet() then return end
	if owner and not IsClassObject(owner, CServerFightableCharacter) then return end
	owner.m_MyOptBullets = owner.m_MyOptBullets or {}
	owner.m_MyOptBullets[self:GetUId()] = true
end

function CServerBulletOpt:IsOnRegionId(r)
	local owner = self:GetOwner()
	local x, y, z = self:GetPixelPosition()
	return owner and owner:IsPosOnRegionId(x, y, z, r)
end

function CServerBulletOpt:PlayEffectAtPos(...)
	local owner = self:GetOwner()
	return owner and owner:PlayEffectAtPos(...)
end

function CServerBulletOpt:GetRandomPlayerInScene()
	local owner = self:GetOwner()
	return owner and owner:GetRandomPlayerInScene()
end

function CServerBulletOpt:GetRandomObjectAroundMe(...)
	local owner = self:GetOwner()
	return owner and owner:GetRandomObjectAroundMe()
end

--这边定义不需要清的数据,
local __no_clear_keys = 
{
}
function CServerBulletOpt:OnReturnToPool(...)
	if false then
		--可以如下调用PrintClassInstanceKVBeforeReturnToPool()查看OnReturnToPoolDefault中
		---即将要被清的key,value以及不会被清的key，value
		PrintClassInstanceKVBeforeReturnToPool(self, __no_clear_keys)
	end

	OnReturnToPoolDefault(self, __no_clear_keys, ...)
	--额外需要清的数据写这里，比如Ctor里初始化的某些key确定后面用不到了，需要置nil
	ClearAllClassData(self.m_BulletMoveData)
	self.m_Share:OnReturn()
end

function CServerBulletOpt:OnReuseFromPool()
	OnReuseFromPoolDefault(self)
	--额外的一些初始化逻辑写这里
	self.m_BulletMoveData:Ctor()
end

function CServerBulletOpt:GetSyncAndSelfIS()
	local owner = self:GetOwner()
	if not owner then return end
	return owner:GetSyncAndSelfIS()
end

function CServerBulletOpt:GridDistanceToObject(target)
	if not (target and target.m_engineObject) then return 1000000 end
	local a,b,c = self:GetPixelPosition()
	local x,y,z = target.m_engineObject:GetPixelPosv3()
	return math.sqrt( (a-x)^2 + (b-y)^2 + (c-z)^2) / EnumGlobalConstants.PIXEL_PER_GRID
end

function CServerBulletOpt:IsPixelPosInAnyWater(x, y, z)
	return self:GetOwner():IsPixelPosInAnyWater(x, y, z)
end

function CServerBulletOpt:GetHitRotationZ(x, y, z)
	local px, py, pz = self:GetPixelPosition()
	local owner = self:GetOwner()
	if not owner then
		return 0
	end

	local coreScene = owner.m_Scene.m_CoreScene
	if not px or not py or not pz then
		return 0
	end
	local minZ, maxZ
	local gridX, gridY, gridZ = GetGridByPixel2(px, py, pz)
	for x = -1, 1 do
		for y = -1, 1 do
			gridZ = coreScene:GetNearestStandGridPixelZByPixel(px + x * EnumGlobalConstants.PIXEL_PER_GRID, py + y * EnumGlobalConstants.PIXEL_PER_GRID, pz)
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

function CServerBulletOpt:IsPixelPosInWater(x, y, z)
	return self:GetOwner():IsPixelPosInWater(x, y, z)
end

function CServerBulletOpt:GetEngineObjectGlobalId()
    return self:GetUId()
end

function CServerBulletOpt:GetFaceToPos(dist, rotate, bNotOnGround)
    local x, y, z = self:GetPixelPosition()
    local owner = self:GetOwner()
    local scene = owner.m_Scene
    local dir = math.rad(self:GetFaceDirection() + (rotate or 0))

    local newX, newY = x + math.cos(dir) * dist * pixel_per_grid, y + math.sin(dir) * dist * pixel_per_grid
    local gridX, gridY = GetGridByPixel2(newX, newY)
    if newX >= 0 and newY >= 0 and scene.m_CoreScene:IsGridInBoundary_Lua(gridX, gridY) then
        return newX, newY, bNotOnGround and z or scene.m_CoreScene:GetNearestStandGridPixelZByPixel(newX, newY, z)
    else
        for i = dist, 0, -0.5 do
            newX, newY = x + math.cos(dir) * i * pixel_per_grid, y + math.sin(dir) * i * pixel_per_grid
            gridX, gridY = GetGridByPixel2(newX, newY)
            if newX >= 0 and newY >= 0 and scene.m_CoreScene:IsGridInBoundary_Lua(gridX, gridY) then
                return newX, newY,
                    bNotOnGround and z or scene.m_CoreScene:GetNearestStandGridPixelZByPixel(newX, newY, z)
            end
        end
        return x, y, z
    end
end

function CServerBulletOpt:GetGroundPos(randomInGrid) --randomInGrid表示是否在当前格子里进行小偏移（不出格子）
    local x, y, z = self:GetGroundXYZ(randomInGrid)
    if not x then
        return
    end

    return { x = x, y = y, z = z }
end

function CServerBulletOpt:GetGroundXYZ(randomInGrid)

    local x, y, z = self:GetPixelPosition()
    local owner = self:GetOwner()
    local scene = owner.m_Scene
    z = scene.m_CoreScene:GetNearestBelowGridPixelZ(x / EnumGlobalConstants.PIXEL_PER_GRID,
        y / EnumGlobalConstants.PIXEL_PER_GRID, z / EnumGlobalConstants.PIXEL_PER_GRID)

    if randomInGrid then
        local newX, newY = x, y
        local gridX, gridY = math.floor(x / EnumGlobalConstants.PIXEL_PER_GRID),
            math.floor(y / EnumGlobalConstants.PIXEL_PER_GRID)

        while newX == x and newY == y do
            newX = x + math.random(0, 63)
            newY = y + math.random(0, 63)
        end

        x, y = newX, newY
    end

    return x, y, z
end

function CServerBulletOpt:GetTargetObject()
	return self.m_BulletMoveData and GetCharacterByEngineObjectGlobalId(self.m_BulletMoveData.m_TargeterEngineObjectId)
end

