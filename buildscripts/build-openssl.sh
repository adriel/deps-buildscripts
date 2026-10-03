#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# OpenSSL provides the TLS backend for FFmpeg. Apple's SecureTransport (the
# previous backend) is deprecated and only supports up to TLS 1.2, so https
# servers that require TLS 1.3 could not be opened.
#
# Only static libraries are built. They are linked into libavformat, so no
# extra dylibs have to be bundled with IINA.

DEP_NAME="openssl"
VERSION="${OPENSSL_VERSION}"
TARBALL="${DEP_NAME}-${VERSION}.tar.gz"
SRC_DIR="${SOURCES_DIR}/${DEP_NAME}-${VERSION}"

build_for_arch() {
    local arch="$1"
    local prefix build_dir target
    prefix="$(get_prefix "$arch")"
    build_dir="$(get_build_dir "$DEP_NAME" "$arch")"

    case "$arch" in
        arm64)  target="darwin64-arm64-cc" ;;
        x86_64) target="darwin64-x86_64-cc" ;;
        *) echo "ERROR: Unknown arch: ${arch}" >&2; exit 1 ;;
    esac

    log_step "=== ${DEP_NAME} ${VERSION} — ${arch} ==="
    setup_arch_env "$arch"

    # OpenSSL does not support out-of-tree builds for every target, so work on
    # a per-arch copy of the source tree.
    rm -rf "$build_dir" && mkdir -p "$(dirname "$build_dir")"
    cp -R "$SRC_DIR" "$build_dir"
    cd "$build_dir"

    # Configure picks up CFLAGS/LDFLAGS (arch, deployment target, sysroot) from
    # the environment set by setup_arch_env.
    #
    # --openssldir=/etc/ssl makes the default CA bundle /etc/ssl/cert.pem,
    # which ships with macOS, so certificate verification works out of the box
    # when mpv's tls-verify is enabled.
    ./Configure "$target" \
        --prefix="$prefix" \
        --libdir=lib \
        --openssldir=/etc/ssl \
        no-shared \
        no-tests \
        no-apps \
        no-docs \
        -fPIC

    make -j"$JOBS" build_libs
    make install_dev
}

download_and_verify "$OPENSSL_URL" "$OPENSSL_SHA256" "$TARBALL"
extract_source "$TARBALL" "${DEP_NAME}-${VERSION}"
apply_patches "$DEP_NAME" "$SRC_DIR"

for arch in $ARCHS; do build_for_arch "$arch"; done
