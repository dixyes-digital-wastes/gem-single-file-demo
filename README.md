# gem-single-file-demo

A single-file PHP demo binary for the gem GEMM and GEMV kernels. One executable
contains the PHP micro SAPI, an INI block and a phar archive: no PHP shared
objects, no extension directory, no model files.

The inputs are pinned as submodules:

| path | repository | commit |
| --- | --- | --- |
| `third_party/php-src` | https://github.com/php/php-src | `4a51e519d7199bd80be1660b167179386c76aa48` |
| `third_party/micro` | https://github.com/dixyes/phpmicro | `ccdfa7cc16f12aa86444a014b32cf501d2cf0697` |
| `third_party/swow` | https://github.com/swow/swow | `691a2ced3072a7e3cd983a6863e74dc76169391c` |
| `third_party/gem` | https://github.com/dixyes-digital-wastes/gem | `280b4e458bf055530eaa941e4bd4e2de38a5dc66` |
| `third_party/ext-toy` | https://github.com/dixyes-digital-wastes/ext-toy | `739ab0275923f3bfdb3a18bf88b14a16d7ceef08` |

## Requirements

- Linux x86_64
- gcc with C23 support, make, autoconf, bison, re2c, patch, pkg-config
- libffi and zlib development headers
- PHP 8.4 or newer with the phar extension for `build-phar.php`

## Build

```bash
git clone --recurse-submodules <repository> gem-single-file-demo
cd gem-single-file-demo

./build-micro.sh                        # static micro SAPI with swow and toy
php -d phar.readonly=0 build-phar.php   # build/gem.phar
./build-demo.sh                         # gem-demo-linux-x86_64
```

`build-micro.sh` copies `third_party/php-src` into `build/php-src`, so the
submodule working trees stay untouched. The build tree is rebuilt from scratch
on every run; set `JOBS` to limit the parallelism.

Configure switches of the micro build: ZTS, `--enable-micro`, `--disable-all`,
`--disable-cgi`, `--disable-cli`, `--disable-phpdbg`, `--enable-phar`,
`--with-zlib`, `--with-ffi`, `--enable-swow` and `--enable-toy`. The optional
swow transports (cURL, OpenSSL, PDO pgsql) are disabled, the demo needs the
thread and shared memory API only.

Two build adjustments are applied to the copy under `build/` only:

- `patches/php-jit-24635.patch` carries the upstream tracing JIT fix for a
  stale stack slot read at a side exit.
- `third_party/ext-toy/config.m4` resolves its generated headers against
  `$abs_srcdir`, which is the PHP root for an in-tree build. The copy is
  rewritten to `@ext_srcdir@` so `codegen/include` is found.

opcache needs no configure switch: since PHP 8.5 it is always built into the
binary, and only its JIT options are configured.

## Run

```bash
./gem-demo-linux-x86_64 version
./gem-demo-linux-x86_64 gemm 256 2
./gem-demo-linux-x86_64 gemv q8_0 64 128 2
```

Every other command is forwarded to the matching entry script of the gem
package: `generate`, `chat`, `bench`, `model`, `verify` and `inspect`. The
model commands need a GGUF file, no model is embedded in the binary.

## Binary layout

```
micro.sfx | fd f6 69 e6 | 00 00 00 78 | INI text | gem.phar
```

`gem-demo-linux-x86_64` is the `micro.sfx` executable followed by one INI block
and the phar archive. The micro SAPI finds the end of its own ELF image, reads
the INI block, and executes the remaining bytes as a phar payload. The INI
header is the four byte magic `fd f6 69 e6` and the INI length as a big endian
32 bit value. No micro source file is modified to get this layout.

The embedded INI block:

```ini
opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=64M
ffi.enable=1
memory_limit=-1
register_argc_argv=0
```

`register_argc_argv=0` keeps worker threads from deriving `$_SERVER['argv']`
from the empty query string. micro passes the real argument vector to the main
script, so `$argv` is still populated there.

The phar holds `src/`, `bin/` and a generated PSR-4 autoloader for
`Dixyes\Gem\`. Entry scripts are stored without their shebang, and tests,
models and phpunit are not packed. Entries are uncompressed so the demo needs
no phar patch.

### Payload access from worker threads

The gem benchmarks start Swow worker threads that include the autoloader
themselves. A phar alias registered by `Phar::mapPhar` belongs to one thread,
and the binary path has no `.phar` suffix, so such a thread cannot open the
payload through the alias.

The stub therefore writes the payload to a temporary `.phar` file and includes
everything from that path, which every thread can open by name. The file is
removed at shutdown; only its size (the phar, about 260 KB) is written, the
payload itself stays part of the binary. `Phar::mapPhar` still publishes the
payload as `gem.phar` for the main thread.

The unpacking happens only under the micro SAPI. `php build/gem.phar <command>`
keeps its own `.phar` path and writes nothing.

## Expected output

```console
$ ./gem-demo-linux-x86_64 version
SAPI: micro
PHP: 8.7.0-dev (ZTS)
JIT: on (tracing)
FFI: on (ffi.enable=1)
swow: 2.0.0-dev
toy: 0.1.0
default threads: 4
```

## Windows preview

A Windows x86_64 preview is built from the same `micro.sfx` layout:

```bat
gem-demo-windows-x86_64.exe version
gem-demo-windows-x86_64.exe gemm 256 2
gem-demo-windows-x86_64.exe gemv q8_0 64 128 2
```

It includes ZTS, opcache tracing JIT, FFI, swow and toy. The Windows build
uses the PHP SDK toolchain and MSVC; the preview does not yet have a checked-in
build script.

## Continuous integration

`.github/workflows/build.yml` has separate Linux, macOS and Windows jobs.
Linux is the reference build. The macOS universal package combines x86_64 and
arm64 micro artifacts with `lipo`. The Windows job is still being brought up.

## Limitations

- Linux x86_64 is the reference target. Windows x86_64 has a working preview;
  macOS universal is not finished.
- PHP and its extensions are linked into the binary; libc, libm, libz and
  libffi are still resolved from the host system.
- The unpacked payload needs a writable temporary directory.
