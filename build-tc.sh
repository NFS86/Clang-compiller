#!/usr/bin/env bash

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Inlined function to post a message
export BOT_MSG_URL="https://api.telegram.org/bot$TG_TOKEN/sendMessage"
tg_post_msg() {
	curl -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" \
	-d "disable_web_page_preview=true" \
	-d "parse_mode=html" \
	-d text="$1"

}
tg_post_build() {
	curl --progress-bar -F document=@"$1" "$BOT_MSG_URL" \
	-F chat_id="$TG_CHAT_ID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=html" \
	-F caption="$3"
}

# Build Info
rel_date="$(date "+%Y%m%d")" # ISO 8601 format
rel_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
builder_commit="$(git rev-parse HEAD)"

# Send a notificaton to TG
tg_post_msg "<b>$LLVM_NAME: Toolchain Compilation Started</b>%0A<b>Date : </b><code>$rel_friendly_date</code>%0A<b>Toolchain Script Commit : </b><code>$builder_commit</code>%0A"

# Build LLVM
msg "$LLVM_NAME: Building LLVM..."
tg_post_msg "<b>$LLVM_NAME: Building LLVM. . .</b>"
./build-llvm.py \
	--clang-vendor "$LLVM_NAME" \
        --branch "main" \
	--projects "clang;lld;polly" \
	--targets "ARM;AArch64" \
	--defines "LLVM_PARALLEL_COMPILE_JOBS=8 LLVM_PARALLEL_LINK_JOBS=4" \
	--shallow-clone \
	--incremental \
	--build-type "Release" 2>&1 | tee build.log

# Check if the final clang binary exists or not.
[ ! -f install/bin/clang-1* ] && {
	err "Building LLVM failed ! Kindly check errors !!"
	tg_post_build "build.log" "$TG_CHAT_ID" "Error Log"
	exit 1
}

# Build binutils
msg "$LLVM_NAME: Building binutils..."
tg_post_msg "<b>$LLVM_NAME: Building Binutils. . .</b>"
./build-binutils.py --targets arm aarch64

# Remove unused products
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

tg_post_msg "<b>$LLVM_NAME: Toolchain compilation Finished</b>%0A<b>Clang Version : </b><code>$clang_version</code>%0A<b>LLVM Commit : </b>$llvm_commit_url%0A<b>Binutils Version : </b><code>$binutils_ver</code>"

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
tg_post_msg "<b>$LLVM_NAME: Toolchain pushed to </b>https://$GH_PUSH_REPO_URL"
