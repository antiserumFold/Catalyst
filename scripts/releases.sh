#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="$(grep -m1 '^VERSION' Makefile | sed 's/.*=\s*//' | tr -d '[:space:]')"
EXE="$(grep -m1 '^EXE' Makefile | sed 's/.*=\s*//' | tr -d '[:space:]')"
BIN_DIR="bin"
DIST_DIR="dist"

LINUX_TARGETS=(x86-64 avx2 bmi2 avx512 avx512vnni)
WIN_TARGETS=(x86-64 avx2 bmi2 avx512 avx512vnni)

usage() {
    echo "Usage: $0 [--linux] [--win] [--all] [--no-build] [--upload]"
    echo "  --linux     build and package Linux targets only"
    echo "  --win       build and package Windows targets only"
    echo "  --all       build and package all targets (default)"
    echo "  --no-build  skip building, only package existing binaries"
    echo "  --upload    create GitHub release and upload via gh CLI"
    exit 0
}

DO_LINUX=false
DO_WIN=false
DO_BUILD=true
DO_UPLOAD=false

for arg in "$@"; do
    case "$arg" in
        --linux)    DO_LINUX=true ;;
        --win)      DO_WIN=true ;;
        --all)      DO_LINUX=true; DO_WIN=true ;;
        --no-build) DO_BUILD=false ;;
        --upload)   DO_UPLOAD=true ;;
        --help|-h)  usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

if ! $DO_LINUX && ! $DO_WIN; then
    DO_LINUX=true
    DO_WIN=true
fi

die() { echo "ERROR: $*" >&2; exit 1; }

check_deps() {
    local missing=()
    command -v make    >/dev/null 2>&1 || missing+=(make)
    command -v zip     >/dev/null 2>&1 || missing+=(zip)
    if $DO_UPLOAD; then
        command -v gh  >/dev/null 2>&1 || missing+=(gh)
    fi
    [[ ${#missing[@]} -eq 0 ]] || die "Missing dependencies: ${missing[*]}"
}

build_targets() {
    echo "==> Building Catalyst v${VERSION}"

    if $DO_LINUX; then
        echo "--> Building Linux targets"
        make release-linux -j"$(nproc)"
    fi

    if $DO_WIN; then
        echo "--> Building Windows targets"
        make release-win -j"$(nproc)"
    fi
}

package_binary() {
    local binary="$1"
    local zip_name="$2"

    [[ -f "$binary" ]] || { echo "WARN: $binary not found, skipping"; return; }

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    cp "$binary" "$tmp_dir/"
    cp README.md "$tmp_dir/" 2>/dev/null || true
    cp LICENSE   "$tmp_dir/" 2>/dev/null || true

    local out="${DIST_DIR}/${zip_name}"
    zip -j "$out" "$tmp_dir"/* >/dev/null
    rm -rf "$tmp_dir"

    local size
    size="$(du -sh "$out" | cut -f1)"
    echo "    [ok] $zip_name  ($size)"
}

package_all() {
    echo "==> Packaging into ${DIST_DIR}/"
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    if $DO_LINUX; then
        echo "--> Packaging Linux"
        for target in "${LINUX_TARGETS[@]}"; do
            local binary="${BIN_DIR}/${EXE}-linux-${target}"
            local zip_name="${EXE}-v${VERSION}-linux-${target}.zip"
            package_binary "$binary" "$zip_name"
        done
    fi

    if $DO_WIN; then
        echo "--> Packaging Windows"
        for target in "${WIN_TARGETS[@]}"; do
            local binary="${BIN_DIR}/${EXE}-win-${target}.exe"
            local zip_name="${EXE}-v${VERSION}-win-${target}.zip"
            package_binary "$binary" "$zip_name"
        done
    fi
}

upload_release() {
    echo "==> Creating GitHub release v${VERSION}"

    local tag="v${VERSION}"
    local zips=("$DIST_DIR"/*.zip)

    [[ ${#zips[@]} -gt 0 && -f "${zips[0]}" ]] || die "No zips found in $DIST_DIR"

    if gh release view "$tag" >/dev/null 2>&1; then
        echo "--> Release $tag already exists, uploading assets"
        gh release upload "$tag" "${zips[@]}" --clobber
    else
        echo "--> Creating new release $tag"
        gh release create "$tag" \
            --title "Catalyst v${VERSION}" \
            --generate-notes \
            "${zips[@]}"
    fi

    echo "==> Release v${VERSION} done"
}

main() {
    check_deps

    echo "Catalyst Release Script"
    echo "Version : v${VERSION}"
    echo "Targets : Linux=${DO_LINUX}  Win=${DO_WIN}"
    echo "Build   : ${DO_BUILD}"
    echo "Upload  : ${DO_UPLOAD}"
    echo ""

    $DO_BUILD && build_targets
    package_all

    echo ""
    echo "Packages:"
    ls -lh "$DIST_DIR"/*.zip 2>/dev/null | awk '{print "  ", $NF, $5}'

    $DO_UPLOAD && upload_release

    echo ""
    echo "Done."
}

main