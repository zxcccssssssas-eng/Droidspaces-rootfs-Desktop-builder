English | [中文](README.md) | [Back to project README](../README_english.md)

# scripts Directory

This directory contains installers used while building the RootFS, maintenance tools copied into the RootFS, and systemd service templates. Before running a file manually, check whether it belongs in the Linux container or the image build environment.

## File Overview

| File | Run in | Purpose |
| --- | --- | --- |
| `install-desktop.sh`, `desktops/*.sh` | RootFS build environment | Dispatches stable desktop profile slugs and owns per-distribution package sets. |
| `configure-desktop.sh` | RootFS build environment | Writes desktop/backend configuration and optionally installs the common auto-start service. |
| `start-desktop-session.sh` | Linux container | Starts the selected session from `/etc/droidspaces-desktop.conf`. |
| `install-mesa.sh` | ARM64 Linux container | Installs the latest Android-container Mesa build and MediaCodec VA-API driver, then locks Mesa packages. |
| `install-anland-kde.sh` | ARM64 Linux container | Installs Anland patched KWin/Xwayland Release packages and locks them. |
| `lib/kde-package-config.sh`, `lib/build-anland-kde-in-container.sh`, `lib/pack-anland-kde-archive.sh` | Package build environment | Builds patched KWin/Xwayland packages independently of RootFS (deb/rpm/pkg). |
| `install-usb-manager.sh` | Linux container | Installs Droidspaces USB Manager, distribution dependencies, launchers, and user permissions. |
| `systemd257.sh` | RootFS build environment | Installs a complete package-manager-owned systemd 257 family when required by an old Android kernel. |
| `download-firmware` | Debian/Ubuntu container | Installs `linux-firmware` and decompresses its `.zst` firmware. |
| `nosnap.sh` | Ubuntu RootFS build environment | Removes Snap, prevents reinstallation, and configures traditional deb sources. |
| `bashrc.sh` | Linux user shell | Adds Docker aliases, thermal helpers, and an SSH file-transfer helper. |
| `start/desktop-session.service` | Linux container systemd | Starts the selected desktop session through one common entry point. |
| `binfmt/*` | Linux container systemd/kernel | Checks and mounts `binfmt_misc` for QEMU cross-architecture execution. |

## Mesa Installer

`install-mesa.sh` selects the ARM64 Mesa asset for the current distribution from the latest `lfdevs/mesa-for-android-container` GitHub Release, then installs `msm_drm_drv_video.so` from the latest stable `Re-s/droidspaces-media-decode` Release. It supports Debian 13, Ubuntu 24.04/25.10/26.04, Fedora 43/44, and Arch Linux. Every target installs the media decode driver at `/usr/lib/aarch64-linux-gnu/dri/msm_drm_drv_video.so`.

The installer strictly validates Release tags, asset names, and official download URLs. Mirror downloads of the Mesa archive are verified against the SHA-256 digest published by the GitHub Release API. For every source, the media decode driver is checked against the Release API digest, upstream `SHA256SUMS`, and the published asset size. Downloads can resume, and temporary files are removed on exit.

Run interactively from the repository root:

```bash
sudo ./scripts/install-mesa.sh
```

With no option, the script probes all three sources and prompts for a choice. Select a source directly for unattended builds:

```bash
sudo ./scripts/install-mesa.sh --1  # GitHub
sudo ./scripts/install-mesa.sh --2  # gh-proxy.com
sudo ./scripts/install-mesa.sh --3  # ghproxy.net
```

The source options are mutually exclusive and apply to both the Mesa and media decode driver downloads. `-1`, `-2`, and `-3` are equivalent short options; use `--help` for built-in help. Third-party sources still require access to `api.github.com` for trusted metadata, plus `jq` and `sha256sum`. Downloads use either `curl` or `wget`.

After installation, persistent package locks are written for each distribution:

| Distribution | Lock location and mechanism |
| --- | --- |
| Debian/Ubuntu | `/etc/apt/preferences.d/hold-anland-package` with `Pin-Priority: -1` |
| Fedora | Installer-managed `exclude` block in `/etc/dnf/dnf.conf` |
| Arch | Installer-managed `IgnorePkg` block in `/etc/pacman.conf` |

The lock list is generated only from Mesa packages present in the archive. KWin and Xwayland are locked exclusively by `install-anland-kde.sh`. Managed configuration is idempotent, and unrelated existing configuration is preserved.

## Adding a Desktop Profile

Desktop names, target capabilities, and backend compatibility live in `lib/desktop-config.sh`. To add a desktop:

1. Register its stable slug in `desktop_normalize`, `desktop_label`, and the support matrix.
2. Add an executable `desktops/<slug>.sh` that installs packages according to `/etc/os-release`.
3. Map its session command in `start-desktop-session.sh`; `install-desktop.sh` automatically discovers executable profiles for valid slugs.
4. Add its display label to the `desktop` choice in both workflow entry files.

All seven Dockerfiles and the reusable workflow already use the generic profile interface, so an ordinary X11 desktop does not require copied Dockerfiles. Register a profile in `desktop_uses_anland_kde_packages` only when it truly requires patched KWin/Xwayland.

## Anland KDE Installer

