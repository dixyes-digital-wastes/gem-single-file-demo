@echo off
buildconf.bat
if errorlevel 1 exit /b 1
configure.bat --disable-all --enable-micro=yes --enable-zts --disable-cgi --disable-cli --disable-phpdbg --enable-phar --with-ffi --with-php-build=..\deps --enable-curl --enable-swow --enable-swow-curl --enable-swow-ssl --disable-swow-pdo-pgsql
if errorlevel 1 exit /b 1
nmake micro LIBS_MICRO="libssl.lib libcrypto.lib libcurl.lib libssh2.lib nghttp2.lib zlibstatic.lib libffi.lib crypt32.lib wldap32.lib ws2_32.lib shell32.lib"
exit /b %ERRORLEVEL%
