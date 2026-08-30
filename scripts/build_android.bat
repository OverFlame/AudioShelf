@echo off
rem ============================================================
rem  AudioShelf Android 构建脚本（Windows）
rem  前提：Flutter 已加入 PATH、JDK 17+、Android SDK 已安装
rem ============================================================
setlocal
cd /d "%~dp0.."

rem 中国镜像
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

rem Android SDK 路径：优先用已设置的环境变量，否则默认 D:\Android\sdk
if "%ANDROID_HOME%"=="" set "ANDROID_HOME=D:\Android\sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

echo ==^> flutter pub get
call flutter pub get
if errorlevel 1 goto :err

echo ==^> flutter build apk --release
call flutter build apk --release
if errorlevel 1 goto :err

echo.
echo 构建完成：build\app\outputs\flutter-apk\app-release.apk
goto :eof

:err
echo 构建失败（退出码 %errorlevel%）
exit /b 1
