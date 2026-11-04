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

## Image Variants

Every build publishes two variants (both multi-arch AMD64 + ARM64), from the same
multi-stage Dockerfile:

| Tag | Target | Contents |
|---|---|---|
| `<sha>`, `latest` | `build` | Full image: toolchain (gcc/cmake/colcon/ccache), dev headers (`libpcl-dev` → VTK/OpenCV/boost-all), all ROS deps incl. `pcl_ros`/`slam_toolbox`/`imu_tools`, vendor artifacts. Use this to **compile** overlay packages. Behavior identical to historical releases. Measured **3.44 GB** (amd64, uncompressed). |
| `<sha>-slim`, `latest-slim` | `slim` | **Runtime-only**: bare `ubuntu:22.04` + `ros-humble-ros-base` runtime metapackage, no toolchain/dev headers, no VTK/OpenCV/JDK/LLVM chain, no rviz rendering chain (slam_toolbox / imu_tools / nav2_rviz_plugins / mppi / constrained-smoother excluded), `libpcl` runtime subset, nav2 per-package. Six bloom-poisoned debs (octomap-server / autoware-ndt / robot-localization / nav2-map-server / nav2-waypoint-follower / smac) ship as **runtime file copies** from the build stage with an `ldd` sentinel. Measured **2.51 GB** at the intermediate revision (ros-base base + 3-package surgery); final revision (ubuntu base + full surgery) targets **~1.2–1.6 GB** — CI-measured value is authoritative. |

Differences that are *visible at runtime* (slim vs full):

* 2D `slam_toolbox` legacy fallback is **not available** in slim (its humble deb
  hard-depends on rviz_common/ogre/Qt5). Use the full image where 2D fallback matters.
* `imu_tools` is absent (zero references in the downstream repo).
* No `colcon`/`gcc`/`cmake` inside the image — packages cannot be rebuilt in-container.

```dockerfile
# Runtime-only base for downstream runtime images:
ARG ROS_IMAGE=ghcr.io/linuxsuren/nav-base:latest-slim
FROM ${ROS_IMAGE}
```

## Multi-Arch Build

GitHub Actions uses **native runners** for each architecture — no QEMU:

```
build job (matrix):
  ubuntu-latest     → AMD64 native build   (--target build + --target slim)
  ubuntu-24.04-arm  → ARM64 native build   (--target build + --target slim)

manifest job (docker buildx imagetools create):
  ghcr.io/linuxsuren/nav-base:<sha>        (multi-arch, full)
  ghcr.io/linuxsuren/nav-base:latest       (multi-arch, full)
  ghcr.io/linuxsuren/nav-base:<sha>-slim   (multi-arch, runtime-only)
  ghcr.io/linuxsuren/nav-base:latest-slim  (multi-arch, runtime-only)
```

## Local Build

```bash
# Full image (toolchain + dev headers, for compiling overlays)
docker build --target build -t nav-base:dev .

# Runtime-only slim image
docker build --target slim -t nav-base:dev-slim .

# Multi-architecture (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <your-registry>/nav-base:dev --target build \
  --push .
```

## Directory Structure

```
├── Dockerfile                  ← Multi-stage: apt deps + SDK compile + colcon vendor workspace
├── .github/workflows/          ← GitHub Actions CI (native multi-arch build)
├── docker/                     ← Reference ROS base image recipe
└── src/third_party/            ← Vendor source code (Livox/DLIO/genisom/agibot)
```
