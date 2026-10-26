<?php

declare(strict_types=1);

use Dixyes\Gem\Thread\ThreadConfig;

/*
 * Entry point of the single-file demo.
 *
 * The binary is the micro SAPI followed by an INI header and this phar. micro
 * hides the payload behind a stream on the binary path, so the phar has no
 * .phar path of its own; mapPhar publishes it as "gem.phar" for this thread.
 */
Phar::mapPhar('gem.phar');

function gemBase(): string
{
    static $base = null;
    if ($base !== null) {
        return $base;
    }

    $running = Phar::running(false);
    if ($running !== '') {
        return $base = 'phar://' . $running;
    }

    if (PHP_SAPI !== 'micro') {
        return $base = 'phar://' . __FILE__;
    }

    /*
     * Swow worker threads include the autoloader on their own, and the phar
     * alias is only registered in the thread that called mapPhar. Write the
     * payload to a real .phar file instead, every thread opens that by name.
     */
    if (!function_exists('micro_get_self_filename')) {
        fwrite(STDERR, "gem: the phar payload is not addressable\n");
        exit(1);
    }

    $payload = sys_get_temp_dir() . '/gem-demo-' . getmypid() . '-' . bin2hex(random_bytes(4)) . '.phar';
    $source = fopen(micro_get_self_filename(), 'rb');
    $target = $source === false ? false : fopen($payload, 'wb');
    if ($target === false || stream_copy_to_stream($source, $target) <= 0) {
        fwrite(STDERR, "gem: cannot unpack the phar payload to {$payload}\n");
        exit(1);
    }
    fclose($source);
    fclose($target);

    register_shutdown_function(static function () use ($payload): void {
        @unlink($payload);
    });

    return $base = 'phar://' . $payload;
}

function gemUsage(string $program): string
{
    return <<<TXT
usage: {$program} <command> [options]

commands:
  generate <model.gguf> [options]     generate tokens from a GGUF model
  chat <model.gguf> [options]         interactive chat session
  bench [size] [threads]              decode and square GEMM benchmark
  model                               reference GGUF model helper
  gemm [size] [threads]               square f32 GEMM benchmark
  gemv <format> [k] [n] [threads]     GEMV benchmark, format is f32, q4_0 or q8_0
  verify <vectors.txt>                check GEMM output against reference vectors
  inspect <tokenize|sample|compare>   inspect model data and logits
  version                             print runtime capabilities
  help                                print this text

A command without arguments prints its own usage.
TXT;
}

$program = basename($argv[0] ?? 'gem-demo');
$command = $argv[1] ?? null;

if ($command === null || $command === 'help' || $command === '-h' || $command === '--help') {
    echo gemUsage($program), "\n";
    exit(0);
}

if ($command === 'version') {
    require gemBase() . '/vendor/autoload.php';

    $status = function_exists('opcache_get_status') ? @opcache_get_status(false) : false;
    $jit = 'off';
    if (is_array($status) && ($status['jit']['on'] ?? false)) {
        $jit = match ($status['jit']['kind'] ?? null) {
            5 => 'on (tracing)',
            3 => 'on (function)',
            default => 'on',
        };
    }

    $threads = 'unknown';
    try {
        $threads = (string) ThreadConfig::defaultThreads();
    } catch (Throwable) {
        // keep the unknown marker, a missing topology is not a fatal error here
    }

    printf("SAPI: %s\n", PHP_SAPI);
    printf("PHP: %s (%s)\n", PHP_VERSION, PHP_ZTS ? 'ZTS' : 'NTS');
    printf("JIT: %s\n", $jit);
    printf("FFI: %s\n", extension_loaded('ffi') ? sprintf('on (ffi.enable=%s)', ini_get('ffi.enable')) : 'off');
    printf("swow: %s\n", extension_loaded('swow') ? (phpversion('swow') ?: 'loaded') : 'missing');
    printf("toy: %s\n", extension_loaded('toy') ? (phpversion('toy') ?: 'loaded') : 'missing');
    printf("default threads: %s\n", $threads);
    exit(0);
}

$binaries = [
    'generate' => 'generate.php',
    'chat' => 'chat.php',
    'bench' => 'bench.php',
    'model' => 'model.php',
    'gemm' => 'gemm.php',
    'gemv' => 'gemv.php',
    'verify' => 'verify.php',
    'inspect' => 'inspect.php',
];

if (!isset($binaries[$command])) {
    fwrite(STDERR, sprintf("unknown command: %s\n\n%s\n", $command, gemUsage($program)));
    exit(1);
}

// The entry scripts read the global argv, so hand them their own view of it
$GLOBALS['argv'] = array_merge([$binaries[$command]], array_slice($argv, 2));
$GLOBALS['argc'] = count($GLOBALS['argv']);

require gemBase() . '/bin/' . $binaries[$command];

__HALT_COMPILER();
