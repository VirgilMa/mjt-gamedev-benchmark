# 任务：实现 CircleChase 回环追踪轨迹

## 现象

配置为 `Trajectory = "CircleChase, 3000, 5, 2"` 的子弹完全不动：启动后停在原地，既不追踪目标也不飞行。

## 设计规格

CircleChase 是**回环追踪**轨迹：子弹向目标俯冲，进入外圈半径 r1 后逐步转向减速，进入内圈半径 r2 后盘旋收拢，并在总时间 totalTime 内收敛命中目标。轨迹参数 `(totalTime, r1, r2)` = `(3000ms, 5格, 2格)`。

判分测试严格按以下六条规格断言，实现前请逐条读完：

- **S1 速率守恒**　`Speed` 单位是像素/秒。每帧的**三维**位移严格等于 `Speed × dt / 1000`（dt 为毫秒）。Z 方向位移计入同一预算——不允许 XY 走满速率、Z 再额外白送。

- **S2 抵达节奏**　抵达时刻由 totalTime 决定，**不是"尽快命中"**。总速率恒为 Speed，其中**朝向目标的径向分量应随剩余时间自适应**：剩余距离要在剩余时间内走完。速率中未用于靠近的部分转为绕目标的切向分量——这正是"回环"的来源。因此在总时间耗尽前，子弹应在环内绕行，**不应提前撞上目标**。

- **S3 超时行为**　总时间耗尽（leftTime ≤ 0）后全速直冲目标，且**仍持续追踪**：目标此时移动（哪怕移到子弹正后方）也要掉头逼近，不能沿旧朝向直线飞走。

- **S4 转向限速**　朝向不能瞬间对准目标。转向角速度上限 = `Speed`（度/秒）；在环带内（r2 < d ≤ r1）降为 `Speed / 6`，转得更慢即绕出更大的弧。

- **S5 无目标**　目标不存在时沿当前朝向直线飞行。**不带目标也必须启动成功**（启动函数所在分支须返回 `true`，返回 false 会让上层销毁子弹）；逐帧更新须在目标判空之后再读时间字段，否则会因 nil 崩服。

- **S6 双端一致**　服务端与客户端跑的是同一份 `common/` 移动代码，同样的输入必须产出逐帧完全一致的三维坐标。

> **环境说明**：本环境**没有命中判定**（子弹配置 `NoAoiHit = 1`，场景的目标查询返回空）。
> 子弹靠近甚至穿过目标都不会触发命中、不会停止、不会销毁——你的逐帧更新应当始终按同样规则继续飞行。
> 换言之 S1 的「每帧位移严格等于 `Speed × dt / 1000`」在整个生命周期内无条件成立，不存在「抵达后停下」这种状态。

## 你的任务

在 `real/` 目录下**实现缺失的 CircleChase 轨迹路径**。缺失的部分（都被删除了，需要你补上）：

1. `real/gas/objects/BulletTrajectoryImp.lua` 的 `_StartBulletTrajectoryMove` 中 CircleChase 的启动分派分支（调用 StartCircleChaseMove）
2. `BulletTrajectoryImp:StartCircleChaseMove` 启动函数（解析轨迹参数、记录目标与起始时刻、启动逐帧移动）
3. `real/common/objects/character/BulletCommon.lua` 的 `CBulletTrackMgr:UpdateCircleChase` 逐帧更新函数（回环追踪的移动数学）
4. `BulletCommon.lua` 的 `TrajectoryUpdateMap` 分发表中 CircleChase 的条目（注册你的 update 函数）

## 已就绪的设施（不要重复造）

- 轨迹枚举 `EnumBulletTracjectory.CircleChase` 已存在（BulletCommonInc.lua）
- 数据类 `CBulletData_CircleChase` 已声明（BulletDataInc.lua），成员：`m_StartTime`（起始时刻）、`m_TotalTime`（总时间 ms）、`m_Radius1`/`m_Radius2`（外圈/内圈半径，**配置单位是格，需 ×64 转像素**）
- 目标对象：`m_TargeterEngineObjectId` 记录目标引擎 ID；`EID2OBJ(id)` 按 ID 取目标（取不到返回 nil）；目标位置用 `target.m_engineObject:GetPixelPosv3()` 读取（返回 x,y,z）
- 时间：`GetGlobalTime_ms()` 取全局毫秒时钟
- 朝向：`bullet:GetFaceDirection()` 取当前朝向角（度，0°=+X）；`NormalizeAngle(deg)` 把角度归一到 (-180, 180]
- 参考同文件里兄弟轨迹的实现（如 `UpdateAsChase`/`StartChaseTarget`、`UpdateRepeatHitTarget`/`StartRepeatHitTarget`）——你的实现风格应与它们一致
- ⚠️ 这些兄弟轨迹是**共享真码**：你实现 CircleChase 时不能改坏它们；评测会检查既有轨迹不回归

## 约束

- 只能修改 `real/` 目录下的代码
- 禁止修改 `stubs/`、`runtime.lua`（引擎环境桩）与评测基础设施

## 判分

采用 SWE-bench 准则：`resolved = 全部 F2P 转绿 且 全部 P2P 零回归`，二值 1.0 / 0.0。

- **F2P**（修复验证）：两道 CircleChase 行为测试，**不随题目分发**，判分时由出题人按绝对路径调用
- **P2P**（回归检查）：评测环境中的既有轨迹检查，任一变红直接 0 分

F2P 测试只断言**本文件描述过的行为**——设计规格首段（回环形状、总时间内收敛命中）、S1–S6 六条、
环境说明，以及「已就绪的设施」一节列出的字段名与单位换算。
不断言实现细节：函数内部结构、变量命名、中间量、绕行方向、瞄准点偏移都由你自由决定。
