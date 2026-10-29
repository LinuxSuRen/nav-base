# device-robot-base — 导航系统 vendor 基础镜像
#
# 完全自建：ros:humble-ros-base-jammy + 全量编译依赖 + vendor SDK 编译产物。
# 不依赖 device-navigation-base-image:dev（其 arm64 变体有已知的 rcutils
# 缺失问题，见 docker/Dockerfile 哨兵校验注释）。
#
# 主仓库 device-navigation FROM 本镜像，只编译业务代码（nav_sys_* + web_console）。
# 版本发布：tag v<major>.<minor>，通知主仓库更新 FROM tag。

ARG ROS_IMAGE=docker.m.daocloud.io/library/ros:humble-ros-base-jammy

FROM ${ROS_IMAGE}

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
