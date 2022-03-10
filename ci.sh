#!/usr/bin/env bash

set -eu

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

tg_post_build() {
	curl --progress-bar -F document=@"$1" "$BOT_MSG_URL" \
	-F chat_id="$TG_CHAT_ID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=html" \
	-F caption="$3"
}

function parse_parameters() {
    rel_date="$(date "+%Y%m%d")" # ISO 8601 format
    rel_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
    builder_commit="$(git rev-parse HEAD)"
    while ((${#})); do
        case ${1} in
            all | binutils | deps | push | llvm) ACTION=${1} ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
    do_push
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
    curl -s https://api.telegram.org/$TG_TOKEN/sendMessage -d "disable_web_page_preview=true" -d "parse_mode=html" -d chat_id=$TG_CHAT_ID -d text="<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$rel_friendly_date</code>%0A<b>Toolchain Script Commit : </b><code>$builder_commit</code>%0A"
    msg "$LLVM_NAME: Building llvm..."
    ./build-llvm.py \
        --assertions \
        --clang-vendor "$LLVM_NAME" \
        --branch "main" \
        --incremental \
        --build-stage1-only \
        --install-stage1-only \
        --projects "clang;lld;llvm;polly" \
        --shallow-clone \
        --targets "ARM;AArch64" \
        --defines "LLVM_PARALLEL_COMPILE_JOBS=8 LLVM_PARALLEL_LINK_JOBS=8"
        --build-type "Release" 2>&1 | tee build.log
    
    [ ! -f install/bin/clang-1* ] && {
	err "Building LLVM failed ! Kindly check errors !!"
	tg_post_build "build.log" "$TG_CHAT_ID" "Error Log"
	exit 1
}

function do_binutils() {
    msg "$LLVM_NAME: Building binutils..."
    ./build-binutils.py -t arm aarch64
}

function do_push() {
    rm -fr install/include
    rm -f install/lib/*.a install/lib/*.la
    # Strip remaining products
    for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	    strip -s "${f: : -1}"
    done

    # Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
    for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	    bin="${bin: : -1}"

	    echo "$bin"
	    patchelf --set-rpath "$DIR/install/lib" "$bin"
    done

    # Release Info
    pushd llvm-project
    llvm_commit="$(git rev-parse HEAD)"
    short_llvm_commit="$(cut -c-8 <<< "$llvm_commit")"
    popd

    llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
    binutils_ver="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
    clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

    curl -s https://api.telegram.org/$TG_TOKEN/sendMessage -d "disable_web_page_preview=true" -d "parse_mode=html" -d chat_id=$TG_CHAT_ID -d text="<b>$LLVM_NAME: Toolchain compilation Finished</b>%0A<b>Clang Version : </b><code>$clang_version</code>%0A<b>LLVM Commit : </b>$llvm_commit_url%0A<b>Binutils Version : </b><code>$binutils_ver</code>"

    # Push to GitHub
    # Update Git repository
    git config --global user.name $GH_USERNAME
    git config --global user.email $GH_EMAIL
    git clone https://$GH_USERNAME:$GH_TOKEN@$GH_PUSH_REPO_URL rel_repo
    pushd rel_repo
    rm -fr ./*
    cp -r ../install/* .
    echo "# $LLVM_NAME Clang $clang_version" >> README.md
    git add . -f
    git commit -asm "Release $LLVM_NAME Clang Bump $(/bin/date)
    Build completed on:  $(/bin/date)

    LLVM commit: $llvm_commit_url
    Clang Version: $clang_version
    Binutils version: $binutils_ver
    Builder commit: https://$GH_PUSH_REPO_URL/commit/$builder_commit"
    git gc
    git push origin main -f
    popd
    curl -s https://api.telegram.org/$TG_TOKEN/sendMessage -d "disable_web_page_preview=true" -d "parse_mode=html" -d chat_id=$TG_CHAT_ID -d text="<b>$LLVM_NAME: Toolchain pushed to </b>https://$GH_PUSH_REPO_URL"
}

parse_parameters "${@}"
do_"${ACTION:=all}"
