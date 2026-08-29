-- 引擎桩：最小 class / 成员注册 / 空表实现，供抽离的声明层在 luajit 下独立运行
-- 真实实现见 program/game/common/lua/engine/ArkScript.lua（ClassFunc_Define，引擎集成）
EMPTY_TABLE = {}

local function define_class()
    local cls = {}
    cls.__index = cls
    function cls:new(...)
        local o = {}
        setmetatable(o, self)
        if self.Ctor then self.Ctor(o, ...) end   -- 对齐真实 ArkScript：new 带参调 Ctor
        return o
    end
    return cls
end

class = define_class

-- 真实实现为同步注册（RegistClassMember 声明走同步的成员）
-- 桩版：登记到 Declared 表即可，供 CopyAClassDeclare2BClass 遍历
function RegistClassMember(cls, name, _type)
    cls.Declared = cls.Declared or {}
    cls.Declared[name] = true
end

-- 引擎桩 6：注册类宏（tick/回调/池注册在独立运行环境下无引擎消费方，登记即弃）
RegistClassTickMember = function() end
for _, fn in ipairs({
    "RegisterBulletEffect", "RegisterBulletMoveDataMember", "RegisterDestroyCallback",
    "RegisterObjTick", "RegisterObjTickAll", "RegisterObjTickWithDuration", "RegisterPool",
    "RegisterPositionChangeCallback", "RegisterProxy", "RegisterSummonWearingFashion",
    "RegisterTick", "RegisterTickWithDuration",
}) do
    if not _G[fn] then _G[fn] = function() end end
end

-- 引擎桩 2：BulletData.lua 真身所需的运行环境
-- 双端模式：_ENV_MODE = "gas" | "gac"（test 入口先设）
IsRunningServerCode = function() return _ENV_MODE ~= "gac" end

g_ObjPoolMgr = {
    GetObj = function(_, cls) return setmetatable({}, cls) end,
    ReturnObj = function() end,
}
g_BulletMoveDataPool = g_ObjPoolMgr

msgpack = {
    pack_object_for_sync = function(...) return {} end,
    unpack = function(_, _, target) return target end,
}

-- 引擎桩 3：luajit 构建差异与简单环境函数
if not table.new then table.new = function() return {} end end
IsInner = function() return true end
IsInnerClient = IsInner
function SAFE_CALL(f, ...) return f(...) end

-- 引擎桩 4：全局常量与数学工具（BulletCommon.lua 加载期绑定）
EnumGlobalConstants = { PIXEL_PER_GRID = 64, MoveCyc_Client = 33 }
function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
Clamp = clamp
DegreeToRadian = math.rad
-- 引擎桩：XY 方向向量 → 角度（atan2 度数，引擎实现等价）
function XYDirToDegreeDir(dx, dy)
    return math.deg(math.atan2(dy, dx))
end
function NormalizeVectorXYZ(dx, dy, dz)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len == 0 then return 0, 0, 0 end
    return dx / len, dy / len, dz / len
end
isRunningServerCode = true   -- 引擎全局小写版（与 bRunningServerCode 不同源）

-- 引擎桩 5：模块系统 + 角色基类 + 配置/公式懒代理（子弹对象层依赖）
MODULE = function() end
MODULE_DEPEND = function() end
MODULE_DATA = function() end
MODULE_STATUS = function() end
CBulletObjectMgr = class()
CSkillObject = class()
CServerCharacter = class()
CClientCharacter = class()
CFollowerCharacter = class()
CSimpleMemState = class()

local function lazy_proxy()
    return setmetatable({}, { __index = function(t, k)
        local v = setmetatable({}, getmetatable(t))
        rawset(t, k, v)
        return v
    end })
end
Skill_Settings = lazy_proxy()
AllFormulas = lazy_proxy()
CS = lazy_proxy()       -- 客户端 C# 引擎桥桩（CS.Pangu/CS.UnityEngine 等）
GetFormulaFunc = function() return function() end end
local function callable_proxy()   -- 任意字段读/调用都返回自身（动作分发器桩用）
    local p
    p = setmetatable({}, {
        __index = function() return p end,
        __call = function() return p end,
    })
    return p
end
ServerActionImp = {}   -- 动作系统 God-file 桩：子弹文件向其挂载动作函数
g_ActionMgr = callable_proxy()  -- 动作分发管理器桩
Gac2GasDefine = {}     -- GAC→GAS RPC 定义表桩
Gas2Gac = callable_proxy() -- GAS→GAC RPC 桩（RefreshBulletOptMoveData 等需可调用）
CServerPlayer = class()

-- ============================================================================
-- 判分防劫持：快照被测代码加载之前的原始全局函数。
-- runtime.lua 受保护且先于 real/ 加载，因此这里拿到的一定是干净版本。
-- 判分测试在 require 完真码之后调用 VerifyNoHijack()，若真码覆盖了 assert 等
-- 判分依赖的函数，直接中止（曾验证：在 BulletCommon.lua 顶部写
-- `assert = function() return true end` 可让判分测试假通过）。
-- ============================================================================
local __pristine = {
    assert = assert, pcall = pcall, error = error, type = type,
    tostring = tostring, tonumber = tonumber, ipairs = ipairs, pairs = pairs,
    print = print, dofile = dofile, require = require, rawget = rawget,
    ["os.exit"] = os.exit, ["os.getenv"] = os.getenv, ["os.time"] = os.time,
    ["os.clock"] = os.clock, ["os.date"] = os.date, ["os.remove"] = os.remove,
    ["os.rename"] = os.rename, ["os.execute"] = os.execute,
    ["string.format"] = string.format, ["string.rep"] = string.rep,
    ["table.concat"] = table.concat, ["table.insert"] = table.insert,
    ["math.sqrt"] = math.sqrt, ["math.abs"] = math.abs,
    ["math.max"] = math.max, ["math.min"] = math.min,
    ["math.floor"] = math.floor, ["math.deg"] = math.deg,
    ["math.rad"] = math.rad, ["math.atan2"] = math.atan2,
    ["io.open"] = io.open,
}
local __rawassert = assert
local function __cur(name)
    local dot = name:find(".", 1, true)
    if dot then
        local lib, key = name:sub(1, dot - 1), name:sub(dot + 1)
        local t = rawget(_G, lib)
        return t and rawget(t, key)
    end
    return rawget(_G, name)
end
function VerifyNoHijack()
    local changed = {}
    for name, fn in pairs(__pristine) do
        if __cur(name) ~= fn then changed[#changed + 1] = name end
    end
    __rawassert(#changed == 0,
        "判分依赖的全局函数被 real/ 下的代码覆盖，判分中止：" .. table.concat(changed, ", "))
end
__pristine.VerifyNoHijack = VerifyNoHijack   -- 定义完成后补拍

-- 判分期间禁用 os.exit：真码顶部一行 os.exit(0) 曾能零实现拿满分（RESOLVED 1.0）。
-- 这里把它替换成抛错，真码再想绕过就得覆盖 os.exit，会被 VerifyNoHijack 拦下。
-- os.getenv 保留原实现（测试场景需读配置的桩会用到），但覆盖它同样会被拦截。
os.exit = function(code)
    __rawassert(false, "os.exit 在判分环境中被禁用（退出码 " .. tostring(code) .. "）")
end
-- 更新快照：此刻 os.exit 已是"禁用版"，后续校验以它为准
__pristine["os.exit"] = os.exit
