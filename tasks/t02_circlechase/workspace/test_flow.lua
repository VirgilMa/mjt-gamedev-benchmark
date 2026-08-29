-- 里程碑 3：create→init→start→tick 真码流程打通测试
-- 驱动链：CServerBulletOpt:InitBullet(真实配置解析) → StartBulletTrajectoryMove(真实移动向量/最大距离)
--        → OnMoveTick → GetLuaNextMove → TrajectoryUpdateMap → UpdateAsDirection(真实逐帧步进)
--        → CheckCrossBuilding → OnBulletMove(真实命中查询/Z轴过滤路径)
_ENV_MODE = "gas"
package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")

-- 流程级引擎桩
EBarrierType = { eBT_MidBarrier = 0, eBT_HighBarrier = 1, eBT_OutRange = 2 }
LogCallContext_lua = function() end
PQERR = function() end
Bullet_Bullet_f = setmetatable({}, { __index = function() return nil end })
bddpairs = pairs
bddipairs = ipairs
IsClassObject = function() return false end
SafeUnRegisterTick = function() end
RegisterTickWithDuration = function() return "fake_tick" end
UnRegisterObjTick = function() end
RegisterObjTick = function() return "fake_tick" end
UnRegisterObjTickAll = function() end
flowchart = setmetatable({}, { __index = function() return function() end end })
g_App = { GetFrameTime = function() return 0 end, GetGlobalTime = function() return 0 end }
CServerFightableCharacter = class()
-- 引擎 tick 间隔表桩：轨迹→间隔(ms)，缺省 33
OPT_BULLET_MOVE_TICK_INTERVAL = setmetatable({}, { __index = function() return 33 end })
OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL = 33
GetGridByPixel2 = function(x, y, z) z = z or 0; return math.floor(x / 64), math.floor(y / 64), math.floor(z / 64) end

-- 角色基类桩（流程用到的成员）
function CServerCharacter.Init(self) end
function CServerCharacter:GetOwner() return self end
function CServerCharacter:GetTimeScale() return 1 end
function CServerCharacter:SetOwner(owner) self.m_Owner = owner end

-- 真码：轨迹 Imp + ServerCharacter 子弹片段
require("objects/BulletTrajectoryImp")
dofile("real/gas/objects/ServerCharacter_extract.lua")

-- 真码：子弹对象层全链（同 test_gas）
require("objects/bullet/CBulletObjectMgrInc")
require("objects/bullet/CSkillObjectInc")
require("objects/bullet/ServerBulletOptInc")
require("objects/bullet/ServerBulletInc")

-- 召唤技能走引擎流程，本环境桩掉
CServerBulletOpt.BeginOnSummonSkill = function() end
CServerBullet.BeginOnSummonSkill = function() end

-- 假场景（无障碍、无命中目标）与假 owner
local fakeCoreScene = {
    GetPixelLine = function() return {} end,
    GetBarrierv3 = function() return 0 end,
    QueryObjectsWithAngleInDirectionRectanglevt = function() return {} end,
}
local owner = CServerCharacter:new()
owner.m_engineObjectId = 42
owner.m_CharacterType = 1
owner.m_Scene = { m_CoreScene = fakeCoreScene }
function owner:IsBullet() return false end
local isProxy
isProxy = setmetatable({}, {
    __index = function() return isProxy end,
    __call = function() return isProxy end,
})
function owner:GetSyncAndSelfIS() return isProxy end
GetCharacterByEngineObjectGlobalId = function() return owner end

-- 假配置（Bullet_Bullet 表 + 行数据）
local designData = {
    ID = 900001,
    Speed = 2500,            -- 超 MAX_BULLET_AOI_HIT_SPEED(1910)
    NoAoiHit = nil,          -- BV-2: 缺配 → 真码应把速度静默 clamp 到 1910
    Trajectory = { "Direction", 18 },
    OnHitSkill = 0,
    HitZ = 0,
    AutoDestroy = -1,
    OnGroundMove = 0,
    DelayMoveTime = 0,
    LifeTime = 100,
    CrossBuilding = 0,
    MultiEyeSight = 5,
}
Bullet_Bullet = { [900001] = designData }

g_BulletObjectMgr = CBulletObjectMgr:new()
g_BulletObjectMgr:Ctor()
g_BulletObjectMgr:LoadZAboveBelow()   -- 真码：HitZ/HitZPair → ZAboveBelow 映射（BV-7 数据准备）

-- 创建 + Init（全真码）
local b = CServerBulletOpt:new()
b:Ctor()
b.m_Share.m_LiftTime = 100
assert(b:InitBullet(designData, 1, 100, 200, 0, 1, 0, 0, owner), "InitBullet 失败")

-- 验证 1: 轨迹被真实解析
assert(b.m_BulletMoveData.m_Trajectory == EnumBulletTracjectory.Direction,
    "轨迹解析失败: " .. tostring(b.m_BulletMoveData.m_Trajectory))

-- 验证 2: BV-2 真实现——NoAoiHit 缺配 → 速度静默 clamp 到 1910
assert(b.m_BulletMoveData.m_BulletSpeed == 1910,
    "BV-2 clamp 失败, 实际: " .. tostring(b.m_BulletMoveData.m_BulletSpeed))

-- 验证 3: 启动移动（Opt:StartBulletTrajectoryMove 包装无返回值，成功与否看移动向量）
b:StartBulletTrajectoryMove({})
assert(b.m_BulletMoveData.m_MoveVectorX ~= nil, "移动向量未计算")
assert(b.m_BulletMoveData.m_MaxDistance == 1152, "18 格最大距离应为 1152 像素")

-- 验证 4: per-tick 真移动
local startX = b.m_BulletMoveData.m_CurX
for i = 1, 100 do
    b:OnMoveTick(0.033)
end
local dist = math.abs(b.m_BulletMoveData.m_CurX - startX)
assert(dist > 6 and dist < 6.4, "100 tick 移动量异常: " .. tostring(dist))
print(("OK: create→init→start→tick 真码流程打通 — 移动 %.2f 像素, BV-2 速度 clamp 生效"):format(dist))
