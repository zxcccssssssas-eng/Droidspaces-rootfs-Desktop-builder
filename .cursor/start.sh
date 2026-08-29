#!/usr/bin/env bash
# Per-boot Cloud Agent start step for the Droidspaces RootFS builder.
#
# Brings up the Docker daemon (the VM has no systemd), enables aarch64 QEMU
# emulation, and prepares the Buildx builder the build scripts expect. It is
# idempotent: safe to run repeatedly, and it returns once Docker is ready.
#
# dockerd, the binfmt_misc mount and socket ownership require root, but every
# docker/buildx command the repository's build scripts run uses the plain
# `docker` client as the agent user (via the docker group). start.sh mirrors
# that so the buildx builder it creates is visible to those scripts.
set -euo pipefail

ROOT=""
if [ "$(id -u)" -ne 0 ]; then
  ROOT="sudo"
fi

echo "==> Ensuring binfmt_misc is mounted"
if ! mount | grep -q "on /proc/sys/fs/binfmt_misc "; then
  $ROOT mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc || true
fi

echo "==> Ensuring the Docker daemon is running"
if ! $ROOT docker info >/dev/null 2>&1; then
  $ROOT sh -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
  for _ in $(seq 1 30); do
    if $ROOT docker info >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if ! $ROOT docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon failed to start; see /var/log/dockerd.log" >&2
  $ROOT tail -n 40 /var/log/dockerd.log 2>/dev/null || true
  exit 1
fi

echo "==> Granting the agent user access to the Docker socket"
if [ -S /var/run/docker.sock ]; then
  $ROOT chown root:docker /var/run/docker.sock || true
  $ROOT chmod 660 /var/run/docker.sock || true
fi

# Helper: run docker as the agent user (matching the build scripts). Falls back
# to root only if the agent user cannot reach the daemon for some reason.
run_docker() {
  if docker "$@" 2>/dev/null; then
    return 0
  fi
  $ROOT docker "$@"
}

echo "==> Registering QEMU binfmt handlers for cross-architecture builds"
# Matches build_rootfs-qemu-aarch64.sh. The fix-binary flag keeps the
# interpreter available inside build containers (BuildKit). Handlers register
# into the host kernel, so they are visible regardless of which user runs it.
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  run_docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
fi

echo "==> Ensuring the droidspaces-builder Buildx builder exists (agent user)"
# Created as the agent user so the build scripts, which run docker without sudo,
# can see and use it.
if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  docker buildx create --name droidspaces-builder --driver docker-container >/dev/null 2>&1 || true
fi

echo "==> start.sh complete"
docker version --format 'Docker {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})' 2>/dev/null \
  || $ROOT docker version --format 'Docker {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})' 2>/dev/null \
  || true
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  echo "aarch64 emulation: registered"
fi
if docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  echo "buildx builder droidspaces-builder: ready (agent user)"
fi
