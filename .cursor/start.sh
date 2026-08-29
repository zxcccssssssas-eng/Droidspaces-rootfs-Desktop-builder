#!/usr/bin/env bash
# Per-boot Cloud Agent start step for the Droidspaces RootFS builder.
#
# Brings up the Docker daemon (the VM has no systemd), enables aarch64 QEMU
# emulation, and prepares the Buildx builder the build scripts expect. It is
# idempotent: safe to run repeatedly, and it returns once Docker is ready.
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

echo "==> Ensuring binfmt_misc is mounted"
if ! mount | grep -q "on /proc/sys/fs/binfmt_misc "; then
  $SUDO mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc || true
fi

echo "==> Ensuring the Docker daemon is running"
if ! $SUDO docker info >/dev/null 2>&1; then
  $SUDO sh -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
  for _ in $(seq 1 30); do
    if $SUDO docker info >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if ! $SUDO docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon failed to start; see /var/log/dockerd.log" >&2
  $SUDO tail -n 40 /var/log/dockerd.log 2>/dev/null || true
  exit 1
fi

echo "==> Fixing docker socket ownership for the docker group"
if [ -S /var/run/docker.sock ]; then
  $SUDO chown root:docker /var/run/docker.sock || true
  $SUDO chmod 660 /var/run/docker.sock || true
fi

echo "==> Registering QEMU binfmt handlers for cross-architecture builds"
# Matches the mechanism used by build_rootfs-qemu-aarch64.sh. The fix-binary
# flag keeps the interpreter available inside build containers (BuildKit).
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  $SUDO docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
fi

echo "==> Ensuring the droidspaces-builder Buildx builder exists"
if ! $SUDO docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  $SUDO docker buildx create --name droidspaces-builder --driver docker-container >/dev/null
fi

echo "==> start.sh complete"
$SUDO docker version --format 'Docker {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})' 2>/dev/null || true
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  echo "aarch64 emulation: registered"
fi
