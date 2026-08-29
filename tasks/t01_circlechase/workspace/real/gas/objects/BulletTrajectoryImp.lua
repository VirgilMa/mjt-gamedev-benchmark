-- 子弹轨迹移动相关接口
-- 请注意：
-- 由于优化子弹CServerBulletOpt没有继承自CServerCharacter且没有引擎对象, 添加轨迹接口时需要注意
--
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

BulletTrajectoryImp = {}

function BulletTrajectoryImp:SetBulletMoveTrajectory(obj, Trajectory)
	local bulletData = obj.m_BulletMoveData
	if not bulletData then return end
	local trajectory = EnumBulletTracjectory[Trajectory]
	if not trajectory then
		LogCallContext_lua()
		return
	end

	if not obj.m_IsOptBullet then 
		local nowSpecData = bulletData.m_Data_Spec
		if not nowSpecData or bulletData.m_Trajectory ~= trajectory then
			bulletData.m_Trajectory = trajectory
			bulletData.m_Data_Spec = BulletTrajectoryClassTb[trajectory] and BulletTrajectoryClassTb[trajectory]:new()
			bulletData.m_SpecMP = nil
		end
	else
		bulletData.m_Trajectory = trajectory
	end
	obj:RemoveDelayBulletMoveTick()
end

-- 检验目标和子弹在同一个场景 @virgilma
function BulletTrajectoryImp:CheckBulletAndTargetIdInSameScene(Obj, TargetId)
	if not TargetId then return end
	local target = GetCharacterByEngineObjectGlobalId(TargetId)
	if target and Obj.m_IsBullet and target.m_Scene ~= Obj.m_Scene then
		LogCallContext_lua()
	end
end

function BulletTrajectoryImp:CheckBulletAndTargetInSameScene(Obj, Target)
	if Obj.m_IsBullet and Target.m_Scene ~= Obj.m_Scene then
		LogCallContext_lua()
	end
end

function BulletTrajectoryImp:_StartBulletTrajectoryMove(obj, MoveArgs)
	if not obj.m_IsOptBullet and not obj.m_engineObject then return false end
	local BulletData = obj.m_BulletMoveData

	local trajectory, trajectoryArgs = obj:GetBulletMoveTrajectory()
	if trajectory == EnumBulletTracjectory.AIControl then
		if obj.m_IsOptBullet and obj:IsPureClientBullet() then
			obj:RefreshBulletMoveData()
		end
		return true
	elseif trajectory == EnumBulletTracjectory.Missile then
		local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
		if target then
			self:CheckBulletAndTargetInSameScene(obj, target)
			local bNoStop
			if type(trajectoryArgs) == "table" then
				bNoStop = trajectoryArgs[1]
			else
				bNoStop = trajectoryArgs
			end
            self:StartChaseTarget(obj, target, true, nil, nil, nil, nil, nil, nil, bNoStop)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.Missile2 then
		local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
		if target then
			self:CheckBulletAndTargetInSameScene(obj, target)
			self:StartChaseTarget(obj, target, true, nil, nil, nil, nil, nil, BulletData.m_TrajectoryArgs)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.ChasingMissile then
		local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
		if target then
			self:CheckBulletAndTargetInSameScene(obj, target)
			self:StartSemiChaseTarget(obj, target, nil, nil, true)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.Line then
		if MoveArgs.DestPosX and MoveArgs.DestPosY and MoveArgs.DestPosZ then
			local pos = {x=MoveArgs.DestPosX,y=MoveArgs.DestPosY,z=MoveArgs.DestPosZ}
			self:StartChasePos(obj, pos,true)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.Direction_Opt then
		self:StartDirectionMove_Opt(obj, nil, nil, MoveArgs)
		return true
	elseif trajectory == EnumBulletTracjectory.Direction then
		self:StartDirectionMove(obj, nil, nil, MoveArgs)
		return true
	elseif trajectory == EnumBulletTracjectory.DirectionLine then
		if MoveArgs.TargetId then
			local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
			if target then
				self:CheckBulletAndTargetInSameScene(obj, target)
				local pos = {}
				pos.x,pos.y,pos.z = target.m_engineObject:GetPixelPosv3()
				local owner = obj:GetOwner()
				if owner then
					local ownerPosX, ownerPosY, ownerPosZ = owner.m_engineObject:GetPixelPosv3()
					if not trajectoryArgs or trajectoryArgs * EnumGlobalConstants.PIXEL_PER_GRID <= math.abs(ownerPosZ - pos.z) then
						pos.z = pos.z + (MoveArgs.OffsetZ or 0)
						obj.m_BulletOnGroundMoveZ = -1
						obj.m_BulletDistToGround = 0
						self:StartChasePos(obj, pos,true)
						return true
					end
				end
			end
		end
		self:StartDirectionMove(obj, nil, true, MoveArgs)
		return true
	elseif trajectory == EnumBulletTracjectory.LineHook then
		if MoveArgs.TargetId then
			local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
			if target then
				self:CheckBulletAndTargetInSameScene(obj, target)
				local pos = {}
				pos.x,pos.y,pos.z = target.m_engineObject:GetPixelPosv3()
				pos.z = pos.z + (MoveArgs.OffsetZ or 0)
				self:StartChasePos(obj, pos,true)
				return true
			end
		elseif MoveArgs.DestPosX and MoveArgs.DestPosY and MoveArgs.DestPosZ then
			local pos = {x=MoveArgs.DestPosX,y=MoveArgs.DestPosY,z=obj.m_BulletMoveData.m_CurZ or 0}
			self:StartChasePos(obj, pos,true)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.ParabolaPos then
		if MoveArgs.DestPosX and MoveArgs.DestPosY and MoveArgs.DestPosZ then
			local pos = {x=MoveArgs.DestPosX,y=MoveArgs.DestPosY,z=MoveArgs.DestPosZ}
			self:StartParabolaPos(obj, pos)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.ParabolaExPos then
		if MoveArgs.DirX and MoveArgs.DirY and MoveArgs.DirZ then
			self:StartParabolaExPos(obj, nil, nil, MoveArgs.DirX, MoveArgs.DirY, MoveArgs.DirZ)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.ParabolaTarget then
		if MoveArgs.TargetId then
			self:CheckBulletAndTargetIdInSameScene(obj, MoveArgs.TargetId)
			self:StartParabolaTarget(obj, MoveArgs.TargetId)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.Chase then
		if MoveArgs.TargetId then
			local tar = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
			if not tar then return end
			self:CheckBulletAndTargetInSameScene(obj, tar)
			self:StartChaseTarget(obj, tar)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.BezierCurvePos then
		if MoveArgs.DestPosX and MoveArgs.DestPosY and MoveArgs.DestPosZ then
			local pos = {x=MoveArgs.DestPosX, y = MoveArgs.DestPosY, z = MoveArgs.DestPosZ}
			self:StartBezierCurvePos(obj, pos)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.BezierCurveTarget then
		if MoveArgs.TargetId then
			local tar = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
			if not tar then return end
			self:CheckBulletAndTargetInSameScene(obj, tar)
			self:StartBezierCurveTarget(obj, tar)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.Arc then
		if MoveArgs.StartAngle and MoveArgs.EndAngle and MoveArgs.Radius then
			self:StartArcMove(obj, MoveArgs.StartAngle, MoveArgs.EndAngle, MoveArgs.Radius)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.TractionAndCircling then
		if MoveArgs.originVector and MoveArgs.rotaVector and MoveArgs.rotateSpeed and MoveArgs.tracionLimitDist and MoveArgs.tractionSpeed and MoveArgs.tractionAllTime then
			self:StartTractionAndCircling(obj, MoveArgs.originVector, MoveArgs.rotaVector, MoveArgs.rotateSpeed, MoveArgs.tracionLimitDist, MoveArgs.tractionSpeed, MoveArgs.tractionAllTime)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.EffectBullet then 
		self:StartEffectBulletMove(obj, MoveArgs, trajectoryArgs)
		return true
	elseif trajectory == EnumBulletTracjectory.HavokMove then 
		if not obj.m_IsOptBullet and MoveArgs.DestPosX and MoveArgs.DestPosY and MoveArgs.DestPosZ then
			self:StartHavokTrajectoryMove(obj, MoveArgs.DestPosX, MoveArgs.DestPosY, MoveArgs.DestPosZ, MoveArgs.HkSpeedMul, MoveArgs.HKMoveTime)
			return true
		end
	elseif trajectory == EnumBulletTracjectory.RepeatHitTarget then 
		self:StartRepeatHitTarget(obj, MoveArgs)
		return true
	elseif trajectory then 
		return true
	end
	return false
