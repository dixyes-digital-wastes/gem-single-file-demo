param(
    [string]$Sfx = "build/php-src/x64/Release_TS/micro.sfx",
    [string]$Phar = "build/gem.phar",
    [string]$Target = "gem-demo-windows-x86_64.exe"
)

$ErrorActionPreference = "Stop"
$ini = "opcache.enable=1`nopcache.enable_cli=1`nopcache.jit=tracing`nopcache.jit_buffer_size=64M`nffi.enable=1`nmemory_limit=-1`nregister_argc_argv=0`n"
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $Sfx))
$pharBytes = [IO.File]::ReadAllBytes((Resolve-Path $Phar))
$iniBytes = [Text.Encoding]::ASCII.GetBytes($ini)
$header = [byte[]](0xfd, 0xf6, 0x69, 0xe6, (($iniBytes.Length -shr 24) -band 0xff), (($iniBytes.Length -shr 16) -band 0xff), (($iniBytes.Length -shr 8) -band 0xff), ($iniBytes.Length -band 0xff))
$out = New-Object IO.MemoryStream
$out.Write($bytes, 0, $bytes.Length)
$out.Write($header, 0, $header.Length)
$out.Write($iniBytes, 0, $iniBytes.Length)
$out.Write($pharBytes, 0, $pharBytes.Length)
[IO.File]::WriteAllBytes((Join-Path (Get-Location) $Target), $out.ToArray())
Write-Output "$Target $($out.Length)"
