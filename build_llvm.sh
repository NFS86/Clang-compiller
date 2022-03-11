#!/usr/bin/env bash

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

curl -s https://api.telegram.org/bot$TG_TOKEN/sendMessage -d "disable_web_page_preview=true" -d "parse_mode=html" -d chat_id=$TG_CHAT_ID -d text="<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$rel_friendly_date</code>%0A<b>Toolchain Script Commit : </b><code>$builder_commit</code>%0A"
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