`install-anland-kde.sh` reads `anland-kde-manifest` from the fixed `anland-kde-packages` rolling Release in `Goldzxcbug/droidspaces-package` by default, then installs the matching patched KWin/Xwayland packages for Debian 13, Ubuntu 26.04, Fedora 43/44, or Arch Linux on ARM64.

```bash
sudo ./scripts/install-anland-kde.sh
```

It also accepts `--1`, `--2`, or `--3` for GitHub, `gh-proxy.com`, or `ghproxy.net`; with no option, it probes the sources and prompts. Both the manifest and archive from a mirror are checked against GitHub API digests. Messages follow the system locale, and APT holds, DNF excludes, or Pacman `IgnorePkg` entries prevent upgrades from replacing the installed packages.

To install packages published by a public fork, override only the repository. The fork must provide the fixed `anland-kde-packages` tag:

```bash
sudo ANLAND_KDE_RELEASE_REPOSITORY=owner/repository \
  ./scripts/install-anland-kde.sh --1
```

The Anland host module, app, SELinux policy, bind mount, and Droidspaces permissions must still be configured as described in the [project Wayland and Anland setup](../README_english.md#wayland-and-anland-setup).

## Independent KWin/KDE package builds

The RootFS workflow does not compile KWin. To produce independent Debian/Ubuntu `.deb` files (and Fedora RPMs or Arch packages), run `build_kde_packages.sh` from the repository root, or the GitHub Actions workflow `Build and Release Anland KDE Wayland packages`. That path only clones Anland producer scripts and packages them in the matching distro container; it never writes a RootFS.

```bash
./build_kde_packages.sh -t Debian13
```

Outputs include the installer `.tar.gz` plus native packages under `kde-packages/packages/<target>/` for `apt install`, `dnf install`, or `pacman -U`. GitHub Actions also uploads those native files as `anland-kde-native-*` artifacts.

## USB Manager Installer

`install-usb-manager.sh` supports Debian/Ubuntu, Fedora, and Arch. It installs PyQt5, ADB, udev, NTFS, exFAT, and other matching dependencies, followed by the `usb-manager`, `usb-passthrough`, and `usb-storage-passthrough` commands.

```bash
sudo ./scripts/install-usb-manager.sh --user "$USER"
```

`--user USER` selects the user that receives USB management permissions and desktop launchers. When omitted, the installer tries `SUDO_USER`, the logged-in user, and then the first regular user. Development and offline tests can use a local Droidspaces-USB-Manager checkout through `--source DIR`; run `--help` for all options.

Hardware access must be enabled when importing the RootFS into Droidspaces, or `/sys/bus/usb` and `/sys/bus/scsi` will not be visible inside the container.

## systemd 257 Compatibility Script

Dockerfiles call `systemd257.sh` when `enable_systemd257=true`. It checks the installed systemd major version: version 257 and older are skipped, while newer systems install their complete native package family from the frozen compatibility Release `systemd257-packages` in `Goldzxcbug/droidspaces-package`. Related systemd packages are then locked. New package sets are first published under an immutable tag containing the source version and repository commit; the RootFS updates the tag, per-platform SHA-256 values, expected package counts, and package-repository commit together only after that Release is complete.

```bash
sudo ./scripts/systemd257.sh
```

This is an experimental compatibility step for old Android kernels. Test systemd, D-Bus, udev, networking, and desktop sessions on the target device before distributing the resulting RootFS.

## Firmware Tool

`download-firmware` is copied to `/usr/local/bin/download-firmware` in Debian 13 and Ubuntu 24/25/26 RootFS images, but it is not run automatically. Run it inside the container when required:

```bash
sudo download-firmware
```

It installs `zstd` and `linux-firmware`, decompresses `.zst` files under `/lib/firmware`, and repairs symlinks that point to compressed files. A successful run creates `/var/lib/.fw-setup-completed`; this marker currently does not skip later runs.

## Other Build and Startup Files

- `nosnap.sh` is Ubuntu-only. It stops and removes Snap, cleans leftovers, writes APT pins that prevent reinstallation, and configures the traditional deb sources required by the project. It changes packages and APT configuration and must run as root in the target RootFS or build layer.
- `start/desktop-session.service` is the common service template. It calls `start-desktop-session.sh`, reads the desktop configuration, runs the selected session as RootFS UID 1000, and rate-limits restarts after abnormal exits.
- `binfmt/qemu-binfmt-register.sh` and its service verify kernel `binfmt_misc` support and mount it when needed; unsupported kernels are skipped safely. QEMU interpreters are still required for actual cross-architecture execution.
- `bashrc.sh` is shell configuration appended to a user environment, not a standalone installer.

## Development Checks

After changing a shell script, run at least a syntax check. Use ShellCheck when it is installed:

```bash
bash -n scripts/install-mesa.sh
bash -n scripts/install-anland-kde.sh
bash -n scripts/install-usb-manager.sh
bash -n scripts/lib/kde-package-config.sh
bash -n scripts/lib/pack-anland-kde-archive.sh
bash -n build_kde_packages.sh
bash scripts/lib/kde-package-config.sh
shellcheck scripts/install-mesa.sh
```

Changes to package installation or lock handling should also be tested in APT, DNF, and Pacman containers. Run each installer twice to verify idempotency.
