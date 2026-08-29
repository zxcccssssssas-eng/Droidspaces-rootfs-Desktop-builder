中文 | [English](README_english.md)

# Droidspaces RootFS 自动构建

本项目用于通过 GitHub Actions 自动构建适用于 Droidspaces 的 Linux RootFS。构建流程采用可扩展的桌面 profile，可以按需选择发行版、桌面、显示后端、中文环境、输入法、GPU 加速、音频转发、TMOE、Docker 和开发工具。目前提供 KDE 与 KDE Mobile profile，后续桌面可独立加入 `scripts/desktops/`。

项目目标是减少在 Android 设备上手动配置桌面 Linux 容器的工作量。你只需要 Fork 仓库，在 Actions 页面选择构建参数，等待 Release 产物生成，然后把 `.tar.xz` RootFS 导入 Droidspaces。

## 目录

- [支持的系统](#支持的系统)
- [功能概览](#功能概览)
- [构建选项说明](#构建选项说明)
- [使用 GitHub Actions 构建](#使用-github-actions-构建)
- [导入 Droidspaces](#导入-droidspaces)
- [启动桌面](#启动桌面)
- [Wayland 和 Anland 配置](#wayland-和-anland-配置)
- [Droidspaces USB Manager](#droidspaces-usb-manager)
- [账户、密码和用户名修改](#账户密码和用户名修改)
- [本地构建](#本地构建)
- [安装硬件固件](#安装硬件固件)
- [仓库结构](#仓库结构)
- [已知限制](#已知限制)
- [致谢](#致谢)

## 支持的系统

| 构建目标 | 基础镜像 | 桌面 profile | Anland Wayland | 备注 |
| --- | --- | --- | --- | --- |
| `Debian-13` | `debian:trixie` | `none`、`KDE`、`KDE mobile` | 支持 | Debian 13 使用 Trixie 软件源。 |
| `Ubuntu-24` | `ubuntu:24.04` | `none`、`KDE` | 不支持 | 支持 `nosnap`。 |
| `Ubuntu-25` | `ubuntu:25.10` | `none`、`KDE` | 不支持 | 支持 `nosnap`。 |
| `Ubuntu-26` | `ubuntu:26.04` | `none`、`KDE`、`KDE mobile` | 支持 | 支持 `nosnap`，推荐用于 Anland KDE。 |
| `Fedora-43` | `fedora:43` | `none`、`KDE`、`KDE mobile` | 支持 | 某些设备需要启用硬件访问。 |
| `Fedora-44` | `fedora:44` | `none`、`KDE`、`KDE mobile` | 支持 | 某些设备需要启用硬件访问。 |
| `Arch` | `ogarcia/archlinux` | `none`、`KDE`、`KDE mobile` | 支持 | 使用 ARM64 Arch patched KWin/Xwayland；当前不建议使用本项目的 QEMU/binfmt 跨架构方案。 |

`all` 会构建全部 Dockerfile 模板。`all-wayland` 在 `KDE` 和 `KDE mobile` 模式下构建 `Debian-13`、`Ubuntu-26`、`Fedora-43`、`Fedora-44` 和 `Arch`；`KDE mobile` 会强制启用 Wayland 支持。

## 功能概览

- 多发行版 RootFS 构建：支持 Debian、Ubuntu、Fedora 和 Arch。
- 桌面选择：支持命令行 RootFS、KDE 和 KDE mobile。
- 桌面自动启动与故障恢复：X11、Plasma Wayland 和 Plasma Mobile 使用统一的 systemd 服务模板，异常退出后会限频自动重启。
- Termux:X11 桌面启动：X11 模式下默认使用 `DISPLAY=:5`。
- PulseAudio 音频转发：支持 Unix socket、TCP 和关闭音频转发。
- 中文环境：可选启用 `zh_CN.UTF-8` 和 `Asia/Shanghai` 时区。
- 输入法：可选安装 Fcitx5；启用中文环境时会额外安装中文输入支持。
- Snapdragon GPU 支持：集成来自 `mesa-for-android-container` 的高通 GPU 相关配置。
- 全部七个发行版通过 `scripts/install-mesa.sh` 安装对应的 ARM64 Mesa 驱动及最新版 `droidspaces-media-decode` VA-API 驱动，并仅锁定相关 Mesa 包。KWin/Xwayland 的锁定由 Anland KDE 专用安装器负责。镜像源选择、完整性校验和各发行版锁定机制见 [scripts 目录说明](scripts/README.md#mesa-安装器)。
- 原生 ARM64 Google Chrome：全部桌面模式以 Chrome Stable 取代 Chromium；Debian/Ubuntu 和 Fedora 使用 Google 官方软件源，Arch 使用 AUR 的 ARM64 打包配方。

- 骁龙 8 Gen 2 Wayland 花屏修复：可选将 Turnip UBWC 修复开关写入 RootFS 环境变量。
- 容器增强：补充 Android/Droidspaces 环境下常见的硬件、网络和用户组识别配置。
- TMOE：可选集成 TMOE，容器内执行 `tmoe` 即可启动。
- 开发工具：可选安装编译器、CMake、Python 开发环境等。
- 压缩工具：可选安装 `zip`、`unzip`、`7z`、`xz`、`tar`、`gzip` 等工具。
- Docker：可选在 RootFS 内安装 Docker 相关软件包。
- 旧内核 systemd 兼容：可选在 systemd 主版本高于 257 的 apt、dnf 或 pacman 发行版中安装由包管理器管控的完整 systemd 257 包族；Debian 13 等已是 257 或更低版本时会自动跳过。
- Wayland/Anland：通过独立的 [`droidspaces-package`](https://github.com/Goldzxcbug/droidspaces-package) 仓库，为 Debian 13、Ubuntu 26.04、Fedora 43/44 和 Arch Linux 提供 ARM64 patched KWin 与 Xwayland 包。
- USB 设备管理：全部发行版内置 Droidspaces USB Manager，支持 USB 存储、ADB 设备节点、挂载、卸载和系统托盘。
- Release 自动发布：构建完成后会把 RootFS `.tar.xz` 上传到 GitHub Release。

## 构建选项说明

GitHub Actions 的主要输入项如下：

| 选项 | 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 选择要构建的发行版 (`build_target`) | 发行版目标、`all`、`all-wayland` | `Debian-13` | 选择要构建的 RootFS。 |
| 自定义用户名 (`custom_username`) | 1–32 位字母、数字、`_`、`-`，以字母或 `_` 开头 | `Gold` | RootFS 默认用户。 |
| 桌面选择 (`desktop`) | `none`、`KDE`、`KDE mobile` | `KDE` | 选择命令行环境或当前提供的桌面 profile。 |
| 桌面开机自启动 (`desktop_autostart`) | `true`、`false` | `true` | 是否创建统一的桌面自启动 systemd 服务。选择 `none` 时必须关闭。 |
| 显示后端 (`display_backend`) | `x11`、`anland-wayland` | `x11` | 桌面与显示后端彼此独立；KDE Mobile 会强制使用 `anland-wayland`。 |
| PulseAudio 音频转发 (`PulseAudio`) | `socket`、`tcp`、`none` | `socket` | X11 模式下的音频转发方式。启用 Anland 时会被强制改为 `none`。 |
| 使用中文语言和时区 (`enable_zh_tz`) | `true`、`false` | 中文工作流默认为 `true` | 启用中文 locale 并设置上海时区。 |
| 高通骁龙 GPU 支持 (`enable_mesa`) | `true`、`false` | `true` | 启用高通 GPU/Mesa 相关支持。 |
| 修复 8Gen2 Wayland 花屏 (`enable_8gen2_wayland`) | `true`、`false` | `false` | 为 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch 写入 `FD_DEV_FEATURES=enable_tp_ubwc_flag_hint=1` 到 `/etc/environment`。 |
| 集成 TMOE (`enable_tmoe`) | `true`、`false` | `true` | 集成 TMOE。 |
| 移除 Ubuntu Snap (`nosnap`) | `true`、`false` | `false` | 只对 Ubuntu 有意义，用于移除 Snap、snapd 和可能重新安装 snapd 的 APT 策略。 |
| systemd 257 旧内核兼容 (`enable_systemd257`) | `true`、`false` | `false` | 启用后，在当前 systemd 主版本高于 257 时从 `droidspaces-package` 安装完整的原生包族；systemd 257 及更低版本自动跳过。安装完成后会锁定 systemd 相关包，避免再次升级覆盖。 |
| 输入法 Fcitx5 支持 (`enable_srf`) | `true`、`false` | `false` | 安装 Fcitx5 输入法。 |
| 跨架构支持 (`enable_binfmt`) | `true`、`false` | `false` | 在 RootFS 内加入 binfmt 跨架构支持组件。Arch 当前不建议使用。 |
| NAT 和硬件识别支持 (`enable_yj`) | `true`、`false` | `true` | 启用容器硬件和网络识别增强。 |
| 开发工具集成 (`enable_kfgj`) | `true`、`false` | `false` | 安装开发工具链。 |
| 压缩工具集成 (`enable_zip`) | `true`、`false` | `true` | 安装常用压缩工具。 |
| Docker 集成 (`enable_docker`) | `true`、`false` | `false` | 在 RootFS 内安装 Docker 相关包。 |
| Wayland 软件包仓库 (`wayland_package_repository`) | 公开的 `owner/repository` | `Goldzxcbug/droidspaces-package` | 指定 `anland-kde-packages` Release 的来源。可填本仓库，以使用本仓库独立软件包工作流发布的包。 |
| 将 patched KWin 打进 RootFS (`embed_anland_kde_packages`) | `true`、`false` | `true` | 仅在 `anland-wayland` 时生效。关闭后 RootFS 只安装发行版自带的 KDE，patched KWin/Xwayland 由独立软件包工作流或 `install-anland-kde.sh` 提供。 |

桌面模式说明：

| 模式 | 说明 | 适合场景 |
| --- | --- | --- |
| `none` | 不安装 KDE 桌面，只保留命令行环境。 | 需要轻量 RootFS、SSH、开发环境或自定义桌面的用户。 |
| `KDE` | KDE 桌面，包含系统工具、监控、文件管理和多媒体组件。 | 日常桌面使用。 |
| `KDE mobile` | KDE Plasma Mobile 相关组件。 | 手机屏幕和触控优先场景；会强制启用 Wayland。 |

音频模式说明：

| 模式 | 说明 |
| --- | --- |
| `socket` | 使用 Unix socket 转发 PulseAudio。通常延迟更低，推荐在 X11 模式下使用。 |
| `tcp` | 使用 `127.0.0.1:4713` 转发 PulseAudio。兼容性较直观，但暴露面更大。 |
| `none` | 不配置 PulseAudio。Anland 模式下会自动使用此模式，因为 Anland App 自带音频路径。 |

### systemd 257 旧内核兼容

开启 `enable_systemd257` 后，RootFS 会运行 `scripts/systemd257.sh`。脚本会先检测发行版现有的 systemd 主版本：

- 257 或更低版本（例如 Debian 13、Ubuntu 24.04）直接跳过；
- 高于 257 的 apt、dnf 和 pacman 系统从 `droidspaces-package` 的冻结兼容 Release `systemd257-packages` 安装对应发行版的完整 systemd 257 包族；后续包族先发布到不可变标签，再由 RootFS 一次性更新标签与校验元数据；
- 安装由发行版包管理器完成，并锁定 systemd 相关软件包，防止后续升级覆盖兼容版本。

该选项主要面向旧 Android 内核，属于实验性兼容方案，会显著增加构建时间；建议先在目标内核上验证桌面、dbus、udev 和网络功能。

## 使用 GitHub Actions 构建

RootFS 与 patched KWin/KDE Debian（以及 RPM/Arch）软件包是两条独立工作流，互不触发。

| 工作流 | 产物 | 说明 |
| --- | --- | --- |
| `编译并发布 Droidspaces RootFS` / `Build and Release Droidspaces RootFS` | `.tar.xz` RootFS | 只组装发行版根文件系统。Wayland 模式下默认把已发布的 patched 包打进镜像。 |
| `构建并发布 Anland KDE Wayland 软件包` / `Build and Release Anland KDE Wayland packages` | `anland-kde-packages` Release 压缩包，以及独立的 `.deb`/`.rpm`/`.pkg.tar.*` 工件 | 只构建 KWin/Xwayland，不生成 RootFS。Debian 13 与 Ubuntu 26.04 产出独立 deb 包。 |

1. Fork 本仓库到自己的 GitHub 账号。
2. 打开 Fork 后仓库的 `Actions` 页面。
3. 若只要 RootFS：选择中文工作流 `编译并发布 Droidspaces RootFS`，或英文工作流 `Build and Release Droidspaces RootFS`。
4. 若只要独立 KWin/KDE 软件包：选择 `构建并发布 Anland KDE Wayland 软件包`（或英文同名工作流），目标可选 `Debian13`、`ubuntu2604` 或 `all`。
5. 点击 `Run workflow`。
6. RootFS 工作流中选择发行版、桌面 profile、显示后端、用户名和功能开关。
7. 如果要使用 Wayland/Anland，选择 `display_backend=anland-wayland`；支持 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch。
8. 默认 RootFS 读取 `Goldzxcbug/droidspaces-package`。若已在本仓库跑过软件包工作流，把 `wayland_package_repository` 改成当前仓库的 `owner/repository`。
9. 若希望 RootFS 与软件包完全分离，将 `embed_anland_kde_packages` 设为 `false`，导入容器后再运行 `scripts/install-anland-kde.sh`，或用 `apt install` 安装独立 deb。
10. 等待对应 Actions 完成。RootFS 在 `Releases` 下载 `.tar.xz`；独立软件包在 `anland-kde-packages` Release 或 `anland-kde-native-*` 工件中。

Release 通常包含：

- 一个或多个 RootFS 压缩包
- RootFS 文件名会同时记录桌面 slug 和显示后端，例如 `Ubuntu-26-kde-Wayland-Droidspaces-rootfs-aarch64-v20260702-120000.tar.xz`。
- Release 正文会记录构建目标、桌面 profile、显示后端、用户名和各功能开关。

## 导入 Droidspaces

1. 在 Droidspaces 中创建或导入容器。
2. RootFS 文件选择 Release 下载的 `.tar.xz`。
3. 如果 RootFS 包含 KDE 桌面，必须在 Droidspaces 中开启 GPU 访问。
4. Ubuntu 和 Debian 系建议在特权模式中开启 `noseccomp`，并确保内核启用 `USER_NS`。否则某些桌面操作可能出现明显卡顿。
5. Fedora 某些设备需要开启硬件访问，否则可能出现桌面闪屏或崩溃。
6. Arch 建议宿主内核版本为 5.10 或更新。
7. 如果使用 X11 模式，准备好 Termux:X11。
8. 如果使用 Wayland/Anland 模式，按本文的 Wayland 和 Anland 配置完成宿主侧准备。

## 启动桌面

启用 `desktop_autostart` 后，构建流程安装统一的 `desktop-session.service`；服务读取 `/etc/droidspaces-desktop.conf` 决定实际会话：

| 桌面模式 | 服务文件 | 启动命令 |
| --- | --- | --- |
| KDE + X11 | `desktop-session.service` | `DISPLAY=:5 startplasma-x11` |
| KDE + Anland Wayland | `desktop-session.service` | `startplasma-wayland` |
| KDE Mobile + Anland Wayland | `desktop-session.service` | `startplasmamobile` |

该服务以 UID 1000 用户运行并读取 `/etc/environment`。桌面进程异常退出时会在 2 秒后自动重启；如果 60 秒内启动失败超过 5 次，systemd 会暂时停止重试，防止形成崩溃循环。正常退出不会触发自动重启。

### X11 模式

X11 模式适用于 `display_backend=x11` 的构建。默认环境变量为：

```text
DISPLAY=:5
```

建议保持 `desktop_autostart=true`，这也是当前默认选项。启用后 RootFS 会创建通用桌面自启动服务；只有需要自行管理桌面进程，或构建 `none` 命令行环境时，才应关闭该选项。

关闭自启动后，可以进入容器手动启动：

```bash
startplasma-x11
```

自启动的实际效果仍取决于 Droidspaces 的 systemd、权限和显示后端配置。如果自启动没有拉起桌面，可以进入容器后执行 `startplasma-x11` 排查。

### Wayland/Anland 模式

Wayland/Anland 模式适用于选择 `display_backend=anland-wayland` 的 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch 构建。默认环境变量包括：

```text
WAYLAND_DISPLAY=wayland-0
DISPLAY=:0
QT_QPA_PLATFORM=wayland
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
```

完成宿主侧 Anland 配置后，在容器内执行：

```bash
startplasma-wayland
```

如果构建的是 `KDE mobile` 模式，对应的手动启动命令为：

```bash
startplasmamobile
```

## Wayland 和 Anland 配置

Wayland 支持依赖 [anland](https://github.com/superturtlee/anland) 和 [`droidspaces-package`](https://github.com/Goldzxcbug/droidspaces-package) Release 中的 patched KWin/Xwayland 预编译包。建议使用 `Ubuntu-26`，也可以使用 `Debian-13`、`Fedora-43`、`Fedora-44` 或 `Arch`。包的构建、更新和固定滚动 Release 均由独立包仓库维护。

### 一键安装 Anland KDE Release 包

`scripts/install-anland-kde.sh` 会自动识别 ARM64 发行版，默认从 `Goldzxcbug/droidspaces-package` 的固定滚动 Release 安装匹配的 patched KWin/Xwayland 包，并锁定相关软件包。支持的系统、下载镜像、完整性校验、参数和独立安装方法已移至 [scripts 目录说明](scripts/README.md#anland-kde-安装器)。

从仓库根目录运行：

```bash
sudo ./scripts/install-anland-kde.sh
```

推荐构建选项：

| 选项 | 推荐值 |
| --- | --- |
| `build_target` | `Ubuntu-26` |
| `desktop` | `KDE` 或 `KDE mobile` |
| `desktop_autostart` | `true` |
| `display_backend` | `anland-wayland` |
| `PulseAudio` | 无需手动设置，启用 Anland 后会变为 `none` |

宿主侧配置步骤：

1. 从 [anland Releases](https://github.com/superturtlee/anland/releases) 下载 `virtual-drm-daemon.zip`，刷入后重启设备。
2. 从同一 Release 下载并安装 `app-debug.apk`。
3. 导入 Droidspaces 容器时开启硬件访问。
4. 开启 SELinux 宽容模式，或使用后文的精确 SELinux 策略修补。
5. 在特权模式中开启 `nocaps` 和 `noseccomp`。
6. 在高级选项中添加绑定挂载：

```text
/data/local/tmp/display_daemon.sock -> /run/display.sock
```

7. 启动容器，选择普通用户登录。
8. 在容器内执行：

```bash
startplasma-wayland
```

如果选择 `KDE mobile`，工作流会强制启用 Wayland，因为 Plasma Mobile 在本项目中按 Wayland 路径配置。

## Droidspaces USB Manager

全部 7 个发行版模板都会通过 `scripts/install-usb-manager.sh` 安装 [Droidspaces-USB-Manager](https://github.com/Yizhou147/Droidspaces-USB-Manager)，包括发行版依赖、命令行入口、应用菜单和桌面快捷方式。安装参数和更新方法见 [scripts 目录说明](scripts/README.md#usb-manager-安装器)。

导入 RootFS 时必须开启 Droidspaces 的硬件访问，否则容器内看不到 `/sys/bus/usb` 和 `/sys/bus/scsi` 设备。安装器会同时创建应用菜单入口和 `~/Desktop/usb-manager.desktop` 桌面快捷方式。进入 KDE 后，也可以运行：

```bash
usb-manager
```

另外提供两个命令行入口：

```bash
usb-passthrough
usb-storage-passthrough
```

## 本地构建

本项目主要面向 GitHub Actions，但也可以在本地使用 Docker Buildx 构建。你需要准备：

- Docker
- Docker Buildx
- `xz`
- 如果要跨架构构建，需要可用的 QEMU/binfmt 环境

原生架构构建示例：

```bash
chmod +x build_rootfs-native.sh
./build_rootfs-native.sh \
  -i Debian-13.Dockerfile \
  -v local \
  -K KDE \
  -L true \
  -B x11 \
  -P socket \
  -g true \
  -a false \
  -b true \
  -c true \
  -d false \
  -e true \
  -f false \
  -h false \
  -j true \
  -n false \
  -S false \
  -t false \
  -u Gold
```

使用 QEMU 构建 arm64 RootFS 示例：

```bash
chmod +x build_rootfs-qemu-aarch64.sh
./build_rootfs-qemu-aarch64.sh \
  -i Ubuntu-26.Dockerfile \
  -v local \
  -K KDE \
  -L true \
  -B anland-wayland \
  -P none \
  -g true \
  -a false \
  -b true \
  -c true \
  -d false \
  -e true \
  -f false \
  -h true \
  -j true \
  -n true \
  -S false \
  -t false \
  -u Gold
```

构建完成后会生成类似下面的文件：

```text
Ubuntu-26-kde-Wayland-Droidspaces-rootfs-aarch64-local.tar.xz
```

只构建独立 KWin/KDE 软件包、不生成 RootFS 的示例（需要 ARM64 Docker 或 `linux/arm64` 模拟）：

```bash
chmod +x build_kde_packages.sh
./build_kde_packages.sh -t Debian13
./build_kde_packages.sh -t ubuntu2604
```

Debian/Ubuntu 会在 `kde-packages/` 下同时生成安装器用 `.tar.gz` 和独立的 `.deb` 文件。导入未打进 patched 包的 RootFS 后，可以用这些 deb 更新 KWin/Xwayland：

```bash
sudo apt-get install -y --allow-downgrades ./kde-packages/packages/debian13/*.deb
```

## 安装硬件固件

Debian 13 和 Ubuntu 24/25/26 RootFS 内置 `/usr/local/bin/download-firmware`，用于安装并解压硬件固件。依赖、重复运行行为和处理流程见 [scripts 目录说明](scripts/README.md#固件工具)。

该工具只会被复制到 RootFS，不会在构建或容器启动时自动执行。需要使用时，在容器内手动运行：

```bash
sudo download-firmware
```

## 仓库结构

```text
.
├── Arch.Dockerfile
├── Debian-13.Dockerfile
├── Fedora-43.Dockerfile
├── Fedora-44.Dockerfile
├── Ubuntu-24.Dockerfile
├── Ubuntu-25.Dockerfile
├── Ubuntu-26.Dockerfile
├── build_rootfs-native.sh
├── build_rootfs-qemu-aarch64.sh
├── build_kde_packages.sh
├── scripts/
│   ├── README.md
│   ├── README_english.md
│   ├── configure-desktop.sh
│   ├── install-desktop.sh
│   ├── start-desktop-session.sh
│   ├── desktops/
│   │   ├── kde.sh
│   │   └── kde-mobile.sh
│   ├── lib/
│   │   ├── desktop-config.sh
│   │   ├── kde-package-config.sh
│   │   ├── build-anland-kde-in-container.sh
│   │   └── pack-anland-kde-archive.sh
│   ├── start/
│   │   └── desktop-session.service
│   ├── bashrc.sh
│   ├── download-firmware
│   ├── install-usb-manager.sh
│   ├── install-anland-kde.sh
│   ├── install-mesa.sh
│   ├── nosnap.sh
│   └── systemd257.sh
├── scripts/binfmt/
│   ├── qemu-binfmt-register.service
│   └── qemu-binfmt-register.sh
└── .github/workflows/
    ├── build-rootfs-core.yml
    ├── build-rootfs-releases-en.yml
    ├── build-rootfs-releases.yml
    ├── build-kde-wayland-core.yml
    ├── build-kde-wayland.yml
    └── build-kde-wayland-en.yml
```

KDE Wayland 包可以在本仓库用独立工作流构建，也可以继续从 [`droidspaces-package`](https://github.com/Goldzxcbug/droidspaces-package) 读取固定滚动 Release `anland-kde-packages`。RootFS 工作流不会自动触发软件包工作流。默认仍读取官方包仓库；要使用本仓库自己构建的包，把 `wayland_package_repository` 设为当前仓库的 `owner/repository`。关闭 `embed_anland_kde_packages` 时，RootFS 不再内置 patched KWin，导入后可用独立 deb 或 `install-anland-kde.sh` 安装。

## 已知限制

- Wayland/Anland 当前覆盖 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch。
- Ubuntu 24 和 Ubuntu 25 当前按 X11 路径使用。
- `KDE mobile` 模式支持 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch。
- 选择 `anland-wayland` 后，工作流会关闭 PulseAudio 转发，因为 Anland App 自带音频路径。
- Fedora 在部分设备上需要硬件访问，否则可能闪屏或崩溃。
- Ubuntu 和 Debian 在未启用 `noseccomp` 或内核缺少 `USER_NS` 时，可能出现卡顿。
- 默认密码为 `1234`，导入后应立即修改。
- 本项目内置的预编译 Wayland 包与上游 anland 的兼容性取决于构建时的上游状态。

## 致谢

- [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS/)：本项目运行环境的基础。
- [mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container)：高通 Snapdragon GPU 驱动支持。
- [droidspaces-media-decode](https://github.com/Re-s/droidspaces-media-decode)：基于 Android MediaCodec 的容器 VA-API 硬件解码驱动。
- [TMOE](https://github.com/2moe/tmoe)：容器内管理工具。
- [anland](https://github.com/superturtlee/anland)：Wayland 显示后端和 patched KDE 相关工作。
- [Droidspaces-USB-Manager](https://github.com/Yizhou147/Droidspaces-USB-Manager)：适用于Droidspaces 的 USB 存储和 ADB 设备管理工具。
