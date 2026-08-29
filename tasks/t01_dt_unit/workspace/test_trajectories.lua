-- 环境自检（P2P）：轨迹更新函数完整性 + 邻近轨迹未被改坏
--
-- 存在意义：其余 P2P（test_m1/gas/gac/flow）只覆盖 Direction 一条轨迹，
-- 把 UpdateAsChase 改成空操作它们全绿——即「实现了本题轨迹但顺手改坏了别的」
-- 不会被扣分。题面又明确让 agent 去参考 UpdateAsChase / UpdateRepeatHitTarget，
-- 这两条正是最容易被误改的。本测试补上这个网。
--
-- 覆盖上限（诚实说明）：只验 18 个 update 函数存在 + 两条邻近轨迹「确实会动」。
-- 细微数学改动（如系数微调）不在覆盖范围内。
_ENV_MODE = "gas"
package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")

-- 防劫持守卫的本地引用：真码可以覆盖全局 VerifyNoHijack，但覆盖不了这个 local 引用
local __verifyNoHijack = VerifyNoHijack

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
OPT_BULLET_MOVE_TICK_INTERVAL = setmetatable({}, { __index = function() return 33 end })
OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL = 33
GetGridByPixel2 = function(x, y, z) z = z or 0; return math.floor(x / 64), math.floor(y / 64), math.floor(z / 64) end
-- 两点距离（名字里的 2 指「两个点」不是平方）：真码用 Dist_XYZ2(...)/speed 换算时间，故返回距离本身
Dist_XY2 = function(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end
Dist_XYZ2 = function(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
IsNanOrInf = function(v)
    return v ~= v or v == math.huge or v == -math.huge
end

function CServerCharacter.Init(self) end
function CServerCharacter:GetOwner() return self end
function CServerCharacter:GetTimeScale() return 1 end
function CServerCharacter:SetOwner(owner) self.m_Owner = owner end

require("objects/BulletTrajectoryImp")
dofile("real/gas/objects/ServerCharacter_extract.lua")
require("objects/bullet/CBulletObjectMgrInc")
require("objects/bullet/CSkillObjectInc")
require("objects/bullet/ServerBulletOptInc")
require("objects/bullet/ServerBulletInc")
CServerBulletOpt.BeginOnSummonSkill = function() end
CServerBullet.BeginOnSummonSkill = function() end

-- 防劫持：本测试的职责就是抓破坏，自身必须先确认判分函数没被覆盖
__verifyNoHijack()

-- ===== P1：轨迹更新函数完整性 =====
-- 分发表 TrajectoryUpdateMap 是 BulletCommon.lua 里的 local，外部取不到；
-- 退而验证它引用的那些 CBulletTrackMgr 方法都还在（被删/改名会在这里暴露）。
local REQUIRED = {
    "UpdateRepeatHitTarget", "UpdateBezierCircle", "UpdateAsEffectBullet",
    "UpdateAsBezierPos", "UpdateAsBezierPos_NoStop", "UpdateAsArc",
    "UpdateAsTractionAndCircling", "UpdateBoatFrontMove2D", "UpdateAsParabolaExPos",
    "UpdateAsParabolaPos", "UpdateAsChase", "UpdateAsHalfChase", "UpdateAsCircle",
    "UpdateAsBaFangJue", "UpdateAsDirection", "UpdateAsChase3D", "UpdateAsCustom",
    "UpdateAsForwardChase2D",
}
local missing = {}
for _, name in ipairs(REQUIRED) do
    if type(CBulletTrackMgr[name]) ~= "function" then
        missing[#missing + 1] = name
    end
end
assert(#missing == 0,
    "轨迹更新函数缺失（被删除或改名）：" .. table.concat(missing, ", "))

-- ===== P2：邻近轨迹确实会动（防止被改成空操作） =====
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
isProxy = setmetatable({}, { __index = function() return isProxy end, __call = function() return isProxy end })
function owner:GetSyncAndSelfIS() return isProxy end
owner.m_engineObject = { GetPixelPosv3 = function() return 100, 100, 0 end }

local tgt
tgt = { m_engineObject = { GetPixelPosv3 = function() return 1400, 700, 0 end } }
local function resolveObj(id)
    if id == nil then return nil end
    if id == owner.m_engineObjectId then return owner end
    return tgt
end
EID2OBJ = resolveObj
GetCharacterByEngineObjectGlobalId = resolveObj
g_TimeMs = 0
GetGlobalTime_ms = function() return g_TimeMs end

g_BulletObjectMgr = CBulletObjectMgr:new()
g_BulletObjectMgr:Ctor()

local function runTrajectory(id, trajectory, moveArgs)
    local designData = {
        ID = id, Speed = 600, NoAoiHit = 1, Trajectory = trajectory,
        OnHitSkill = 0, HitZ = 0, AutoDestroy = -1, OnGroundMove = 0,
        DelayMoveTime = 0, LifeTime = 300, CrossBuilding = 0, MultiEyeSight = 5,
    }
    Bullet_Bullet = { [id] = designData }
    g_BulletObjectMgr:LoadZAboveBelow()
    local b = CServerBulletOpt:new()
    b:Ctor()
    b.m_Share.m_LiftTime = 100
    assert(b:InitBullet(designData, 1, 100, 100, 0, 1, 0, 0, owner),
        ("InitBullet 失败：%s"):format(trajectory[1]))
    b:StartBulletTrajectoryMove(moveArgs or {})
    local md = b.m_BulletMoveData
    local x0, y0, z0 = md.m_CurX, md.m_CurY, md.m_CurZ
    for _ = 1, 10 do
        g_TimeMs = g_TimeMs + 33
        b:OnMoveTick(33)
    end
    local dx, dy, dz = md.m_CurX - x0, md.m_CurY - y0, md.m_CurZ - z0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Direction：题面之外的基准轨迹，10 帧应飞约 198 像素
local movedDir = runTrajectory(970001, { "Direction", 30 })
assert(movedDir > 150,
    ("Direction 轨迹被改坏：10 帧只移动了 %.1f 像素（应约 198）"):format(movedDir))

-- Chase：题面明确让 agent 参考 UpdateAsChase，最容易被误改
local movedChase = runTrajectory(970002, { "Chase" }, { TargetId = 83 })
assert(movedChase > 150,
    ("Chase 轨迹被改坏：10 帧只移动了 %.1f 像素（应约 198）"):format(movedChase))

print(("OK: 轨迹更新函数 %d 个齐备，Direction/Chase 均正常移动（%.1f / %.1f 像素）")
    :format(#REQUIRED, movedDir, movedChase))
