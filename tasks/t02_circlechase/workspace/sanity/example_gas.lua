-- 【用法示例，不判分】服务端：造一颗 CircleChase 子弹并逐帧驱动 60 帧，打印位置
-- 目的是让你看清这套环境怎么用（建对象 → 初始化 → 启动 → OnMoveTick），不含任何判分阈值
-- 运行：luajit_rolling.exe sanity/example_gas.lua （在 workspace 根目录下运行）
_ENV_MODE = "gas"
package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")

-- ---- 引擎边界桩（与判分测试同款，照抄即可） ----
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
owner.m_engineObject = { GetPixelPosv3 = function() return 100, 100, 0 end }

-- ---- 假目标：斜向匀速移动，位于 Z=400 高处 ----
local g_Tick = 0
local g_FakeTarget
g_FakeTarget = {
    x = 1200, y = 100, z = 400,
    m_engineObject = { GetPixelPosv3 = function() return g_FakeTarget.x, g_FakeTarget.y, g_FakeTarget.z end },
}
local function advanceTarget()
    g_Tick = g_Tick + 1
    g_FakeTarget.x, g_FakeTarget.y = 1200 + 2 * g_Tick, 100 + g_Tick
end
-- 两个目标解析 API 在真实引擎里指向同一对象，桩必须一致
local function resolveObj(id)
    if id == nil then return nil end
    if id == owner.m_engineObjectId then return owner end
    return g_FakeTarget
end
EID2OBJ = resolveObj
GetCharacterByEngineObjectGlobalId = resolveObj

-- ---- 可控时钟 ----
g_TimeMs = 0
GetGlobalTime_ms = function() return g_TimeMs end

g_BulletObjectMgr = CBulletObjectMgr:new()
g_BulletObjectMgr:Ctor()

-- ---- 造子弹：Trajectory = CircleChase, 总时间 3000ms, r1=5格, r2=2格 ----
local designData = {
    ID = 940001, Speed = 600, NoAoiHit = 1,
    Trajectory = { "CircleChase", 3000, 5, 2 },
    OnHitSkill = 0, HitZ = 0, AutoDestroy = -1, OnGroundMove = 0,
    DelayMoveTime = 0, LifeTime = 300, CrossBuilding = 0, MultiEyeSight = 5,
}
Bullet_Bullet = { [940001] = designData }
g_BulletObjectMgr:LoadZAboveBelow()

local b = CServerBulletOpt:new()
b:Ctor()
b.m_Share.m_LiftTime = 100
assert(b:InitBullet(designData, 1, 100, 100, 0, 1, 0, 0, owner), "InitBullet 失败")
b:StartBulletTrajectoryMove({ TargetId = 83 })
-- S5 关心的是分派函数的返回值（false 会让上层销毁子弹），单独验一下：
local started = BulletTrajectoryImp:_StartBulletTrajectoryMove(b, { TargetId = 83 })
print(("_StartBulletTrajectoryMove 返回：%s（须为 true）"):format(tostring(started)))

local md = b.m_BulletMoveData
print(("启动后：m_TotalTime=%s  m_Radius1=%s  m_Radius2=%s  m_TargeterEngineObjectId=%s  m_StartTime=%s")
    :format(tostring(md.m_TotalTime), tostring(md.m_Radius1), tostring(md.m_Radius2),
        tostring(md.m_TargeterEngineObjectId), tostring(md.m_StartTime)))

-- ---- 逐帧驱动（33ms/帧，等价于真实引擎的 MoveTick）----
print("frame |    bullet x,y,z     |   target x,y,z   |  step3d | dist")
local px, py, pz = md.m_CurX, md.m_CurY, md.m_CurZ
for t = 1, 60 do
    advanceTarget()
    g_TimeMs = g_TimeMs + 33
    b:OnMoveTick(33)
    local dx, dy, dz = md.m_CurX - px, md.m_CurY - py, md.m_CurZ - pz
    local step3d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local tdx, tdy, tdz = g_FakeTarget.x - md.m_CurX, g_FakeTarget.y - md.m_CurY, g_FakeTarget.z - md.m_CurZ
    local dist = math.sqrt(tdx * tdx + tdy * tdy + tdz * tdz)
    if t <= 5 or t % 5 == 0 then
        print(("%5d | %6.1f %6.1f %6.1f | %5d %5d %5d | %7.2f | %6.1f")
            :format(t, md.m_CurX, md.m_CurY, md.m_CurZ,
                g_FakeTarget.x, g_FakeTarget.y, g_FakeTarget.z, step3d, dist))
    end
    px, py, pz = md.m_CurX, md.m_CurY, md.m_CurZ
end
print("（未实现时位置恒定不动；实现后应看到子弹绕向目标）")
