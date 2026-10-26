#!/usr/bin/env bash
#
# Build a static PHP micro SAPI binary from the pinned submodules.
#
# The submodule working trees are never modified. Everything happens in a copy
# below build/.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build=$root/build
tree=$build/php-src
if [ -n "${JOBS:-}" ]; then
    jobs=$JOBS
elif command -v nproc >/dev/null 2>&1; then
    jobs=$(nproc)
else
    jobs=$(sysctl -n hw.ncpu)
fi

fail() {
    echo "build-micro: $*" >&2
    exit 1
}

need() {
    [ -e "$1" ] || fail "missing $1; run git submodule update --init"
}

need "$root/third_party/php-src/configure.ac"
need "$root/third_party/micro/php_micro.c"
need "$root/third_party/swow/ext/config.m4"
need "$root/third_party/ext-toy/config.m4"
need "$root/patches/php-jit-24635.patch"

echo "build-micro: copying the PHP source tree"
rm -rf "$tree"
mkdir -p "$build"
cp -a "$root/third_party/php-src" "$tree"
rm -rf "$tree/.git"

echo "build-micro: applying the tracing JIT fix"
patch -d "$tree" -p1 --batch --no-backup-if-mismatch --forward \
    -i "$root/patches/php-jit-24635.patch"

echo "build-micro: installing the micro SAPI"
cp -a "$root/third_party/micro" "$tree/sapi/micro"
rm -rf "$tree/sapi/micro/.git"
patch -d "$tree" -p1 --batch --no-backup-if-mismatch --forward \
    -i "$tree/sapi/micro/patches/cli_checks_87.patch"
patch -d "$tree" -p1 --batch --no-backup-if-mismatch --forward \
    -i "$tree/sapi/micro/patches/disable_huge_page_84.patch"

echo "build-micro: installing the swow and toy extensions"
cp -a "$root/third_party/swow/ext" "$tree/ext/swow"
rm -rf "$tree/ext/swow/.git"
cp -a "$root/third_party/ext-toy" "$tree/ext/toy"
rm -rf "$tree/ext/toy/.git"
# ext-toy points its codegen headers at $abs_srcdir, which is the PHP source
# root in an in-tree build. @ext_srcdir@ makes the path follow the extension.
# Only the copy under build/ is rewritten.
sed -i.bak 's#-I\$abs_srcdir/codegen/include#-I@ext_srcdir@/codegen/include#' "$tree/ext/toy/config.m4"
rm -f "$tree/ext/toy/config.m4.bak"
grep -q '@ext_srcdir@/codegen/include' "$tree/ext/toy/config.m4" ||
    fail "ext-toy codegen header path was not rewritten"

cd "$tree"
echo "build-micro: running buildconf"
./buildconf --force

curl_args=()
if [ "${WITH_CURL:-0}" = 1 ]; then
    echo "build-micro: enabling the curl extension"
    curl_args+=(--with-curl)
fi

if [ "${SWOW_CURL:-0}" = 1 ]; then
    echo "build-micro: enabling swow curl"
    swow_args+=(--enable-swow-curl)
else
    swow_args+=(--disable-swow-curl)
fi
if [ "${SWOW_SSL:-0}" = 1 ]; then
    echo "build-micro: enabling swow ssl"
    swow_args+=(--enable-swow-ssl)
else
    swow_args+=(--disable-swow-ssl)
fi

# opcache is unconditional since PHP 8.5, so only its JIT toggle is relevant.
echo "build-micro: running configure"
./configure \
    --prefix="$build/install" \
    --enable-zts \
    --enable-micro=yes \
    --disable-all \
    --disable-cgi \
    --disable-cli \
    --disable-phpdbg \
    --enable-phar \
    --with-zlib \
    --with-ffi \
    --enable-swow \
    --disable-swow-pdo-pgsql \
    --enable-toy \
    "${curl_args[@]}" \
    "${swow_args[@]}"

if [ -n "${STATIC_LIBS_TAIL:-}" ]; then
    echo "build-micro: appending static library tail"
    awk -v extra="$STATIC_LIBS_TAIL" '
        /^EXTRA_LIBS =/ { $0 = $0 " " extra }
        { print }
    ' Makefile > Makefile.static && mv Makefile.static Makefile
fi

echo "build-micro: running make -j$jobs micro"
make -j"$jobs" micro

[ -x "$tree/sapi/micro/micro.sfx" ] || fail "micro.sfx was not produced"
echo "build-micro: $tree/sapi/micro/micro.sfx"
