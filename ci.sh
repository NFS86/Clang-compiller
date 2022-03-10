#!/usr/bin/env bash

set -eu

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

function parse_parameters() {
    while ((${#})); do
        case ${1} in
            all | binutils | deps | llvm) ACTION=${1} ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
}

function do_deps() {
    apt-get -y install --no-install-recommends \
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
        libssl-dev \
        make \
        ninja-build \
        python3 \
        texinfo \
        xz-utils \
        zlib1g-dev
}

function do_llvm() {
    curl -s https://api.telegram.org/$TG_TOKEN/sendMessage -d "disable_web_page_preview=true" -d "parse_mode=html" -d chat_id=$TG_CHAT_ID -d text="<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$rel_friendly_date</code>%0A<b>Toolchain Script Commit : </b><code>$builder_commit</code>%0A"
    msg "$LLVM_NAME: Building llvm..."
    ./build-llvm.py \
        --clang-vendor "$LLVM_NAME" \
        --branch "main" \
        --projects "clang;lld;llvm;polly" \
        --targets "ARM;AArch64" \
        --shallow-clone \
        --incremental \
        --defines "LLVM_PARALLEL_COMPILE_JOBS=8 LLVM_PARALLEL_LINK_JOBS=8" \
        --build-type "Release" 2>&1 | tee build.log
}

function do_binutils() {
    msg "$LLVM_NAME: Building binutils..."
    ./build-binutils.py -t arm aarch64
}

parse_parameters "${@}"
do_"${ACTION:=all}"