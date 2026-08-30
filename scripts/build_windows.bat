@echo off
rem AudioShelf Windows 构建脚本
setlocal
cd /d "%~dp0.."

rem 中国镜像
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo ==^> flutter pub get
call flutter pub get
if errorlevel 1 goto :err

echo ==^> flutter build windows --release
call flutter build windows --release
if errorlevel 1 goto :err

echo.
echo 构建完成：build\windows\x64\runner\Release\
goto :eof

:err
echo 构建失败
exit /b 1
