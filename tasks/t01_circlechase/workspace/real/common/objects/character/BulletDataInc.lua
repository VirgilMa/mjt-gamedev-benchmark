CBulletMoveData = {}	--不添加任何数据

------------------------------------------------------------
--注意！这边加的数据都是会走同步的！如果有不需要同步的变量，请放到角色下！！！
--注意！这边加的数据都是会走同步的！如果有不需要同步的变量，请放到角色下！！！
--注意！这边加的数据都是会走同步的！如果有不需要同步的变量，请放到角色下！！！
--注意！这边加的数据都是会走同步的！如果有不需要同步的变量，请放到角色下！！！

CBulletData_Freq = class()	--这里是每次update移动都可能会发生变化的
RegistClassMember(CBulletData_Freq, "m_NewBorn")		--刚出生的时候设为true,后续就是出生了多久
RegistClassMember(CBulletData_Freq, "m_CurX")
RegistClassMember(CBulletData_Freq, "m_CurY")
RegistClassMember(CBulletData_Freq, "m_CurZ")

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

CBulletData_NoFreq = class()
RegistClassMember(CBulletData_NoFreq, "m_AbsorbedBy")
RegistClassMember(CBulletData_NoFreq, "m_BulletDataId")
RegistClassMember(CBulletData_NoFreq, "m_UseOtherBulletClientResource")
RegistClassMember(CBulletData_NoFreq, "m_BulletSpeed")
RegistClassMember(CBulletData_NoFreq, "m_DestX")
RegistClassMember(CBulletData_NoFreq, "m_DestY")
RegistClassMember(CBulletData_NoFreq, "m_DestZ")
RegistClassMember(CBulletData_NoFreq, "m_DestOffsetX")
RegistClassMember(CBulletData_NoFreq, "m_DestOffsetY")
RegistClassMember(CBulletData_NoFreq, "m_DestOffsetZ")
RegistClassMember(CBulletData_NoFreq, "m_TargeterEngineObjectId")
RegistClassMember(CBulletData_NoFreq, "m_Trajectory")
RegistClassMember(CBulletData_NoFreq, "m_TrajectoryArgs")
RegistClassMember(CBulletData_NoFreq, "m_OwnerId")
RegistClassMember(CBulletData_NoFreq, "m_RootOwnerId")
RegistClassMember(CBulletData_NoFreq, "m_RootOwnerCharacterType")
RegistClassMember(CBulletData_NoFreq, "m_CrossBarrierAbility")
-- 初始创建时为1
-- 后续调用InitMoveDataByBulletId时为2
-- 运动过程中为nil
RegistClassMember(CBulletData_NoFreq, "m_Status") 

--ClientBulletData
--子弹3d初始朝向
RegistClassMember(CBulletData_NoFreq, "m_DirZ")

RegistClassMember(CBulletData_NoFreq, "m_RandomTrans")

RegistClassMember(CBulletData_NoFreq, "m_IsPaused") -- 是否暂停
RegistClassMember(CBulletData_NoFreq, "m_IsInvisible") -- 是否隐身
RegistClassMember(CBulletData_NoFreq, "m_ReplaceClassByCharacterDef") -- piece替换情况 
RegistClassMember(CBulletData_NoFreq, "m_TimeScale")
RegistClassMember(CBulletData_NoFreq, "m_DirTrackTargetId") -- 客户端方向追踪目标 engineObjectId，nil/0 表示不追踪
-- 自定义数据：纯客户端子弹（IsPureClientBullet==1）创建时由服务端通过 CreateSomeBullet.CustomData 带入，
-- 随 RefreshBulletOptMoveData 同步到客户端保存，客户端用 GetCustomDataClientBullet() 按 key 读取；不填时默认为 nil
RegistClassMember(CBulletData_NoFreq, "m_CustomData")

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