end

function BulletTrajectoryImp:StartRepeatHitTarget(Obj, MoveArgs)
	local BulletData = Obj.m_BulletMoveData
	if not BulletData then
		return
	end
	BulletData.m_TargeterEngineObjectId = MoveArgs.TargetId
	BulletData.m_LeftTickTime = 0
	BulletData.m_RandomSequence = math.random(0, 2147483647)
	BulletData.m_RandomTime = 0
	BulletData.m_LastDDirXYLocalAbs = 0
	local speedMax = BulletData.m_BulletSpeed
	local trajectoryArgs = BulletData.m_TrajectoryArgs
	-- local radius = trajectoryArgs[1] * 64
	local acceleration = trajectoryArgs and trajectoryArgs[1] or 1000
	local angleSpeed = trajectoryArgs and trajectoryArgs[2] or 180
	local speedMin = trajectoryArgs and trajectoryArgs[3] or 500

	-- local sectorAngleRad = DegreeToRadian(sectorAngleDegree)
	-- local angleSpeed = RadianToDegree(speedMin / (radius * math.tan(sectorAngleRad / 2)))
	-- local acceleration = (speedMax - speedMin) * (speedMax + speedMin) / (2 * radius)
	-- BulletData.m_Radius = radius
	BulletData.m_SpeedMax = speedMax
	BulletData.m_SpeedMin = speedMin
	BulletData.m_Acceleration = acceleration
	BulletData.m_AngleSpeed = angleSpeed
	BulletData.m_BulletDir = Obj:GetFaceDirection()
	Obj:RefreshBulletMoveData()
	Obj:StartLuaMove()
end


