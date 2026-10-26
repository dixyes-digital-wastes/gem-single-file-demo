#!/usr/bin/env bash
#
# Concatenate the micro SAPI, an INI header and the gem phar into one file.
#
# Layout: micro.sfx | magic | INI length | INI | gem.phar
#
# The micro SAPI finds the end of its own image (micro.sfx) through the ELF
# section headers, reads the INI block that follows, and executes the rest of
# the file as a phar payload.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build=$root/build
sfx=${SFX:-$build/php-src/sapi/micro/micro.sfx}
phar=${GEM_PHAR:-$build/gem.phar}
target=${TARGET:-$root/gem-demo-$(uname -s | tr "[:upper:]" "[:lower:]")-$(uname -m)}

fail() {
    echo "build-demo: $*" >&2
    exit 1
}

[ -f "$sfx" ] || fail "missing $sfx; run ./build-micro.sh first"
[ -f "$phar" ] || fail "missing $phar; run php -d phar.readonly=0 build-phar.php first"

# INI block read by the micro SAPI at startup
# register_argc_argv=0 keeps worker threads from deriving $_SERVER['argv'] from
# the empty query string, which PHP reports as deprecated
ini='opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=64M
ffi.enable=1
memory_limit=-1
register_argc_argv=0
'

length=${#ini}

{
    cat "$sfx"
    # magic MARK_INI, then the INI length as a big endian 32 bit value
    printf '\xfd\xf6\x69\xe6'
    printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
        $(((length >> 24) & 0xff)) \
        $(((length >> 16) & 0xff)) \
        $(((length >> 8) & 0xff)) \
        $((length & 0xff)))"
    printf '%s' "$ini"
    cat "$phar"
} > "$target"

chmod 0755 "$target"

expected=$(( $(wc -c < "$sfx") + 8 + length + $(wc -c < "$phar") ))
actual=$(wc -c < "$target")
[ "$actual" -eq "$expected" ] || fail "size mismatch: $actual != $expected"

echo "build-demo: $target ($actual bytes, ini $length bytes)"