CBulletData_Direction = class()
RegistClassMember(CBulletData_Direction, "m_MoveDistance")
RegistClassMember(CBulletData_Direction, "m_MoveVectorX")
RegistClassMember(CBulletData_Direction, "m_MoveVectorY")
RegistClassMember(CBulletData_Direction, "m_MoveVectorZ")
RegistClassMember(CBulletData_Direction, "m_MaxDistance")
RegistClassMember(CBulletData_Direction, "m_StartTime")
RegistClassMember(CBulletData_Direction, "m_Accel")

CBulletData_Parabola = class()
RegistClassMember(CBulletData_Parabola, "m_ParabolaH")
RegistClassMember(CBulletData_Parabola, "m_SourceX")
RegistClassMember(CBulletData_Parabola, "m_SourceY")
RegistClassMember(CBulletData_Parabola, "m_SourceZ")
RegistClassMember(CBulletData_Parabola, "m_ParabolaA")
RegistClassMember(CBulletData_Parabola, "m_ParabolaB")
RegistClassMember(CBulletData_Parabola, "m_ParabolaC")
RegistClassMember(CBulletData_Parabola, "m_ParabolaAllTime")
RegistClassMember(CBulletData_Parabola, "m_ParabolaStartTime")
RegistClassMember(CBulletData_Parabola, "m_NowTime")
RegistClassMember(CBulletData_Parabola, "m_bTrackZ")

CBulletData_ParabolaEx = class()
RegistClassMember(CBulletData_ParabolaEx, "m_G")
RegistClassMember(CBulletData_ParabolaEx, "m_OriDirX")
RegistClassMember(CBulletData_ParabolaEx, "m_OriDirY")
RegistClassMember(CBulletData_ParabolaEx, "m_OriDirZ")
RegistClassMember(CBulletData_ParabolaEx, "m_VectorZ")

CBulletData_Bezier = class()
RegistClassMember(CBulletData_Bezier, "m_SourceX")
RegistClassMember(CBulletData_Bezier, "m_SourceY")
RegistClassMember(CBulletData_Bezier, "m_SourceZ")
RegistClassMember(CBulletData_Bezier, "m_BezierStartTime")
RegistClassMember(CBulletData_Bezier, "m_HorizontalParam")
RegistClassMember(CBulletData_Bezier, "m_VerticalParam")
RegistClassMember(CBulletData_Bezier, "m_ZParam")
RegistClassMember(CBulletData_Bezier, "m_CosParam")
RegistClassMember(CBulletData_Bezier, "m_SinParam")
RegistClassMember(CBulletData_Bezier, "m_SmoothParam")
RegistClassMember(CBulletData_Bezier, "m_FlightTime")
RegistClassMember(CBulletData_Bezier, "m_TrackTime")
RegistClassMember(CBulletData_Bezier, "m_ZDegree")
RegistClassMember(CBulletData_Bezier, "m_OriDist")
RegistClassMember(CBulletData_Bezier, "m_NowTime")
RegistClassMember(CBulletData_Bezier, "m_PreDeltaX")
RegistClassMember(CBulletData_Bezier, "m_PreDeltaY")
RegistClassMember(CBulletData_Bezier, "m_PreDeltaZ")
RegistClassMember(CBulletData_Bezier, "m_InflectionSpeed")
RegistClassMember(CBulletData_Bezier, "m_NoStop") --到达终点不停止，继续沿着当前方向直行
RegistClassMember(CBulletData_Bezier, "m_bReachedTarget") -- 已经到达目标点


CBulletData_Arc = class()
RegistClassMember(CBulletData_Arc, "m_ArcCurYawAngle")
RegistClassMember(CBulletData_Arc, "m_ArcRotateCurAngle")
RegistClassMember(CBulletData_Arc, "m_ArcRotateMaxAngle")
RegistClassMember(CBulletData_Arc, "m_ArcRotateRadius")

