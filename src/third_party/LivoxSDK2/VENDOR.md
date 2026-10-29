# LivoxSDK2（vendored）

## 来源

- 上游仓库：https://github.com/Livox-SDK/Livox-SDK2
- 钉住版本：**master @ `c0796f04c143143899c87a773d9f6b7136453c0b`**（2026-09-21，
  CHANGELOG 自报 1.5.2）
- 取用日期：2026-10-28 · 本仓消费方：`src/third_party/livox_ros_driver2/`（其
  CMakeLists 以 `find_library(liblivox_lidar_sdk_shared.so /usr/local/lib REQUIRED)`
  定位本库）
- 无 `package.xml`：**不是 colcon 包**，不会出现在 `colcon list`；由 Dockerfile
  显式 cmake 构建并安装到 `/usr/local`

## 为什么是 master 而不是 v1.3.1（选版依据，2026-10-28 实测）

- 上游 **tag 最新只到 v1.3.1**，1.4/1.5 只存在于 master（无 tag）。
- 钉住的 livox_ros_driver2 master（1.2.8）源码引用 `LivoxLidarDoubleEchoRawPoint` /
  `kLivoxLidarDoubleEchoData`（双回波，`pub_handler.cpp`）——这些类型 v1.3.1 没有，
  配 v1.3.1 编译直接失败；master（≥1.4）才有。
- driver master 与 SDK master 同日提交（2026-09-21），是上游事实配对。
- Mid360S 支持在 master 完好验证：`parse_cfg_file.cpp` 节名映射含
  `{"Mid360s", kLivoxLidarTypeMid360s}`，`params_check.cpp` 保留 56100 端口组校验，
  与 `src/nav_sys_core/config/lidars/mid360s_m1_driver.json` 完全对应。

## 与上游的差异

- 仅删除 `.git/` 与新增本 VENDOR.md，源码零修改。

## 构建安装（Dockerfile 已自动执行；裸机手动执行）

```bash
cmake -S src/third_party/LivoxSDK2 -B /tmp/livoxsdk2-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/livoxsdk2-build -j$(nproc)
cmake --install /tmp/livoxsdk2-build   # 默认前缀 /usr/local（lib + include）
rm -rf /tmp/livoxsdk2-build
```

## ⚠ 已知坑（M1 实测记录，2026-10-28）

1. **json 的 extrinsic x/y/z 必须是整数**（`"x": 0` 而非 `0.0`）——驱动用 rapidjson
   `GetInt()` 解析，浮点直接断言崩溃（进程 abort，日志只见 rapidjson Assertion）。
   roll/pitch/yaw 是 `GetFloat()`，浮点无碍。上游 `config/MID360s_config.json` 样例
   即整数写法。
2. `lidar_summary_info.lidar_type: 8` 与 `"Mid360s"` 节（SDK 侧 type 35）**并存是上游
   官方样例写法**（见驱动 `config/MID360s_config.json`），非配置错误。
