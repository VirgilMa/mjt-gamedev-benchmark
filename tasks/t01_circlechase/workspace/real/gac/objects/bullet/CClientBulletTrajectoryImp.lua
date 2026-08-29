-- 纯客户端子弹轨迹启动实现
-- 对应服务端 gas/lua/objects/BulletTrajectoryImp.lua，适配纯客户端子弹变轨逻辑

ClientBulletTrajectoryImp = {}

function ClientBulletTrajectoryImp:SetBulletMoveTrajectory(obj, Trajectory)
	local bulletData = obj.m_BulletMoveData
	if not bulletData then return end
	local trajectory = EnumBulletTracjectory[Trajectory]
	if not trajectory then
		LogCallContext_lua()
		return
	end
	bulletData.m_Trajectory = trajectory
	UnRegisterObjTick(obj, "DelayMoveTick")
end

function ClientBulletTrajectoryImp:CalcBezierCurveValue(obj)
	local bulletData = obj.m_BulletMoveData
	local x, y = bulletData.m_DestX, bulletData.m_DestY
	if bulletData.m_TargeterEngineObjectId then
		local target = GetCharacterByEngineObjectGlobalId(bulletData.m_TargeterEngineObjectId, true)
		if target then
			if target.m_engineObject then
				x, y = target.m_engineObject:GetPixelPosv3()
			elseif target.GetPixelPosition then
				x, y = target:GetPixelPosition()
			end
		end
	end
	if x and y then
		local d = math.sqrt((bulletData.m_SourceX - x)^2 + (bulletData.m_SourceY - y)^2)
		bulletData.m_CosParam, bulletData.m_SinParam = PowerFunctionCurve.CalculateAngle(bulletData.m_HorizontalParam, bulletData.m_VerticalParam, d, bulletData.m_SmoothParam)
	else
		bulletData.m_CosParam, bulletData.m_SinParam = 1, 0
	end
end

function ClientBulletTrajectoryImp:StartBezierCurvePos(obj, pos, customArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then
		return
	end

	self:SetBulletMoveTrajectory(obj, "Bezier")

	local DestPosX, DestPosY, DestPosZ = pos.x, pos.y, pos.z
	if not (DestPosX and DestPosY and DestPosZ) then
		LogCallContext_lua()
		return
	end

	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
	BulletData.m_SourceX = BulletData.m_CurX
	BulletData.m_SourceY = BulletData.m_CurY
	BulletData.m_SourceZ = BulletData.m_CurZ

	local args = customArgs or BulletData.m_TrajectoryArgs
	BulletData.m_HorizontalParam = args[2] * 64
	BulletData.m_VerticalParam = -args[1] * 64
	BulletData.m_FlightTime = args[5] or -1
	BulletData.m_ZDegree = BulletData.m_VerticalParam > 0 and args[3] or -args[3]
	BulletData.m_SmoothParam = args[4] or 0.5
	BulletData.m_InflectionSpeed = args[6] or -1

	self:CalcBezierCurveValue(obj)

	obj:StartLuaMove()
end

function ClientBulletTrajectoryImp:StartBezierCurveTarget(obj, target, customArgs)
	local BulletData = obj.m_BulletMoveData
	if not BulletData then
		return
	end

	self:SetBulletMoveTrajectory(obj, "Bezier")

	local DestPosX, DestPosY, DestPosZ
	if target.m_engineObject then
		DestPosX, DestPosY, DestPosZ = target.m_engineObject:GetPixelPosv3()
	elseif target.GetPixelPosition then
		DestPosX, DestPosY, DestPosZ = target:GetPixelPosition()
	else
		LogCallContext_lua()
		return
	end

	BulletData.m_DestX, BulletData.m_DestY, BulletData.m_DestZ = DestPosX, DestPosY, DestPosZ
	BulletData.m_SourceX = BulletData.m_CurX
	BulletData.m_SourceY = BulletData.m_CurY
	BulletData.m_SourceZ = BulletData.m_CurZ

	local args = customArgs or BulletData.m_TrajectoryArgs
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

	obj:StartLuaMove()
end

--给策划流程图用
function CClientBulletOpt:StartBezierCurvePos(...) return ClientBulletTrajectoryImp:StartBezierCurvePos(self, ...) end
function CClientBulletOpt:StartBezierCurveTarget(...) return ClientBulletTrajectoryImp:StartBezierCurveTarget(self, ...) end