CBulletData_Chase = class()
RegistClassMember(CBulletData_Chase, "m_TargetOffsetZ")
RegistClassMember(CBulletData_Chase, "m_SideSpeed")
RegistClassMember(CBulletData_Chase, "m_BulletSpeedNow")
RegistClassMember(CBulletData_Chase, "m_SideSpeedDecay")
RegistClassMember(CBulletData_Chase, "m_TargetBonePos")
RegistClassMember(CBulletData_Chase, "m_Accel")
RegistClassMember(CBulletData_Chase, "m_NoStop")
RegistClassMember(CBulletData_Chase, "m_MaxAngleSpeed")

CBulletData_HalfChase = class()
RegistClassMember(CBulletData_HalfChase, "m_TargetOffsetZ")
RegistClassMember(CBulletData_HalfChase, "m_SideSpeed")
RegistClassMember(CBulletData_HalfChase, "m_BulletSpeedNow")
RegistClassMember(CBulletData_HalfChase, "m_SideSpeedDecay")
RegistClassMember(CBulletData_HalfChase, "m_StopChaseAngle")
RegistClassMember(CBulletData_HalfChase, "m_MaxChaseAngle")
RegistClassMember(CBulletData_HalfChase, "m_ChaseSuccessed")
RegistClassMember(CBulletData_HalfChase, "m_MaxChaseAngleDecay") -- 最大追踪角度衰减
RegistClassMember(CBulletData_HalfChase, "m_TrackTime") -- 追踪时间

CBulletData_TractionAndCircling = class()
RegistClassMember(CBulletData_TractionAndCircling, "m_OriginWithTarget")
RegistClassMember(CBulletData_TractionAndCircling, "m_OriginId")
RegistClassMember(CBulletData_TractionAndCircling, "m_StartPoint")
RegistClassMember(CBulletData_TractionAndCircling, "m_RotateVector")
RegistClassMember(CBulletData_TractionAndCircling, "m_RotateSpeed")
RegistClassMember(CBulletData_TractionAndCircling, "m_IsTraction")
RegistClassMember(CBulletData_TractionAndCircling, "m_TractionSpeed")
RegistClassMember(CBulletData_TractionAndCircling, "m_TracionLimitDist")
RegistClassMember(CBulletData_TractionAndCircling, "m_IsZMove")
RegistClassMember(CBulletData_TractionAndCircling, "m_RotateZSpeed")
RegistClassMember(CBulletData_TractionAndCircling, "m_RotateZLimitHigh")
RegistClassMember(CBulletData_TractionAndCircling, "m_TractionAllTime")
RegistClassMember(CBulletData_TractionAndCircling, "m_TractionStartTime")

CBulletData_Circle = class()
RegistClassMember(CBulletData_Circle, "m_CircleRadius")
RegistClassMember(CBulletData_Circle, "m_CircleMaxHeight")
RegistClassMember(CBulletData_Circle, "m_CircleMinHeight")
RegistClassMember(CBulletData_Circle, "m_TargetPos")
RegistClassMember(CBulletData_Circle, "m_CircleSpeedZ")
RegistClassMember(CBulletData_Circle, "m_RelativeZ")
RegistClassMember(CBulletData_Circle, "m_OwnerPos")
RegistClassMember(CBulletData_Circle, "m_Wait")
RegistClassMember(CBulletData_Circle, "m_Step")
RegistClassMember(CBulletData_Circle, "m_FlyHeight")
RegistClassMember(CBulletData_Circle, "m_ClockWise")
RegistClassMember(CBulletData_Circle, "m_RadiusEquipToDistance_TargetId")

CBulletData_BaFangJue = class()
RegistClassMember(CBulletData_BaFangJue, "m_LinePos")
RegistClassMember(CBulletData_BaFangJue, "m_VerticalPos")
RegistClassMember(CBulletData_BaFangJue, "m_SideA1")
RegistClassMember(CBulletData_BaFangJue, "m_SideA2")
RegistClassMember(CBulletData_BaFangJue, "m_SideSpeedDir")

