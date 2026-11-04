# device-robot-base — 导航系统 vendor 基础镜像
#
# 完全自建：ros:humble-ros-base-jammy + 全量编译依赖 + vendor SDK 编译产物。
# 不依赖 device-navigation-base-image:dev（其 arm64 变体有已知的 rcutils
# 缺失问题，见 docker/Dockerfile 哨兵校验注释）。
#
# 主仓库 device-navigation FROM 本镜像，只编译业务代码（nav_sys_* + web_console）。
# 版本发布：tag v<major>.<minor>，通知主仓库更新 FROM tag。
#
# ── 两个产物（多阶段，同一 Dockerfile，Actions 按 target 分别打 tag）─────────
#   build 阶段 → <tag> / latest          ：全量（编译工具链 + dev 头文件 + vendor
#                                           源码），行为与历史版本完全一致，
#                                           主仓库编译业务包仍用它。
#   slim  阶段 → <tag>-slim / latest-slim：仅运行期内容（运行库 deb + vendor
#                                           编译产物），基底为裸 ubuntu:22.04，
#                                           无编译链 / dev 头文件链 / rviz 渲染
#                                           链（细节见 slim 阶段头注释；体积
#                                           以 CI 实测为准，目标 ~1.2-1.6GB）。
# ─────────────────────────────────────────────────────────────────────────────

ARG ROS_IMAGE=docker.m.daocloud.io/library/ros:humble-ros-base-jammy
# slim 阶段基底：ubuntu:22.04 裸底（ros:humble-ros-base-jammy 镜像自带
# build-essential/cmake/colcon 约 700MB，且低层无法通过 purge 回收——
# slim 改用裸 ubuntu + ros-humble-ros-base 运行时 deb 重建）
ARG UBUNTU_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04

FROM ${ROS_IMAGE} AS build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /opt/vendor_ws

# ── 全量编译依赖（与 docker/Dockerfile 保持一致——含 pcl_ros/octomap/nav2）──
ARG UBUNTU_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu
ARG UBUNTU_SECURITY_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu
ARG ROS2_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu

