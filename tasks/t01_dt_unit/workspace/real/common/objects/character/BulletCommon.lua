--
-- $Id$
--

local pixel_per_grid = EnumGlobalConstants.PIXEL_PER_GRID
local sqrt, abs, sin, cos, atan2, floor, max, min, random = math.sqrt, math.abs, math.sin, math.cos, math.atan2, math.floor, math.max, math.min, math.random
local rad = math.rad
local deg = math.deg
local clamp = clamp
local pi = math.pi
local pi2 = pi * 2

-- 蹦极悬挂在绳尾时的晃动参数(振幅单位米,时间秒)
local BUNGEE_HANG_AMP_START = 1.2   -- 初始振幅
local BUNGEE_HANG_AMP_STEADY = 0.35 -- 衰减后的稳态振幅
local BUNGEE_HANG_DECAY = 0.3       -- 衰减系数,越大停得越快
local BUNGEE_HANG_FREQ = 3.5        -- 晃动角频率 rad/s

local function sqrDistPointSegment(p0X, p0Y, p1X, p1Y, pRadius, qX, qY)
	local p0p1X, p0p1Y = p1X - p0X, p1Y - p0Y
	local p0qX, p0qY = qX - p0X, qY - p0Y 
	local p1qX, p1qY = qX - p1X, qY - p1Y

	local e = p0qX *p0p1X + p0qY + p0p1Y
	if e <= 0 then
		return p0qX * p0qX + p0qY * p0qY
	end
	local f = p0p1X * p0p1X + p0p1Y * p0p1Y
	if e >= f then
		return p1qX * p1qX + p1qY * p1qY
	end

	return  p0qX * p0qX + p0qY * p0qY - e * e / f
end

--p0: 起点 p1:终点 pR:伤害半径 q:目标点 qR：目标半径
function OverlapTest(p0X, p0Y, p1X, p1Y, pRadius, qX, qY, qRadius)
	local rSum = pRadius + qRadius
	local distSqr = sqrDistPointSegment(p0X, p0Y, p1X, p1Y, pRadius, qX, qY)
	return distSqr <= rSum
end

local isRunningServerCode = IsRunningServerCode()
local debugWorker = false

--"m_SkillId"
--"m_TargeterEngineObjectId"
--"m_BulletDataId"
--"m_DestX"
--"m_DestY"
--"m_DestZ"
--"m_CurX"
--"m_CurY"
--"m_CurZ"
--"m_BulletSpeed"
--"m_HookCharacterId"
--"m_DestObjId"
local DeltaTime

function CBulletTrackMgr:GetMoveCyc(bullet)
	return DeltaTime
end

function CBulletTrackMgr:UpdateRepeatHitTarget(bullet, deltaTime)
    local BulletData = bullet.m_BulletMoveData
    local leftTickTime = BulletData.m_LeftTickTime

    leftTickTime = leftTickTime + deltaTime
    local dir = BulletData.m_BulletDir
    local targetEID = BulletData.m_TargeterEngineObjectId
    local acc = BulletData.m_Acceleration
    local speedMax = BulletData.m_SpeedMax
    local speedMin = BulletData.m_SpeedMin
    local x, y, z = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ

    local target = EID2OBJ(targetEID)
    local tickTime = 0

    if not target then
        -- delay destroy
        RegisterObjTickWithDuration(bullet, "TrajectroyDelayDestroy", function()
            if bullet.m_IsValid then
                bullet:Destroy()
            end
        end, 1, 1)
        return
    end

    local tx, ty, tz = target.m_engineObject:GetPixelPosv3()
    local LastDDirXYLocalAbs = BulletData.m_LastDDirXYLocalAbs
    local speed = BulletData.m_BulletSpeed
    local angleSpeedSetting = BulletData.m_AngleSpeed
    local angleSpeed
    local bHitTarget

    deltaTime = 16
    local deltaTime_s = deltaTime / 1000
    -- 分批次计算保证target位置准确时，服务器与客户端的位置完全一致
    while (leftTickTime > deltaTime and tickTime < 60) do
        tickTime = tickTime + 1
        leftTickTime = leftTickTime - deltaTime
        local stepxyz = deltaTime_s * speed
        local dx, dy, dz = tx - x, ty - y, tz - z
        local dxyz = sqrt(dx * dx + dy * dy + dz * dz)
        local ddirxy = deg(atan2(dy, dx))
        local ddirxyLocal = NormalizeAngle(ddirxy - dir)
        local ddirxyLocalAbs = abs(ddirxyLocal)

        if ddirxyLocalAbs > 170 and dxyz < 64 * 3 then
            angleSpeed = 1 -- 设一个小值
        else
            angleSpeed = angleSpeedSetting
        end

        local maxDirDiff = angleSpeed * deltaTime_s

        -- 当目标处于子弹后方时减速，前方时加速
        local newSpeed, avgSpeed
        if ddirxyLocalAbs > 90 then
            newSpeed = max(speedMin, speed - acc * deltaTime_s)
            avgSpeed = (speed + newSpeed) / 2
        elseif ddirxyLocalAbs < 5 then
            newSpeed = min(speedMax, speed + acc * deltaTime_s)
            avgSpeed = (speed + newSpeed) / 2
        else
            newSpeed = speed
            avgSpeed = speed
        end
        speed = newSpeed
        stepxyz = deltaTime_s * avgSpeed

        local changeSign = 1
        -- 当目标处于子弹的接近正后方时，加random造成一点扰动，避免一直顺时针或逆时针旋转，random用服务器统一产生的序列
        if LastDDirXYLocalAbs < 175 and ddirxyLocalAbs > 175 then
            local randomSequence = BulletData.m_RandomSequence
            local randomTime = BulletData.m_RandomTime
            changeSign = (bit.band(bit.rshift(randomSequence, randomTime % 32), 1) == 1) and 1 or -1
            BulletData.m_RandomTime = randomTime + 1
            -- pppf("changeSign", changeSign, string.format("%x", randomSequence), randomTime)
        else
            changeSign = (ddirxyLocal < 0 and -1 or 1)
        end
        local dirDiff = min(ddirxyLocalAbs, maxDirDiff) * changeSign

        local newDir = dir + dirDiff
        local newDirRad = rad(newDir)
        local dxy = sqrt(dx * dx + dy * dy)

        -- todo: need a quaternian to record rotation
        local stepxy, stepz
        if dxyz ~= 0 and dxy ~= 0 then
            stepz = stepxyz / dxyz * dz
            stepxy = stepxyz / dxyz * dxy
        else
            stepz = 0
            stepxy = stepxyz
        end

        local stepx, stepy = stepxy * cos(newDirRad), stepxy * sin(newDirRad)

        x, y, z = x + stepx, y + stepy, z + stepz
        -- pppf(string.format("%d\t(%.2f, %.2f)\t(%.2f, %.2f)\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f", leftTickTime, x, y, stepx,
        --     stepy, dir, newDir, ddirxyLocalAbs, angleSpeed, speed))
        dir = newDir
        LastDDirXYLocalAbs = ddirxyLocalAbs

        if isRunningServerCode then
            if tx - x < 32 and ty - y < 32 and tz - z < 32 then
                bHitTarget = true
            end
        end
    end
    BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ = x, y, z
    BulletData.m_LastDDirXYLocalAbs = LastDDirXYLocalAbs
    BulletData.m_LeftTickTime = leftTickTime
    BulletData.m_BulletDir = dir
    BulletData.m_BulletSpeed = speed

    if isRunningServerCode then
        if bHitTarget then
            bullet:TargetReached()
        end
    else
        bullet.m_BulletMoveNeedTurn = true
    end
end

function NormalizeAngle(angle)
    angle = angle % 360
    if angle > 180 then
        angle = angle - 360
    end
    return angle
end

function CBulletTrackMgr:UpdateCircleChase(bullet, deltaTime)
    local BulletData = bullet.m_BulletMoveData
    local x, y, z = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
    local targetEID = BulletData.m_TargeterEngineObjectId
    local target = EID2OBJ(targetEID)
    local speed = BulletData.m_BulletSpeed
    local angleSpeed = speed -- init angle speed
    local stepxyz = deltaTime * speed / 1000
    local dir = bullet:GetFaceDirection()

    local totalTime = BulletData.m_TotalTime
    local radius1 = BulletData.m_Radius1
    local radius2 = BulletData.m_Radius2

    -- txyz: target xyz
    -- dxyz: source-target xyz
    -- stepxyz: current movement xyz

    if not target then
        local stepx, stepy = stepxyz * math.cos(math.rad(dir)), stepxyz * math.sin(math.rad(dir))
        BulletData.m_CurX, BulletData.m_CurY = x + stepx, y + stepy
        return
    end

    local tx, ty, tz = target.m_engineObject:GetPixelPosv3()
    tz = tz + 64 + 64 -- z轴抬升一格
    local dx, dy, dz = tx - x, ty - y, tz - z
    local dxyz = math.sqrt(dx * dx + dy * dy + dz * dz)
    local startTime = BulletData.m_StartTime
    local now = GetGlobalTime_ms()
    local leftTime = totalTime - (now - startTime)
    local verticalSpeed
    if leftTime <= 0 then
        verticalSpeed = speed
    elseif dxyz > radius1 then
        verticalSpeed = speed
    elseif dxyz > radius2 then
        verticalSpeed = dxyz / leftTime * 1000
        angleSpeed = speed / 6
    else
        verticalSpeed = dxyz / leftTime * 1000
        angleSpeed = speed
    end

    -- 子弹预期local方向
    local localExpectedDirAbs
    if verticalSpeed >= speed then
        localExpectedDirAbs = 0
    else
        -- 保持在圆环内的最大角度
        local limitedAngle = 90 - math.deg(math.asin(stepxyz / dxyz)) / 2 - 1 -- 减少1度保证圆环不会变大

        localExpectedDirAbs = math.deg(math.acos(verticalSpeed / speed))
        localExpectedDirAbs = math.min(limitedAngle, localExpectedDirAbs)
    end

    -- 子弹与目标连线方向
    local bullet2TargetDir = math.deg(math.atan2(dy, dx))

    -- 切换到子弹与目标连线方向为x轴的空间
    -- 局部子弹方向
    local localBulletDir = NormalizeAngle(dir - bullet2TargetDir)
    local localDirAbs = localBulletDir
    local changeDir = 1
    if localBulletDir < 0 then
        changeDir = -changeDir
        localDirAbs = -localBulletDir
    end
    if localDirAbs > localExpectedDirAbs then
        changeDir = -changeDir
    end

    -- 移动角度
    local deltaAngle = math.min(angleSpeed * deltaTime / 1000, math.abs(localDirAbs - localExpectedDirAbs))

    local newDir = dir + deltaAngle * changeDir

    local dxy = math.sqrt(dx * dx + dy * dy)
    local stepz = stepxyz / dxyz * dz
    local stepxy = stepxyz / dxyz * dxy
    local stepx, stepy = stepxy * math.cos(math.rad(newDir)), stepxy * math.sin(math.rad(newDir))

	-- ppp("before", BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ, dir)
    BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ = x + stepx, y + stepy, z + stepz
    if not isRunningServerCode then
        bullet.m_BulletMoveNeedTurn = true
    end
    -- ppp(deltaTime, dxyz, verticalSpeed, deltaAngle * changeDir, localBulletDir, localExpectedDirAbs)
	-- ppp("after", BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ, newDir)
	-- ppp("---")
end

-- 蹦极悬停判定:配置了 BungeeParams.HangOnEnd 且到达终点(正向末尾或反向起点)且未点"离开"时,吊在绳尾等待主动离开
function CBulletTrackMgr:IsBungeeHang(bullet, loop, atEnd, atStart)
      local BulletData = bullet.m_BulletMoveData
      if not BulletData or not BulletData.m_IsBungee then return false end
      if bullet.m_BungeeForceLeave then return false end
      -- 保底: 状态被打断后不再悬停,让移动逻辑恢复正常,防止悬停卡死
      if g_StatusMgr:GetStatus(bullet, EPropStatus.BezierSplineMove) == 0 then return false end
      if loop or not (atEnd or atStart) then return false end
      local splineData = g_SplineMgr:GetBezierSplineData(BulletData.m_SplineIndex)
      if not splineData or not splineData.BungeeParams or splineData.BungeeParams.HangOnEnd ~= 1 then return false end
      return true
end

-- 悬停中速度清零,返回本帧高度偏移;非悬停返回 nil
function CBulletTrackMgr:GetBungeeHangOffset(bullet, deltaTime)
      local BulletData = bullet.m_BulletMoveData
      if not BulletData then return nil end
      BulletData.m_Speed = 0
      if not bullet.m_BungeeHangTime then
            bullet.m_BungeeHangTime = 0
      end
      bullet.m_BungeeHangTime = bullet.m_BungeeHangTime + deltaTime
      local hangT = bullet.m_BungeeHangTime / 1000
      local hangAmp = BUNGEE_HANG_AMP_STEADY + (BUNGEE_HANG_AMP_START - BUNGEE_HANG_AMP_STEADY) * math.exp(-BUNGEE_HANG_DECAY * hangT)
      return hangAmp * math.sin(BUNGEE_HANG_FREQ * hangT) * pixel_per_grid
end

