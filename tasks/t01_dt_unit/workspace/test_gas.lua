-- 里程碑 2 (GAS)：真实子弹对象层全流程加载测试
_ENV_MODE = "gas"
package.path = "./real/gas/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")
require("objects/bullet/CBulletObjectMgrInc")
require("objects/bullet/CSkillObjectInc")
require("objects/bullet/ServerBulletOptInc")
require("objects/bullet/ServerBulletInc")
print("OK: GAS 子弹对象层全链加载成功")