RUN sed -i "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g; s|http://security.ubuntu.com/ubuntu|${UBUNTU_SECURITY_MIRROR}|g" /etc/apt/sources.list \
    && sed -i "s|^URIs: .*|URIs: ${ROS2_MIRROR}|" /etc/apt/sources.list.d/ros2.sources \
    && sed -i "s|^Types: .*|Types: deb|" /etc/apt/sources.list.d/ros2.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    APT_OPTS=(-o Acquire::Retries=10 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::http::Pipeline-Depth=0) \
    && ok=0 \
    && for i in 1 2 3 4 5; do \
        apt-get "${APT_OPTS[@]}" update \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            bash build-essential ccache cmake curl \
            iproute2 iputils-ping net-tools procps \
            python3-colcon-common-extensions \
            python3-pip python3-setuptools python3-venv python3-yaml \
            libeigen3-dev libomp-dev libprotobuf-dev protobuf-compiler \
        && ldconfig \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            ros-humble-navigation2 \
            ros-humble-nav2-bringup \
            ros-humble-rmw-cyclonedds-cpp \
            ros-humble-rosidl-default-generators \
            ros-humble-sensor-msgs-py \
            ros-humble-tf-transformations \
            ros-humble-robot-localization \
            ros-humble-imu-tools \
        && ldconfig \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            ros-humble-octomap \
            ros-humble-octomap-msgs \
            ros-humble-octomap-ros \
            ros-humble-octomap-server \
            ros-humble-pointcloud-to-laserscan \
            ros-humble-autoware-internal-debug-msgs \
            ros-humble-autoware-map-msgs \
            ros-humble-autoware-ndt-scan-matcher \
            ros-humble-slam-toolbox \
            ros-humble-pcl-ros \
            ros-humble-pcl-conversions \
        && ldconfig \
        && dpkg --configure -a \
        && ok=1 \
        && break; \
        dpkg --configure -a || true; \
        apt-get -f install -y || true; \
        apt-get clean; \
        echo "apt-get failed (attempt ${i}/5), retrying..." >&2; \
        sleep 10; \
      done \
    && test "${ok}" = "1" \
    && rm -rf /var/lib/apt/lists/*

# ── 哨兵校验 + 自修复：QEMU/mirror 抖动时 apt 可能静默坏包。
#    先强制重装关键 ROS 包（幂等，正常时秒级），再校验 .so 完整性（非空非断链）。──
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    APT_OPTS=(-o Acquire::Retries=10 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30) \
    && apt-get "${APT_OPTS[@]}" update \
    && apt-get "${APT_OPTS[@]}" install -y --reinstall \
        ros-humble-rcutils ros-humble-rcpputils ros-humble-rcl \
        ros-humble-rclcpp ros-humble-rmw \
    && dpkg --configure -a \
    && rm -rf /var/lib/apt/lists/*

RUN missing=""; \
    for lib in librcutils.so librcpputils.so librcl.so librmw.so \
               librclcpp.so libbuiltin_interfaces__rosidl_typesupport_cpp.so; do \
      f="/opt/ros/humble/lib/${lib}"; \
      if [ ! -e "$f" ] || [ -L "$f" -a ! -e "$(readlink -f "$f")" ]; then \
        missing="${missing} ${lib}(broken)"; \
      elif [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -lt 1024 ]; then \
        missing="${missing} ${lib}(tiny)"; \
      fi; \
    done; \
    for dir in ament_cmake rosidl_default_generators nav2_bt_navigator octomap_server pcl_ros; do \
      if [ ! -d "/opt/ros/humble/share/${dir}" ]; then missing="${missing} share/${dir}"; fi; \
    done; \
    if [ -n "${missing}" ]; then \
      echo "FATAL: base image missing critical ROS artifacts:${missing}" >&2; \
      exit 1; \
    fi

# ── LivoxSDK2（无 colcon 清单，cmake 直接安装到 /usr/local）──
COPY src/third_party/LivoxSDK2 /tmp/LivoxSDK2
RUN --mount=type=cache,target=/root/.ccache,sharing=locked \
    cmake -S /tmp/LivoxSDK2 -B /tmp/livoxsdk2-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    && cmake --build /tmp/livoxsdk2-build \
    && cmake --install /tmp/livoxsdk2-build \
    && ldconfig \
    && rm -rf /tmp/livoxsdk2-build /tmp/LivoxSDK2

# ── genisom_robot_sdk（二进制分发：include/ + lib/）──
COPY src/third_party/genisom_robot_sdk /opt/vendor_sdk/genisom_robot_sdk
RUN arch=$(uname -m) \
    && if [ -d "/opt/vendor_sdk/genisom_robot_sdk/lib/${arch}" ]; then \
        cp -a /opt/vendor_sdk/genisom_robot_sdk/lib/${arch}/*.so* /usr/local/lib/ 2>/dev/null || true; \
        ldconfig; \
    fi

# ── agibot_sdk（二进制分发）──
COPY src/third_party/agibot_sdk /opt/vendor_sdk/agibot_sdk
RUN arch=$(uname -m) \
    && if [ -d "/opt/vendor_sdk/agibot_sdk/lib/${arch}" ]; then \
        cp -a /opt/vendor_sdk/agibot_sdk/lib/${arch}/*.so* /usr/local/lib/ 2>/dev/null || true; \
        ldconfig; \
    fi

# ── colcon 构建 livox_ros_driver2 + DLIO（输出 /opt/vendor_ws/install）──
COPY src/third_party/livox_ros_driver2 ./src/livox_ros_driver2
COPY src/third_party/direct_lidar_inertial_odometry ./src/direct_lidar_inertial_odometry

ARG BUILD_JOBS=0
RUN --mount=type=cache,target=/root/.ccache,sharing=locked \
    source /opt/ros/humble/setup.bash \
    && export CCACHE_DIR=/root/.ccache \
    && if [ "${BUILD_JOBS}" -gt 0 ] 2>/dev/null; then \
        export MAKEFLAGS="-j${BUILD_JOBS}"; \
        COLCON_JOBS="--parallel-workers ${BUILD_JOBS}"; \
    else \
        COLCON_JOBS=""; \
    fi \
    && colcon build --event-handlers console_direct+ ${COLCON_JOBS} \
        --cmake-args \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    && rm -rf build log src

# ── vendor workspace 环境（主仓库 source 此文件后 colcon build 为 overlay）──
RUN printf '%s\n' \
    'source /opt/ros/humble/setup.bash' \
    'source /opt/vendor_ws/install/setup.bash' \
    > /opt/vendor_ws/setup.bash \
    && chmod +x /opt/vendor_ws/setup.bash \
    && printf '%s\n' \
    'source /opt/vendor_ws/setup.bash' \
    > /etc/profile.d/vendor_ws.sh \
    && chmod +x /etc/profile.d/vendor_ws.sh

# ── 编译产物哨兵校验 ──
RUN test -f /opt/vendor_ws/install/livox_ros_driver2/lib/livox_ros_driver2/livox_ros_driver2_node \
    && test -f /opt/vendor_ws/install/direct_lidar_inertial_odometry/lib/direct_lidar_inertial_odometry/dlio_odom_node \
    && echo "vendor workspace OK" \
    || { echo "FATAL: vendor colcon build artifacts missing" >&2; exit 1; }

LABEL org.opencontainers.image.title="device-robot-base" \
      org.opencontainers.image.description="Navigation vendor base (full deps + Livox SDK + DLIO + genisom/agibot)" \
      org.opencontainers.image.vendor="fstech"

# ═══════════════════════════════════════════════════════════════════════════
# slim 阶段：仅运行期内容（tag 后缀 -slim），基底 = 裸 ubuntu:22.04
#（ros:humble-ros-base-jammy 镜像自带 build-essential/cmake/colcon ~700MB，
#  且低层字节无法 purge 回收）+ ros-humble-ros-base 运行时元包。
#
# 与 build 阶段的取舍（差异全部为“运行机器人业务不需要”项）：
#   - 编译链（build-essential/cmake/ccache/colcon/pip/venv/protobuf-compiler）
#   - dev 头文件链（libpcl-dev → VTK/OpenCV/boost-all/JDK/LLVM/gdal；改用
#     libpcl 运行库子集）
#   - slam_toolbox（deb 硬依赖 rviz/OGRE/Qt5 渲染链；2D legacy 回退用 full）
#     ＋ navigation2 元包拆包安装（去 nav2_rviz_plugins / nav2-bringup）
#   - imu_tools（业务仓库零引用）、rosidl-default-generators（仅生成期）
#   - mppi-controller / constrained-smoother（业务 nav2 配置未使用）
#   - 六个"bloom 把构建依赖烤进 Depends"的包改为从 build 阶段拷贝运行时
#     文件（octomap-server / autoware-ndt / robot-localization / nav2-map-server
#     / nav2-waypoint-follower / nav2_smac_planner）——ldd 哨兵保证链接完整
# 保留：nav2 运行节点（生产配置所用全套）、octomap 套件、autoware NDT、
#   pointcloud-to-laserscan、rmw-cyclonedds、libpcl 运行库子集、libomp5、
#   libprotobuf23、运维工具、python3-yaml；vendor 编译产物原样拷贝。
# 体积：full 实测 3.44GB；slim 过程版（ros-base 基底+三包手术）实测 2.51GB；
#   最终版（ubuntu 基底+六包手术）预计 ~1.2-1.6GB，以 CI 实测为准。
# ═══════════════════════════════════════════════════════════════════════════
FROM ${UBUNTU_IMAGE} AS slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /opt/vendor_ws

# 镜像源与 build 阶段同参（国内网络环境一致）
ARG UBUNTU_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu
ARG UBUNTU_SECURITY_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu
ARG ROS2_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu

# ubuntu:22.04 基底没有 ROS 源：apt 源文件直接从 build 阶段拷贝（build 基底
# = ros:humble-ros-base-jammy，其 ros2.sources 已指向上方镜像，且 ROS 签名
# 密钥内嵌在 Signed-By 字段里——自包含，无需另拷 keyring / 网络取 ros.key）。
# ubuntu 自身源换镜像加速。
COPY --from=build /etc/apt/sources.list.d/ros2.sources /etc/apt/sources.list.d/ros2.sources
# 裸 ubuntu 无 ca-certificates：apt 源一律走 http（包完整性由 apt 的 GPG
# 签名校验保证，TLS 非必需）；ca-certificates 随首批包安装，供运行期 https。
RUN sed -i "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g; s|http://security.ubuntu.com/ubuntu|${UBUNTU_SECURITY_MIRROR}|g" /etc/apt/sources.list \
    && sed -i "s|^URIs: .*|URIs: ${ROS2_MIRROR}|" /etc/apt/sources.list.d/ros2.sources \
    && sed -i "s|^Types: .*|Types: deb|" /etc/apt/sources.list.d/ros2.sources \
    && sed -i "s|https://|http://|g" /etc/apt/sources.list /etc/apt/sources.list.d/ros2.sources

# ── 运行期依赖（无任何 -dev / 编译工具；nav2 逐包安装避开 rviz 渲染链）──
# libpcl 运行库子集：业务仓库自研 C++ 节点 + DLIO + livox 驱动实际链接的
#   common/io/filters/kdtree/octree/search/segmentation/surface 及其依赖；
#   不含 visualization（VTK）/people/stereo/outofcore/apps。
#
# ⚠ 以下三个 ROS deb 不可 apt 安装（bloom 把构建依赖烤进了 Depends，会拖回
#   libpcl-dev → VTK/OpenCV/boost-all/JDK 全链，slim 实测因此仅省 160MB）：
#   ros-humble-pcl-conversions（Depends libpcl-dev）
#   ros-humble-octomap-server（Depends libpcl-dev + pcl-ros）
#   ros-humble-autoware-ndt-scan-matcher（Depends autoware-utils-pcl → libpcl-dev）
# ldd 实测（2026-11-04）：octomap_server_node 与 autoware_ndt_scan_matcher_node
# 运行期不链接任何 libpcl/vtk/opencv 共享库——改为从 build 阶段拷贝运行时
# 文件（见下方 COPY --from=build）；pcl_conversions 是纯头文件包，运行期
# 零文件，无需处理。
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    APT_OPTS=(-o Acquire::Retries=10 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30) \
    && ok=0 \
    && for i in 1 2 3 4 5; do \
        apt-get "${APT_OPTS[@]}" update \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            bash ca-certificates curl iproute2 iputils-ping net-tools procps \
            python3-yaml \
            libomp5 libprotobuf23 \
            ros-humble-ros-base \
            ros-humble-rmw-cyclonedds-cpp \
            ros-humble-sensor-msgs-py \
            ros-humble-tf-transformations \
        && ldconfig \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            ros-humble-octomap \
            ros-humble-octomap-msgs \
            ros-humble-octomap-ros \
            ros-humble-pointcloud-to-laserscan \
            ros-humble-autoware-internal-debug-msgs \
            ros-humble-autoware-map-msgs \
            libpcl-common1.12 \
            libpcl-features1.12 \
            libpcl-filters1.12 \
            libpcl-io1.12 \
            libpcl-kdtree1.12 \
            libpcl-keypoints1.12 \
            libpcl-ml1.12 \
            libpcl-octree1.12 \
            libpcl-recognition1.12 \
            libpcl-registration1.12 \
            libpcl-sample-consensus1.12 \
            libpcl-search1.12 \
            libpcl-segmentation1.12 \
            libpcl-surface1.12 \
            libpcl-tracking1.12 \
        && ldconfig \
        && apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --fix-missing \
            ros-humble-nav2-amcl \
            ros-humble-nav2-behavior-tree \
            ros-humble-nav2-behaviors \
            ros-humble-nav2-bt-navigator \
            ros-humble-nav2-collision-monitor \
            ros-humble-nav2-controller \
            ros-humble-nav2-core \
            ros-humble-nav2-costmap-2d \
            ros-humble-nav2-dwb-controller \
            ros-humble-nav2-lifecycle-manager \
            ros-humble-nav2-msgs \
            ros-humble-nav2-navfn-planner \
            ros-humble-nav2-planner \
            ros-humble-nav2-regulated-pure-pursuit-controller \
            ros-humble-nav2-rotation-shim-controller \
            ros-humble-nav2-route \
            ros-humble-nav2-simple-commander \
            ros-humble-nav2-smoother \
            ros-humble-nav2-theta-star-planner \
            ros-humble-nav2-util \
            ros-humble-nav2-velocity-smoother \
            ros-humble-nav2-voxel-grid \
        && ldconfig \
        && dpkg --configure -a \
        && ok=1 \
        && break; \
        dpkg --configure -a || true; \
        apt-get -f install -y || true; \
        apt-get clean; \
        echo "apt-get failed (attempt ${i}/5), retrying..." >&2; \
        sleep 10; \
      done \
    && test "${ok}" = "1" \
    && rm -rf /var/lib/apt/lists/*

# ── vendor 编译产物（来自 build 阶段，与 full 镜像同源）──
#   /opt/vendor_ws/install：livox_ros_driver2 + DLIO
#   /usr/local/lib：LivoxSDK2 + genisom/agibot librobot_sdk（原生架构）
#   /opt/vendor_sdk 双架构源树不拷（slim 内无编译场景）
COPY --from=build /opt/vendor_ws/install /opt/vendor_ws/install
COPY --from=build /opt/vendor_ws/setup.bash /opt/vendor_ws/setup.bash
COPY --from=build /etc/profile.d/vendor_ws.sh /etc/profile.d/vendor_ws.sh
COPY --from=build /usr/local/lib /usr/local/lib

# ── 三个"Depends 拖 dev 链"包的运行时文件（与 build 阶段同源同架构）──
# octomap_server：节点 + 私有库 + share（launch）+ ament index 标记
COPY --from=build /opt/ros/humble/lib/octomap_server /opt/ros/humble/lib/octomap_server
COPY --from=build /opt/ros/humble/lib/libcolor_octomap_server.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/share/octomap_server /opt/ros/humble/share/octomap_server
# pcl_conversions：纯头文件包（无 .so 无 share 依赖）——运行期零文件，不拷
# autoware NDT：节点 + share（launch/config，nav_sys ndt_adapter 引用）
COPY --from=build /opt/ros/humble/lib/autoware_ndt_scan_matcher /opt/ros/humble/lib/autoware_ndt_scan_matcher
COPY --from=build /opt/ros/humble/share/autoware_ndt_scan_matcher /opt/ros/humble/share/autoware_ndt_scan_matcher

# ── 更多"bloom 把构建依赖烤进 Depends"的运行期手术包（同因，同法）──
#   robot_localization（Depends libboost-dev → libboost1.74-dev ~150MB）：ekf 用
COPY --from=build /opt/ros/humble/lib/robot_localization /opt/ros/humble/lib/robot_localization
COPY --from=build /opt/ros/humble/lib/librl_lib.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/lib/librobot_localization__rosidl_*.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/share/robot_localization /opt/ros/humble/share/robot_localization
#   nav2_map_server（Depends graphicsmagick-dev-compat → libicu-dev ~80MB）：核心
COPY --from=build /opt/ros/humble/lib/nav2_map_server /opt/ros/humble/lib/nav2_map_server
COPY --from=build /opt/ros/humble/lib/libmap_io.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/lib/libmap_server_core.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/share/nav2_map_server /opt/ros/humble/share/nav2_map_server
#   nav2_waypoint_follower（Depends cv-bridge → libopencv-dev ~400MB）：WaitAtWaypoint 用
COPY --from=build /opt/ros/humble/lib/nav2_waypoint_follower /opt/ros/humble/lib/nav2_waypoint_follower
COPY --from=build /opt/ros/humble/lib/libwait_at_waypoint.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/lib/libinput_at_waypoint.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/lib/libwaypoint_follower_core.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/share/nav2_waypoint_follower /opt/ros/humble/share/nav2_waypoint_follower
#   nav2_smac_planner（Depends ompl → flann-dev → hdf5/openmpi/gfortran ~200MB）：
#   生产 planner（SmacPlanner2D；ldd 实测无 ompl 运行库依赖）
COPY --from=build /opt/ros/humble/lib/libnav2_smac_planner*.so /opt/ros/humble/lib/
COPY --from=build /opt/ros/humble/share/nav2_smac_planner /opt/ros/humble/share/nav2_smac_planner
# photo_at_waypoint 插件不拷（运行期链接 cv-bridge/opencv，slim 不带；
# 配置里只加载 WaitAtWaypoint，如需 PhotoAtWaypoint 用 full 镜像）

# ament resource index 标记（get_package_share_directory / ros2 pkg / pluginlib 解析需要）
COPY --from=build /opt/ros/humble/share/ament_index/resource_index/packages/octomap_server \
                    /opt/ros/humble/share/ament_index/resource_index/packages/autoware_ndt_scan_matcher \
                    /opt/ros/humble/share/ament_index/resource_index/packages/robot_localization \
                    /opt/ros/humble/share/ament_index/resource_index/packages/nav2_map_server \
                    /opt/ros/humble/share/ament_index/resource_index/packages/nav2_waypoint_follower \
                    /opt/ros/humble/share/ament_index/resource_index/packages/nav2_smac_planner \
                    /opt/ros/humble/share/ament_index/resource_index/packages/

RUN ldconfig

# ── slim 哨兵校验：vendor 产物 + 关键运行库 + 拷贝节点的动态链接完整性 ──
RUN missing=""; \
    test -f /opt/vendor_ws/install/livox_ros_driver2/lib/livox_ros_driver2/livox_ros_driver2_node \
      || missing="${missing} livox_ros_driver2_node"; \
    test -f /opt/vendor_ws/install/direct_lidar_inertial_odometry/lib/direct_lidar_inertial_odometry/dlio_odom_node \
      || missing="${missing} dlio_odom_node"; \
    test -e /usr/local/lib/liblivox_lidar_sdk_shared.so \
      || missing="${missing} liblivox_lidar_sdk_shared.so"; \
    test -e /usr/local/lib/librobot_sdk.so \
      || missing="${missing} librobot_sdk.so"; \
    test -e /opt/ros/humble/lib/librmw_cyclonedds_cpp.so \
      || missing="${missing} librmw_cyclonedds_cpp.so"; \
    test -f /opt/ros/humble/lib/octomap_server/octomap_server_node \
      || missing="${missing} octomap_server_node"; \
    test -f /opt/ros/humble/lib/autoware_ndt_scan_matcher/autoware_ndt_scan_matcher_node \
      || missing="${missing} autoware_ndt_scan_matcher_node"; \
    test -f /opt/ros/humble/lib/robot_localization/ekf_node \
      || missing="${missing} ekf_node"; \
    test -f /opt/ros/humble/lib/nav2_map_server/map_server \
      || missing="${missing} map_server"; \
    test -f /opt/ros/humble/lib/nav2_waypoint_follower/waypoint_follower \
      || missing="${missing} waypoint_follower"; \
    test -e /opt/ros/humble/lib/libnav2_smac_planner_2d.so \
      || missing="${missing} libnav2_smac_planner_2d.so"; \
    test -e /opt/ros/humble/lib/libwait_at_waypoint.so \
      || missing="${missing} libwait_at_waypoint.so"; \
    for dir in nav2_bt_navigator nav2_costmap_2d robot_localization octomap_server autoware_ndt_scan_matcher nav2_map_server nav2_smac_planner nav2_waypoint_follower; do \
      if [ ! -d "/opt/ros/humble/share/${dir}" ]; then missing="${missing} share/${dir}"; fi; \
    done; \
    if [ -n "${missing}" ]; then \
      echo "FATAL: slim image missing critical artifacts:${missing}" >&2; \
      exit 1; \
    fi \
    && ldd_missing="$(LD_LIBRARY_PATH=/opt/ros/humble/lib ldd \
        /opt/ros/humble/lib/octomap_server/octomap_server_node \
        /opt/ros/humble/lib/autoware_ndt_scan_matcher/autoware_ndt_scan_matcher_node \
        /opt/ros/humble/lib/robot_localization/ekf_node \
        /opt/ros/humble/lib/nav2_map_server/map_server \
        /opt/ros/humble/lib/nav2_waypoint_follower/waypoint_follower \
        /opt/ros/humble/lib/libnav2_smac_planner_2d.so \
        /opt/ros/humble/lib/librl_lib.so \
        2>/dev/null | grep -c 'not found' || true)" \
    && test "${ldd_missing}" = "0" \
      || { echo "FATAL: copied nodes have unresolved shared libs (ldd not found=${ldd_missing})" >&2; exit 1; } \
    && echo "slim vendor workspace OK"

LABEL org.opencontainers.image.title="device-robot-base-slim" \
      org.opencontainers.image.description="Navigation vendor base, runtime-only (no toolchain/dev headers/rviz chain)" \
      org.opencontainers.image.vendor="fstech"
