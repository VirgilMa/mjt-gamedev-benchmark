-- Deterministic CircleChase trajectory runner.
-- Usage: lua trajectory_runner.lua <server|client> <static|moving> [outer] [inner] [frames]

local side = arg[1] or "server"
local targetMode = arg[2] or "moving"
local radiusOuter = tonumber(arg[3]) or 5
local radiusInner = tonumber(arg[4]) or 2
local frames = tonumber(arg[5]) or 600

assert(side == "server" or side == "client", "side must be server or client")
assert(targetMode == "static" or targetMode == "moving", "target mode must be static or moving")

local DT = 33
local SPEED = 600
local TOTAL_TIME = 3000
local START_X, START_Y = 100, 100
local CLIENT_TARGET_DELAY_FRAMES = 4

local function targetPosition(frame)
    if targetMode == "moving" then
        return 1200 + 2 * frame, 100 + frame
    end
    return 1200, 100
end

local function printPoint(frame, x, y, targetX, targetY, observedX, observedY)
    print(("%d,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f"):format(
        frame, frame * DT, x, y, targetX, targetY, observedX, observedY))
end

if side == "server" then
    _ENV_MODE = "gas"
    package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
    dofile("runtime.lua")

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
    OPT_BULLET_MOVE_TICK_INTERVAL = setmetatable({}, { __index = function() return DT end })
    OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL = DT
    GetGridByPixel2 = function(x, y, z)
        z = z or 0
        return math.floor(x / 64), math.floor(y / 64), math.floor(z / 64)
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
    owner.m_engineObject = { GetPixelPosv3 = function() return START_X, START_Y, 0 end }

    local target = { x = targetPosition(0), y = select(2, targetPosition(0)), z = 0 }
    target.m_engineObject = {
        GetPixelPosv3 = function() return target.x, target.y, target.z end,
    }
    local function resolveObject(id)
        if id == nil then return nil end
        if id == owner.m_engineObjectId then return owner end
        return target
    end
    EID2OBJ = resolveObject
    GetCharacterByEngineObjectGlobalId = resolveObject

    g_TimeMs = 0
    GetGlobalTime_ms = function() return g_TimeMs end
    g_BulletObjectMgr = CBulletObjectMgr:new()
    g_BulletObjectMgr:Ctor()

    local bulletId = 980001
    local designData = {
        ID = bulletId,
        Speed = SPEED,
        NoAoiHit = 1,
        Trajectory = { "CircleChase", TOTAL_TIME, radiusOuter, radiusInner },
        OnHitSkill = 0,
        HitZ = 0,
        AutoDestroy = -1,
        OnGroundMove = 0,
        DelayMoveTime = 0,
        LifeTime = 1000,
        CrossBuilding = 0,
        MultiEyeSight = 5,
    }
    Bullet_Bullet = { [bulletId] = designData }
    g_BulletObjectMgr:LoadZAboveBelow()

    local bullet = CServerBulletOpt:new()
    bullet:Ctor()
    bullet.m_Share.m_LiftTime = 100
    assert(bullet:InitBullet(designData, 1, START_X, START_Y, 0, 1, 0, 0, owner))
    bullet:StartBulletTrajectoryMove({ TargetId = 83 })

    print("frame,time_ms,bullet_x,bullet_y,target_x,target_y,observed_target_x,observed_target_y")
    printPoint(0, START_X, START_Y, target.x, target.y, target.x, target.y)
    for frame = 1, frames do
        target.x, target.y = targetPosition(frame)
        g_TimeMs = g_TimeMs + DT
        bullet:OnMoveTick(DT)
        local moveData = bullet.m_BulletMoveData
        printPoint(frame, moveData.m_CurX, moveData.m_CurY,
            target.x, target.y, target.x, target.y)
    end
else
    _ENV_MODE = "gac"
    package.path = "./real/gac/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
    dofile("runtime.lua")

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
    OPT_BULLET_MOVE_TICK_INTERVAL = setmetatable({}, { __index = function() return DT end })
    OPT_BULLET_MOVE_TICK_DEFAULT_INTERVAL = DT
    OPT_BULLET_AI_LOAD_RETRY_COUNT = 0
    GetGridByPixel2 = function(x, y, z)
        z = z or 0
        return math.floor(x / 64), math.floor(y / 64), math.floor(z / 64)
    end

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
    CClientBulletOpt.SetBulletRotation = function(self, dx, dy, dz)
        self.m_Degree = XYDirToDegreeDir(dx, dz)
    end
    CClientBulletOpt.InitRenderObject = function() end
    CClientBulletOpt.OnFlowchartEvent = function() end

    g_BulletObjectMgr = CBulletObjectMgr:new()
    g_BulletObjectMgr:Ctor()

    local target = { x = targetPosition(0), y = select(2, targetPosition(0)), z = 0 }
    local observed = { x = target.x, y = target.y, z = 0 }
    target.m_engineObject = {
        GetPixelPosv3 = function() return observed.x, observed.y, observed.z end,
    }
    local function resolveObject(id)
        if id == nil then return nil end
        return target
    end
    EID2OBJ = resolveObject
    GetCharacterByEngineObjectGlobalId = resolveObject

    g_TimeMs = 0
    GetGlobalTime_ms = function() return g_TimeMs end

    local bulletId = 980001
    Bullet_Bullet = {
        [bulletId] = {
            ID = bulletId,
            Speed = SPEED,
            Trajectory = { "CircleChase", TOTAL_TIME, radiusOuter, radiusInner },
        },
    }

    local bullet = CClientBulletOpt:new()
    bullet:Ctor()
    local moveData = CBulletMoveDataOpt:new()
    moveData.m_BulletDataId = bulletId
    moveData.m_BulletSpeed = SPEED
    moveData.m_CurX, moveData.m_CurY, moveData.m_CurZ = START_X, START_Y, 0
    moveData.m_Trajectory = EnumBulletTracjectory.CircleChase
    moveData.m_TrajectoryArgs = { TOTAL_TIME, radiusOuter, radiusInner }
    moveData.m_TotalTime = TOTAL_TIME
    moveData.m_Radius1 = radiusOuter * 64
    moveData.m_Radius2 = radiusInner * 64
    moveData.m_TargeterEngineObjectId = 83
    moveData.m_StartTime = 0
    moveData.m_MoveDistance = 0
    bullet.m_BulletMoveData = moveData
    bullet.m_Degree = 0
    bullet:Init(1, 0, 0, 0, START_X)
    bullet:StartLuaMove()

    print("frame,time_ms,bullet_x,bullet_y,target_x,target_y,observed_target_x,observed_target_y")
    printPoint(0, START_X, START_Y, target.x, target.y, observed.x, observed.y)
    for frame = 1, frames do
        target.x, target.y = targetPosition(frame)
        observed.x, observed.y = targetPosition(math.max(0, frame - CLIENT_TARGET_DELAY_FRAMES))
        g_TimeMs = g_TimeMs + DT
        bullet:OnMoveTick(DT)
        local diffX = moveData.m_CurX - bullet.m_OldX
        local diffY = moveData.m_CurY - bullet.m_OldY
        local diffZ = moveData.m_CurZ - bullet.m_OldZ
        bullet:SetBulletRotation(diffX, diffZ, diffY)
        printPoint(frame, moveData.m_CurX, moveData.m_CurY,
            target.x, target.y, observed.x, observed.y)
    end
end