function BulletTrajectoryImp:StartEffectBulletMove(obj, MoveArgs, trajectoryArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData or not trajectoryArgs then 
		return 
	end
	
	self:SetBulletMoveTrajectory(obj, "EffectBullet")

	local chaseTarget = type(trajectoryArgs) == "table" and trajectoryArgs[4]

	BulletData.m_TotalTime = 0
	BulletData.m_RandomSeed = math.random(1, 999999)

	-- 根据PosType已经算出了起始位置
	BulletData.m_SourceX = BulletData.m_CurX / 64
	BulletData.m_SourceY = BulletData.m_CurY / 64
	BulletData.m_SourceZ = BulletData.m_CurZ / 64
	BulletData.m_DestX = BulletData.m_SourceX
	BulletData.m_DestY = BulletData.m_SourceY
	BulletData.m_DestZ = BulletData.m_SourceZ

	if type(MoveArgs.DestPosX) == "number" and type(MoveArgs.DestPosY) == "number" and type(MoveArgs.DestPosZ) == "number" and not chaseTarget then
		BulletData.m_TargeterEngineObjectId = nil
		BulletData.m_DestX = MoveArgs.DestPosX / 64
		BulletData.m_DestY = MoveArgs.DestPosY / 64
		BulletData.m_DestZ = MoveArgs.DestPosZ / 64
	else
		-- @virgilma
		local target = GetCharacterByEngineObjectGlobalId(MoveArgs.TargetId)
		if target and obj.m_IsBullet and target.m_Scene ~= obj.m_Scene then LogCallContext_lua() end

		BulletData.m_TargeterEngineObjectId = MoveArgs.TargetId
		BulletData.m_DestOffsetX = MoveArgs.DestOffsetX or 0
		BulletData.m_DestOffsetY = MoveArgs.DestOffsetY or 0
		BulletData.m_DestOffsetZ = MoveArgs.DestOffsetZ or 0
	end

	if type(trajectoryArgs) == "number" then 
		BulletData.m_EffectBulletID = trajectoryArgs
	else 
		BulletData.m_EffectBulletID = trajectoryArgs[1]

		if trajectoryArgs[2] == "Dir" then
			local maxDistance = trajectoryArgs[3] or 15
			maxDistance = self:GetDirectionMaxDistance(obj, nil, maxDistance)
			local moveVectorX, moveVectorY, moveVectorZ = self:GetDirectionMoveVector(obj, BulletData, nil, MoveArgs)

			BulletData.m_TargeterEngineObjectId = nil
			BulletData.m_DestX = (BulletData.m_CurX + moveVectorX * maxDistance) / 64
			BulletData.m_DestY = (BulletData.m_CurY + moveVectorY * maxDistance) / 64
			BulletData.m_DestZ = (BulletData.m_CurZ + moveVectorZ * maxDistance) / 64
		end
	end

	-- 特效子弹开始移动时，基于特效路径刷新起点
	local EffectBulletID = BulletData.m_EffectBulletID
	local EffectBulletData = Bullet_EffectBullet[EffectBulletID]
	local moveTime = EffectBulletData.MoveTime
	local bulletMgr = g_ServerEffectMgr:GetBulletMgr()
	local fDestPosX, fDestPosY, fDestPosZ = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	local fDeltaTime = 0
	local fCurX, fCurY, fCurZ, _curRotX, _curRotY, _curRotZ, _curRotW = bulletMgr:EffectBulletEvaluate(
		EffectBulletData.ResourceID, moveTime, BulletData.m_TotalTime, fDeltaTime, 
		BulletData.m_SourceX, BulletData.m_SourceZ, BulletData.m_SourceY, fDestPosX, fDestPosZ, fDestPosY,
		0, BulletData.m_RandomSeed, BulletData.m_CurX/64, BulletData.m_CurZ/64, BulletData.m_CurY/64,
		0, 0, 0, 0
	)
	BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ = fCurX * 64, fCurZ * 64, fCurY * 64


	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:CalcBezierCurveValue(obj)
	local bulletData = obj.m_BulletMoveData
	local x, y = bulletData.m_DestX, bulletData.DestPosY
	if bulletData.m_TargeterEngineObjectId then
		local Targeter = GetCharacterByEngineObjectGlobalId(bulletData.m_TargeterEngineObjectId, true)
		if Targeter then
			x, y = Targeter.m_engineObject:GetPixelPosv3()
		end
	end
	if x and y then
		local d = math.sqrt((bulletData.m_SourceX - x)^2 + (bulletData.m_SourceY - y)^2)
		bulletData.m_CosParam, bulletData.m_SinParam = PowerFunctionCurve.CalculateAngle(bulletData.m_HorizontalParam, bulletData.m_VerticalParam, d, bulletData.m_SmoothParam)
	else
		bulletData.m_CosParam, bulletData.m_SinParam = 1, 0
	end
end

function BulletTrajectoryImp:StartBezierCurvePos(obj, pos, customArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then 
		return 
	end
	
	self:SetBulletMoveTrajectory(obj, "Bezier")
	
	local DestPosX,DestPosY,DestPosZ = pos.x, pos.y, pos.z
	if not (DestPosX and DestPosY and DestPosZ) then
		LogCallContext_lua()
		return
	end

	local BulletPosX, BulletPosY, BulletPosZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local _, args = obj:GetBulletMoveTrajectory()
    args = customArgs and customArgs or args

	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
	BulletData.m_SourceX = BulletPosX
	BulletData.m_SourceY = BulletPosY
	BulletData.m_SourceZ = BulletPosZ
	--方便策划配置，这里做个横纵坐标的转换
	BulletData.m_HorizontalParam = args[2] * 64
	BulletData.m_VerticalParam = -args[1] * 64
	BulletData.m_FlightTime = args[5] or -1
	BulletData.m_ZDegree = BulletData.m_VerticalParam > 0 and args[3] or -args[3]
	BulletData.m_SmoothParam = args[4] or 0.5
	BulletData.m_InflectionSpeed = args[6] or -1

	self:CalcBezierCurveValue(obj)
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartBezierCurveTarget(obj, target, customArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then 
		return 
	end
	self:SetBulletMoveTrajectory(obj, "Bezier")
	
	local DestPosX, DestPosY, DestPosZ = target.m_engineObject:GetPixelPosv3()
	local BulletPosX, BulletPosY, BulletPosZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local _, args = obj:GetBulletMoveTrajectory()
    args = customArgs and customArgs or args

	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
	BulletData.m_SourceX = BulletPosX
	BulletData.m_SourceY = BulletPosY
	BulletData.m_SourceZ = BulletPosZ
	--方便策划配置，这里做个横纵坐标的转换
	BulletData.m_HorizontalParam = args[2] * 64
	BulletData.m_VerticalParam = -args[1] * 64
	BulletData.m_TrackTime = args[5] or -1
	BulletData.m_FlightTime = args[6] or -1
	BulletData.m_InflectionSpeed = args[7] or -1

	BulletData.m_TargeterEngineObjectId = target.m_engineObjectId
	BulletData.m_ZDegree = BulletData.m_VerticalParam > 0 and args[3] or -args[3]
	BulletData.m_SmoothParam = args[4] or 0.5
	BulletData.m_NoStop = args[8] or -1

	self:CalcBezierCurveValue(obj)
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartArcMove(obj, startAngle, endAngle, radius)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	self:SetBulletMoveTrajectory(obj, "Arc")

	BulletData.m_ArcRotateCurAngle = 0
	BulletData.m_ArcRotateMaxAngle = endAngle - startAngle
	BulletData.m_ArcRotateRadius = radius
	BulletData.m_ArcCurYawAngle = obj:GetFaceDirection() - startAngle

	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartParabolaPos(obj, pos)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	self:SetBulletMoveTrajectory(obj, "ParabolaPos")
	
	local BulletPosX,BulletPosY,BulletPosZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local _,args = obj:GetBulletMoveTrajectory()
	
	BulletData.m_ParabolaA = (type(args) == 'table' and args[1] or args)
	BulletData.m_ParabolaH = (type(args) == 'table' and args[2])
	BulletData.m_ParabolaAllTime = (type(args) == 'table' and args[3])
	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = pos.x, pos.y, pos.z
	BulletData.m_SourceX = BulletPosX
	BulletData.m_SourceY = BulletPosY
	BulletData.m_SourceZ = BulletPosZ
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartParabolaExPos(obj, speed, g, dirX, dirY, dirZ)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end

	self:SetBulletMoveTrajectory(obj, "ParabolaExPos")
	
	if not g then
		local _, args = obj:GetBulletMoveTrajectory()
		g = args
	end
	
	if not speed then 
		speed = BulletData.m_BulletSpeed 
	else
		BulletData.m_BulletSpeed = speed
	end
	if not dirX then
		dirX, dirY, dirZ = obj:GetFaceDirectionXYZ()
	elseif dirX >= 1 or dirY >= 1 or dirZ >= 1 then
		dirX, dirY, dirZ = NormalizeVectorXYZ(dirX, dirY, dirZ)
	end
	BulletData.m_G = g or (9.8*64)
	BulletData.m_VectorZ = speed * dirZ
	BulletData.m_OriDirX, BulletData.m_OriDirY, BulletData.m_OriDirZ = dirX, dirY, dirZ
	BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ = obj:GetPixelPosition()

	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartParabolaTarget(obj, targetId)
	--LOG_PRINT(DEBUG,"StartParabolaPos", pos.x,pos.y,pos.z)
	local target = GetCharacterByEngineObjectGlobalId(targetId)
	if not target then
		return
	end
	local BulletData = obj.m_BulletMoveData
	if not BulletData then 
		return 
	end
	
	self:SetBulletMoveTrajectory(obj, "ParabolaPos")
	
	
	local DestPosX,DestPosY,DestPosZ = target.m_engineObject:GetPixelPosv3()
	local BulletPosX,BulletPosY,BulletPosZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local _,args = obj:GetBulletMoveTrajectory()
	
	BulletData.m_ParabolaA = (type(args) == 'table' and args[1] or args)
	BulletData.m_ParabolaH = (type(args) == 'table' and args[2])
	BulletData.m_ParabolaAllTime = (type(args) == 'table' and args[3])
	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX,DestPosY,DestPosZ
	BulletData.m_TargeterEngineObjectId = targetId
	BulletData.m_SourceX = BulletPosX
	BulletData.m_SourceY = BulletPosY
	BulletData.m_SourceZ = BulletPosZ
	BulletData.m_bTrackZ = (type(args) == 'table' and args[4] == 1 or nil)
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartDirectionMove_Opt(obj, Dir, bIgnoreMaxD, MoveArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then
		return
	end
	self:SetBulletMoveTrajectory(obj, "Direction_Opt")
	
	BulletData.m_MoveVectorX, BulletData.m_MoveVectorY, BulletData.m_MoveVectorZ = self:GetDirectionMoveVector(obj, BulletData, Dir, MoveArgs)
	BulletData.m_Accel = obj:GetData("NoAoiHit") and obj:GetData("Acceleration") or 0
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj:GetPixelPosition()
	-- print("测试", BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ)

	local _, maxD = obj:GetBulletMoveTrajectory()
	BulletData.m_MaxDistance = self:GetDirectionMaxDistance(obj, bIgnoreMaxD, maxD)

	if MoveArgs then
		BulletData.m_StartTime = MoveArgs.StartTime
	end
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartDirectionMove(obj, Dir, bIgnoreMaxD, MoveArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then
		return
	end
	self:SetBulletMoveTrajectory(obj, "Direction")
	
	BulletData.m_MoveVectorX, BulletData.m_MoveVectorY, BulletData.m_MoveVectorZ = self:GetDirectionMoveVector(obj, BulletData, Dir, MoveArgs)
	BulletData.m_Accel = obj:GetData("NoAoiHit") and obj:GetData("Acceleration") or 0
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj:GetPixelPosition()
	-- print("测试", BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ)

	local _, maxD = obj:GetBulletMoveTrajectory()
	BulletData.m_MaxDistance = self:GetDirectionMaxDistance(obj, bIgnoreMaxD, maxD)

	if MoveArgs then
		BulletData.m_StartTime = MoveArgs.StartTime
	end
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:GetDirectionMoveVector(obj, BulletData, Dir, MoveArgs)
	local dir = Dir or DegreeToRadian(obj:GetFaceDirection())

	if MoveArgs and MoveArgs.DestPosX then
		if MoveArgs.IsClientSelectPos then 
			local ignoreClientSelectPos = obj:GetData("IgnoreClientSelectPos")
			if not ignoreClientSelectPos then
				local dx, dy, dz = MoveArgs.DestPosX - obj.m_BulletMoveData.m_CurX, MoveArgs.DestPosY - obj.m_BulletMoveData.m_CurY, MoveArgs.DestPosZ - obj.m_BulletMoveData.m_CurZ
				if obj.m_BulletOnGroundMoveZ and obj.m_BulletOnGroundMoveZ >= 0 then
					dz = 0
				end
				local dist = math.sqrt(dx^2 + dy^2 + dz^2)
				if dist > 0 then
					local distXY =  math.sqrt((dx/dist)^2 + (dy/dist)^2)
					if distXY == 0 then
						distXY = 0.001
					end
					
					local x = distXY * math.cos(dir)
					local y = distXY * math.sin(dir)
					return x, y, dz /dist
				end
			else
				if ignoreClientSelectPos > 0 then
					local owner = obj:BulletGetOwner()
					if owner then
						local ownerX, ownerY, ownerZ = owner.m_engineObject:GetPixelPosv3()
						local dx, dy, dz = MoveArgs.DestPosX - ownerX, MoveArgs.DestPosY - ownerY, MoveArgs.DestPosZ - ownerZ - ignoreClientSelectPos
						if math.abs(dz) <= 4 * EnumGlobalConstants.PIXEL_PER_GRID then	--这个4后面肯定要调，但是具体怎么调未定，先就这么写着了
							local dist = math.sqrt(dx^2 + dy^2 + dz^2)
							if dist > 0 then
								return dx/dist, dy/dist, dz/dist
							end
						end
					end
				end
			end
		end
	end
	if MoveArgs and MoveArgs.Is3DDir then
		return MoveArgs.DirX, MoveArgs.DirY, MoveArgs.DirZ
	end

	return math.cos(dir), math.sin(dir), 0
end

function BulletTrajectoryImp:GetDirectionMaxDistance(obj, bIgnoreMaxD, maxD)
	if not bIgnoreMaxD then
		local owner = obj:BulletGetOwner()
		local rangeMulti = 1
		if owner and IsClassObject(owner, CServerFightableCharacter) then
			rangeMulti = 1 + owner:GetParam(EFightProp.Range)
		end
		return maxD and maxD * EnumGlobalConstants.PIXEL_PER_GRID * rangeMulti
	else
		return nil
	end
end

function BulletTrajectoryImp:StartSemiChaseTarget(obj, ChaseTarget, MaxChaseAngle, StopChaseAngle, bNoSideSpeed, OffsetZ, SideSpeed, SideSpeedDecay, MaxChaseAngleDecay)
	if not ChaseTarget or not ChaseTarget.m_engineObject then return end
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	
	self:SetBulletMoveTrajectory(obj, "HalfChase")
	
	OffsetZ = OffsetZ or 0
	BulletData.m_TargeterEngineObjectId = ChaseTarget.m_engineObjectId
	
	local bx, by, bz = obj:GetPixelPosition()
	local cx, cy, cz = ChaseTarget.m_engineObject:GetPixelPosv3()
	cz = cz + OffsetZ
	
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = bx, by, bz
	BulletData.m_DestX,BulletData.m_DestY,BulletData.m_DestZ = cx, cy, cz
	BulletData.m_TargetOffsetZ = OffsetZ
	
	if not bNoSideSpeed then
		if SideSpeed then 
			BulletData.m_SideSpeed = SideSpeed
		else
			BulletData.m_SideSpeed = obj:GetBulletMoveSideSpeed()
		end
		if SideSpeedDecay then 
			BulletData.m_SideSpeedDecay = SideSpeedDecay
		else
			BulletData.m_SideSpeedDecay = obj:GetBulletMoveSpeed() / (Dist_XYZ2(bx, by, bz, cx, cy, cz) / obj:GetBulletMoveSpeed() / 1.2)--2分之一的时间用来速度分量的消失,则每秒削减多少速度
		end
	else
		BulletData.m_SideSpeed = 0
		BulletData.m_SideSpeedDecay = 0
	end
	BulletData.m_BulletSpeedNow = 0
	BulletData.m_MaxChaseAngle = MaxChaseAngle
	BulletData.m_StopChaseAngle = StopChaseAngle
	BulletData.m_MaxChaseAngleDecay = MaxChaseAngleDecay
	BulletData.m_TrackTime = 0
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartChaseTarget(obj, ChaseTarget, bNoSideSpeed, OffsetZ, SideSpeed, SideSpeedDecay, OffsetX, OffsetY, MaxAngleSpeed, bNoStop)
	--LOG_PRINT(DEBUG,obj.m_engineObjectId, "StartChaseTarget", ChaseTarget.m_engineObjectId, OffsetZ)
	if not ChaseTarget or not ChaseTarget.m_engineObject then return end
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end

	if IsRunningServerCode() and not obj.m_IsOptBullet and obj.m_Scene ~= ChaseTarget.m_Scene then
		return
	end
	
	self:SetBulletMoveTrajectory(obj, "Chase")

	-- 新加的offset用destoffset，老的用targetoffset
	BulletData.m_DestOffsetX = OffsetX or BulletData.m_DestOffsetX
	BulletData.m_DestOffsetY = OffsetY or BulletData.m_DestOffsetY
	BulletData.m_DestOffsetZ = OffsetZ or BulletData.m_DestOffsetZ
	
	OffsetZ = OffsetZ or 0
	BulletData.m_TargeterEngineObjectId = ChaseTarget.m_engineObjectId
	
	local bx, by, bz = obj:GetPixelPosition()
	local cx, cy, cz = ChaseTarget.m_engineObject:GetPixelPosv3()
	cz = cz + OffsetZ
	cx = cx + (OffsetX or 0)
	cy = cy + (OffsetY or 0)

	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = bx, by, bz
	BulletData.m_DestX,BulletData.m_DestY,BulletData.m_DestZ = cx, cy, cz
	BulletData.m_TargetOffsetZ = OffsetZ
	BulletData.m_Accel = obj:GetData("NoAoiHit") and obj:GetData("Acceleration") or 0
	BulletData.m_NoStop = bNoStop
	
	if not bNoSideSpeed then
		if SideSpeed then 
			BulletData.m_SideSpeed = SideSpeed
		else
			BulletData.m_SideSpeed = obj:GetBulletMoveSideSpeed()
		end
		if SideSpeedDecay then 
			BulletData.m_SideSpeedDecay = SideSpeedDecay
		else
			local dist = Dist_XYZ2(bx, by, bz, cx, cy, cz)
			if dist > 0 then
				BulletData.m_SideSpeedDecay = obj:GetBulletMoveSpeed() / (Dist_XYZ2(bx, by, bz, cx, cy, cz) / obj:GetBulletMoveSpeed() / 1.2)--2分之一的时间用来速度分量的消失,则每秒削减多少速度
			else
				-- 如果在同一个位置，那么不需要有边速度
				BulletData.m_SideSpeed = 0
				BulletData.m_SideSpeedDecay = 0
			end
		end
	else
		BulletData.m_SideSpeed = 0
		BulletData.m_SideSpeedDecay = 0
	end
	BulletData.m_BulletSpeedNow = 0
    if MaxAngleSpeed and MaxAngleSpeed >= 0 then
        BulletData.m_MaxAngleSpeed = MaxAngleSpeed
	else
        BulletData.m_MaxAngleSpeed = nil
    end
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartChasePos(obj, Pos, bNoSideSpeed, SideSpeed, SideSpeedDecay, MaxAngleSpeed)
	--LOG_PRINT(DEBUG,obj.m_engineObjectId, "StartChasePos", Pos.x,Pos.y,Pos.z)
	if not Pos then return end
	if type(Pos.x) ~= "number" or type(Pos.y) ~= "number" or type(Pos.z) ~= "number" then
		QERR("StartChasePos invalid Pos", obj and obj.m_engineObjectId, type(Pos.x), type(Pos.y), type(Pos.z))
		return
	end
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	
	self:SetBulletMoveTrajectory(obj, "Chase")

	BulletData.m_TargeterEngineObjectId = nil
	local bx, by, bz = obj:GetPixelPosition()
	
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = bx, by, bz
	BulletData.m_DestX,BulletData.m_DestY,BulletData.m_DestZ = Pos.x,Pos.y,Pos.z
	BulletData.m_Accel = obj:GetData("NoAoiHit") and obj:GetData("Acceleration") or 0
	
	if not bNoSideSpeed then
		if SideSpeed then 
			BulletData.m_SideSpeed = SideSpeed
		else
			BulletData.m_SideSpeed = obj:GetBulletMoveSideSpeed()
		end
		if SideSpeedDecay then 
			BulletData.m_SideSpeedDecay = SideSpeedDecay
		else
			BulletData.m_SideSpeedDecay = obj:GetBulletMoveSpeed() / (Dist_XYZ2(bx, by, bz, Pos.x, Pos.y, Pos.z) / obj:GetBulletMoveSpeed() / 1.2)--2分之一的时间用来速度分量的消失,则每秒削减多少速度
		end
	else
		BulletData.m_SideSpeed = 0
		BulletData.m_SideSpeedDecay = 0
	end
    if MaxAngleSpeed and MaxAngleSpeed >= 0 then
        BulletData.m_MaxAngleSpeed = MaxAngleSpeed
    end
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartTractionAndCircling(obj, isOriginWithTarget, originId, originVector, rotaVector, rotateSpeed, isTraction, tracionLimitDist, tractionSpeed, isZMove, rotateZSpeed, rotateZLimitHigh, tractionAllTime)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end

	self:SetBulletMoveTrajectory(obj, "TractionAndCircling")
	local newOriginWithTarget = isOriginWithTarget or BulletData.m_OriginWithTarget
	local newOriginId = originId or BulletData.m_OriginId
	local newStartPoint = originVector or BulletData.m_StartPoint
	local newRotaVector = rotaVector or BulletData.m_RotateVector
	local newRotateSpeed = rotateSpeed or BulletData.m_RotateSpeed
	local newIsTraction = isTraction or BulletData.m_IsTraction
	local newTractionSpeed = tractionSpeed or BulletData.m_TractionSpeed
	local newTracionLimitDist = tracionLimitDist or BulletData.m_TracionLimitDist
	local newIsZMove = isZMove or BulletData.m_IsZMove
	local newRotateZSpeed = rotateZSpeed or BulletData.m_RotateZSpeed
	local newRotateZLimitHigh = rotateZLimitHigh or BulletData.m_RotateZLimitHigh
	local newAllTime = tractionAllTime or BulletData.m_TractionAllTime

	local haveStartPoint
	if newOriginWithTarget then
		local target = GetObjectByGlobalId(newOriginId)
		if not target then
			return
		end
		haveStartPoint = true
	else
		haveStartPoint = not not newStartPoint
	end

	if newIsTraction then
		if not newTractionSpeed or not newTracionLimitDist then
			return
		end
	end

	if newIsZMove then
		if not newRotateZLimitHigh or not newRotateZSpeed then
			return
		end
	end

	if not haveStartPoint or not newRotaVector or not newRotateSpeed or not newAllTime then
		return
	end
	
	newRotaVector = NormalizeVector3D({x = newRotaVector[1], y = newRotaVector[2], z = newRotaVector[3]})
	newRotaVector = {newRotaVector.x, newRotaVector.y, newRotaVector.z}

	BulletData.m_OriginWithTarget = newOriginWithTarget
	BulletData.m_OriginId = newOriginId
	BulletData.m_StartPoint = newStartPoint
	BulletData.m_RotateVector = newRotaVector
	BulletData.m_RotateSpeed = newRotateSpeed
	BulletData.m_IsTraction = newIsTraction
	BulletData.m_TractionSpeed = newTractionSpeed
	BulletData.m_TracionLimitDist = newTracionLimitDist
	BulletData.m_IsZMove = newIsZMove
	BulletData.m_RotateZSpeed = newRotateZSpeed
	BulletData.m_RotateZLimitHigh = newRotateZLimitHigh
	BulletData.m_TractionAllTime = newAllTime
	BulletData.m_TractionStartTime = g_App:GetGlobalTime() / 1000
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj:GetPixelPosition()
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartBoatFrontMove2D(obj, speed, angleSpeed, time, bUpdate)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end

	if not bUpdate then
		self:SetBulletMoveTrajectory(obj, "BoatFrontMove2D")
	else
		BulletData = {}
		BulletData.m_AngleSpeed =  math.rad(angleSpeed)
		BulletData.m_TotalTime = time
		BulletData.m_BulletSpeed = speed
		-- 加0.1是因为服务器同步到客户端会有延迟，做一个补偿
		BulletData.ChangePoint = (g_App:GetGlobalTime() + 0.1) / 1000
		CServerBullet.UpdateProperty(obj, "m_LateChangeData", BulletData)
		return 
	end
	
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj.m_engineObject:GetPixelPosv3()
	
	
	BulletData.m_AngleSpeed =  math.rad(angleSpeed)
	BulletData.m_StartX,BulletData.m_StartY = obj:GetPixelPosition()
	BulletData.m_TotalTime = time
	BulletData.m_StartTime = g_App:GetGlobalTime() / 1000
	BulletData.m_StartRad = math.rad(obj:GetFaceDirection())
	BulletData.m_BulletSpeed = speed
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartCircleTarget(obj, CircleTarget, CircleRadius, CircleMaxHeight, CircleMinHeight, CircleSpeedZ, CircleClockWise, ExtraArgs)
	if not CircleTarget or not CircleTarget.m_engineObject then return end
	-- LOG_PRINT(DEBUG,"StartCircleTarget", CircleTarget.m_engineObjectId, CircleRadius, CircleMaxHeight, CircleMinHeight, CircleSpeedZ, CircleTarget.m_IsMonster and CircleTarget:GetTemplateId(), ExtraArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	
	self:SetBulletMoveTrajectory(obj, "Circle")
	
	local newRadius = CircleRadius or BulletData.m_CircleRadius
	local newMaxHeight = CircleMaxHeight or BulletData.m_CircleMaxHeight
	local newMinHeight = CircleMinHeight or BulletData.m_CircleMinHeight
	local newSpeedZ = CircleSpeedZ or BulletData.m_CircleSpeedZ

	if not newRadius or not newMaxHeight or not newMinHeight or not newSpeedZ then return end
	if newMinHeight > newMaxHeight then LogCallContext_lua() return end
	
	BulletData.m_TargeterEngineObjectId = CircleTarget.m_engineObjectId

	local TargetPos = {}
	TargetPos.x, TargetPos.y, TargetPos.z = CircleTarget.m_engineObject:GetPixelPosv3()
	
	BulletData.m_CircleRadius = newRadius
	BulletData.m_CircleMaxHeight = newMaxHeight
	BulletData.m_CircleMinHeight = newMinHeight
	BulletData.m_CircleSpeedZ = newSpeedZ
	BulletData.m_ClockWise = CircleClockWise
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj:GetPixelPosition()
	BulletData.m_RelativeZ = 0
	BulletData.m_TargetPos = TargetPos
	BulletData.m_RadiusEquipToDistance_TargetId = ExtraArgs and ExtraArgs.RadiusEquipToDistance_TargetId

	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartChaseTarget3D(obj, ChaseTarget, SideTime, XZDegree, XYDegree)
	if not ChaseTarget or not ChaseTarget.m_engineObject then return end
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	
	self:SetBulletMoveTrajectory(obj, "Chase3D")
	
	
	BulletData.m_TargeterEngineObjectId = ChaseTarget.m_engineObjectId
	BulletData.m_CurX,BulletData.m_CurY,BulletData.m_CurZ = obj:GetPixelPosition()
	BulletData.m_DestX,BulletData.m_DestY,BulletData.m_DestZ = ChaseTarget.m_engineObject:GetPixelPosv3()
	
	XZDegree = DegreeToRadian(XZDegree)
	XYDegree = DegreeToRadian(XYDegree)
	
	local XZSpeed = obj:GetBulletMoveSpeed() * 0.65
	local SideSpeed = XZSpeed * math.cos(XZDegree)
	BulletData.m_SideSpeedX = SideSpeed * math.cos(XYDegree)
	BulletData.m_SideSpeedY = SideSpeed * math.sin(XYDegree)
	BulletData.m_BulletSpeedNow = 0
	BulletData.m_SideTime = SideTime * 1000
	BulletData.m_ZSpeed = math.abs(XZSpeed * math.sin(XZDegree))
	BulletData.m_ZSpeedDecay = BulletData.m_ZSpeed / BulletData.m_SideTime			--pixel/ms
	BulletData.m_XSpeedDecay = BulletData.m_SideSpeedX / BulletData.m_SideTime
	BulletData.m_YSpeedDecay = BulletData.m_SideSpeedY / BulletData.m_SideTime
	
	obj:RefreshBulletMoveData()
	obj:StartLuaMove()
end

function BulletTrajectoryImp:StartHavokTrajectoryMove(obj, x, y, z, speedMul, moveTime)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end
	self:SetBulletMoveTrajectory(obj, "HavokMove")
	
	local pathId, cutBegin, cutEnd = nil, nil, nil
	if type(BulletData.m_TrajectoryArgs) == "number" then 
		pathId = BulletData.m_TrajectoryArgs
	else
		pathId, cutBegin, cutEnd = BulletData.m_TrajectoryArgs[1], BulletData.m_TrajectoryArgs[2], BulletData.m_TrajectoryArgs[3] 
	end
	if not pathId then 
		LogCallContext_lua()
		return 
	end
	cutBegin = cutBegin or -1
	cutEnd = cutEnd or -1

	if moveTime then 
		local diffTime = cutEnd - cutBegin
		if diffTime <= 0 or moveTime <= 0 then 
			LogCallContext_lua()
			return 
		end
		speedMul = diffTime / moveTime
	end
	speedMul = speedMul or 1
	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = x, y, z

	obj:RefreshBulletMoveData()
	BulletData.m_Status = nil
	obj.m_engineObject:IntHavokMoveWithEndPos(pathId, 0, x, y, z, speedMul, cutBegin, cutEnd, MoveArgs.eMA_BambooJump, 0)
end

function BulletTrajectoryImp:StartBezierSplineMove(obj, splineIndex, startIndex, isForward)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then return end

	obj:StartBezierSplineMove(splineIndex, startIndex, isForward)
end

function BulletTrajectoryImp:StartForwardChase2D(obj, ChaseTarget, v_max, omega_max, a_max, alpha_max, stop_dis, v_turn)
    local BulletData = obj.m_BulletMoveData
    if not BulletData then return end
    local x, y, z = obj:GetPixelPosition()
    local theta = obj:Get360DegreeDirection()
    local now = GetGlobalTime_ms()
    local Kp, Kd = 1, 1.3 -- 经验值

    BulletData.m_TargetEID = ChaseTarget.m_engineObjectId
    BulletData.m_Simulator = CForwardMoveSimulator:new(x, y, z, theta, 0, v_max * 0.35, v_max, a_max, alpha_max * 0.35, alpha_max, omega_max, 0.015, now) 
	--BulletData.m_Simulator = CForwardMoveSimulator:new(x, y, z, theta, 0, 0, v_max, omega_max, a_max, alpha_max, 33, now, Kp, Kd, stop_dis, v_turn)
end
