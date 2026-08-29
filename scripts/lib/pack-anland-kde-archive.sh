#!/usr/bin/env bash
# Collect built KWin/Xwayland packages, write installer-compatible tar.gz, and
# copy independent native packages (deb/rpm/pkg) next to that archive.
set -euo pipefail

: "${BUILD_TARGET:?BUILD_TARGET is required}"
: "${PKG_PATTERN:?PKG_PATTERN is required}"
: "${ASSET_PREFIX:?ASSET_PREFIX is required}"
: "${ASSET_ARCH:?ASSET_ARCH is required}"
: "${ARCHIVE_TARGET:?ARCHIVE_TARGET is required}"
: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${ASSET_DIR:?ASSET_DIR is required}"

STAGING_ROOT="${STAGING_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
PACKAGE_DIR="$STAGING_ROOT/anland-kde-packages/$ARCHIVE_TARGET"
INDEPENDENT_DIR="$ASSET_DIR/packages"
rm -rf "$PACKAGE_DIR" "$ASSET_DIR"
mkdir -p "$PACKAGE_DIR" "$ASSET_DIR" "$INDEPENDENT_DIR"

copy_packages_from() {
    local source_dir="$1"
    local maxdepth="${2:-}"
    local -a find_args=("$source_dir" -type f -name "$PKG_PATTERN")

    [[ -d "$source_dir" ]] || return 0
    if [[ -n "$maxdepth" ]]; then
        find_args=("$source_dir" -maxdepth "$maxdepth" -type f -name "$PKG_PATTERN")
    fi
    find "${find_args[@]}" \
        ! -name '*debug*' ! -name '*dbgsym*' ! -name '*.src.*' \
        ! -name 'kwin-dev_*' ! -name 'kwin-devel-*' ! -name 'kwin-doc-*' \
        ! -name 'xorg-x11-server-Xwayland-devel-*' \
        -exec cp -v {} "$PACKAGE_DIR/" \;
}

if [[ "$BUILD_TARGET" == Arch ]]; then
    copy_packages_from "$OUTPUT_DIR"
else
    copy_packages_from "$OUTPUT_DIR/kwin"
    copy_packages_from "$OUTPUT_DIR/xwayland"
    copy_packages_from "$OUTPUT_DIR/xorg-x11-server-Xwayland"
fi

package_count="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$PKG_PATTERN" | wc -l)"
package_count="${package_count//[[:space:]]/}"
if [[ "$package_count" -eq 0 ]]; then
    copy_packages_from "$OUTPUT_DIR" 1
    package_count="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$PKG_PATTERN" | wc -l)"
    package_count="${package_count//[[:space:]]/}"
fi
if [[ "$package_count" -eq 0 ]]; then
    echo "No installable packages were collected for $BUILD_TARGET" >&2
    exit 1
fi

kwin_version="$(tr -d '[:space:]' < "$OUTPUT_DIR/.kwin-version")"
case "$kwin_version" in
    ''|*[!A-Za-z0-9.+~_-]*)
        echo "KWin version contains characters that cannot be used in a filename: $kwin_version" >&2
        exit 1
        ;;
esac

asset_name="${ASSET_PREFIX}${kwin_version}-${ASSET_ARCH}.tar.gz"
asset_path="$ASSET_DIR/$asset_name"
build_time="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf 'target=%s\nkwin_version=%s\nbuild_time=%s\n' \
    "$ARCHIVE_TARGET" "$kwin_version" "$build_time" > "$PACKAGE_DIR/.anland-kde-build-info"

find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$PKG_PATTERN" -exec cp -v {} "$INDEPENDENT_DIR/" \;

tar -C "$STAGING_ROOT" -czf "$asset_path" "anland-kde-packages/$ARCHIVE_TARGET"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        printf 'asset_path=%s\n' "$asset_path"
        printf 'asset_name=%s\n' "$asset_name"
        printf 'package_dir=%s\n' "$PACKAGE_DIR"
        printf 'independent_dir=%s\n' "$INDEPENDENT_DIR"
        printf 'package_count=%s\n' "$package_count"
        printf 'kwin_version=%s\n' "$kwin_version"
    } >> "$GITHUB_OUTPUT"
fi

printf 'Packed %s files into %s (build time: %s)\n' \
    "$package_count" "$asset_name" "$build_time"
printf 'Independent packages: %s\n' "$INDEPENDENT_DIR"
