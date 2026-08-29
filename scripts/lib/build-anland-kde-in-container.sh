#!/usr/bin/env bash
# Runs inside a distro container. Clones Anland, builds patched KWin/Xwayland
# packages with the upstream producer script, and writes .kwin-version.
set -euo pipefail

: "${ANLAND_REPO:?ANLAND_REPO is required}"
: "${ANLAND_COMMIT:?ANLAND_COMMIT is required}"
: "${BUILD_SCRIPT:?BUILD_SCRIPT is required}"
: "${BUILD_TARGET:?BUILD_TARGET is required}"

PACKAGE_OUTPUT="${WORKDIR:-}"
if [[ -z "$PACKAGE_OUTPUT" ]]; then
    if [[ "$BUILD_TARGET" == Arch ]]; then
        PACKAGE_OUTPUT=/tmp/kde-packages
    else
        PACKAGE_OUTPUT=/root/kde-packages
    fi
fi
mkdir -p "$PACKAGE_OUTPUT"

case "$BUILD_TARGET" in
    Debian13|ubuntu2604)
        apt-get update
        apt-get install -y --no-install-recommends \
            git ca-certificates sudo \
            build-essential devscripts dpkg-dev fakeroot patch
        ;;
    Fedora43|Fedora44)
        dnf install -y --setopt=install_weak_deps=False \
            git ca-certificates sudo \
            dnf-plugins-core rpmdevtools rpm-build patch tar xz
        ;;
    Arch)
        pacman -Syu --noconfirm
        pacman -S --noconfirm --needed base-devel git ca-certificates sudo
        if ! id -u anland >/dev/null 2>&1; then
            useradd -m -s /bin/bash anland
        fi
        printf 'anland ALL=(root) NOPASSWD: /usr/bin/pacman\n' > /etc/sudoers.d/anland-pacman
        chmod 0440 /etc/sudoers.d/anland-pacman
        if grep -q '^#PACMAN_AUTH=()' /etc/makepkg.conf; then
            sed -i 's/^#PACMAN_AUTH=().*/PACMAN_AUTH=(sudo)/' /etc/makepkg.conf
        elif ! grep -q '^PACMAN_AUTH=' /etc/makepkg.conf; then
            printf '\nPACMAN_AUTH=(sudo)\n' >> /etc/makepkg.conf
        fi
        chown -R anland:anland "$PACKAGE_OUTPUT"
        ;;
    *)
        echo "Unsupported package build target: $BUILD_TARGET" >&2
        exit 1
        ;;
esac

git init --quiet /tmp/anland
git -C /tmp/anland remote add origin "$ANLAND_REPO"
git -C /tmp/anland fetch --quiet --depth=1 origin "$ANLAND_COMMIT"
git -C /tmp/anland checkout --quiet --detach FETCH_HEAD

# Debian 13 uses DEB822 sources; the upstream producer requires deb-src.
if [[ "$BUILD_TARGET" == Debian13 && -f /etc/apt/sources.list.d/debian.sources ]]; then
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
    apt-get update
fi

test -f "/tmp/anland/$BUILD_SCRIPT"
chmod +x "/tmp/anland/$BUILD_SCRIPT"

if [[ "$BUILD_TARGET" == Arch ]]; then
    su -s /bin/bash anland -c \
        "cd /tmp/anland/$(dirname "$BUILD_SCRIPT") && WORKDIR=$PACKAGE_OUTPUT ./$(basename "$BUILD_SCRIPT") --noconfirm"
    chmod -R a+rwX "$PACKAGE_OUTPUT"
else
    cd "/tmp/anland/$(dirname "$BUILD_SCRIPT")"
    WORKDIR="$PACKAGE_OUTPUT" sudo -E "./$(basename "$BUILD_SCRIPT")"
fi

kwin_package=""
kwin_version=""
case "$BUILD_TARGET" in
    Debian13|ubuntu2604)
        kwin_package="$(find "$PACKAGE_OUTPUT" -type f -name 'kwin-wayland_*.deb' -print | sort | head -n1)"
        if [[ -z "$kwin_package" ]]; then
            kwin_package="$(find "$PACKAGE_OUTPUT" -type f -name 'kwin-x11_*.deb' -print | sort | head -n1)"
        fi
        [[ -n "$kwin_package" ]] || { echo "No kwin deb package was found" >&2; exit 1; }
        kwin_version="$(dpkg-deb -f "$kwin_package" Version)"
        ;;
    Fedora43|Fedora44)
        kwin_package="$(find "$PACKAGE_OUTPUT" -type f -name 'kwin-[0-9]*.rpm' -print | sort | head -n1)"
        [[ -n "$kwin_package" ]] || { echo "No kwin rpm package was found" >&2; exit 1; }
        kwin_version="$(rpm -qp --queryformat '%{VERSION}' "$kwin_package")"
        ;;
    Arch)
        kwin_package="$(find "$PACKAGE_OUTPUT" -type f -name 'kwin-[0-9]*.pkg.tar.*' -print | sort | head -n1)"
        [[ -n "$kwin_package" ]] || { echo "No kwin Arch package was found" >&2; exit 1; }
        kwin_version="$(pacman -Qp "$kwin_package" | awk 'NR == 1 { print $2 }')"
        ;;
esac

# Drop epoch and distro/Arch pkgrel; keep the upstream KWin version in the asset name.
kwin_version="${kwin_version#*:}"
case "$BUILD_TARGET" in
    Debian13|ubuntu2604|Arch) kwin_version="${kwin_version%-*}" ;;
esac
[[ -n "$kwin_version" ]] || { echo "Unable to parse the KWin version" >&2; exit 1; }
printf '%s\n' "$kwin_version" > "$PACKAGE_OUTPUT/.kwin-version"
printf 'Built %s KWin %s from %s\n' "$BUILD_TARGET" "$kwin_version" "$kwin_package"
