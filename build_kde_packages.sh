#!/usr/bin/env bash
# Build independent Anland KWin/Xwayland packages without producing a RootFS.
# Requires Docker on ARM64 (or Docker with linux/arm64 emulation).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/kde-package-config.sh
source "$REPO_DIR/scripts/lib/kde-package-config.sh"

BUILD_TARGET="Debian13"
ANLAND_REPO="${ANLAND_REPO:-https://github.com/superturtlee/anland.git}"
ANLAND_REF="${ANLAND_REF:-main}"
ANLAND_COMMIT="${ANLAND_COMMIT:-}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_DIR/kde-packages}"

usage() {
    cat <<EOF
Usage: $0 [-t TARGET] [-r ANLAND_REF] [-R ANLAND_REPO] [-o OUTPUT_DIR]

Build patched KWin/Xwayland packages independently of RootFS.

  -t TARGET       ubuntu2604, Debian13, Fedora43, Fedora44, Arch, or all
                  (default: Debian13)
  -r ANLAND_REF   Anland branch, tag, or commit (default: main)
  -R ANLAND_REPO  Anland git URL (default: https://github.com/superturtlee/anland.git)
  -o OUTPUT_DIR   Output directory (default: ./kde-packages)
  -h              Show this help

Environment:
  ANLAND_COMMIT   Pin a previously resolved commit instead of ANLAND_REF
  OUTPUT_ROOT     Same as -o

Debian and Ubuntu targets produce independent .deb files plus the installer
tar.gz that RootFS consumes. Fedora produces .rpm files; Arch produces
.pkg.tar.* files.
EOF
}

while getopts "t:r:R:o:h" opt; do
    case "$opt" in
        t) BUILD_TARGET="$OPTARG" ;;
        r) ANLAND_REF="$OPTARG" ;;
        R) ANLAND_REPO="$OPTARG" ;;
        o) OUTPUT_ROOT="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

if ! kde_package_targets_json "$BUILD_TARGET" >/dev/null; then
    echo "Unsupported package target: $BUILD_TARGET" >&2
    usage >&2
    exit 1
fi

command -v docker >/dev/null 2>&1 || {
    echo "Docker is required to build Anland KDE packages." >&2
    exit 1
}
command -v git >/dev/null 2>&1 || {
    echo "git is required to resolve the Anland source commit." >&2
    exit 1
}

resolve_anland_commit() {
    if [[ -n "$ANLAND_COMMIT" ]]; then
        return 0
    fi
    local tmp_dir source_dir
    tmp_dir="$(mktemp -d)"
    source_dir="$tmp_dir/anland"
    git init --quiet "$source_dir"
    git -C "$source_dir" remote add origin "$ANLAND_REPO"
    git -C "$source_dir" fetch --quiet --depth=1 origin "$ANLAND_REF"
    ANLAND_COMMIT="$(git -C "$source_dir" rev-parse FETCH_HEAD)"
    git -C "$source_dir" cat-file -e "${ANLAND_COMMIT}^{commit}"
    rm -rf "$tmp_dir"
}

build_one_target() {
    local target="$1"
    kde_package_resolve "$target" || return 1

    local output_dir asset_dir
    output_dir="$OUTPUT_ROOT/build/$target"
    asset_dir="$OUTPUT_ROOT/release/$target"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    echo "========================================================="
    echo " Building independent packages: $KDE_PACKAGE_LABEL"
    echo " Image: $KDE_PACKAGE_IMAGE"
    echo " Anland: $ANLAND_REPO @ $ANLAND_COMMIT"
    echo "========================================================="

    docker run --rm \
        --platform linux/arm64 \
        -e ANLAND_REPO \
        -e ANLAND_COMMIT \
        -e BUILD_SCRIPT="$KDE_PACKAGE_SCRIPT" \
        -e BUILD_TARGET="$target" \
        -e PKG_PATTERN="$KDE_PACKAGE_PATTERN" \
        -v "$output_dir:/root/kde-packages" \
        -v "$output_dir:/tmp/kde-packages" \
        -v "$REPO_DIR/scripts/lib/build-anland-kde-in-container.sh:/usr/local/bin/build-anland-kde-in-container.sh:ro" \
        "$KDE_PACKAGE_IMAGE" \
        bash /usr/local/bin/build-anland-kde-in-container.sh

    STAGING_ROOT="$OUTPUT_ROOT/staging" \
    BUILD_TARGET="$target" \
    PKG_PATTERN="$KDE_PACKAGE_PATTERN" \
    ASSET_PREFIX="$KDE_PACKAGE_ASSET_PREFIX" \
    ASSET_ARCH="$KDE_PACKAGE_ASSET_ARCH" \
    ARCHIVE_TARGET="$KDE_PACKAGE_ARCHIVE_TARGET" \
    OUTPUT_DIR="$output_dir" \
    ASSET_DIR="$asset_dir" \
    bash "$REPO_DIR/scripts/lib/pack-anland-kde-archive.sh"

    mkdir -p "$OUTPUT_ROOT"
    cp -a "$asset_dir/." "$OUTPUT_ROOT/"
    if [[ -d "$asset_dir/packages" ]]; then
        mkdir -p "$OUTPUT_ROOT/packages/$KDE_PACKAGE_ARCHIVE_TARGET"
        cp -a "$asset_dir/packages/." "$OUTPUT_ROOT/packages/$KDE_PACKAGE_ARCHIVE_TARGET/"
    fi
}

resolve_anland_commit
echo "Resolved $ANLAND_REPO @ $ANLAND_REF to $ANLAND_COMMIT"

if [[ "$BUILD_TARGET" == all ]]; then
    mapfile -t TARGETS < <(kde_package_known_targets)
else
    TARGETS=("$BUILD_TARGET")
fi
for target in "${TARGETS[@]}"; do
    [[ -n "$target" ]] || continue
    build_one_target "$target"
done

echo "========================================================="
echo " Independent package build finished."
echo " Archives and native packages are under: $OUTPUT_ROOT"
echo "========================================================="
