# device-navigation-base-image 依赖层基础镜像
#
# 内容 = ros:humble-ros-base-jammy + 构建/网络工具 + nav2/octomap/NDT/pcl 等
# ROS 运行时依赖 + 国内镜像源。主 Dockerfile 的编译装配层在此之上进行。
#
# 复原自 git 历史（chore/base-image 分支切换预构建基础镜像时从主 Dockerfile
# 移出的依赖清单，见提交 b32abc4），保证本仓库不依赖不可追溯的外部镜像。
#
# 构建与推送（详见同目录 README.md）：
#   docker build -t fstech-registry.cn-beijing.cr.aliyuncs.com/dev/device-navigation-base-image:dev \
#     -f docker/base-image/Dockerfile .
#   docker push fstech-registry.cn-beijing.cr.aliyuncs.com/dev/device-navigation-base-image:dev

ARG ROS_BASE_IMAGE=docker.m.daocloud.io/library/ros:humble-ros-base-jammy

FROM ${ROS_BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV NAV_SYS_WORKSPACE=/opt/nav_sys_ws
ENV UNITREE_SDK2_ROOT=/opt/unitree_robotics
ENV CONFIG_PATH=/opt/nav_sys_ws/web_console/backend/config.docker.yaml
ENV LD_LIBRARY_PATH=/opt/unitree_robotics/lib/x86_64:/opt/unitree_robotics/lib
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

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
            bash \
            build-essential \
            ccache \
            cmake \
            curl \
            iproute2 \
            iputils-ping \
            net-tools \
            procps \
            python3-colcon-common-extensions \
            python3-pip \
            python3-setuptools \
            python3-venv \
            python3-yaml \
            libeigen3-dev \
            libomp-dev \
            ros-humble-navigation2 \
            ros-humble-nav2-bringup \
            ros-humble-rmw-cyclonedds-cpp \
            ros-humble-rosidl-default-generators \
            ros-humble-sensor-msgs-py \
            ros-humble-tf-transformations \
            ros-humble-robot-localization \
            ros-humble-imu-tools \
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

# 哨兵校验：QEMU/mirror 抖动时 apt-get -f install 可能以"删除损坏包"收场
# （2026-10-28 现场：arm64 基础镜像静默丢了 ros-humble-rcutils，下游
# find_package(rcutils) 全崩）。关键运行库缺失在此响亮失败，绝不静默出镜像。
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    missing=""; \
    for lib in librcutils.so librcpputils.so librcl.so librmw.so \
               librclcpp.so libbuiltin_interfaces__rosidl_typesupport_cpp.so; do \
      if [ ! -e "/opt/ros/humble/lib/${lib}" ]; then missing="${missing} ${lib}"; fi; \
    done; \
    for dir in ament_cmake rosidl_default_generators nav2_bt_navigator octomap_server; do \
      if [ ! -d "/opt/ros/humble/share/${dir}" ]; then missing="${missing} share/${dir}"; fi; \
    done; \
    if [ -n "${missing}" ]; then \
      echo "FATAL: base image missing critical ROS artifacts:${missing}" >&2; \
      exit 1; \
    fi

WORKDIR /opt/nav_sys_ws
