-- 里程碑 1：真实声明层（BulletCommonInc + BulletDataInc）在 luajit 下独立加载、实例化
package.path = "./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")
require("objects/character/BulletCommonInc")  -- 内部 require 链: BulletDataInc(真) → BulletData(桩)

-- 验证 1：轨迹类可实例化、本类成员可读写
local b = CBulletData_Direction:new()
b.m_MaxDistance = 18
b.m_MoveDistance = 0
b.m_MoveVectorX = 0.5
assert(b.m_MaxDistance == 18, "m_MaxDistance 读写失败")
assert(b.m_MoveDistance == 0, "m_MoveDistance 读写失败")

-- 验证 2：轨迹映射表完整（18 种轨迹 + 公共对象实例）
assert(BulletTrajectoryClassTb[EnumBulletTracjectory.Direction] == CBulletData_Direction,
    "Direction 映射错误")
assert(BulletTrajectoryClassTb[EnumBulletTracjectory.ParabolaPos] ~= nil,
    "ParabolaPos 映射缺失")
-- 注意：服务端映射表无 BezierCurvePos/BezierCurveTarget（12/13 号走客户端侧实现）
assert(BulletTrajectoryClassTb[EnumBulletTracjectory.BezierCurveTarget] == nil,
    "BezierCurveTarget 不应出现在服务端映射表")
assert(BulletTrajectory2PublicObj[EnumBulletTracjectory.ParabolaPos] ~= nil,
    "公共对象未实例化")

local n = 0
for _ in pairs(BulletTrajectoryClassTb) do n = n + 1 end
print(("OK: 声明层独立运行成功 — %d 种轨迹已注册, Direction 实例化/成员读写正常"):format(n))

-- 验证 3：BV-3 需目标白名单（真实数据）
assert(EnumBulletTracjectoryNeedTarget[EnumBulletTracjectory.Missile] == true, "Missile 应需目标")
assert(EnumBulletTracjectoryNeedTarget[EnumBulletTracjectory.BezierCurveTarget] == true, "BezierCurveTarget 应需目标")
assert(not EnumBulletTracjectoryNeedTarget[EnumBulletTracjectory.Direction], "Direction 不应需目标")
local nneed = 0
for _ in pairs(EnumBulletTracjectoryNeedTarget) do nneed = nneed + 1 end
print(("OK: 需目标白名单 %d 种轨迹"):format(nneed))

-- 验证 4：真实 init 层可运行——CBulletMoveData 池化构造（真 Ctor 链）
local md = CBulletMoveData:new()
assert(md ~= nil, "CBulletMoveData:new 失败")
assert(md.m_Data_Freq ~= nil and md.m_Data_NoFreq ~= nil,
    "Ctor 链未正确初始化 Freq/NoFreq 数据段")
-- m_Data_Spec 在服务端为 nil 属正常（轨迹数据到达时才填充）
assert(md.m_Data_Spec == nil, "新鲜实例不应有 Spec 段")

-- 验证 5：真实 mt.__index/__newindex 成员路由——m_CurX 是 Freq 段成员(kind=2)
md.m_CurX = 5
assert(md.m_Data_Freq.m_CurX == 5, "__newindex 未路由到 Freq 段")
assert(md.m_CurX == 5, "__index 未从 Freq 段读回")
print("OK: CBulletMoveData 真实 Ctor 链 + mt 成员路由运行成功")
