#!/usr/bin/env bash

set -eu

BASE=$(CIRRUS_WORKING_DIR "$(readlink -f "${0}")")

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Build Info
rel_date="$(date "+%Y%m%d")" # ISO 8601 format
rel_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
builder_commit="$(git rev-parse HEAD)"

function parse_parameters() {
    while ((${#})); do
        case ${1} in
            all | binutils | deps | kernel | llvm) ACTION=${1} ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
    do_kernel
}

function do_deps() {
    apt-get -y update && apt-get -y upgrade && apt-get -y install --no-install-recommends \
        bc \
        bison \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        flex \
        gcc \
        g++ \
        git \
        libelf-dev \
        libssl-dev \
        lld \
        make \
        ninja-build \
        python3 \
        texinfo \
        xz-utils \
        zlib1g-dev
}

function do_llvm() {
    msg "$LLVM_NAME: Building llvm..."
    ./build-llvm.py \
        --assertions \
        --clang-vendor "$LLVM_NAME" \
        --branch "main" \
        --incremental \
        --build-stage1-only \
        --check-targets clang lld llvm polly \
        --install-stage1-only \
        --projects "clang;lld;llvm;polly" \
        --shallow-clone \
        --targets "ARM;AArch64" \
        --build-type "Release" 2>&1 | tee build.log
}

function do_binutils() {
    msg "$LLVM_NAME: Building binutils..."
    ./build-binutils.py -t arm aarch64
}

parse_parameters "${@}"
do_"${ACTION:=all}"
