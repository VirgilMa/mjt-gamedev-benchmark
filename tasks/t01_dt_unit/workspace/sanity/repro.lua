-- 【复现示例，不判分】造一颗 900002 子弹并逐帧驱动，打印每帧位置与累计飞行距离
-- 目的：让你直接看到"瞬间到达终点"的现象，并作为环境用法示例
-- 运行：luajit_rolling.exe sanity/repro.lua （在 workspace 根目录下运行）
_ENV_MODE = "gas"
package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")

-- ---- 引擎边界桩 ----
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

-- ---- 假场景 + 假 owner（owner 缺场景会让 CheckCrossBuilding 回退、子弹不动）----
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
GetCharacterByEngineObjectGlobalId = function() return owner end

-- ---- 被测配置：900002 号子弹（Direction 30 格、800 像素/秒）----
local designData = {
    ID = 900002, Speed = 800, NoAoiHit = nil,
    Trajectory = { "Direction", 30 },
    OnHitSkill = 0, HitZ = 0, AutoDestroy = -1, OnGroundMove = 0,
    DelayMoveTime = 0, LifeTime = 100, CrossBuilding = 0, MultiEyeSight = 5,
}
Bullet_Bullet = { [900002] = designData }

g_BulletObjectMgr = CBulletObjectMgr:new()
g_BulletObjectMgr:Ctor()
g_BulletObjectMgr:LoadZAboveBelow()

local b = CServerBulletOpt:new()
b:Ctor()
b.m_Share.m_LiftTime = 100
assert(b:InitBullet(designData, 1, 100, 200, 0, 1, 0, 0, owner), "InitBullet 失败")
b:StartBulletTrajectoryMove({})

local md = b.m_BulletMoveData
print(("配置解析：Speed=%s  MaxDistance=%s（30 格 × 64）")
    :format(tostring(md.m_BulletSpeed), tostring(md.m_MaxDistance)))
print("设计预期：800 像素/秒匀速，每帧 33ms 走 26.4 像素，约 73 帧飞满 1920 像素")
print("")
print("frame |    x    |  MoveDistance / MaxDistance")
for t = 1, 12 do
    b:OnMoveTick(33)
    print(("%5d | %7.1f | %8.1f / %s"):format(t, md.m_CurX, md.m_MoveDistance, tostring(md.m_MaxDistance)))
end
print("")
print("（修复前：第 1 帧就把 MoveDistance 走满并停住；修复后：每帧 +26.4 像素）")
