# 任务：修复子弹飞行速度异常

## 现象

900002 号子弹的配置为 `Trajectory = "Direction, 30"`、`Speed = 800`。设计预期：子弹出膛后以 800 像素/秒匀速飞行，约 2.4 秒飞满 30 格（1920 像素）后停止。

**实际行为：子弹出膛后瞬间到达终点并停止。**

## 你的任务

找出根因，修改代码，使测试通过。

## 约束

- 只能修改 `real/` 目录下的代码
- 禁止修改 `stubs/`、`runtime.lua`（引擎环境桩，由 C++ 团队维护）与评测基础设施

## 判分

采用 SWE-bench 准则：`resolved = F2P 转绿 且 P2P 零回归`，二值 1.0 / 0.0。
F2P 是一道飞行行为测试，**不随题目分发**；断言内容不超出上面「现象」一节描述的设计预期
（800 像素/秒匀速、30 格 = 1920 像素、约 2.4 秒飞满）。评测测试不随题目分发。

## 环境说明

- `real/`：服务端（gas）子弹系统真码。`real/common/objects/character/BulletCommon.lua` 是轨迹移动数学所在
- `stubs/` + `runtime.lua`：C++ 引擎边界桩（引擎对象、场景查询、管理器等）
- 运行链：`CServerBulletOpt:InitBullet`（配置解析）→ `StartBulletTrajectoryMove`（启动）→ `OnMoveTick`（每帧）→ `GetLuaNextMove` → `UpdateAsDirection`（逐帧步进）
- 评测环境以固定 tick 驱动，模拟真实引擎运行