CBulletData_Chase3D = class()
RegistClassMember(CBulletData_Chase3D, "m_TargetOffsetZ")
RegistClassMember(CBulletData_Chase3D, "m_BulletSpeedNow")
RegistClassMember(CBulletData_Chase3D, "m_ZSpeedDecay")
RegistClassMember(CBulletData_Chase3D, "m_XSpeedDecay")
RegistClassMember(CBulletData_Chase3D, "m_YSpeedDecay")
RegistClassMember(CBulletData_Chase3D, "m_SideSpeedX")
RegistClassMember(CBulletData_Chase3D, "m_SideSpeedY")
RegistClassMember(CBulletData_Chase3D, "m_SideTime")
RegistClassMember(CBulletData_Chase3D, "m_ZSpeed")

CBulletData_EffectBullet = class()
RegistClassMember(CBulletData_EffectBullet, "m_SourceX")
RegistClassMember(CBulletData_EffectBullet, "m_SourceY")
RegistClassMember(CBulletData_EffectBullet, "m_SourceZ")
RegistClassMember(CBulletData_EffectBullet, "m_TotalTime")
RegistClassMember(CBulletData_EffectBullet, "m_EffectBulletID")
RegistClassMember(CBulletData_EffectBullet, "m_RandomSeed")

CBulletData_BezierCircle = class()
RegistClassMember(CBulletData_BezierCircle, "m_NormalizedTime")
RegistClassMember(CBulletData_BezierCircle, "m_SplineIndex")
RegistClassMember(CBulletData_BezierCircle, "m_PointIndex")
RegistClassMember(CBulletData_BezierCircle, "m_TotalLength")
RegistClassMember(CBulletData_BezierCircle, "m_IsLoop")
RegistClassMember(CBulletData_BezierCircle, "m_IsForward")
RegistClassMember(CBulletData_BezierCircle, "m_Speed")
RegistClassMember(CBulletData_BezierCircle, "m_ZOffset")
RegistClassMember(CBulletData_BezierCircle, "m_RotX")
RegistClassMember(CBulletData_BezierCircle, "m_RotY")
RegistClassMember(CBulletData_BezierCircle, "m_RotZ")
RegistClassMember(CBulletData_BezierCircle, "m_JumpHeight")
RegistClassMember(CBulletData_BezierCircle, "m_JumpGravity")
RegistClassMember(CBulletData_BezierCircle, "m_JumpSpeed")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveX")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveY")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveDirX")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveDirY")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveSpeed")
RegistClassMember(CBulletData_BezierCircle, "m_LocalMoveRadius")
RegistClassMember(CBulletData_BezierCircle, "m_PhysicsGravity")
RegistClassMember(CBulletData_BezierCircle, "m_PhysicMinSpeed")
RegistClassMember(CBulletData_BezierCircle, "m_PhysicMaxSpeed")
RegistClassMember(CBulletData_BezierCircle, "m_BehaviorId")
RegistClassMember(CBulletData_BezierCircle, "m_BehaviorLastTime")
RegistClassMember(CBulletData_BezierCircle, "m_CalculatedCircle")
RegistClassMember(CBulletData_BezierCircle, "m_CirclePointX")
RegistClassMember(CBulletData_BezierCircle, "m_CirclePointY")
RegistClassMember(CBulletData_BezierCircle, "m_CirclePointZ")
RegistClassMember(CBulletData_BezierCircle, "m_CircleLoop") -- 圆环loop轨道
RegistClassMember(CBulletData_BezierCircle, "m_DirectionOnCircle") -- 圆环loop轨道上的运动方向 0-静止 1-顺时针 2-逆时针
RegistClassMember(CBulletData_BezierCircle, "m_SinOffSet")
RegistClassMember(CBulletData_BezierCircle, "m_Amplitude")
RegistClassMember(CBulletData_BezierCircle, "m_Frequency")
RegistClassMember(CBulletData_BezierCircle, "m_Phase")
RegistClassMember(CBulletData_BezierCircle, "m_CollisionRadius")
RegistClassMember(CBulletData_BezierCircle, "m_CollisionOffsetY")
RegistClassMember(CBulletData_BezierCircle, "m_IsSwing")
RegistClassMember(CBulletData_BezierCircle, "m_HasPathTransform")
RegistClassMember(CBulletData_BezierCircle, "m_PathOffsetX")
RegistClassMember(CBulletData_BezierCircle, "m_PathOffsetY")
RegistClassMember(CBulletData_BezierCircle, "m_PathOffsetZ")
RegistClassMember(CBulletData_BezierCircle, "m_PathYawOffset")
RegistClassMember(CBulletData_BezierCircle, "m_EasePeak")      -- 缓动最快位置：nil=匀速, 0=起点最快, 0.5=中间最快, 1=终点最快
RegistClassMember(CBulletData_BezierCircle, "m_EasePower")     -- 缓动强度：>= 1，默认2
RegistClassMember(CBulletData_BezierCircle, "m_TargetSpeed")       -- 目标速度(grid/ms)，nil=不渐变
RegistClassMember(CBulletData_BezierCircle, "m_SpeedAcceleration") -- 加速度(grid/ms²)，正=加速/负=减速
RegistClassMember(CBulletData_BezierCircle, "m_IsBungee")          -- 蹦极模式:速度由曲线高度驱动
RegistClassMember(CBulletData_BezierCircle, "m_IsPaused")

