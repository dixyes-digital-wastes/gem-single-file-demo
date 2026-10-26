<?php

declare(strict_types=1);

/*
 * Pack the gem library and its entry scripts into one phar.
 *
 * The archive holds src/, bin/ and a generated PSR-4 autoloader only: no
 * tests, no models and no phpunit. Entries are stored uncompressed so the
 * micro SAPI can run the archive without the optional phar patch.
 */
if ((bool) ini_get('phar.readonly')) {
    fwrite(STDERR, "build-phar: phar.readonly is on, run php -d phar.readonly=0 build-phar.php\n");
    exit(1);
}

$root = __DIR__;
$source = $root . '/third_party/gem';
$target = $argv[1] ?? $root . '/build/gem.phar';

if (!is_file($source . '/src/Format.php')) {
    fwrite(STDERR, "build-phar: third_party/gem is missing, run git submodule update --init\n");
    exit(1);
}

if (!str_ends_with($target, '.phar')) {
    fwrite(STDERR, "build-phar: the target name must end with .phar\n");
    exit(1);
}

if (is_file($target)) {
    unlink($target);
}

if (!is_dir(dirname($target))) {
    mkdir(dirname($target), 0755, true);
}

$files = [];
foreach (['src', 'bin'] as $directory) {
    $base = $source . '/' . $directory;
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS),
    );
    foreach ($iterator as $file) {
        if (!$file->isFile()) {
            continue;
        }
        $relative = $directory . '/' . substr($file->getPathname(), strlen($base) + 1);
        $files[$relative] = $file->getPathname();
    }
}
ksort($files);

$phar = new Phar($target, 0, 'gem.phar');
$phar->startBuffering();

foreach ($files as $relative => $path) {
    $content = file_get_contents($path);
    if (str_starts_with($relative, 'bin/') && str_starts_with($content, '#!')) {
        // Entry scripts lose their shebang, the phar is never executed by a shell
        $content = substr($content, strpos($content, "\n") + 1);
    }
    $phar->addFromString($relative, $content);
}

$phar->addFromString('vendor/autoload.php', <<<'PHP'
<?php

declare(strict_types=1);

// Minimal PSR-4 autoloader for Dixyes\Gem\ inside the phar
$gemPrefix = 'Dixyes\\Gem\\';
$gemSource = dirname(__DIR__) . '/src/';

spl_autoload_register(static function (string $class) use ($gemPrefix, $gemSource): void {
    if (!str_starts_with($class, $gemPrefix)) {
        return;
    }

    $file = $gemSource . str_replace('\\', '/', substr($class, strlen($gemPrefix))) . '.php';
    if (is_file($file)) {
        require $file;
    }
});
PHP
);

$phar->setStub(file_get_contents($root . '/stub.php'));
$phar->setSignatureAlgorithm(Phar::SHA256);
$phar->stopBuffering();

printf("build-phar: %s, %d entries\n", $target, count($files) + 1);
