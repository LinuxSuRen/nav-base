# Agibot D1 Max SDK（vendored）

## 来源

- 上游仓库：https://github.com/AgibotTech/Agibot_D1_Max
- 取用目录：`ubuntu22.04(x86_64_arm64)/RobotSDK-0.1.1/`（include + lib）
- vendor 日期：2026-03 · 本仓消费方：`src/agibot_bridge/`（CMake 直接引用，本目录非 colcon 包）

## ⚠ 版本强绑定（升级机器人前必读）

SDK 版本与机器人系统版本**不向后兼容**（上游 README 版本矩阵）。本 vendor 对应：

| SDK | 兼容的系统版本（V4 系） |
|---|---|
| 0.1.1 | 0.1.1-A / 0.1.3 / 0.1.4 / 0.1.5 / 0.1.6 / 0.1.7 / 0.1.8 / 0.1.9 / 0.2.0 / 0.2.1 |

**机器人 OTA 升级后**：先核对上游 README 矩阵 → 按需更新本目录（include + lib 全量替换）
→ 重新 colcon build → 实机回归（TakeControl/Move/急停/数据流四项）。

## 内容

```
include/robot_sdk/    5 个头文件（SDKClient / 回调 / 数据结构 / 连接配置）
lib/aarch64/          librobot_sdk.so（Orin NX = aarch64 用这组）
lib/x86_64/           librobot_sdk.so（开发机用）
```

## 关键事实（供 agibot_bridge 维护者）

- 传输：**UDP**（`SDKClient(ip, port, TransportProtocol::Udp)`，示例 `192.168.234.1:8081`）
- `MotionData.quat` 为 **[w,x,y,z]** 序（ROS geometry_msgs 是 x,y,z,w，桥内必须转换）
- 回调**只做拷贝**（SDK 文档要求：轻量回调，耗时操作放别的线程）
- `OnMcData` 50Hz 需先 `SetMcConfig(true)` 开启；`OnRobotStateData` 1Hz 主动上报
- 控制流：`TakeControl → SetMode(1=General) → StandUp` 前置，然后 `Move(lr, fb, yaw)`
- 急停：`SoftEmergencyStop(bool)`（可恢复）；`OnControlLost` 表示控制权丢失（需重新 TakeControl）
- 许可证：以上游仓库声明为准；二进制原样 vendor，未做任何修改