CBulletData_RepeatHitTarget = class()
RegistClassMember(CBulletData_RepeatHitTarget, "m_LeftTickTime")
RegistClassMember(CBulletData_RepeatHitTarget, "m_LastDDirXYLocalAbs")
RegistClassMember(CBulletData_RepeatHitTarget, "m_RandomSequence")
RegistClassMember(CBulletData_RepeatHitTarget, "m_RandomTime")
RegistClassMember(CBulletData_RepeatHitTarget, "m_BulletDir")
RegistClassMember(CBulletData_RepeatHitTarget, "m_SpeedMax")
RegistClassMember(CBulletData_RepeatHitTarget, "m_SpeedMin")
RegistClassMember(CBulletData_RepeatHitTarget, "m_Acceleration")
RegistClassMember(CBulletData_RepeatHitTarget, "m_AngleSpeed")

CForwardMoveSimulator = class()
RegistClassMember(CForwardMoveSimulator, "x")
RegistClassMember(CForwardMoveSimulator, "y")
RegistClassMember(CForwardMoveSimulator, "z")
RegistClassMember(CForwardMoveSimulator, "theta")
RegistClassMember(CForwardMoveSimulator, "v")
RegistClassMember(CForwardMoveSimulator, "omega")
RegistClassMember(CForwardMoveSimulator, "v_max")
RegistClassMember(CForwardMoveSimulator, "omega_max")
RegistClassMember(CForwardMoveSimulator, "a_max")
RegistClassMember(CForwardMoveSimulator, "alpha_max")
RegistClassMember(CForwardMoveSimulator, "stop_dis2")
RegistClassMember(CForwardMoveSimulator, "dt") -- useless
RegistClassMember(CForwardMoveSimulator, "last_ts")
RegistClassMember(CForwardMoveSimulator, "Kp")
RegistClassMember(CForwardMoveSimulator, "Kd")
RegistClassMember(CForwardMoveSimulator, "v_turn")

RegistClassMember(CForwardMoveSimulator, "v_z")
RegistClassMember(CForwardMoveSimulator, "v_z_end_ts")

CBulletData_ForwardChase2D = class()
RegistClassMember(CBulletData_ForwardChase2D, "m_Simulator", "CForwardMoveSimulator")
RegistClassMember(CBulletData_ForwardChase2D, "m_TargetEID")

CBulletData_BoatFrontMove2D = class()
RegistClassMember(CBulletData_BoatFrontMove2D, "m_StartX")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_StartY")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_StartDir")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_AngleSpeed")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_TotalTime")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_StartTime")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_StartRad")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_BulletRad")
RegistClassMember(CBulletData_BoatFrontMove2D, "m_LateChangeData")
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

