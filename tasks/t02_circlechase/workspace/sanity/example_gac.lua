-- 【用法示例，不判分】客户端：与 example_gas.lua 完全同场景，逐帧驱动 60 帧并打印位置
-- 两端跑的是同一份 common/ 移动代码，同输入应当逐帧同输出——对比两边的打印即可自查 S6
-- 运行：luajit_rolling.exe sanity/example_gac.lua （在 workspace 根目录下运行）
_ENV_MODE = "gac"
package.path = "./real/gac/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")

-- ---- 引擎边界桩 ----
EBarrierType = { eBT_MidBarrier = 0, eBT_HighBarrier = 1, eBT_OutRange = 2 }
LogCallContext_lua = function() end
PQERR = function() end
Bullet_Bullet_f = setmetatable({}, { __index = function() return nil end })
Bullet_Appear = {}
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
OPT_BULLET_MOVE_TICK_INTERVAL = setmetatable({}, { __index = function() return 33 end })
OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL = 33
OPT_BULLET_AI_LOAD_RETRY_COUNT = 0
GetGridByPixel2 = function(x, y, z) z = z or 0; return math.floor(x / 64), math.floor(y / 64), math.floor(z / 64) end

g_ClientOptimizeMgr = { IsNeedCreateBullet = function() return true end }
g_ClientEffectMgr = {}
CS.Pangu.AppFacade.gameManager = { GetTargetFrameRate = function() return 30 end }
GetProcessTime = function() return 0 end
g_SceneLoaded = nil

function CClientCharacter.Init(self) end
function CClientCharacter:GetOwner() return self end
function CClientCharacter:GetTimeScale() return 1 end
function CClientCharacter:SetOwner(owner) self.m_Owner = owner end

require("objects/bullet/CBulletObjectMgrInc")
require("objects/bullet/CClientBulletInc")
require("objects/bullet/CClientBulletOptInc")
require("objects/bullet/CClientBulletTrajectoryImp")
require("objects/bullet/CClientBullet_Override")

CClientBulletOpt.InitClientAI = function() end
CClientBulletOpt.LoadClientAI = function() end
-- SetBulletRotation 真码第 1 行（移动语义：更新朝向角），渲染分支桩掉
CClientBulletOpt.SetBulletRotation = function(self, dx, dy, dz)
    self.m_Degree = XYDirToDegreeDir(dx, dz)
end
CClientBulletOpt.InitRenderObject = function() end
CClientBulletOpt.OnFlowchartEvent = function() end

g_BulletObjectMgr = CBulletObjectMgr:new()
g_BulletObjectMgr:Ctor()

-- ---- 假目标：与服务端示例同一条路径 ----
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
local function resolveObj(id) if id == nil then return nil end return g_FakeTarget end
EID2OBJ = resolveObj
GetCharacterByEngineObjectGlobalId = resolveObj

g_TimeMs = 0
GetGlobalTime_ms = function() return g_TimeMs end

Bullet_Bullet = { [940001] = { ID = 940001, Speed = 600, Trajectory = { "CircleChase", 3000, 5, 2 } } }

-- ---- 客户端不跑启动函数：移动数据由服务端解析后经同步通道送达，这里手工摆出同步现场 ----
-- 注意：判分时客户端拿到的是服务端启动后的**完整状态快照**（真实 RefreshBulletOptMoveData 行为），
--       所以你若在启动函数里注册了新的同步字段，判分环境会一并送达，本示例则不会。
local b = CClientBulletOpt:new()
b:Ctor()
local md = CBulletMoveDataOpt:new()
md.m_BulletDataId = 940001
md.m_BulletSpeed = 600
md.m_CurX, md.m_CurY, md.m_CurZ = 100, 100, 0
md.m_Trajectory = EnumBulletTracjectory.CircleChase
md.m_TrajectoryArgs = { 3000, 5, 2 }
md.m_TotalTime = 3000
md.m_Radius1 = 5 * 64
md.m_Radius2 = 2 * 64
md.m_TargeterEngineObjectId = 83
md.m_StartTime = 0
md.m_MoveDistance = 0
b.m_BulletMoveData = md
b.m_Degree = 0   -- 朝向 0°（+X），与服务端 dir(1,0) 一致
b:Init(1, 0, 0, 0, 100)
b:StartLuaMove()

-- ---- 逐帧驱动：OnMoveTick + 朝向刷新（引擎核循环 AfterGacCoreUpdate 的移动语义部分）----
print("frame |    bullet x,y,z     |   target x,y,z   |  step3d | dist")
local px, py, pz = md.m_CurX, md.m_CurY, md.m_CurZ
for t = 1, 60 do
    advanceTarget()
    g_TimeMs = g_TimeMs + 33
    b:OnMoveTick(33)
    b:SetBulletRotation(md.m_CurX - b.m_OldX, md.m_CurZ - b.m_OldZ, md.m_CurY - b.m_OldY)
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
print("（每一行应与 example_gas.lua 的同帧输出完全一致——这就是 S6 双端一致）")
