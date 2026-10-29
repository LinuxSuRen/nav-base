# genisom RobotSDK（vendored）

## 来源

- 上游仓库：https://github.com/zsibot/genisom_robot_sdk（官方公开）
- 取用目录：镜像 `registry.cn-guangzhou.aliyuncs.com/z_nav/zs_control_sdk:1.4` 内
  `/RobotSDK-0.1.1`（**include + lib 全量**；GitHub 仓库的 lib/ 为空，预编译库只随镜像分发）
- vendor 日期：2026-10-28 · 本仓消费方：`src/genisom_motion/`（CMake 直接引用，
  本目录非 colcon 包）
- 版本：RobotSDK 0.1.1（与 M1 v0.3.1 系统配对，见上游 README 版本矩阵）

## 实测结论（2026-10-28，M1 192.168.168.168）

- **有线模式下 M1 的控制通道 = WebSocket `192.168.168.168:8081`**（Boost.Beast 服务端）。
  传输必须用 SDK 的 `TransportProtocol::WebSocket`——裸 TCP/UDP 全部握手失败
  （UDP 无响应；TCP 上裸 JSON/长度前缀帧被立即断连；手写 WebSocket 缺
  SDK 的自定义握手头同样被拒）。
- WiFi AP 模式（192.168.234.1:8082）走 UDP，本仓库未测。
- StandUp/LieDown 经 WebSocket 通道实测通过（机器人回执 OnStandUp/OnLieDown）。

## 与上游的差异

- 仅删除 `example/`、`docs/`（体积），源码与二进制零修改。

## 内容

```
include/robot_sdk/   SDK 头文件（sdk_client/sdk_callback/sdk_connection/sdk_error/sdk_export/sdk_type）
lib/x86_64/          librobot_sdk.so（x86_64 部署用）
lib/aarch64/         librobot_sdk.so（Orin NX 部署用）
```

## ⚠ 版本强绑定

SDK 版本与机器人系统版本配对（上游 README 矩阵）。M1 OTA 升级后先核对矩阵，
按需更新本目录（include + lib 全量替换）并重编 `genisom_motion`。
