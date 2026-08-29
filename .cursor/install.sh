#!/usr/bin/env bash
# Idempotent Cloud Agent install step for the Droidspaces RootFS builder.
#
# The repository cross-builds aarch64 Linux RootFS tarballs with Docker Buildx.
# On the x86_64 Cloud Agent VM this needs Docker + Buildx, QEMU/binfmt for
# aarch64 emulation, and a nested-container friendly storage driver. Runtime
# daemon startup and binfmt registration live in start.sh; this script only
# installs durable tooling and writes static configuration.
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

echo "==> Installing base build tooling"
$SUDO apt-get update -qq
$SUDO apt-get install "${APT_OPTS[@]}" -qq \
  ca-certificates curl gnupg git make \
  xz-utils jq shellcheck \
  qemu-user-static binfmt-support \
  fuse3 fuse-overlayfs iptables uidmap

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker CE from the official repository"
  $SUDO install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO apt-get install "${APT_OPTS[@]}" -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "==> Docker already installed: $(docker --version)"
fi

echo "==> Writing nested-container friendly Docker daemon configuration"
# The default overlayfs/containerd snapshotter cannot mount overlay inside the
# unprivileged Cloud Agent VM. fuse-overlayfs works and is fast.
$SUDO mkdir -p /etc/docker
printf '%s\n' '{
  "storage-driver": "fuse-overlayfs",
  "features": { "containerd-snapshotter": false }
}' | $SUDO tee /etc/docker/daemon.json >/dev/null

echo "==> Ensuring the docker group grants the agent user socket access"
$SUDO groupadd -f docker
TARGET_USER="${SUDO_USER:-$(id -un)}"
$SUDO usermod -aG docker "$TARGET_USER" || true

echo "==> install.sh complete"
docker --version
docker buildx version
shellcheck --version | sed -n '2p'
