function CServerCharacter:InitBulletMoveData(BulletResData, bx, by, bz, ugcBulletData, Sourcer)
	NewBulletMoveDataToObj(self)
	return self:_InitBulletMoveData(BulletResData, bx, by, bz, ugcBulletData, Sourcer)
end

function CServerCharacter:_InitBulletMoveData(BulletResData, bx, by, bz, ugcBulletData, Sourcer)
	local BulletResDataOverride = self.m_BulletResDataOverride
	self.m_BulletOnGroundMoveZ = BulletResData.OnGroundMove * EnumGlobalConstants.PIXEL_PER_GRID
	self.m_BulletDistToGround = 0
	self.m_BulletMoveData.m_BulletDataId = BulletResData.ID
	self.m_BulletMoveData.m_BulletSpeed = ugcBulletData and ugcBulletData[EnumUGCBulletName2PropId["Speed"]] or BulletResDataOverride and BulletResDataOverride.Speed or BulletResData.Speed		--单位秒，Track 角度/秒 其他 像素/秒
	if not BulletResData.NoAoiHit then
		self.m_BulletMoveData.m_BulletSpeed = math.min(self.m_BulletMoveData.m_BulletSpeed, MAX_BULLET_AOI_HIT_SPEED)
	end
	if Sourcer and Sourcer.IsACMonster and Sourcer:IsACMonster() then
		local speedMul = Sourcer:GetParam(EFightProp[AC_AttrName_Bullet_Speed_Ratio])
		self.m_BulletMoveData.m_BulletSpeed = self.m_BulletMoveData.m_BulletSpeed * (1 + speedMul)
	end
	self.m_BulletMoveData.m_CurX = bx
	self.m_BulletMoveData.m_CurY = by
	self.m_BulletMoveData.m_CurZ = bz
    local needDefault = true
    local ugcTrajectory = ugcBulletData and ugcBulletData[EnumUGCBulletName2PropId["Trajectory"]]
	if ugcTrajectory then
        needDefault = false
		local realTrajectory, realTrajectoryArgs
        local info = EnumUgcTrajectory[ugcTrajectory]
        if info then
            realTrajectory = info.Trajectory
            realTrajectoryArgs = info.TrajectoryArgs(ugcBulletData)

            BulletTrajectoryImp:SetBulletMoveTrajectory(self, realTrajectory)
            self.m_BulletMoveData.m_TrajectoryArgs = realTrajectoryArgs
        else
            LogCallContext_lua()
			needDefault = true
        end
    end

    if needDefault then
        local trajectory = BulletResDataOverride and BulletResDataOverride.Trajectory or BulletResData.Trajectory
        BulletTrajectoryImp:SetBulletMoveTrajectory(self, trajectory[1])
        self.m_BulletMoveData.m_TrajectoryArgs = trajectory[2]	
        if #trajectory > 2 then --多于一个的参数		
            local t = {}
            for i = 2, #trajectory do  			
                table.insert(t, trajectory[i])
            end
            self.m_BulletMoveData.m_TrajectoryArgs = t
        end
    end

	if BulletResData.DelayMoveTime > 0 then
		self.m_BulletDelayMoveTime = BulletResData.DelayMoveTime
	end
	if BulletResData.CollisionBuildingFixOff then
		self.m_BulletCollisionFixOff = BulletResData.CollisionBuildingFixOff * 64
	else
		self.m_BulletCollisionFixOff = nil
	end

    local crossBuilding = BulletResData.CrossBuilding
    if ugcBulletData then
        crossBuilding = ugcBulletData[EnumUGCBulletName2PropId["CrossBuilding"]] == 1 and 2 or 0
    end
	if crossBuilding == 2 then
		self.m_BulletMoveData.m_CrossBarrierAbility = EBarrierType.eBT_OutRange --忽略所有障碍检查
	elseif crossBuilding == 1 then
		self.m_BulletMoveData.m_CrossBarrierAbility = EBarrierType.eBT_HighBarrier
	else
		self.m_BulletMoveData.m_CrossBarrierAbility = EBarrierType.eBT_MidBarrier
	end
	self.m_BulletMoveData.m_TimeScale = Sourcer and Sourcer:GetTimeScale()
end

function CServerCharacter:GetBulletMoveTrajectory()
	return self.m_BulletMoveData.m_Trajectory, self.m_BulletMoveData.m_TrajectoryArgs
end

function CServerCharacter:GetBulletMoveDataMsgPack()
	return self.m_BulletMoveData:GetMsgPack()
end

function CServerCharacter:RefreshBulletMoveData(RpcAddress)
	if not self.m_BulletMoveData then return end
	local freqMP, noFreqMP, specMP = self:GetBulletMoveDataMsgPack()
	Gas2Gac:RefreshBulletMoveData(RpcAddress or self:GetSyncAndSelfIS(), self.m_engineObjectId, freqMP, noFreqMP, specMP)
end

function CServerCharacter:GetBulletMoveSideSpeed()
	return self:GetBulletMoveSpeed() * 1
end

function CServerCharacter:GetBulletMoveSpeed()
	return self.m_BulletMoveData.m_BulletSpeed or 0 
end

