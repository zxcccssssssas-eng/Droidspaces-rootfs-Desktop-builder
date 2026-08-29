#!/usr/bin/env bash
# Shared target metadata for independent Anland KWin/Xwayland package builds.
# Target IDs match the GitHub Actions matrix: ubuntu2604, Debian13, Fedora43,
# Fedora44, and Arch.

kde_package_known_targets() {
    printf '%s\n' ubuntu2604 Debian13 Fedora43 Fedora44 Arch
}

kde_package_targets_json() {
    local requested="${1:-all}"
    case "$requested" in
        all)
            printf '%s\n' '["ubuntu2604","Debian13","Fedora43","Fedora44","Arch"]'
            ;;
        ubuntu2604|Debian13|Fedora43|Fedora44|Arch)
            printf '["%s"]\n' "$requested"
            ;;
        *)
            return 1
            ;;
    esac
}

kde_package_resolve() {
    local target="${1:-}"

    KDE_PACKAGE_IMAGE=""
    KDE_PACKAGE_SCRIPT=""
    KDE_PACKAGE_PATTERN=""
    KDE_PACKAGE_ASSET_PREFIX=""
    KDE_PACKAGE_ASSET_ARCH=""
    KDE_PACKAGE_ARCHIVE_TARGET=""
    KDE_PACKAGE_LABEL=""

    case "$target" in
        ubuntu2604)
            KDE_PACKAGE_IMAGE="ubuntu:26.04"
            KDE_PACKAGE_SCRIPT="producers/kde/ubuntu2604_v5/build.sh"
            KDE_PACKAGE_PATTERN='*.deb'
            KDE_PACKAGE_ASSET_PREFIX="anland-kde-ubuntu2604-kwin-"
            KDE_PACKAGE_ASSET_ARCH="arm64"
            KDE_PACKAGE_ARCHIVE_TARGET="ubuntu2604"
            KDE_PACKAGE_LABEL="Ubuntu 26.04"
            ;;
        Debian13)
            KDE_PACKAGE_IMAGE="debian:trixie"
            KDE_PACKAGE_SCRIPT="producers/kde/Debian13_v5/build.sh"
            KDE_PACKAGE_PATTERN='*.deb'
            KDE_PACKAGE_ASSET_PREFIX="anland-kde-debian13-kwin-"
            KDE_PACKAGE_ASSET_ARCH="arm64"
            KDE_PACKAGE_ARCHIVE_TARGET="debian13"
            KDE_PACKAGE_LABEL="Debian 13"
            ;;
        Fedora43)
            KDE_PACKAGE_IMAGE="fedora:43"
            KDE_PACKAGE_SCRIPT="producers/kde/Fedora43_v5/build.sh"
            KDE_PACKAGE_PATTERN='*.rpm'
            KDE_PACKAGE_ASSET_PREFIX="anland-kde-fedora43-kwin-"
            KDE_PACKAGE_ASSET_ARCH="aarch64"
            KDE_PACKAGE_ARCHIVE_TARGET="fedora43"
            KDE_PACKAGE_LABEL="Fedora 43"
            ;;
        Fedora44)
            KDE_PACKAGE_IMAGE="fedora:44"
            # Fedora 44 reuses the Fedora 43 Anland producer with a Fedora 44 image.
            KDE_PACKAGE_SCRIPT="producers/kde/Fedora43_v5/build.sh"
            KDE_PACKAGE_PATTERN='*.rpm'
            KDE_PACKAGE_ASSET_PREFIX="anland-kde-fedora44-kwin-"
            KDE_PACKAGE_ASSET_ARCH="aarch64"
            KDE_PACKAGE_ARCHIVE_TARGET="fedora44"
            KDE_PACKAGE_LABEL="Fedora 44"
            ;;
        Arch)
            KDE_PACKAGE_IMAGE="ogarcia/archlinux:latest"
            KDE_PACKAGE_SCRIPT="producers/kde/Arch_v5/build.sh"
            KDE_PACKAGE_PATTERN='*.pkg.tar.*'
            KDE_PACKAGE_ASSET_PREFIX="anland-kde-arch-kwin-"
            KDE_PACKAGE_ASSET_ARCH="aarch64"
            KDE_PACKAGE_ARCHIVE_TARGET="arch"
            KDE_PACKAGE_LABEL="Arch Linux"
            ;;
        *)
            return 1
            ;;
    esac
}

kde_package_is_deb_target() {
    case "${1:-}" in
        Debian13|ubuntu2604) return 0 ;;
        *) return 1 ;;
    esac
}

kde_package_write_github_output() {
    local target="${1:-}"
    local output_file="${2:-${GITHUB_OUTPUT:-}}"

    kde_package_resolve "$target" || return 1
    [[ -n "$output_file" ]] || return 1

    {
        printf 'image=%s\n' "$KDE_PACKAGE_IMAGE"
        printf 'script=%s\n' "$KDE_PACKAGE_SCRIPT"
        printf 'package_pattern=%s\n' "$KDE_PACKAGE_PATTERN"
        printf 'asset_prefix=%s\n' "$KDE_PACKAGE_ASSET_PREFIX"
        printf 'asset_arch=%s\n' "$KDE_PACKAGE_ASSET_ARCH"
        printf 'archive_target=%s\n' "$KDE_PACKAGE_ARCHIVE_TARGET"
        printf 'label=%s\n' "$KDE_PACKAGE_LABEL"
    } >> "$output_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    expected_count=0
    while IFS= read -r target; do
        kde_package_resolve "$target"
        [[ -n "$KDE_PACKAGE_IMAGE" ]]
        [[ -n "$KDE_PACKAGE_SCRIPT" ]]
        [[ -n "$KDE_PACKAGE_PATTERN" ]]
        [[ -n "$KDE_PACKAGE_ASSET_PREFIX" ]]
        [[ -n "$KDE_PACKAGE_ASSET_ARCH" ]]
        [[ -n "$KDE_PACKAGE_ARCHIVE_TARGET" ]]
        expected_count=$((expected_count + 1))
    done < <(kde_package_known_targets)
    [[ "$expected_count" -eq 5 ]]
    [[ "$(kde_package_targets_json all)" == '["ubuntu2604","Debian13","Fedora43","Fedora44","Arch"]' ]]
    [[ "$(kde_package_targets_json Debian13)" == '["Debian13"]' ]]
    kde_package_is_deb_target Debian13
    kde_package_is_deb_target ubuntu2604
    ! kde_package_is_deb_target Arch
    ! kde_package_resolve not-a-target
    printf 'kde-package-config self-test passed (%s targets)\n' "$expected_count"
fi
