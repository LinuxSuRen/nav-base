# nav-base

Navigation system vendor base image. Multi-architecture (AMD64 + ARM64) built via GitHub Actions native runners.

## Contents

| Component | Version | Description |
|---|---|---|
| LivoxSDK2 | 1.5.2 | cmake build to `/usr/local/lib` |
| livox_ros_driver2 | 1.2.8 | colcon build to `/opt/vendor_ws/install` |
| DLIO (SLAM) | patched | colcon build to `/opt/vendor_ws/install` |
| genisom_robot_sdk | 0.1.1 (binary) | `/opt/vendor_sdk/` + `.so` to `/usr/local/lib` |
| agibot_sdk | (binary) | `/opt/vendor_sdk/` + `.so` to `/usr/local/lib` |
| ROS 2 Humble deps | — | pcl_ros, nav2, octomap, autoware, slam_toolbox |

## Usage

```dockerfile
# Pull from GitHub Container Registry
ARG ROS_IMAGE=ghcr.io/linuxsuren/nav-base:latest
# Or pin to a specific version
# ARG ROS_IMAGE=ghcr.io/linuxsuren/nav-base:<short-sha>

FROM ${ROS_IMAGE}

# Vendor packages are in /opt/vendor_ws/install
# Source them, then colcon build your packages as overlay
RUN source /opt/vendor_ws/setup.bash && colcon build --packages-above my_package
```

## Multi-Arch Build

GitHub Actions uses **native runners** for each architecture — no QEMU:

```
build job (matrix):
  ubuntu-latest     → AMD64 native build
  ubuntu-24.04-arm  → ARM64 native build

manifest job:
  docker manifest create → ghcr.io/linuxsuren/nav-base:<sha> (multi-arch)
                           ghcr.io/linuxsuren/nav-base:latest (multi-arch)
```

## Local Build

```bash
# Single architecture
docker build -t nav-base:dev .

# Multi-architecture (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <your-registry>/nav-base:dev \
  --push .
```

## Directory Structure

```
├── Dockerfile                  ← Multi-stage: apt deps + SDK compile + colcon vendor workspace
├── .github/workflows/          ← GitHub Actions CI (native multi-arch build)
├── docker/                     ← Reference ROS base image recipe
└── src/third_party/            ← Vendor source code (Livox/DLIO/genisom/agibot)
```