BulletTrajectoryClassTb = {
	[EnumBulletTracjectory.Chase] = CBulletData_Chase,
	[EnumBulletTracjectory.HalfChase] = CBulletData_HalfChase,
	[EnumBulletTracjectory.Direction] = CBulletData_Direction,
	[EnumBulletTracjectory.Direction_Opt] = CBulletData_Direction,
	[EnumBulletTracjectory.Chase3D] = CBulletData_Chase3D,
	[EnumBulletTracjectory.Circle] = CBulletData_Circle,
	[EnumBulletTracjectory.BaFangJue] = CBulletData_BaFangJue,
	[EnumBulletTracjectory.ParabolaPos] = CBulletData_Parabola,
	[EnumBulletTracjectory.ParabolaExPos] = CBulletData_ParabolaEx,
	[EnumBulletTracjectory.Bezier] = CBulletData_Bezier,
	[EnumBulletTracjectory.Arc] = CBulletData_Arc,
	[EnumBulletTracjectory.TractionAndCircling] = CBulletData_TractionAndCircling,
	[EnumBulletTracjectory.EffectBullet] = CBulletData_EffectBullet,
	[EnumBulletTracjectory.BezierCircle] = CBulletData_BezierCircle,
	[EnumBulletTracjectory.RepeatHitTarget] = CBulletData_RepeatHitTarget,
	[EnumBulletTracjectory.ForwardChase2D] = CBulletData_ForwardChase2D,
	[EnumBulletTracjectory.BoatFrontMove2D] = CBulletData_BoatFrontMove2D,
}

BulletTrajectory2PublicObj = {
	[EnumBulletTracjectory.Chase] = CBulletData_Chase:new(),
	[EnumBulletTracjectory.HalfChase] = CBulletData_HalfChase:new(),
	[EnumBulletTracjectory.Direction] = CBulletData_Direction:new(),
	[EnumBulletTracjectory.Direction_Opt] = CBulletData_Direction:new(),
	[EnumBulletTracjectory.Chase3D] = CBulletData_Chase3D:new(),
	[EnumBulletTracjectory.Circle] = CBulletData_Circle:new(),
	[EnumBulletTracjectory.BaFangJue] = CBulletData_BaFangJue:new(),
	[EnumBulletTracjectory.ParabolaPos] = CBulletData_Parabola:new(),
	[EnumBulletTracjectory.ParabolaExPos] = CBulletData_ParabolaEx:new(),
	[EnumBulletTracjectory.Bezier] = CBulletData_Bezier:new(),
	[EnumBulletTracjectory.Arc] = CBulletData_Arc:new(),
	[EnumBulletTracjectory.TractionAndCircling] = CBulletData_TractionAndCircling:new(),
	[EnumBulletTracjectory.EffectBullet] = CBulletData_EffectBullet:new(),
	[EnumBulletTracjectory.BezierCircle] = CBulletData_BezierCircle:new(),
	[EnumBulletTracjectory.RepeatHitTarget] = CBulletData_RepeatHitTarget:new(),
	[EnumBulletTracjectory.ForwardChase2D] = CBulletData_ForwardChase2D:new(),
	[EnumBulletTracjectory.BoatFrontMove2D] = CBulletData_BoatFrontMove2D:new(),
}

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

CBulletMoveDataOpt = class()	--优化版本, 服务器去掉了元表
local function CopyAClassDeclare2BClass(aCls, bCls)
	for k in pairs(aCls.Declared or EMPTY_TABLE) do 
		if not bCls.Declared or not bCls.Declared[k] then 
			RegistClassMember(bCls, k)	
		end
	end
end
CopyAClassDeclare2BClass(CBulletData_Freq, CBulletMoveDataOpt)
CopyAClassDeclare2BClass(CBulletData_NoFreq, CBulletMoveDataOpt)
for k, v in pairs(BulletTrajectoryClassTb) do 
    CopyAClassDeclare2BClass(v, CBulletMoveDataOpt)
end

require "objects/character/BulletData"
