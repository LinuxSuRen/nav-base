# livox_ros_driver2（vendored）

## 来源

- 上游仓库：https://github.com/Livox-SDK/livox_ros_driver2
- 钉住版本：**master @ `21445540f0d100dc86a7e6df312dd70bbdb4afdf`**（2026-09-21，
  自报版本 **1.2.8**，`src/include/livox_ros_driver2.h`）
- 取用日期：2026-10-28 · 本仓消费方：`src/nav_sys_bringup/launch/mid360s_driver.launch.py`
  （`dedicated_launch` 模式按 lidar profile 拉起，Mid360/Mid360S 系 profile 依赖）
- 依赖：**LivoxSDK2 master（@ c0796f0，1.5.2，vendored 于 `src/third_party/LivoxSDK2/`）**。
  注意：驱动 1.2.8 源码引用双回波类型（`LivoxLidarDoubleEchoRawPoint` 等），SDK2 需
  ≥1.4；上游 1.4+ 无 tag，故钉 master commit（与驱动 master 同日提交，上游事实配对）。
  构建方式见其 VENDOR.md；容器镜像在 Dockerfile 中预装，裸机构建先手动 `cmake --install`

## 与上游的差异（升级时必须重新套用）

1. **新增 `package.xml`**：上游只带 `package_ROS1.xml` / `package_ROS2.xml`（构建脚本
   按发行版改名），本仓直接提交了 `package_ROS2.xml` 的副本，使 colcon 能发现本包。
   升级时用新版 `package_ROS2.xml` 覆盖 `package.xml`。相应地，上游 `.gitignore` 里
   忽略 `package.xml` 的一行已移除（该文件为本仓刻意提交物）。
2. **删除 `.git/`**：vendor 惯例，来源以本文件记录为准。
3. **CMakeLists.txt 补丁**：上游 `DISTRO_ROS` 从未定义，导致 Humble 构建必挂
   （`LIVOX_INTERFACES_INCLUDE_DIRECTORIES` NOTFOUND）。补丁从 `$ENV{ROS_DISTRO}`
   推导，并为空属性加兜底。升级时核对该段是否上游已修，未修则重新套用。
4. 其余源码**零修改**。

## 版本门槛（为什么是 1.2.8）

- Mid360S（`lidar_summary_info`/`Mid360s` 配置节、`kLivoxLidarTypeMid360s`）需要
  驱动 ≥ 1.2.6（`docs/faq.md`、`docs/research/2026-10-livox-integration.md`）；
  1.2.8 为钉住日 master，含 Mid360s 数据路径（`src/comm/pub_handler.cpp:135`）。
- xfer_format=0（PointCloud2，PointXYZRTLT）是本栈契约：`timestamp` 字段为**帧内相对
  ns 偏移**，DLIO 已按此打补丁（`src/third_party/direct_lidar_inertial_odometry/
  src/dlio/odom.cc` 搜 `nav_sys patch`）。

## 本地构建（裸机，容器内已由 Dockerfile 自动处理）

```bash
# ① 先装 LivoxSDK2（见 ../LivoxSDK2/VENDOR.md）
# ② 再编驱动（必须在 <ws>/src/ 下，上游 README 要求）
colcon build --packages-select livox_ros_driver2
```

注意：工作区全量 `colcon build` 会包含本包；未预装 LivoxSDK2 时 CMake 的
`find_library(... /usr/local/lib REQUIRED)` 会直接报错并中断——先装 SDK2 再全量构建。
