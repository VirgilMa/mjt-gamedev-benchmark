-- 里程碑 2 (GAC)：真实客户端子弹对象层全流程加载测试
_ENV_MODE = "gac"
package.path = "./real/gac/?.lua;./real/common/?.lua;./stubs/?.lua;" .. package.path
dofile("runtime.lua")
require("objects/bullet/CBulletObjectMgrInc")
require("objects/bullet/CClientBulletInc")
require("objects/bullet/CClientBulletOptInc")
require("objects/bullet/CClientBulletTrajectoryImp")
require("objects/bullet/CClientBullet_Override")
print("OK: GAC 子弹对象层全链加载成功")
