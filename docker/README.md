# device-navigation-base-image（依赖层基础镜像）

主 `Dockerfile` 的 `FROM ${ROS_IMAGE}` 依赖此镜像。内容：

- 基底：`ros:humble-ros-base-jammy`（公开镜像，默认走 DaoCloud 国内源）
- 构建工具：colcon / ccache / cmake / build-essential / curl / 网络排查工具
- ROS 运行时依赖：nav2 全家桶、rmw-cyclonedds、robot-localization、octomap
  系列、pointcloud-to-laserscan、autoware NDT/地图消息、slam-toolbox、pcl
- 国内 apt / ROS2 镜像源（清华）与工作区环境变量

配方由 git 历史精确复原（`chore/base-image` 分支提交 b32abc4 把这些依赖
从主 Dockerfile 移入预构建镜像），**本目录即权威配方**，fstech 仓里的
`dev/device-navigation-base-image` 只是它的预构建副本。

## 为什么默认拉 fstech 仓副本

- CI（Jenkins）与机器人本地构建都要拉这层；裸 `ros:humble-ros-base-jammy`
  缺 nav2 等运行时依赖，不能直接顶替
- fstech 北京实例是公司内网可达、有推送凭据（`aliyun-image`）的权威副本，
  主 `Dockerfile` 与 `build_real_image.sh` 默认指向它
- 环境无 fstech 凭据时：`NAV_SYS_ROS_IMAGE`（脚本）或 `--build-arg ROS_IMAGE=`
  （compose/手搭）覆盖为任意可达副本

## 重建并推送（依赖变更时）

单架构（amd64，快速本地重建）：

```bash
cd <仓库根>
docker build \
  --pull \
  -t fstech-registry.cn-beijing.cr.aliyuncs.com/dev/device-navigation-base-image:dev \
  -f docker/base-image/Dockerfile .
docker push fstech-registry.cn-beijing.cr.aliyuncs.com/dev/device-navigation-base-image:dev
```

多架构（amd64+arm64，**Jenkins 默认路径已自动执行**；arm64 机器人如智身
M1 需要）——注意推送的是 manifest list，会覆盖同名单架构 tag：

```bash
docker run --privileged --rm tonistiogi/binfmt --install arm64
docker buildx create --name multiarch --driver docker-container --bootstrap
docker buildx use multiarch
docker buildx build --platform linux/amd64,linux/arm64 --provenance=false --sbom=0 \
  -t fstech-registry.cn-beijing.cr.aliyuncs.com/dev/device-navigation-base-image:dev \
  --push . -f docker/base-image/Dockerfile
```

改动本目录 Dockerfile 后按上法重建即可；**不需要**动主 `Dockerfile`
（它始终 `FROM` 同名 tag）。日期戳 tag（如 `:20261018`）可用于回滚，
推送后在主 Dockerfile 的 `ROS_IMAGE` 默认值里升级引用。