-- 清理蹦极悬停状态(主动离开或被打断时调用,防止残留影响下次蹦极)
function CBulletTrackMgr:ClearBungeeHang(bullet)
      if not bullet then return end
      bullet.m_BungeeHang = nil
      bullet.m_BungeeForceLeave = nil
      bullet.m_BungeeHangTime = nil
end

function CBulletTrackMgr:UpdateBezierCircle(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData

	local pointCount = BulletData.m_TotalLength
	local loop = BulletData.m_IsLoop
	local isForward = BulletData.m_IsForward
	local zOffset = BulletData.m_ZOffset
	local pointIndex = BulletData.m_PointIndex
	local curSpeed = BulletData.m_Speed
	-- 速度渐变（加速度功能）
	if BulletData.m_TargetSpeed and BulletData.m_SpeedAcceleration then
		local acc = BulletData.m_SpeedAcceleration
		local newSpeed = BulletData.m_Speed + acc * deltaTime
		local targetSpeed = BulletData.m_TargetSpeed
		if (acc > 0 and newSpeed >= targetSpeed) or (acc < 0 and newSpeed <= targetSpeed) then
			newSpeed = targetSpeed
			BulletData.m_TargetSpeed = nil
			BulletData.m_SpeedAcceleration = nil
		end
		BulletData.m_Speed = newSpeed
		curSpeed = newSpeed
	end
	if BulletData.m_DirectionOnCircle then
		if BulletData.m_DirectionOnCircle == 0 then
			curSpeed = 0
		elseif BulletData.m_DirectionOnCircle == 1 then
			curSpeed = curSpeed * -1
		elseif BulletData.m_DirectionOnCircle == 2 then
			curSpeed = curSpeed
		end
	end

	local normalizedTime, atEnd, atStart = bullet:GetNormalizedTime(deltaTime, BulletData.m_NormalizedTime, loop, curSpeed, pointCount, isForward)

	BulletData.m_NormalizedTime = normalizedTime

	if not loop and ( atEnd or atStart )then
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
			bullet:OnBezierMoveEnded(BulletData.m_SplineIndex, atEnd)
		end
	end

	if isRunningServerCode then
		if loop and atStart then
			bullet:InitBezierSplineBehaviorPerRound()
		end
		bullet:CheckBezierSplineBehavior(normalizedTime, BulletData.m_BehaviorId)
	end

	-- 缓动：对显示距离做非线性映射（内部距离匀速推进保证总时间准确）
	local displayDistance = normalizedTime
	if BulletData.m_EasePeak ~= nil and pointCount > 0 then
		local t = normalizedTime / pointCount
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		displayDistance = g_SplineMgr:GetEasedProgress(t, BulletData.m_EasePeak, BulletData.m_EasePower) * pointCount
	end
	local x, y, z, rx, ry, rz, pointIndex = bullet:GetBezierPosition(displayDistance, pointCount, zOffset, BulletData.m_SplineIndex, pointIndex, isForward)
	if BulletData.m_CircleLoop and not BulletData.m_CalculatedCircle then
		-- 计算圆心
		local x1, y1, z1, rx1, ry1, rz1, pointIndex1 = bullet:GetBezierPosition(pointCount, pointCount, zOffset, BulletData.m_SplineIndex, 3, isForward)
		local x2, y2, z2, rx2, ry2, rz2, pointIndex2 = bullet:GetBezierPosition(pointCount/2, pointCount, zOffset, BulletData.m_SplineIndex, 1, isForward)
		BulletData.m_CirclePointX = (x1+x2)/2
		BulletData.m_CirclePointY = (y1+y2)/2
		BulletData.m_CirclePointZ = (z1+z2)/2
		BulletData.m_CalculatedCircle = true
		print("circle point x=",BulletData.m_CirclePointX,"y=",BulletData.m_CirclePointY,"z=",BulletData.m_CirclePointZ)
	end
	BulletData.m_PointIndex = pointIndex

	-- 摆荡模式：m_IsSwing（数据，BulletData）+ m_SwingContext（运行时，bullet 对象）
	local swingCtx = BulletData.m_IsSwing and bullet.m_SwingContext
	if swingCtx and swingCtx.active then
		-- 取曲线 normal + 3D tangent（C++ 快路径透传 native，Lua 路径走 lerp）
		-- isForward 透传 BulletData，与 GetBezierPosition 同源；zOffset 与 ComputePosition 一致
		local nx, ny, nz, tx3D, ty3D, tz3D = g_SplineMgr:GetSplineNormalAndTangentByDistance(
			BulletData.m_SplineIndex, displayDistance, isForward, zOffset)
		local _, _, _, yawOffset = g_SplineMgr:GetBezierPathTransform(bullet)
		nx, ny, nz = g_SplineMgr:ApplyBezierPathYawToVector(nx, ny, nz, yawOffset)
		tx3D, ty3D, tz3D = g_SplineMgr:ApplyBezierPathYawToVector(tx3D, ty3D, tz3D, yawOffset)
		local adjustedRy
		x, y, z, adjustedRy = g_SplineMgr:SwingStepAndGetPosition(
			swingCtx, deltaTime, x, y, z, ry, curSpeed, tx3D, ty3D, tz3D, nx, ny, nz)
		if x then BulletData.m_CurX = x end
		if y then BulletData.m_CurY = y end
		if z then BulletData.m_CurZ = z end
		-- 纵向摆角 → rotX（前后倾斜），叠加曲线自身的 rotX
		BulletData.m_RotX = rx + (swingCtx.anglePhiDeg or 0)
		-- 使用限幅后的 rotY（兜底控制柄不对称导致的朝向跳变）
		BulletData.m_RotY = adjustedRy or ry
		-- 横向摆角 → rotZ（左右倾斜），叠加曲线自身的 rotZ（P1-4：normal 倾斜后曲线 rz 参与角色姿态）
		BulletData.m_RotZ = rz + (-(swingCtx.angleDeg or 0))
		-- theta 过阈值时给相机额外 Yaw（仅客户端 + 仅主玩家，绳索摆荡 / 滑冰通用）
		if not isRunningServerCode and bullet == g_MainPlayer then
			g_SplineMgr:UpdateSwingExtraCameraYaw(swingCtx)
		end
		return
	end

	if loop and BulletData.m_LoopToIndex == pointIndex then
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
			bullet:OnBezierMoveEnded(BulletData.m_SplineIndex, atEnd)
		end
	end
	
	-- 计算跳跃高度
	local jumpHeight = BulletData.m_JumpHeight
	local jumpSpeed = BulletData.m_JumpSpeed
	local jumpGravity = BulletData.m_JumpGravity

	if jumpSpeed and jumpSpeed ~= 0 then
		local newjumpHeight, newJumpSpeed = bullet:GetJumpHeight(deltaTime, jumpSpeed, jumpGravity, jumpHeight)
		BulletData.m_JumpHeight = newjumpHeight
		BulletData.m_JumpSpeed = newJumpSpeed
		if BulletData.m_CircleLoop and BulletData.m_CalculatedCircle then
			if x and y and z then
				-- 这里向圆环中心更新位置
				local jumpDirectionX = BulletData.m_CirclePointX - x
				local jumpDirectionY = BulletData.m_CirclePointY - y
				local jumpDirectionZ = BulletData.m_CirclePointZ - z
				local dist = math.sqrt(jumpDirectionX* jumpDirectionX + jumpDirectionY * jumpDirectionY + jumpDirectionZ * jumpDirectionZ)
				x = x +  jumpDirectionX / dist * newjumpHeight
				y = y +  jumpDirectionY / dist * newjumpHeight
				z = z +  jumpDirectionZ / dist * newjumpHeight
			end
		else
			if z then
				z = z + newjumpHeight
			end	
		end
	end
	
	-- 计算偏移
	local localMoveDirX = BulletData.m_LocalMoveDirX
	local localMoveDirY = BulletData.m_LocalMoveDirY
	if localMoveDirX ~= 0 or localMoveDirY ~= 0 then
		local localMoveRadius = BulletData.m_LocalMoveRadius
		local localMoveSpeed = BulletData.m_LocalMoveSpeed
		local localMoveX = BulletData.m_LocalMoveX
		local localMoveY = BulletData.m_LocalMoveY
		BulletData.m_LocalMoveX, BulletData.m_LocalMoveY = bullet:BezierSplineLocalMove(deltaTime, 
			localMoveDirX, localMoveDirY, localMoveSpeed, localMoveRadius, localMoveX, localMoveY)
	end
	
	if BulletData.m_LocalMoveX ~= 0 or BulletData.m_LocalMoveY ~= 0 then
		local qx, qy, qz, qw = QuaternionFromEuler3(0, ry, 0, true)
		local ox, oy, oz = QuaternionMulVector3(qx, qy, qz, qw, BulletData.m_LocalMoveX, BulletData.m_LocalMoveY, 0)
		if x then x = x + ox * 64 end
		if y then y = y + oz * 64 end
		if z then z = z + oy * 64 end
	end
	
	-- #1288873 【探索氛围】【413傣族雨林】雨林蹦极探索氛围-程序功能
	if BulletData.m_IsBungee and BulletData.m_PhysicsGravity then
		if CBulletTrackMgr.IsBungeeHang(CBulletTrackMgr, bullet, loop, atEnd, atStart) then
			-- 悬停:吊在绳尾,速度清零 + 余震晃动
			local hangOffset = CBulletTrackMgr.GetBungeeHangOffset(CBulletTrackMgr, bullet, deltaTime)
			if hangOffset then
				z = z + hangOffset
			end
		else
			-- 蹦极:速度只由高度决定(段内能量守恒) 摆动轨迹依赖spline本身
			local curHeight, refHeight, jumpSpeed = g_SplineMgr:GetBungeeHeightAndRef(BulletData.m_SplineIndex, normalizedTime)
			if curHeight then
				local drop = refHeight - curHeight
				if drop < 0 then drop = 0 end
				-- v = sqrt(vMin^2 + vJump^2 + 2*g*h);m_Speed 单位是 grid/ms
				local vMin = (BulletData.m_PhysicMinSpeed or 0) * 1000
				local vJump = jumpSpeed or 0
				local v = math.sqrt(vMin * vMin + vJump * vJump + 2 * BulletData.m_PhysicsGravity * drop) / 1000
				BulletData.m_Speed = math.min(BulletData.m_PhysicMaxSpeed or v, v)
			end
		end
	elseif BulletData.m_PhysicsGravity then
	-- 上下坡分别加速和减速 不去按物理算了 直接按距离做线性加减吧
		local deltaS = (BulletData.m_CurZ - z) / 64
		BulletData.m_Speed = BulletData.m_Speed + BulletData.m_PhysicsGravity * deltaS
		BulletData.m_Speed = math.max(BulletData.m_PhysicMinSpeed, BulletData.m_Speed)
		BulletData.m_Speed = math.min(BulletData.m_PhysicMaxSpeed, BulletData.m_Speed)
	end

	-- 加个正弦的偏移
	if BulletData.m_SinOffSet then 
		local amplitude = (BulletData.m_Amplitude or 0) * 64
		local frequency = (BulletData.m_Frequency or 0) / 1000
		local phase = BulletData.m_Phase or 0
		local offset = amplitude * math.sin(frequency * x + phase)
		z = z + offset
	end

	if x then BulletData.m_CurX = x end
	if y then BulletData.m_CurY = y end
	if z then BulletData.m_CurZ = z end
	
	local delayDo = bullet.m_PreComputeDatas and bullet.m_PreComputeDatas.NeedDelay
	if not delayDo then
		if BulletData.m_CollisionRadius then
			bullet:OnCollisionDetectionOnBezierSplineMove(BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ, BulletData.m_CollisionRadius, BulletData.m_CollisionOffsetY, BulletData.m_SplineIndex)
		end
	end

	BulletData.m_RotX = rx
	BulletData.m_RotY = ry
	BulletData.m_RotZ = rz
end

function CBulletTrackMgr:UpdateAsEffectBullet(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
			if BulletData.m_TargeterEngineObjectId then
				bullet:TargetReached()
				bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
			else
				bullet:OnFlowchartEvent("PosReached")
			end
		end
		return
	end

	local EffectBulletID = BulletData.m_EffectBulletID
	local EffectBulletData = Bullet_EffectBullet[EffectBulletID]
	local moveTime = EffectBulletData.MoveTime
	
	-- Step Time
	local fDeltaTime = deltaTime * 0.001
	BulletData.m_TotalTime = BulletData.m_TotalTime + fDeltaTime

	-- 计算终点世界坐标，偏移或者绝对值
	local fDestPosX, fDestPosY, fDestPosZ = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ

	local Targeter = BulletData.m_TargeterEngineObjectId and GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId)
	if Targeter then
		local TargetX, TargetY, TargetZ = Targeter.m_engineObject:GetPixelPosv3()
		fDestPosX = (BulletData.m_DestOffsetX + TargetX) / 64
		fDestPosY = (BulletData.m_DestOffsetY + TargetY) / 64
		fDestPosZ = (BulletData.m_DestOffsetZ + TargetZ) / 64
	end
		
	local bulletMgr = isRunningServerCode and g_ServerEffectMgr:GetBulletMgr() or g_ClientEffectMgr:GetBulletMgr()
	local fCurX, fCurY, fCurZ, curRotX, curRotY, curRotZ, curRotW = bulletMgr:EffectBulletEvaluate(
		EffectBulletData.ResourceID, moveTime, BulletData.m_TotalTime, fDeltaTime, 
		BulletData.m_SourceX, BulletData.m_SourceZ, BulletData.m_SourceY, fDestPosX, fDestPosZ, fDestPosY,
		0, BulletData.m_RandomSeed, BulletData.m_CurX/64, BulletData.m_CurZ/64, BulletData.m_CurY/64,
		0, 0, 0, 0
	) -- 暂时不支持curRot

	if moveTime > 0 and BulletData.m_TotalTime >= moveTime then
		bullet.m_BulletMoveNextMoveStop = true
	end

	BulletData.m_CurX = fCurX * 64
	BulletData.m_CurY = fCurZ * 64
	BulletData.m_CurZ = fCurY * 64

	-- print("UpdateAsClientBullet ", 
	-- 	ClientBulletData.ResourceID,
	-- 	string.format("%.2f", fDeltaTime),
	-- 	string.format("%.2f", BulletData.m_TotalTime),
	-- 	string.format("%.2f", fCurX),
	-- 	string.format("%.2f", fCurY),
	-- 	string.format("%.2f", fCurZ),
	-- 	Targeter,
	-- 	string.format("%.2f", BulletData.m_DestX),
	-- 	string.format("%.2f", BulletData.m_DestY),
	-- 	string.format("%.2f", BulletData.m_DestZ),
	-- 	string.format("%.2f", BulletData.m_DestOffsetX),
	-- 	string.format("%.2f", BulletData.m_DestOffsetY),
	-- 	string.format("%.2f", BulletData.m_DestOffsetZ));
end

--2阶贝塞尔
function CBulletTrackMgr:BezierFormular2(p0, p1, p2, t)
	return (1 - t) * (1 - t) * p0 + 2 * t * (1 - t) * p1 + t * t * p2
end

--贝塞尔曲线
function CBulletTrackMgr:UpdateAsBezierPos(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	if BulletData.m_NoStop and BulletData.m_bReachedTarget then
		self:UpdateAsBezierPos_NoStop(bullet, deltaTime)
		return
	end

	-- 解决切换轨迹时，没有上一个轨迹的方向信息的问题
    if not isRunningServerCode then
        bullet.m_BulletMoveNeedTurn = true
    end

	if bullet.m_BulletMoveNextMoveStop then
		if isRunningServerCode then
			bullet.m_BulletMoveNextMoveStop = false
			bullet.m_BulletMoveStopMoving = true
			if BulletData.m_TargeterEngineObjectId then
				bullet:TargetReached()
				bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
			else
				bullet:OnFlowchartEvent("PosReached")
			end
		end
		return
	end
	

	--系数初始化
	local DestPosX, DestPosY, DestPosZ = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	local SourcePosX, SourcePosY, SourcePosZ = BulletData.m_SourceX, BulletData.m_SourceY, BulletData.m_SourceZ

	if not (DestPosX and DestPosY and DestPosZ and SourcePosX and SourcePosY and SourcePosZ) then
		BulletData.m_TargeterEngineObjectId = nil
		bullet.m_BulletMoveNextMoveStop = true
		return
	end

	if not BulletData.m_BezierStartTime then
		BulletData.m_BezierStartTime = g_App:GetGlobalTime() - deltaTime
		BulletData.m_NowTime = BulletData.m_BezierStartTime

		BulletData.m_SourceX = BulletData.m_CurX
		BulletData.m_SourceY = BulletData.m_CurY
		BulletData.m_SourceZ = BulletData.m_CurZ
		SourcePosX, SourcePosY, SourcePosZ = BulletData.m_SourceX, BulletData.m_SourceY, BulletData.m_SourceZ


		local distX = DestPosX - SourcePosX
		local distY = DestPosY - SourcePosY
		local distZ = DestPosZ - SourcePosZ
		local dist = math.sqrt(distX * distX + distY * distY + distZ * distZ)
		BulletData.m_OriDist = dist	
		if (not BulletData.m_FlightTime) or (BulletData.m_FlightTime < 0) then 
			BulletData.m_FlightTime = dist / BulletData.m_BulletSpeed
		else --策划指定了飞行的总时间,计算速断
			BulletData.m_BulletSpeed = dist / BulletData.m_FlightTime
		end
	end
	BulletData.m_NowTime = BulletData.m_NowTime + deltaTime

	local nowTime = BulletData.m_NowTime
	local allTime = BulletData.m_FlightTime * 1000
	local startTime = BulletData.m_BezierStartTime
	local durationTime = nowTime - startTime

	local ratio = durationTime / allTime
	ratio = math.min(ratio, 1)
	
	if BulletData.m_TargeterEngineObjectId then
		local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
		--只有存在target，并且还处在追踪时间内，才需要实时计算target坐标
		if Targeter and (BulletData.m_TrackTime < 0 or durationTime < (BulletData.m_TrackTime * 1000)) then
			if isRunningServerCode then
				DestPosX, DestPosY, DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
			else
			local preData = bullet.m_PreComputeDatas
				if preData and preData.valid then
					DestPosX, DestPosY, DestPosZ = preData.m_PreTargetX, preData.m_PreTargetY, preData.m_PreTargetZ
					
				else
					if debugWorker and IsInWorkerpipelineThread() then  QLOG( "debugWorker", BulletData.m_Trajectory, bullet) end
					local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
					if suc then
						DestPosX, DestPosY, DestPosZ = transX, transY, transZ
					else
						DestPosX, DestPosY, DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
					end
				end
			end
			BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
		else
			BulletData.m_TargeterEngineObjectId = nil
		end
	end

	if SourcePosX == DestPosX and SourcePosY == DestPosY then
		bullet.m_BulletMoveNextMoveStop = true
		return
	end
	
	durationTime = math.min(durationTime, allTime)
	
	--Step 1: 以起始点到目标点建立的X轴坐标系
	local src2DstDis = math.sqrt((SourcePosX - DestPosX) * (SourcePosX - DestPosX) + (SourcePosY - DestPosY) * (SourcePosY - DestPosY))
	local x1, y1 = PowerFunctionCurve.CalculateCurve(BulletData.m_HorizontalParam, BulletData.m_VerticalParam, src2DstDis, BulletData.m_SmoothParam, BulletData.m_CosParam, BulletData.m_SinParam, ratio)

	if not (x1 and y1) then
		bullet.m_BulletMoveNextMoveStop = true
		return
	end

	--time_print(x1, y1)

	--Step 2: 将虚拟坐标系旋转指定的角度
	local dir = math.rad(BulletData.m_ZDegree)
	local x2 = x1 --x2不变
	local y2 = y1 * cos(dir)
	local z2 = y1 * sin(dir)

	--Step3 : 将x2 y2 z2 转换成世界坐标

	--算出来cos和sin，直接做后面的运算，不需要算出来具体的角度
	local cos0 = (DestPosX - SourcePosX) / src2DstDis
	local sin0 = (DestPosY - SourcePosY) / src2DstDis

	--根据x轴旋转
	local x3 = x2 * cos0 - y2 * sin0
	local y3 = x2 * sin0 + y2 * cos0

	local prevX, prevY, prevZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ

	--最后加上起始点的偏移，得到最终世界坐标
	BulletData.m_CurX = x3 + SourcePosX
	BulletData.m_CurY = y3 + SourcePosY
	BulletData.m_CurZ = (1 - ratio) * (BulletData.m_SourceZ - BulletData.m_DestZ) + z2 + BulletData.m_DestZ

	local deltaX, deltaY, deltaZ = BulletData.m_CurX - prevX, BulletData.m_CurY - prevY, BulletData.m_CurZ - prevZ
	if BulletData.m_PreDeltaX and BulletData.m_PreDeltaY and BulletData.m_InflectionSpeed and BulletData.m_InflectionSpeed > 0 then
		if (deltaX * BulletData.m_PreDeltaX < 0) or (deltaY * BulletData.m_PreDeltaY) < 0 then
			BulletData.m_BulletSpeed = BulletData.m_InflectionSpeed
		end
	end
	BulletData.m_PreDeltaX, BulletData.m_PreDeltaY, BulletData.m_PreDeltaZ = deltaX, deltaY, deltaZ
	
	if durationTime >= allTime then
        if BulletData.m_NoStop == 1 then
            BulletData.m_bReachedTarget = true
		else
			bullet.m_BulletMoveNextMoveStop = true
        end
	end

	local data = Bullet_Bullet[BulletData.m_BulletDataId]
	if data and data.Acceleration then
		BulletData.m_BulletSpeed = BulletData.m_BulletSpeed + data.Acceleration * deltaTime * 0.001
	end

	local time_new = BulletData.m_OriDist / BulletData.m_BulletSpeed
	
	if BulletData.m_FlightTime ~= time_new then
		--变速了
		allTime = time_new * 1000
		durationTime = time_new * ratio * 1000
		startTime = nowTime - durationTime

		BulletData.m_FlightTime = time_new
		BulletData.m_BezierStartTime = startTime	
	end
end

function CBulletTrackMgr:UpdateAsBezierPos_NoStop(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	local bx, by, bz = bullet.m_engineObject:GetPixelPosv3();

    local dist = deltaTime * BulletData.m_BulletSpeed / 1000
	local dirx, diry, dirz = BulletData.m_PreDeltaX, BulletData.m_PreDeltaY, BulletData.m_PreDeltaZ
    local dirxyz = math.sqrt(dirx * dirx + diry * diry + dirz * dirz)

	BulletData.m_CurX = bx + dirx / dirxyz * dist
	BulletData.m_CurY = by + diry / dirxyz * dist
	BulletData.m_CurZ = bz + dirz / dirxyz * dist
end

local function yaw2dir(degree)
	local radian = math.rad(degree)
	return math.cos(radian), math.sin(radian)
end
local function vector2dRotate(dirX, dirY, radian)
	local newX = dirX * math.cos(radian) - dirY * math.sin(radian)
	local newY = dirX * math.sin(radian) + dirY * math.cos(radian)
	return newX, newY
end
function CBulletTrackMgr:UpdateAsArc(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData

	local yaw = BulletData.m_ArcCurYawAngle
	local curX, curY, curZ = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local t = deltaTime * 0.001
	if BulletData.m_ArcRotateCurAngle == BulletData.m_ArcRotateMaxAngle then
		local dirX, dirY = yaw2dir(yaw)
		BulletData.m_CurX = curX + BulletData.m_BulletSpeed * dirX * t
		BulletData.m_CurY = curY + BulletData.m_BulletSpeed * dirY * t
	else
		local angle = math.deg((BulletData.m_BulletSpeed / BulletData.m_ArcRotateRadius / pixel_per_grid) * t)
		if math.abs(BulletData.m_ArcRotateCurAngle + angle) > math.abs(BulletData.m_ArcRotateMaxAngle) then
			angle = BulletData.m_ArcRotateMaxAngle - BulletData.m_ArcRotateCurAngle
			BulletData.m_ArcRotateCurAngle = BulletData.m_ArcRotateMaxAngle
		else
			BulletData.m_ArcRotateCurAngle = BulletData.m_ArcRotateCurAngle + angle
		end

		local rightDirX, rightDirY = yaw2dir(yaw - 90)
		local centerX = curX + rightDirX * BulletData.m_ArcRotateRadius * pixel_per_grid
		local centerY = curY + rightDirY * BulletData.m_ArcRotateRadius * pixel_per_grid
		local centerZ = curZ

		local newDirX, newDirY = vector2dRotate(-rightDirX, -rightDirY, -math.rad(angle))
		BulletData.m_CurX = centerX + newDirX * BulletData.m_ArcRotateRadius * pixel_per_grid
		BulletData.m_CurY = centerY + newDirY * BulletData.m_ArcRotateRadius * pixel_per_grid
		BulletData.m_CurZ = centerZ
		
		BulletData.m_ArcCurYawAngle = BulletData.m_ArcCurYawAngle - angle
	end
end

local __Circling_MatrixR = {{}, {}, {}, {}}
local __Temp_Dist_Vector = {}
function CBulletTrackMgr:UpdateAsTractionAndCircling(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData

	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
		end
		return
	end

	local x, y, z = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ

	-- 确定圆心
	local originX, originY, originZ
	if BulletData.m_OriginWithTarget then
		local target = GetObjectByGlobalId(BulletData.m_OriginId)
		if target then
			local targetX, targetY, targetZ = target.m_engineObject:GetPixelPosv3()
			originX, originY, originZ = targetX, targetY, targetZ
		else
			bullet.m_BulletMoveNextMoveStop = true
			return
		end
	else
		originX, originY, originZ = BulletData.m_StartPoint[1], BulletData.m_StartPoint[2], BulletData.m_StartPoint[3]
	end

	local destX, destY, destZ = x, y, z
	local rotaVectorX, rotaVectorY, rotaVectorZ = BulletData.m_RotateVector[1], BulletData.m_RotateVector[2], BulletData.m_RotateVector[3]
	local distToFootPoint = ((x - originX) * rotaVectorX + (y - originY) * rotaVectorY + (z - originZ) * rotaVectorZ)
	local pedalFootX, pedalFootY, pedalFootZ = originX + distToFootPoint * rotaVectorX, originY + distToFootPoint * rotaVectorY, originZ + distToFootPoint * rotaVectorZ
	
	local rotateSpeed = BulletData.m_RotateSpeed
	local dt = deltaTime * 0.001
	
	-- 计算绕轴圆周运动
	local alpha = rotateSpeed * dt
	local sina = math.sin(math.rad(alpha))
	local cosa = math.cos(math.rad(alpha))
	local rotaXX, rotaYY, rotaZZ = rotaVectorX * rotaVectorX, rotaVectorY * rotaVectorY, rotaVectorZ * rotaVectorZ
	local rotaXY, rotaXZ, rotaYZ = rotaVectorX * rotaVectorY, rotaVectorX * rotaVectorZ, rotaVectorY * rotaVectorZ
	
	__Circling_MatrixR[1][1] = rotaXX + (rotaYY + rotaZZ) * cosa
	__Circling_MatrixR[2][1] = rotaXY * (1 - cosa) + rotaVectorZ * sina;
	__Circling_MatrixR[3][1] = rotaXZ * (1 - cosa) - rotaVectorY * sina;
	__Circling_MatrixR[4][1] = 0
	__Circling_MatrixR[1][2] = rotaXY * (1 - cosa) - rotaVectorZ * sina;
    __Circling_MatrixR[2][2] = rotaYY + (rotaXX + rotaZZ) * cosa;
	__Circling_MatrixR[3][2] = rotaYZ * (1 - cosa) + rotaVectorX * sina;
    __Circling_MatrixR[4][2] = 0;
	__Circling_MatrixR[1][3] = rotaXZ * (1 - cosa) + rotaVectorY * sina;
	__Circling_MatrixR[2][3] = rotaYZ * (1 - cosa) - rotaVectorX * sina;
	__Circling_MatrixR[3][3] = rotaZZ + (rotaXX + rotaYY) * cosa;
	__Circling_MatrixR[4][3] = 0;

	__Circling_MatrixR[1][4] = (originX * (rotaYY + rotaZZ) - rotaVectorX * (originY * rotaVectorY + originZ * rotaVectorZ)) * (1 - cosa) + (originY * rotaVectorZ - originZ * rotaVectorY) * sina;
    __Circling_MatrixR[2][4] = (originY * (rotaXX + rotaZZ) - rotaVectorY * (originX * rotaVectorX + originZ * rotaVectorZ)) * (1 - cosa) + (originZ * rotaVectorX - originX * rotaVectorZ) * sina; 
	__Circling_MatrixR[3][4] = (originZ * (rotaXX + rotaYY) - rotaVectorZ * (originX * rotaVectorX + originY * rotaVectorY)) * (1 - cosa) + (originX * rotaVectorY - originY * rotaVectorX) * sina;
    __Circling_MatrixR[4][4] = 1
	destX = __Circling_MatrixR[1][1] * x + __Circling_MatrixR[1][2] * y + __Circling_MatrixR[1][3] * z + __Circling_MatrixR[1][4]
	destY = __Circling_MatrixR[2][1] * x + __Circling_MatrixR[2][2] * y + __Circling_MatrixR[2][3] * z + __Circling_MatrixR[2][4]
	destZ = __Circling_MatrixR[3][1] * x + __Circling_MatrixR[3][2] * y + __Circling_MatrixR[3][3] * z + __Circling_MatrixR[3][4]

	--计算拉扯效果
	if BulletData.m_IsTraction then
		local tractionSpeed = BulletData.m_TractionSpeed
		local tractionLimitDist = BulletData.m_TracionLimitDist
		__Temp_Dist_Vector.x =  pedalFootX - destX
		__Temp_Dist_Vector.y =  pedalFootY - destY
		__Temp_Dist_Vector.z =  pedalFootZ - destZ
		
		local distanceTraction = DistVector3D(__Temp_Dist_Vector)
		local tractionNormalizeVector = NormalizeVector3D(__Temp_Dist_Vector)
		
		if not (distanceTraction <= tractionLimitDist) then
			local dist = tractionSpeed * dt
			dist = math.min(dist, distanceTraction - tractionLimitDist)
			destX, destY, destZ = destX + tractionNormalizeVector.x * dist, destY + tractionNormalizeVector.y * dist, destZ + tractionNormalizeVector.z * dist
		end
	end

	-- 计算抬升效果
	if BulletData.m_IsZMove then
		local zSpeed = BulletData.m_RotateZSpeed
		local limitZ = BulletData.m_RotateZLimitHigh
		local newX, newY, newZ = destX + rotaVectorX * zSpeed * dt, destY + rotaVectorY * zSpeed * dt, destZ + rotaVectorZ * zSpeed * dt
		__Temp_Dist_Vector.x = newX - originX
		__Temp_Dist_Vector.y = newY - originY
		__Temp_Dist_Vector.z = newZ - originZ
		local distanceZ = DistVector3D(__Temp_Dist_Vector)
		if not (distanceZ > limitZ) then
			destX = newX
			destY = newY
			destZ = newZ
		end
	end

	BulletData.m_CurX = destX
	BulletData.m_CurY = destY
	BulletData.m_CurZ = destZ
	local allTime = BulletData.m_TractionAllTime
	local startTime = BulletData.m_TractionStartTime
	local nowTime = g_App:GetGlobalTime() / 1000
	local durationTime = nowTime - startTime
	if durationTime >= allTime then
		bullet.m_BulletMoveNextMoveStop = true
	end
end

function CBulletTrackMgr:UpdateBoatFrontMove2D(obj, deltaTime)
    local bulletData = obj.m_BulletMoveData
    local now = deltaTime < 1000 and GetGlobalTime_ms() * 0.001 or deltaTime
	if bulletData.m_LateChangeData and now >= bulletData.m_LateChangeData.ChangePoint then
		-- 延迟生效
		local changeData = bulletData.m_LateChangeData
		bulletData.m_LateChangeData = nil
		self:UpdateBoatFrontMove2D(obj, changeData.ChangePoint)
		obj.m_BulletMoveOldX, obj.m_BulletMoveOldY, obj.m_BulletMoveOldZ = bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ
		bulletData.m_StartTime = changeData.ChangePoint
		changeData.ChangePoint = nil
		for k, v in pairs(changeData) do
			bulletData[k] = v
		end
		bulletData.m_StartRad = bulletData.m_BulletRad
		bulletData.m_StartX,bulletData.m_StartY = bulletData.m_CurX, bulletData.m_CurY
	end

	local allTime = bulletData.m_TotalTime
	local startTime = bulletData.m_StartTime
	local dt = bulletData.m_TotalTime > 0 and math.min(now - startTime, bulletData.m_TotalTime) or now - startTime
	local x, y = bulletData.m_StartX,bulletData.m_StartY
	local theta = bulletData.m_StartRad  
	local omega = bulletData.m_AngleSpeed
	local speed = bulletData.m_BulletSpeed
	local theta_new, dx, dy
	if omega ~= 0 then
		local sin_theta = math.sin(theta + omega * dt)
		local cos_theta = math.cos(theta + omega * dt)
		local sin_theta0 = math.sin(theta)
		local cos_theta0 = math.cos(theta)
	
		dx, dy = (speed / omega) * (sin_theta - sin_theta0), (speed / omega) * (cos_theta0 - cos_theta)
		theta_new = theta + omega * dt
	else
		theta_new = theta
		dx, dy = speed * math.cos(theta) * dt, speed * math.sin(theta) * dt
	end

	bulletData.m_CurX = x + dx
	bulletData.m_CurY = y + dy
	local _, _, z = obj:GetPixelPosition()
	bulletData.m_CurZ = z
	bulletData.m_BulletRad = theta_new
    if not isRunningServerCode then
        obj.m_BulletMoveNeedTurn = true
    end

	if rawget(_G, "_G_Test_P") then
		rawget(_G, "_G_Test_P").m_engineObject:SetPixelPosv3(bulletData.m_CurX, bulletData.m_CurY, 0)
	end
	if dt >= allTime and bulletData.m_TotalTime > 0 then
		obj.m_BulletMoveStopMoving = true
	else
		obj.m_BulletMoveStopMoving = false
	end
end

function CBulletTrackMgr:UpdateAsParabolaExPos(bullet, deltaTime)
	deltaTime = deltaTime * 0.001
	local BulletData = bullet.m_BulletMoveData
	local g = BulletData.m_G
	local speed = BulletData.m_BulletSpeed
	local dirX, dirY = BulletData.m_OriDirX, BulletData.m_OriDirY, BulletData.m_OriDirZ
	local vx, vy, vz = speed * dirX, speed * dirY, BulletData.m_VectorZ
	
	local deltaX = vx * deltaTime
	local deltaY = vy * deltaTime
	local deltaZ = vz * deltaTime - 0.5 * g * deltaTime * deltaTime

	BulletData.m_VectorZ = vz - g * deltaTime
	BulletData.m_CurX = BulletData.m_CurX + deltaX
	BulletData.m_CurY = BulletData.m_CurY + deltaY
	BulletData.m_CurZ = BulletData.m_CurZ + deltaZ
end

function CBulletTrackMgr:UpdateAsParabolaPos(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData

	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
			if BulletData.m_TargeterEngineObjectId then
				bullet:TargetReached()
				bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
			else
				bullet:OnFlowchartEvent("PosReached")
			end
		end
		return
	end

	local DestPosX, DestPosY, DestPosZ = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if Targeter then
		if BulletData.m_DestOffsetX then
			DestPosX, DestPosY, DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
			DestPosX = DestPosX + BulletData.m_DestOffsetX
			DestPosY = DestPosY + BulletData.m_DestOffsetY
			DestPosZ = DestPosZ + BulletData.m_DestOffsetZ
		else
			if isRunningServerCode then
				DestPosX, DestPosY, DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
			else
				local preData = bullet.m_PreComputeDatas
				if preData and preData.valid then
					DestPosX, DestPosY, DestPosZ = preData.m_PreTargetX, preData.m_PreTargetY, preData.m_PreTargetZ
					
				else
					if  debugWorker and IsInWorkerpipelineThread() then  QLOG( "debugWorker", BulletData.m_Trajectory, bullet) end
					local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
					if suc then
						DestPosX, DestPosY, DestPosZ = transX, transY, transZ
					else
						DestPosX, DestPosY, DestPosZ = Targeter.m_engineObject:GetPixelPosv3()
					end
				end
			end
			BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
		end
	end

	local SourcePosX,SourcePosY,SourcePosZ = BulletData.m_SourceX,BulletData.m_SourceY,BulletData.m_SourceZ
	local distX = DestPosX - SourcePosX
	local distY = DestPosY - SourcePosY
	local distZ = DestPosZ - SourcePosZ

	-- 是否实时追踪z轴坐标
	local bTrackZ = BulletData.m_bTrackZ

	if not BulletData.m_ParabolaC then 		
		if not isRunningServerCode then --解决客户端子弹从手飞出去时，抛物线轨迹有折线的问题
			BulletData.m_SourceX, BulletData.m_SourceY, BulletData.m_SourceZ = BulletData.m_CurX, BulletData.m_CurY,
				BulletData.m_CurZ
			SourcePosX, SourcePosY, SourcePosZ = BulletData.m_SourceX, BulletData.m_SourceY, BulletData.m_SourceZ
			distX = DestPosX - SourcePosX
			distY = DestPosY - SourcePosY
			distZ = DestPosZ - SourcePosZ
		end

		local dist = math.sqrt(distX * distX + distY * distY + distZ * distZ)	
		if not BulletData.m_ParabolaAllTime then 
			BulletData.m_ParabolaAllTime = dist / BulletData.m_BulletSpeed
		else --策划指定了飞行的总时间,计算速断
			BulletData.m_BulletSpeed = dist / BulletData.m_ParabolaAllTime
		end

		BulletData.m_ParabolaStartTime = g_App:GetGlobalTime() - deltaTime
		BulletData.m_NowTime = BulletData.m_ParabolaStartTime
		local T = BulletData.m_ParabolaAllTime

		if T == 0 then
			BulletData.m_ParabolaA = BulletData.m_ParabolaA or 0
			BulletData.m_ParabolaB = 0
			BulletData.m_ParabolaC = SourcePosZ
		elseif BulletData.m_ParabolaA ~= 0 then --指定了抛物线的二次系数a(即指定了抛物线的弧度)						
			BulletData.m_ParabolaB = (distZ - BulletData.m_ParabolaA * T * T) / T
			BulletData.m_ParabolaC = SourcePosZ
		else 
			--指定了一个数值H,策划想指定抛物线的高度,这里将这个高度H做简单定义：原点和目标点的中点记为(t1,z1),抛物线在时间t1的高度为z2;那么H=z2-z1				
			local H = BulletData.m_ParabolaH
			local t1 = T / 2
			local z1 = SourcePosZ + distZ / 2						
			local z2 = z1 + H
			local c = SourcePosZ
			local a = (z2 - c - (DestPosZ - c) / T * t1) / (t1 * t1 - T * t1)
			local b = (DestPosZ - c - a * T * T) / T
			BulletData.m_ParabolaA = a
			BulletData.m_ParabolaB = b
			BulletData.m_ParabolaC = c
		end
	elseif bTrackZ then
		local totalTime = BulletData.m_ParabolaAllTime
		local T = totalTime
		local H = BulletData.m_ParabolaH
		local t1 = T / 2
		local z1 = SourcePosZ + distZ / 2						
		local z2 = z1 + H
		local c = SourcePosZ
		local a = (z2 - c - (DestPosZ - c) / T * t1) / (t1 * t1 - T * t1)
		local b = (DestPosZ - c - a * T * T) / T
		BulletData.m_ParabolaA = a
		BulletData.m_ParabolaB = b
		BulletData.m_ParabolaC = c
	end

	BulletData.m_NowTime = BulletData.m_NowTime + deltaTime

	--全都换成毫秒
	local allTime = BulletData.m_ParabolaAllTime * 1000
	local startTime = BulletData.m_ParabolaStartTime
	local nowTime = BulletData.m_NowTime

	local durationTime = (nowTime - startTime)
	local ratio = durationTime / allTime

	durationTime = math.min(durationTime, allTime)
	ratio = math.min(ratio, 1)

	local CurPosX = SourcePosX + distX * ratio
	local CurPosY = SourcePosY + distY * ratio

	local dur_sec = durationTime / 1000
	local CurPosZ = BulletData.m_ParabolaA * dur_sec * dur_sec + BulletData.m_ParabolaB * dur_sec + BulletData.m_ParabolaC	

	BulletData.m_CurX = CurPosX
	BulletData.m_CurY = CurPosY
	BulletData.m_CurZ = CurPosZ

	if durationTime >= allTime then 
		bullet.m_BulletMoveNextMoveStop = true
	end
end


--m_Dir
--m_SideSpeed: 横向/侧向初速度分量（像素/秒），让追踪弹呈现"先横向飘、再转正"的弧线轨迹，避免直角硬拐弯
--m_SideSpeedDecay: 横向速度衰减（像素/秒²），默认用总飞行时间约1/2衰减完，见BulletTrajectoryImp
function CBulletTrackMgr:UpdateAsChase(bullet, deltaTime)
	--print("UpdateAsChase", bx, by, bz)
	local BulletData = bullet.m_BulletMoveData
	
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			if BulletData.m_TrajectoryArgs ~= 1 then
				bullet.m_BulletMoveStopMoving = true
			end
			if BulletData.m_TargeterEngineObjectId then
				bullet:TargetReached()
				bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
			else
				bullet:OnFlowchartEvent("PosReached")
			end
		end
		return
	end

	local bx, by, bz = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local dx, dy, dz

	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if Targeter then
		if BulletData.m_DestOffsetX then
			dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
			dx = dx + BulletData.m_DestOffsetX
			dy = dy + BulletData.m_DestOffsetY
			dz = dz + BulletData.m_DestOffsetZ
		else
			if isRunningServerCode then
				dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
				dz = dz + (BulletData.m_TargetOffsetZ or 0)
			else
				local preData = bullet.m_PreComputeDatas
				if preData and preData.valid then
					dx, dy, dz = preData.m_PreTargetX, preData.m_PreTargetY, preData.m_PreTargetZ
					
				else
					if  debugWorker and IsInWorkerpipelineThread() then  QLOG( "debugWorker", BulletData.m_Trajectory, bullet) end
					if BulletData.m_TargetBonePos then 
						local ro = Targeter:GetRenderObject()
						local pos = ro and ro:GetBonePosition(BulletData.m_TargetBonePos)
						if pos then 
							dx, dy, dz = pos.x * EnumGlobalConstants.PIXEL_PER_GRID, pos.y * EnumGlobalConstants.PIXEL_PER_GRID, pos.z * EnumGlobalConstants.PIXEL_PER_GRID
						end
					else
						local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
						if suc then
							dx, dy, dz = transX, transY, transZ
						end
					end
					if not dx then
						dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
					end
					
					if BulletData.m_RandomTrans then
						dx = dx + BulletData.m_RandomTrans.x
						dy = dy + BulletData.m_RandomTrans.y
						dz = dz + BulletData.m_RandomTrans.z
					end
				end
			end
		end
		BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = dx, dy, dz
	else
		dx, dy, dz  = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	end
	if not dx then return end
	local CurPosX,CurPosY,CurPosZ = bx, by, bz
	

	local t = deltaTime * 0.001
	local oldSpeed = BulletData.m_BulletSpeed
	local newSpeed =  oldSpeed + BulletData.m_Accel * t
	local averageSpeed = (oldSpeed + newSpeed) * 0.5
	
	-- 把本帧平均速度按勾股定理拆成纵向（朝目标推进）+ 横向（SideSpeed惯性）两个垂直分量
	if averageSpeed > BulletData.m_SideSpeed then
		BulletData.m_BulletSpeedNow = math.sqrt(averageSpeed ^ 2 - BulletData.m_SideSpeed ^ 2)
	else
		BulletData.m_BulletSpeedNow = 0
	end
	
	local dist = BulletData.m_BulletSpeedNow * t
	
	local DistanceX = dx - CurPosX
	local DistanceY = dy - CurPosY
	local DistanceZ = dz - CurPosZ
	
	local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
    local maxAngleSpeed = BulletData.m_MaxAngleSpeed or 0
	if maxAngleSpeed > 0 or not isRunningServerCode then
		if Dist < dist * 3 then
			bullet.m_BulletMoveNeedTurn = false
		else
			bullet.m_BulletMoveNeedTurn = true
		end
	end
	
	if Dist <= dist then
		-- 判断nan
		if not IsNanOrInf(dx) then BulletData.m_CurX = dx end
		if not IsNanOrInf(dy) then BulletData.m_CurY = dy end
		if not IsNanOrInf(dz) then BulletData.m_CurZ = dz end
		if not BulletData.m_NoStop then
			bullet.m_BulletMoveNextMoveStop = true
		end
		return
	end
	
	local SideSpeed = BulletData.m_SideSpeed
    local dir = bullet:GetFaceDirection() or 0
	local Dir = dir / 180 * math.pi
    if maxAngleSpeed > 0 and bullet.m_BulletMoveNeedTurn then
        --限制最大角速度
        local angleSpeed = maxAngleSpeed  --角速度限制
        local maxDirDiff = angleSpeed * t   --最大
        local ddirxy = deg(atan2(DistanceY, DistanceX))     --新方向角
        local ddirxyLocal = NormalizeAngle(ddirxy - dir)    --新旧角度差值
        local ddirxyLocalAbs = abs(ddirxyLocal)
        local changeSign = ddirxyLocal < 0 and -1 or 1
        local dirDiff = min(ddirxyLocalAbs, maxDirDiff) * changeSign
        Dir = (dir + dirDiff) / 180 * math.pi

        local zDist = dist * DistanceZ / Dist
        local xyDist = math.sqrt(dist ^ 2 - zDist ^ 2)
        CurPosX = CurPosX + xyDist * math.cos(Dir)
        CurPosY = CurPosY + xyDist * math.sin(Dir)
        CurPosZ = CurPosZ + zDist
    else
        CurPosX = CurPosX + dist * DistanceX / Dist
        CurPosY = CurPosY + dist * DistanceY / Dist
        CurPosZ = CurPosZ + dist * DistanceZ / Dist
    end
	-- 横向惯性位移：沿当前朝向继续飘，叠加在纵向追踪位移之上
	local SideDistX, SideDistY = SideSpeed * math.cos(Dir) * t, SideSpeed * math.sin(Dir) * t
	
	CurPosX = CurPosX + SideDistX
	CurPosY = CurPosY + SideDistY

	if not IsNanOrInf(CurPosX) then BulletData.m_CurX = CurPosX end
	if not IsNanOrInf(CurPosY) then BulletData.m_CurY = CurPosY end
	if not IsNanOrInf(CurPosZ) then BulletData.m_CurZ = CurPosZ end
	
	-- 横向速度随时间衰减，最终归零后变为纯追踪直线
	if SideSpeed > 0 then
		BulletData.m_SideSpeed = SideSpeed - BulletData.m_SideSpeedDecay * t
		if BulletData.m_SideSpeed < 0 then
			BulletData.m_SideSpeed = 0
		end
	end
end

--获取切点
local GetTangentialPoint = function(centerX, centerY, outX, outY, radius, isClockWise)
	local dist = Dist_XY2(centerX, centerY, outX, outY)
	local diff = dist - radius
	if abs(diff) <= 1 then --1像素内的默认就在圆上
		return outX, outY
	elseif diff < 0 then
		outX, outY = RayIntercept2(centerX, centerY, nil, outX, outY, nil, radius * 2 - dist)
	end

	--1. 坐标平移到圆心ptCenter处,求圆外点的新坐标E
	local ex = outX - centerX
	local ey = outY - centerY --平移变换到E
	--2. 求圆与OE的交点坐标F, 相当于E的缩放变换
	local t = radius / math.sqrt(ex ^ 2 + ey ^ 2) --得到缩放比例
	local fx, fy = ex * t, ey * t	--缩放变换到F
	--3. 将E旋转变换角度a到切点G，其中cos(a)=r/OF=t, 所以a=arccos(t)
	local a = math.acos(t)   --得到旋转角度
	if isClockWise then a = -a end
	local gx = fx * math.cos(a) - fy * math.sin(a)
	local gy = fx * math.sin(a) + fy * math.cos(a)    --旋转变换到G

	--4. 将G平移到原来的坐标下得到新坐标H
	local hx = gx + centerX
	local hy = gy + centerY             --平移变换到H

	--5. 返回H
	return hx, hy
end


function CBulletTrackMgr:UpdateAsHalfChase(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
			if BulletData.m_ChaseSuccessed then
				if BulletData.m_TargeterEngineObjectId then
					bullet:TargetReached()
					bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
				else
					bullet:OnFlowchartEvent("PosReached")
				end
			end
		end
		return
	end

	local trackTime = BulletData.m_TrackTime + deltaTime
	BulletData.m_TrackTime = trackTime

	local bx, by, bz = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local dx, dy, dz
	--print("UpdateAsHalfChase", bx, by, bz)

	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if Targeter then
		if BulletData.m_DestOffsetX then
			dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
			dx = dx + BulletData.m_DestOffsetX
			dy = dy + BulletData.m_DestOffsetY
			dz = dz + BulletData.m_DestOffsetZ
		else
			if isRunningServerCode then
				dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
				dz = dz + (BulletData.m_TargetOffsetZ or 0)
			else
				local preData = bullet.m_PreComputeDatas
				if preData and preData.valid then
					dx, dy, dz = preData.m_PreTargetX, preData.m_PreTargetY, preData.m_PreTargetZ
					
				else
					if  debugWorker and IsInWorkerpipelineThread() then  QLOG( "debugWorker", BulletData.m_Trajectory, bullet) end
					local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
					if suc then
						dx, dy, dz = transX, transY, transZ
					else
						dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
					end
				end

				if BulletData.m_RandomTrans then
					dx = dx + BulletData.m_RandomTrans.x
					dy = dy + BulletData.m_RandomTrans.y
					dz = dz + BulletData.m_RandomTrans.z
				end			
			end
		end
		BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = dx, dy, dz
	else
		dx, dy, dz  = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	end
	local CurPosX,CurPosY,CurPosZ = bx, by, bz
	

	local t = deltaTime * 0.001
	local oldSpeed = BulletData.m_BulletSpeed
	local newSpeed = self:PushBulletSpeed(bullet, t)
	local averageSpeed = (oldSpeed + newSpeed) / 2
	
	if averageSpeed > BulletData.m_SideSpeed then
		BulletData.m_BulletSpeedNow = math.sqrt(averageSpeed ^ 2 - BulletData.m_SideSpeed ^ 2)
	else
		BulletData.m_BulletSpeedNow = 0
	end
	
	local dist = BulletData.m_BulletSpeedNow * t
	
	local DistanceX = dx - CurPosX
	local DistanceY = dy - CurPosY
	local DistanceZ = dz - CurPosZ
	
	local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
	if not isRunningServerCode then
		if Dist < dist * 3 then
			bullet.m_BulletMoveNeedTurn = false
		else
			bullet.m_BulletMoveNeedTurn = true
		end
	end

	if Dist <= dist then
		BulletData.m_CurX = dx
		BulletData.m_CurY = dy
		BulletData.m_CurZ = dz
		bullet.m_BulletMoveNextMoveStop = true
		BulletData.m_ChaseSuccessed = true
		return
	end
	
	CurPosX = CurPosX + dist * DistanceX / Dist
	CurPosY = CurPosY + dist * DistanceY / Dist
	CurPosZ = CurPosZ + dist * DistanceZ / Dist
	
	local SideSpeed = BulletData.m_SideSpeed
	local Dir = bullet.m_engineObject:GetDirectionDegree() / 180 * math.pi
	local SideDistX, SideDistY = SideSpeed * math.cos(Dir) * t, SideSpeed * math.sin(Dir) * t
	
	CurPosX = CurPosX + SideDistX
	CurPosY = CurPosY + SideDistY

	local moveDir = VectorToDirection2(BulletData.m_CurX, BulletData.m_CurY, CurPosX, CurPosY)
	local bulletDir = bullet.m_engineObject:GetDirectionDegree()
	local dirDis = math.abs(moveDir - bulletDir )
	if dirDis > 180 then dirDis = 360 - dirDis end
	local maxChangeAngleOri = BulletData.m_MaxChaseAngle or BulletData.m_TrajectoryArgs[1] 

	-- max change angle decay
	local maxChangeAngleDecay = (BulletData.m_MaxChaseAngleDecay or 0) * trackTime / 1000
	local maxChangeAngle = max(maxChangeAngleOri - maxChangeAngleDecay, 0)

	local stopAngle = BulletData.m_StopChaseAngle or BulletData.m_TrajectoryArgs[2]
	if dirDis > maxChangeAngle then
		if moveDir < bulletDir then
			moveDir = bulletDir - maxChangeAngle
		else
			moveDir = bulletDir + maxChangeAngle
		end
		if dirDis > stopAngle then
			bullet.m_BulletMoveNextMoveStop = true
		end
	end
	moveDir = math.mod(moveDir, 360)
	--print("1111", dirDis, moveDir, bulletDir)
	moveDir = moveDir / 180 * math.pi
	local moveDisXY = math.sqrt((CurPosX - BulletData.m_CurX) *  (CurPosX - BulletData.m_CurX) + (CurPosY - BulletData.m_CurY) *  (CurPosY - BulletData.m_CurY))
	local moveDisX = moveDisXY * math.cos(moveDir)
	local moveDisY = moveDisXY * math.sin(moveDir)

	BulletData.m_CurX = BulletData.m_CurX + moveDisX
	BulletData.m_CurY = BulletData.m_CurY + moveDisY
	BulletData.m_CurZ = CurPosZ

	
	if BulletData.m_SideSpeed > 0 then
		BulletData.m_SideSpeed = BulletData.m_SideSpeed - BulletData.m_SideSpeedDecay * t
		if BulletData.m_SideSpeed < 0 then
			BulletData.m_SideSpeed = 0
		end
	end
end

function CBulletTrackMgr:UpdateAsCircle(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	local bx, by, bz = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local tx, ty, tz
	
	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if Targeter then
		tx, ty, tz = Targeter.m_engineObject:GetPixelPosv3()
	else
		local t = BulletData.m_TargetPos
		tx, ty, tz = t.x, t.y, t.z
	end
	
	if BulletData.m_CurZ == tz + BulletData.m_CircleMaxHeight then
		BulletData.m_CircleSpeedZ = -math.abs(BulletData.m_CircleSpeedZ)
	elseif BulletData.m_CurZ == tz + BulletData.m_CircleMinHeight then
		BulletData.m_CircleSpeedZ = math.abs(BulletData.m_CircleSpeedZ)
	end

	local CurPosX,CurPosY,CurPosZ = bx, by, bz

	local moveCyc = deltaTime
	local radius = BulletData.m_CircleRadius
	local speed = BulletData.m_BulletSpeed
	if BulletData.m_RadiusEquipToDistance_TargetId then
		local radiusTarget = EID2OBJ(BulletData.m_RadiusEquipToDistance_TargetId)
		if radiusTarget then
			local rtx, rty = radiusTarget.m_engineObject:GetPixelPosv3()
			local newRadius = math.sqrt((rtx - tx) ^ 2 + (rty - ty) ^ 2)
			local newSpeed = speed / radius * newRadius
			radius = newRadius
			speed = newSpeed
		end
	end
	local dist = moveCyc * speed * 0.001

	local CircleStartPosX, CircleStartPosY = GetTangentialPoint(tx, ty, bx, by, radius, BulletData.m_ClockWise)
	local CircleStartPosZ = Clamp(tz + BulletData.m_RelativeZ, tz + BulletData.m_CircleMinHeight,
		tz + BulletData.m_CircleMaxHeight)
	
	local DistanceX = CircleStartPosX - CurPosX
	local DistanceY = CircleStartPosY - CurPosY
	local DistanceZ = CircleStartPosZ - CurPosZ
		
	local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
	local Dist2 = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2)
	
	if Dist2 > dist then
		CurPosX = CurPosX + dist * DistanceX / Dist
		CurPosY = CurPosY + dist * DistanceY / Dist
		CurPosZ = CurPosZ + dist * DistanceZ / Dist
	else
		if BulletData.m_ClockWise then dist = -dist end
		local distZ = moveCyc * BulletData.m_CircleSpeedZ * 0.001
		local circleDegree = 180 * dist / (math.pi * radius) --转过多少角度

		local newDegree = VectorToDirection2(tx, ty, bx, by) + circleDegree
		local newDir = newDegree / 180 * math.pi

		BulletData.m_RelativeZ = BulletData.m_RelativeZ + distZ
		CurPosX = tx + math.cos(newDir) * radius
		CurPosY = ty + math.sin(newDir) * radius
		CurPosZ = tz + BulletData.m_RelativeZ
		CurPosZ = Clamp(tz + BulletData.m_RelativeZ, tz + BulletData.m_CircleMinHeight, tz + BulletData.m_CircleMaxHeight)
	end

	BulletData.m_CurX = CurPosX
	BulletData.m_CurY = CurPosY
	BulletData.m_CurZ = CurPosZ
end

function CBulletTrackMgr:UpdateAsBaFangJue(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
		end
		return
	end
	
	local moveCyc = deltaTime
	local dist = moveCyc * BulletData.m_BulletSpeed * 0.001
	
	local DestPos = BulletData.m_TargetPos
	
	local LinePos, VerticalPos = BulletData.m_LinePos, BulletData.m_VerticalPos
	if not LinePos then
		BulletData.m_LinePos = {}
		LinePos = BulletData.m_LinePos
		LinePos.x,LinePos.y,LinePos.z = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
		
		BulletData.m_VerticalPos = {}
		VerticalPos = BulletData.m_VerticalPos
		VerticalPos.x,VerticalPos.y = 0,0
	end
	
	local DistanceX = DestPos.x - LinePos.x
	local DistanceY = DestPos.y - LinePos.y
	local DistanceZ = DestPos.z - LinePos.z
	
	local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
	if Dist <= dist then
		BulletData.m_CurX = DestPos.x
		BulletData.m_CurY = DestPos.y
		BulletData.m_CurZ = DestPos.z
		bullet.m_BulletMoveNextMoveStop = true
		return
	end
	
	--直线移动距离
	LinePos.x = LinePos.x + dist * DistanceX / Dist
	LinePos.y = LinePos.y + dist * DistanceY / Dist
	LinePos.z = LinePos.z + dist * DistanceZ / Dist
	
	--SideSpeed移动距离
	if BulletData.m_SideSpeed  and BulletData.m_SideSpeed > 0 then
		local SideDist = BulletData.m_SideSpeed * moveCyc * 0.001 - 0.5 * BulletData.m_SideA1 * (moveCyc * 0.001) ^2
		VerticalPos.x = VerticalPos.x + SideDist * math.cos(BulletData.m_SideSpeedDir)
		VerticalPos.y = VerticalPos.y + SideDist * math.sin(BulletData.m_SideSpeedDir)
	
		BulletData.m_SideSpeed = BulletData.m_SideSpeed - BulletData.m_SideA1 * 0.001 * moveCyc
		if BulletData.m_SideSpeed < 0 then
			BulletData.m_SideSpeed = 0
		end
	elseif BulletData.m_SideSpeed then
		local SideDist = BulletData.m_SideSpeed * moveCyc * 0.001 - 0.5 * BulletData.m_SideA2 * (moveCyc * 0.001) ^2
		VerticalPos.x = VerticalPos.x + SideDist * math.cos(BulletData.m_SideSpeedDir)
		VerticalPos.y = VerticalPos.y + SideDist * math.sin(BulletData.m_SideSpeedDir)
		BulletData.m_SideSpeed = BulletData.m_SideSpeed - BulletData.m_SideA2 * 0.001 * moveCyc
	end
	
	BulletData.m_CurX = LinePos.x + VerticalPos.x
	BulletData.m_CurY = LinePos.y + VerticalPos.y
	BulletData.m_CurZ = LinePos.z
end

function CBulletTrackMgr:PushBulletSpeed(Bullet, T)
	local bulletMoveData = Bullet.m_BulletMoveData
	local speed = bulletMoveData.m_BulletSpeed or 0 
	
	local data = Bullet_Bullet[bulletMoveData.m_BulletDataId]
	if not data then return speed end
	
	local acc = data.Acceleration
	if not acc then return speed end
	local bulletSpeed 
	if not data.NoAoiHit then
		bulletSpeed = min(bulletMoveData.m_BulletSpeed, MAX_BULLET_AOI_HIT_SPEED)
	else
		bulletSpeed = speed + acc * T
	end
	bulletMoveData.m_BulletSpeed = bulletSpeed 
	return bulletSpeed
end

function CBulletTrackMgr:UpdateAsDirection(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			bullet.m_BulletMoveStopMoving = true
		end
		return
	end
	local t = deltaTime
	if BulletData.m_StartTime then
		local lagCompensationTime = g_App:GetGlobalTime() - BulletData.m_StartTime
		lagCompensationTime = Clamp(lagCompensationTime, 0, 300)
		t = t + lagCompensationTime * 0.001
		BulletData.m_StartTime = nil
	end

	local acc = BulletData.m_Accel or 0
	local oldSpeed = BulletData.m_BulletSpeed
	local newSpeed = oldSpeed + acc * t
	
	local dist = (oldSpeed + newSpeed) *0.5 * t
	local dx = BulletData.m_MoveVectorX
	local dy = BulletData.m_MoveVectorY
	local dz = BulletData.m_MoveVectorZ
	
	if BulletData.m_MaxDistance then
		local maxDistance = BulletData.m_MaxDistance
		local moveDistance = BulletData.m_MoveDistance + dist
		BulletData.m_MoveDistance = moveDistance
		if moveDistance >= maxDistance then
			dist = dist - (moveDistance - maxDistance)
			BulletData.m_MoveDistance = maxDistance
			bullet.m_BulletMoveNextMoveStop = true
		end
	end
	
	BulletData.m_CurX = BulletData.m_CurX + dist * dx
	BulletData.m_CurY = BulletData.m_CurY + dist * dy
	BulletData.m_CurZ = BulletData.m_CurZ + dist * dz
end

--m_SideSpeedX
--m_SideSpeedY
--m_DistFromTop
function CBulletTrackMgr:UpdateAsChase3D(bullet, deltaTime)
	local BulletData = bullet.m_BulletMoveData
	
	if bullet.m_BulletMoveNextMoveStop then
		bullet.m_BulletMoveNextMoveStop = false
		if isRunningServerCode then
			if BulletData.m_TrajectoryArgs ~= 1 then
				bullet.m_BulletMoveStopMoving = true
			end
			if BulletData.m_TargeterEngineObjectId then
				bullet:TargetReached()
				bullet:OnFlowchartEvent("TargetReached", BulletData.m_TargeterEngineObjectId)
			else
				bullet:OnFlowchartEvent("PosReached")
			end
		end
		return
	end

	local bx, by, bz = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
	local dx, dy, dz
	--print("UpdateAsChase", bx, by, bz)

	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if Targeter then
		if isRunningServerCode then
			dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
			dz = dz + (BulletData.m_TargetOffsetZ or 0)
		else
			local preData = bullet.m_PreComputeDatas
			if preData and preData.valid then
				dx, dy, dz = preData.m_PreTargetX, preData.m_PreTargetY, preData.m_PreTargetZ
				
			else
				if  debugWorker and IsInWorkerpipelineThread() then  QLOG( "debugWorker", BulletData.m_Trajectory, bullet) end
				local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
				if suc then
					dx, dy, dz = transX, transY, transZ
				else
					dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
				end
			end
		end
		BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = dx, dy, dz
	else
		dx, dy, dz  = BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ
	end
	local CurPosX,CurPosY,CurPosZ = bx, by, bz
	
	local moveCyc = deltaTime
	
	if BulletData.m_SideTime <= 0 then
		BulletData.m_BulletSpeedNow = BulletData.m_BulletSpeed * 1.5
	else
		BulletData.m_BulletSpeedNow = BulletData.m_BulletSpeed * 0.2
	end
	
	local dist = moveCyc * BulletData.m_BulletSpeedNow * 0.001
	
	local DistanceX = dx - CurPosX
	local DistanceY = dy - CurPosY
	local DistanceZ = dz - CurPosZ
	
	if BulletData.m_SideTime > 0 then
		DistanceZ = 0
	end
	
	local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
	if Dist <= dist then
		BulletData.m_CurX = dx
		BulletData.m_CurY = dy
		BulletData.m_CurZ = dz
		bullet.m_BulletMoveNextMoveStop = true
		return
	end
	
	CurPosX = CurPosX + dist * DistanceX / Dist
	CurPosY = CurPosY + dist * DistanceY / Dist
	CurPosZ = CurPosZ + dist * DistanceZ / Dist
	
	if BulletData.m_SideTime > 0 then
		local SideDistX, SideDistY = BulletData.m_SideSpeedX * moveCyc * 0.001, BulletData.m_SideSpeedY * moveCyc * 0.001
		BulletData.m_SideSpeedX = BulletData.m_SideSpeedX - BulletData.m_XSpeedDecay * moveCyc
		BulletData.m_SideSpeedY = BulletData.m_SideSpeedY - BulletData.m_YSpeedDecay * moveCyc
		CurPosX = CurPosX + SideDistX
		CurPosY = CurPosY + SideDistY
	end

	if BulletData.m_SideTime > 0 then
		BulletData.m_SideTime = BulletData.m_SideTime - moveCyc
		CurPosZ = CurPosZ + BulletData.m_ZSpeed * moveCyc * 0.001
		BulletData.m_ZSpeed = BulletData.m_ZSpeed - BulletData.m_ZSpeedDecay * moveCyc
	end

	BulletData.m_CurX = CurPosX
	BulletData.m_CurY = CurPosY
	BulletData.m_CurZ = CurPosZ
end

function CBulletTrackMgr:UpdateAsCustom(BulletData, bullet)
	local trajectoryArgs = BulletData.m_TrajectoryArgs
	local tp = trajectoryArgs and trajectoryArgs[1]

	if tp == 'RotatedWaitTarget' then
		local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
		if not Targeter then return end

		local dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
		BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = dx, dy, dz

		local bx, by, bz = BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ
		local CurPosX,CurPosY,CurPosZ = bx, by, bz
		
		local moveCyc = self:GetMoveCyc()
		
		local dist = moveCyc * BulletData.m_BulletSpeed * 0.001
		
		local DistanceX = dx - CurPosX
		local DistanceY = dy - CurPosY
		local DistanceZ = dz - CurPosZ
		local Dist = math.sqrt( DistanceX ^ 2 + DistanceY ^ 2 + DistanceZ ^ 2)
		if Dist <= dist then
			BulletData.m_CurX = dx
			BulletData.m_CurY = dy
			BulletData.m_CurZ = dz
			bullet.m_BulletMoveNextMoveStop = true
			return
		end
		
		CurPosX = CurPosX + dist * DistanceX / Dist
		CurPosY = CurPosY + dist * DistanceY / Dist
		CurPosZ = CurPosZ + dist * DistanceZ / Dist
	
		-- print("UpdateAsCustom RotatedWaitTarget ", Dist, dist)

		BulletData.m_CurX = CurPosX
		BulletData.m_CurY = CurPosY
		BulletData.m_CurZ = CurPosZ
	end
end

-- ============================================================
-- 主线程预计算：Worker 执行前在主线程 snap C# 骨骼/位置数据
-- 结果写入 bullet.m_PreComputeDatas，Worker 路径的 UpdateAs* 优先消费
-- m_PreComputeDatas = { m_PreTargetX, m_PreTargetY, m_PreTargetZ, m_PrepareFromRO }
-- m_PrepareFromRO: true = 来自 GetHitLocalFramPos，false = 退回 GetPixelPosv3
-- ============================================================
-- Chase 类型：含 C# RenderObject 骨骼查询，需在主线程预计算
function CBulletTrackMgr:PrepareAsChase(bullet)
	local BulletData = bullet.m_BulletMoveData
	

	if isRunningServerCode then return end

	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if not Targeter then 
		if debugWorker then QLOG( "debugWorker PrepareAsChase 1",  bullet) end
		return 
	end

	local dx, dy, dz, bFromRO
	if BulletData.m_TargetBonePos then
		local ro = Targeter:GetRenderObject()
		local pos = ro and ro:GetBonePosition(BulletData.m_TargetBonePos)
		if pos then
			dx = pos.x * EnumGlobalConstants.PIXEL_PER_GRID
			dy = pos.y * EnumGlobalConstants.PIXEL_PER_GRID
			dz = pos.z * EnumGlobalConstants.PIXEL_PER_GRID
			bFromRO = true
		end
	else
		local suc, transX, transY, transZ = Targeter:GetHitLocalFramPos()
		if suc then dx, dy, dz, bFromRO = transX, transY, transZ, true end
	end
	if not dx then
		dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
		bFromRO = false
	end
	if BulletData.m_RandomTrans then
		dx = dx + BulletData.m_RandomTrans.x
		dy = dy + BulletData.m_RandomTrans.y
		dz = dz + BulletData.m_RandomTrans.z
	end
	bullet.m_PreComputeDatas = bullet.m_PreComputeDatas or {}
	bullet.m_PreComputeDatas.m_PreTargetX = dx
	bullet.m_PreComputeDatas.m_PreTargetY = dy
	bullet.m_PreComputeDatas.m_PreTargetZ = dz
	bullet.m_PreComputeDatas.m_PrepareFromRO = bFromRO
	bullet.m_PreComputeDatas.valid = true
	if debugWorker then QLOG( "debugWorker PrepareAsChase 0",  bullet) end
end

function CBulletTrackMgr:PrepareAsGenericTarget(bullet)
	

	if isRunningServerCode then return end
	local BulletData = bullet.m_BulletMoveData
	if not BulletData then return end

	local Targeter = GetCharacterByEngineObjectGlobalId(BulletData.m_TargeterEngineObjectId, true)
	if not Targeter then 
		if debugWorker then QLOG( "debugWorker PrepareAsGenericTarget 1",  bullet) end
		return 
	end

	local suc, dx, dy, dz = Targeter:GetHitLocalFramPos()
	local bFromRO = suc
	if not suc then
		dx, dy, dz = Targeter.m_engineObject:GetPixelPosv3()
	end

	bullet.m_PreComputeDatas = bullet.m_PreComputeDatas or {}
	bullet.m_PreComputeDatas.m_PreTargetX = dx
	bullet.m_PreComputeDatas.m_PreTargetY = dy
	bullet.m_PreComputeDatas.m_PreTargetZ = dz
	bullet.m_PreComputeDatas.m_PrepareFromRO = bFromRO
	bullet.m_PreComputeDatas.valid = true
	if debugWorker then QLOG( "debugWorker PrepareAsGenericTarget 0",  bullet) end
end

function CBulletTrackMgr:PrepareMarkNeedCB(bullet)
	bullet.m_PreComputeDatas = bullet.m_PreComputeDatas or {}
	bullet.m_PreComputeDatas.valid = true
	bullet.m_PreComputeDatas.NeedDelay = true
	if debugWorker then QLOG( "debugWorker PrepareMarkNeedCB 0",  bullet) end
end

function CBulletTrackMgr:DoneUpdateBezierCircle(bullet)
	if isRunningServerCode then return end
	local BulletData = bullet.m_BulletMoveData
	if not BulletData then return end
	if BulletData.m_CollisionRadius then
		bullet:OnCollisionDetectionOnBezierSplineMove(BulletData.m_CurX, BulletData.m_CurY, BulletData.m_CurZ, BulletData.m_CollisionRadius, BulletData.m_CollisionOffsetY, BulletData.m_SplineIndex)
	end	
end

function CBulletTrackMgr:DoneUpdateAsForwardChase2D(bullet)
	if isRunningServerCode then return end
	local BulletData = bullet.m_BulletMoveData
	if not BulletData then return end
	local simulator = bulletData.m_Simulator
	bullet.m_engineObject:SetDirectionDegree(deg(simulator.theta))

	bullet:SetAnimatorFloatParam("fTurnDirection", -math.deg(simulator.omega))
	bullet:SetAnimatorFloatParam("fMoveSpeed", simulator.v / 64)
end

-- 预计算分发表（与 TrajectoryUpdateMap 平行）
-- 仅注册含 C# GetHitLocalFramPos / GetPixelPosv3 调用的轨迹类型
-- 值为 {prepareFn, targetIdField}
local TrajectoryPrepareMap = {
	[EnumBulletTracjectory.Chase]               = CBulletTrackMgr.PrepareAsChase,
	[EnumBulletTracjectory.Bezier]              = CBulletTrackMgr.PrepareAsGenericTarget,
	[EnumBulletTracjectory.TractionAndCircling] = CBulletTrackMgr.PrepareAsGenericTarget,
	[EnumBulletTracjectory.HalfChase]           = CBulletTrackMgr.PrepareAsGenericTarget,
	[EnumBulletTracjectory.Chase3D]             = CBulletTrackMgr.PrepareAsGenericTarget,
	[EnumBulletTracjectory.ParabolaExPos]       = CBulletTrackMgr.PrepareAsGenericTarget,
	[EnumBulletTracjectory.ParabolaPos]         = CBulletTrackMgr.PrepareAsGenericTarget,

	[EnumBulletTracjectory.BezierCircle]      	= CBulletTrackMgr.PrepareMarkNeedCB,
	[EnumBulletTracjectory.ForwardChase2D] 		= CBulletTrackMgr.PrepareMarkNeedCB,

}
rawset(_G, "g_PendingLuaMoveIds", {})
-- 由 C++ CLuaMoveUpdateTask::PrepareOnMainThread 在 SubmitTask 前调用（主线程）
-- 对本帧所有注册的 LuaMoveState 对象，按轨迹类型执行 C# 数据预计算
function LuaMoveObjPrepare(n)
	local ids = rawget(_G, "g_PendingLuaMoveIds")
	if debugWorker then QLOG( "debugWorker LuaMoveObjPrepare",  n, #ids) end
	for i = 1, n do
		local obj = EID2OBJ(ids[i])
		local BulletData = obj and obj.m_BulletMoveData
		local trajectory = BulletData and BulletData.m_Trajectory
		if trajectory then
			local prepareFn = TrajectoryPrepareMap[trajectory]
			if prepareFn then
				prepareFn(CBulletTrackMgr, obj)
			end
		end
	end
end

local TrajectoryDoneMap = {
	[EnumBulletTracjectory.BezierCircle]      	= CBulletTrackMgr.DoneUpdateBezierCircle,
	[EnumBulletTracjectory.ForwardChase2D] 		= CBulletTrackMgr.DoneUpdateAsForwardChase2D,
}
-- 由 C++ CLuaMoveUpdateTask::OnResultCollected 在结果应用完毕后调用（主线程）
-- 对本帧所有 LuaMoveState 对象执行 C# 收尾处理（如更新渲染骨骼、同步 Unity Transform 等）
function LuaMoveObjDone(n)
	local ids = rawget(_G, "g_PendingLuaMoveIds")
	if debugWorker then QLOG( "debugWorker LuaMoveObjDone",  n, #ids) end
	for i = 1, n do
		local obj = EID2OBJ(ids[i])
		local BulletData = obj and obj.m_BulletMoveData
		local trajectory = BulletData and BulletData.m_Trajectory
		if trajectory then
			local preData = obj.m_PreComputeDatas
			if preData then
				preData.valid = nil
				preData.NeedDelay = nil
			end

			local doneFn = TrajectoryDoneMap[trajectory]
			if doneFn then
				doneFn(CBulletTrackMgr, obj)
			end
		end
		ids[i] = nil   -- 清空槽位
	end
end

local TrajectoryUpdateMap = {
	[EnumBulletTracjectory.Direction_Opt] = CBulletTrackMgr.UpdateAsDirection,
	[EnumBulletTracjectory.Direction] = CBulletTrackMgr.UpdateAsDirection,
	[EnumBulletTracjectory.Chase] = CBulletTrackMgr.UpdateAsChase,
	[EnumBulletTracjectory.HalfChase] = CBulletTrackMgr.UpdateAsHalfChase,
	[EnumBulletTracjectory.Chase3D] = CBulletTrackMgr.UpdateAsChase3D,
	[EnumBulletTracjectory.Circle] = CBulletTrackMgr.UpdateAsCircle,
	[EnumBulletTracjectory.BaFangJue] = CBulletTrackMgr.UpdateAsBaFangJue,
	[EnumBulletTracjectory.ParabolaPos] = CBulletTrackMgr.UpdateAsParabolaPos,
	[EnumBulletTracjectory.ParabolaExPos] = CBulletTrackMgr.UpdateAsParabolaExPos,
	[EnumBulletTracjectory.Bezier] = CBulletTrackMgr.UpdateAsBezierPos,
	[EnumBulletTracjectory.Arc] = CBulletTrackMgr.UpdateAsArc,
	[EnumBulletTracjectory.TractionAndCircling] = CBulletTrackMgr.UpdateAsTractionAndCircling,
	[EnumBulletTracjectory.EffectBullet] = CBulletTrackMgr.UpdateAsEffectBullet,
	[EnumBulletTracjectory.BezierCircle] = CBulletTrackMgr.UpdateBezierCircle,
	[EnumBulletTracjectory.CircleChase] = CBulletTrackMgr.UpdateCircleChase,
	[EnumBulletTracjectory.RepeatHitTarget] = CBulletTrackMgr.UpdateRepeatHitTarget,
	[EnumBulletTracjectory.ForwardChase2D] = CBulletTrackMgr.UpdateAsForwardChase2D,
	[EnumBulletTracjectory.BoatFrontMove2D] = CBulletTrackMgr.UpdateBoatFrontMove2D,
}

function GetLuaNextMove(moveData, bullet, deltaTime)
	DeltaTime = deltaTime
	local trajectory = moveData.m_Trajectory
	--local args = moveData.m_TrajectoryArgs

	if moveData.m_IsPaused then
		return
	end
	-- 使用查找表替代 if-else
	local updateFunc = TrajectoryUpdateMap[trajectory]
	if updateFunc then
		updateFunc(CBulletTrackMgr, bullet, DeltaTime)
	end
end

PowerFunctionCurve = {}

function PowerFunctionCurve.Rotate(x, y, c, s)
	return x * c - y * s, y * c + x * s
end

function PowerFunctionCurve.CalculateAngle(x, y, d, sm)
	local dir1 = math.atan2(y, x - d)
	local dir2 = math.atan2(y, x)
	local hi = math.min(math.pi - dir1, math.pi * 0.5 - dir2)
	local lo = math.max(math.pi * 0.5 - dir1, -dir2)
	sm = sm + 1

	local function CalculateFactor(dir)
		local c, s = math.cos(dir), math.sin(dir)
		local xs, ys = PowerFunctionCurve.Rotate(-x, -y, c, s)
		local xe, ye = PowerFunctionCurve.Rotate(d-x, -y, c, s)
		return ys * math.abs(xe)^sm > ye * math.abs(xs)^sm
	end

	for i = 1, 16 do
		local mid = (lo + hi) * 0.5
		if CalculateFactor(mid) then
			lo = mid
		else
			hi = mid
		end
	end

	return math.cos((lo + hi) * 0.5), math.sin((lo + hi) * 0.5)
end

function PowerFunctionCurve.CalculateCurve(x, y, d, sm, c, s, t)
	local xs, ys = PowerFunctionCurve.Rotate(-x, -y, c, s)
	local xe, ye = PowerFunctionCurve.Rotate(d-x, -y, c, s)
	sm = sm + 1
	t = (math.abs(xs) + math.abs(xe)) * t

	local xx, yy
	if t < math.abs(xs) then
		if xs < 0 then
			xx = xs + t
		else
			xx = xs - t
		end
		if xs == 0 then return end
		yy = (math.abs(xx / xs)^sm) * ys
	else
		if xe > 0 then
			xx = t - math.abs(xs)
		else
			xx = math.abs(xs) - t
		end
		if xe == 0 then return end
		yy = (math.abs(xx / xe)^sm) * ye
	end

	xx, yy = PowerFunctionCurve.Rotate(xx, yy, c, -s)
	return xx + x, yy + y
end

--水都子弹
function IsLanDuWaterBullet(bulletId)
	local setting = table.safe_get(GameSetting_Common, "LANDU_WATER_BULLET_ID", "tblVal")
	return setting and setting[bulletId]
end

function OldCheckBulletCollisionDetection(coreScene, PreX, PreY, PreZ, NowX, NowY, NowZ)
	local oldGridPosX, oldGridPosY = GetGridByPixel2(PreX, PreY)
	local newGridPosX, newGridPosY = GetGridByPixel2(NowX, NowY)
	if not (newGridPosX == oldGridPosX and newGridPosY == oldGridPosY) then 
		local gridTbl = coreScene:GetPixelLine(PreX, PreY, PreZ, NowX, NowY, NowZ, false, false)
		for i = 1, #gridTbl, 3 do
			local gridX, gridY, gridZ = GetGridByPixel2(gridTbl[i], gridTbl[i + 1], gridTbl[i + 2])
			local barrierType = coreScene:GetBarrierv3(gridX, gridY, gridZ)
			if barrierType > EBarrierType.eBT_MidBarrier then
				return true, gridX * 64, gridY * 64, gridZ * 64
			end
		end
	end
end

function FixBulletPosToMoveTrack(ax, ay, az, bx, by, bz, px, py, pz, off)
	-- 计算p在ab上的投影点AB
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local apx, apy, apz = px - ax, py - ay, pz - az
	local abLengthSquared = abx * abx + aby * aby + abz * abz
	if abLengthSquared == 0 then
		return ax, ay, az
	end
	local t = (apx * abx + apy * aby + apz * abz) / abLengthSquared
	local tx, ty, tz = ax + abx * t, ay + aby * t, az + abz * t
	if not off then
		return tx, ty, tz
	end
    local length = math.sqrt(abLengthSquared)
    local scale = off / length
	return tx - scale * abx, ty - scale * aby, tz - scale * abz
end

function CBulletTrackMgr:UpdateAsForwardChase2D(obj)
    local bulletData = obj.m_BulletMoveData
    local now = GetGlobalTime_ms() * 0.001
    local simulator = bulletData.m_Simulator
    local targetEID = bulletData.m_TargetEID
    local target = EID2OBJ(targetEID)
    if not target then
        obj.m_BulletMoveStopMoving = true
        return
    end
    local x_t, y_t = target:GetPixelPosition()

    simulator:Step(x_t, y_t, now)

    bulletData.m_CurX, bulletData.m_CurY, bulletData.m_CurZ = simulator.x, simulator.y, simulator.z

	local delayDo = obj.m_PreComputeDatas and obj.m_PreComputeDatas.NeedDelay
	if not delayDo then
		obj.m_engineObject:SetDirectionDegree(deg(simulator.theta))

		-- 动画参数暂时设置在这里，后面有更合适的地方再挪一下
		if not IsRunningServerCode() then
			obj:SetAnimatorFloatParam("fTurnDirection", -math.deg(simulator.omega))
			obj:SetAnimatorFloatParam("fMoveSpeed", simulator.v / 64)
		end
	end
end

--[[
function CForwardMoveSimulator:Ctor(x, y, z, theta, v, omega, v_max, omega_max, a_max, alpha_max, dt, last_ts, Kp, Kd,
                                    stop_dis, v_turn)
    self.x = x
    self.y = y
    self.z = z
    self.theta = theta
    self.v = v
    self.omega = omega
    self.v_max = v_max
    self.omega_max = omega_max
    self.a_max = a_max
    self.alpha_max = alpha_max
    self.dt = dt
    self.last_ts = last_ts
    self.stop_dis = stop_dis
    self.Kp = Kp
    self.Kd = Kd
    self.v_turn = v_turn
	self.v_z = 0
	self.v_z_end_ts = 0
end
]]

--[[
function CForwardMoveSimulator:Step(x_t, y_t, cur_ts)
    local last_ts, x, y, z, theta, v, omega, dt, a_max, alpha_max, Kp, Kd, omega_max, v_max, stop_dis, v_turn =
        self.last_ts, self.x, self.y, self.z, self.theta, self.v, self.omega, self.dt, self.a_max, self.alpha_max,
        self.Kp, self.Kd, self.omega_max, self.v_max, self.stop_dis, self.v_turn
	local v_z, v_z_end_ts = self.v_z, self.v_z_end_ts

    -- while last_ts + dt < cur_ts do
	-- ppp("step start")
    -- last_ts = last_ts + dt
    local a, alpha = self.control_strategy(x, y, theta, v, omega, x_t, y_t, a_max, alpha_max, stop_dis, Kp, Kd, v_turn)
    -- ppp(last_ts, a, alpha)
    x, y, theta, v, omega = self.constrained_xy_step(x, y, theta, v, omega, a, alpha, cur_ts - last_ts, v_max, omega_max)
	-- ppp(last_ts, x_t-x, y_t-y, math.deg(theta), v, math.deg(omega))
	-- ppp("step end")
	-- ppp(" ")
    -- end
	z = self.z_step(z, v_z, last_ts, v_z_end_ts, cur_ts)
	last_ts = cur_ts

    self.last_ts, self.x, self.y, self.z, self.theta, self.v, self.omega = last_ts, x, y, z, theta, v, omega
end
]]

function CForwardMoveSimulator:Ctor(x, y, z, theta, v, v_min, v_max, a_max, alpha_min, alpha_max, omega_max, dt, last_ts)
    self.x = x
    self.y = y
    self.z = z
    self.v = v
	self.v_min = v_min
    self.v_max = v_max
    self.a_max = a_max

	self.delta_theta = 0
	self.theta = theta
	self.alpha_min = alpha_min
	self.alpha_max = alpha_max
	self.alpha = 0
	self.omega_max = omega_max
	self.omega = 0

    self.dt = dt
    self.last_ts = last_ts

	self.v_z = 0
	self.v_z_end_ts = 0
end

function CForwardMoveSimulator:Step(x_t, y_t, cur_ts)
	local function sign(x)
		if x > 0 then
			return 1
		elseif x < 0 then
			return -1
		else
			return 0
		end
	end
	
	local x, y, z, v, v_min, v_max, a_max = self.x, self.y, self.z, self.v, self.v_min, self.v_max, self.a_max
	local _delta_theta, theta, alpha_min, alpha_max, alpha, omega_max, omega = self.delta_theta, self.theta, self.alpha_min, self.alpha_max, self.alpha, self.omega_max, self.omega
    local last_ts, dt = self.last_ts, self.dt
	local v_z, v_z_end_ts = self.v_z, self.v_z_end_ts

	local dX, dY = x_t - x, y_t - y
	local targetDir = atan2(dY, dX)
	local deltaDir = (targetDir - theta + pi) % pi2 - pi

	local a_modf = 0
	local absDeltaDir = abs(deltaDir)
	local deltaDirThreshold = pi * 1 / 2
	if absDeltaDir <= deltaDirThreshold then a_modf = 1 - absDeltaDir / deltaDirThreshold end
	--elseif absDeltaDir <= pi then a_modf = - (absDeltaDir - deltaDirThreshold) / (pi - deltaDirThreshold)  * 0.25
	--else a_modf = -1 end
	local a = a_modf * a_max
	v = clamp(v + a * dt, v_min, v_max)
	v = v * (1 - 0.1 * dt)

	local alphaLimit = (alpha_max - (v - v_min) / (v_max - v_min) * (alpha_max - alpha_min))
	local targetAlpha = clamp(deltaDir / pi * alphaLimit, -absDeltaDir / dt, absDeltaDir / dt)
	local deltaAlpha = targetAlpha - alpha 
	local omegaLimit = abs(deltaAlpha) / dt
	if alpha * targetAlpha < 0 then
		omega = clamp(omega_max * sign(deltaAlpha), -omegaLimit, omegaLimit)
	else
		omega = clamp(deltaAlpha / alpha_max * omega_max, -omegaLimit, omegaLimit)
	end
	
	alpha = alpha * (1 - 0.1 * dt)
	if abs(alpha) >= alphaLimit then alpha = alphaLimit * sign(alpha) end

	alpha = clamp(alpha + omega * dt, -alphaLimit, alphaLimit)
	theta = (theta + alpha * dt) % pi2

	x = x + v * cos(theta) * dt
	y = y + v * sin(theta) * dt
	z = self.z_step(z, v_z, last_ts, v_z_end_ts, cur_ts)
	last_ts = cur_ts

    self.last_ts, self.x, self.y, self.z, self.theta, self.v, self.alpha, self.omega, self.delta_theta = last_ts, x, y, z, theta, v, alpha, alpha / alpha_max * omega_max, deltaDir
end

function CForwardMoveSimulator.control_strategy(x, y, theta, v, omega, x_t, y_t, a_max, alpha_max, stop_dis, Kp, Kd,
                                                v_turn)
    -- 计算目标方向与距离
    local dx = x_t - x
    local dy = y_t - y
    local theta_target = atan2(dy, dx)
    local d2 = dx ^ 2 + dy ^ 2

    -- 方向控制 (PD)
    local delta_theta = (theta_target - theta + pi) % pi2 - pi -- 归一化到 [-π, π]
    local alpha = Kp * delta_theta - Kd * omega
    alpha = clamp(alpha, -alpha_max, alpha_max)

    -- 速度控制 (制动曲线)
    local a
    -- 转弯中
    local delta_theta_abs = abs(delta_theta)
    local in_turn = delta_theta_abs > pi * 0.2
    if in_turn and v > v_turn then
        a = -a_max -- 全力制动
    else
        local brake_distance = v ^ 2 / (2 * a_max) + stop_dis
        local brake_distance2 = brake_distance ^ 2
        if d2 <= brake_distance2 then
            a = -a_max -- 全力制动
        else
            a = a_max  -- 加速到允许的最大速度
        end
    end

    return a, alpha
end

-- 适用于车辆、船舶等前向运动模型的二维模拟
function CForwardMoveSimulator.constrained_xy_step(x, y, theta, v, omega, a, alpha, dt, v_max, omega_max)
    -- 步骤1：计算中间速度（应用限制）
    local v_half = clamp(v + 0.5 * a * dt, 0, v_max)
    local omega_half = clamp(omega + 0.5 * alpha * dt, -omega_max, omega_max)

    -- 步骤2：用受约束的中间速度更新位置和朝向
    local theta_half = theta + omega_half * dt * 0.5
    theta_half = theta_half % pi2
    local dx = v_half * cos(theta_half) * dt
    local dy = v_half * sin(theta_half) * dt
    local new_x = x + dx
    local new_y = y + dy

    -- 步骤3：更新最终状态（二次约束确保稳定性）
    local new_v = clamp(v + a * dt, 0, v_max)
    local new_omega = clamp(omega + alpha * dt, -omega_max, omega_max)
    local new_theta = (theta + omega_half * dt) % pi2

    return new_x, new_y, new_theta, new_v, new_omega
end

function CForwardMoveSimulator.z_step(z, v_z, last_ts, end_ts, cur_ts)
	end_ts = min(end_ts, cur_ts)
	if end_ts < last_ts then
		return z
	end
	local duration = end_ts - last_ts
	local dz = duration * v_z
	return z + dz
end
