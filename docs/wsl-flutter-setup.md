# 本机 WSL 环境搭建 Flutter 工具链

适用机器：`HoshikawaPC-00`，Ubuntu 26.04.1 LTS，WSL2，systemd 已开，WSLg 可用。
目标：能跑 `flutter analyze` 与 `flutter test`，并可选构建 Linux 桌面版与 Android APK。

## 0. 已探明的事实

| 项目 | 实测值 |
|---|---|
| 系统 | Ubuntu 26.04.1 LTS（resolute），amd64 |
| 内核 | 6.6.87.2-microsoft-standard-WSL2 |
| glibc | 2.43 |
| 内存 / 磁盘 | 15 GiB / 根分区可用 947 GB |
| 图形 | WSLg 已启用（`DISPLAY=:0`、`WAYLAND_DISPLAY=wayland-0`） |
| `/dev/dri` | **不存在**，无 GPU 直通 |
| `/dev/kvm` | 存在，嵌套虚拟化已开 |
| sudo | 需要交互输入密码，脚本无法免密 |
| 登录 shell | `/usr/bin/zsh`，oh-my-zsh 装在 `~/.oh-my-zsh`；`~/.zshrc` 存在，`~/.zshenv` 与 `~/.zprofile` 不存在 |
| dsh bash 工具 | `bash -c`（Bash 5.3.9），不读 zsh 的启动文件 |
| 网络 | `storage.googleapis.com` 200、`pub.dev` 200、`dl.google.com` 200、`archive.ubuntu.com` 200 |
| 已有 | git、curl、wget、unzip、tar、xz、make、g++、python3、node v22.23.3 |
| 缺失 | flutter、dart、clang、cmake、ninja、pkg-config、zip、java、adb、GTK3 开发包 |

Flutter 官方源与国内镜像都可访问，**默认走官方源即可**。

本项目要求：

- `pubspec.yaml` 的 `environment.sdk: ^3.12.0`
- README 声明 Flutter 3.47
- 当前最新 stable 是 **Flutter 3.47.5（Dart 3.13.4）**，满足要求

## 1. 装系统依赖（约 3 到 6 分钟）

```bash
sudo apt update
sudo apt install -y \
  curl git unzip zip xz-utils \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev
```

这些是 `flutter build linux` 与 `flutter test` 需要的。`flutter analyze` 与 `flutter test` 本身不需要图形环境。

## 2. 装 Flutter SDK（约 10 到 20 分钟）

```bash
cd ~
curl -fL -o flutter_3.47.5.tar.xz \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
tar -xf flutter_3.47.5.tar.xz -C ~
rm flutter_3.47.5.tar.xz
```

解压后 SDK 位于 `~/flutter`。

写进 PATH。本机登录 shell 是 zsh（oh-my-zsh），所以写 `~/.zshenv`：

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshenv
source ~/.zshenv
```

用 `~/.zshenv` 而不是 `~/.zshrc`，理由有两个：`~/.zshenv` 被所有 zsh 实例读取，包括非交互脚本；oh-my-zsh 不碰这个文件，不会与插件冲突。本机 `~/.zshenv` 原本不存在，追加即可。

若你更愿意写在 `~/.zshrc`，也能用，但那只有交互式 zsh 读得到。

首次运行会下载 Dart SDK（约 5 到 15 分钟）：

```bash
flutter config --no-analytics
flutter --version
```

期望输出包含 `Flutter 3.47.5` 与 `Dart 3.13.4`。

**不要用 snap 装 Flutter。** WSL 下 snap 的挂载与 systemd 交互不可靠。

### 下载慢时改用镜像

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

镜像可用性已实测：`storage.flutter-io.cn` 200，`pub.flutter-io.cn` 200。
追加到 `~/.zshenv` 可长期生效。项目的 `scripts/build_linux.sh` 已内置这两个变量。

## 3. 验证（约 5 到 10 分钟）

```bash
flutter doctor -v
```

必须出现 `[✓] Linux toolchain - develop for Linux desktop`。
`[!] Android toolchain` 在第 5 节之前可以忽略。

```bash
cd ~/code/AudioShelf
flutter pub get
flutter analyze
flutter test -r expanded
```

`flutter pub get` 会拉取 provider、sqflite、sqflite_common_ffi、flutter_soloud、audio_metadata_reader 等依赖。`flutter_soloud` 从源码编译，首次较慢。

`pubspec.yaml` 里有 `hooks: user_defines: sqlite3: source: system` 一段。若 `pub get` 对它报错，先把完整报错贴出来，**不要删掉这段**：它是为了避免从 GitHub 下载 sqlite3 预编译二进制。

## 4. 跑 Linux 桌面版（可选，约 5 分钟）

```bash
cd ~/code/AudioShelf
export NO_XIPH_LIBS=1
flutter run -d linux
```

`NO_XIPH_LIBS=1` 是必须的。本机 glibc 是 2.43，`flutter_soloud` 打包的 `libopus` 在更高 glibc 上编译，不禁用会在运行时加载报错。`scripts/build_linux.sh` 已内置该变量。

`/dev/dri` 不存在，WSLg 无 GPU 直通，界面可能走软件渲染而偏慢。若窗口起不来，加：

```bash
export LIBGL_ALWAYS_SOFTWARE=1
```

跑 `flutter analyze` 与 `flutter test` 不需要这一步。

## 5. 装 Android 工具链（可选，约 30 到 60 分钟）

项目要求 JDK 17（`android/app/build.gradle.kts` 里 `JavaVersion.VERSION_17` 与 Kotlin `JVM_17`）。

```bash
sudo apt install -y openjdk-17-jdk
```

装 SDK 命令行工具：

```bash
mkdir -p ~/Android/Sdk/cmdline-tools
cd ~/Android/Sdk/cmdline-tools
curl -fL -o clt.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip -q clt.zip
mv cmdline-tools latest
rm clt.zip
```

写环境变量（同样进 `~/.zshenv`）：

```bash
cat >> ~/.zshenv <<'EOF'
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
EOF
source ~/.zshenv
```

先读出本项目实际需要的版本号，不要凭猜：

```bash
grep -n "ndkVersion\|compileSdkVersion\|minSdkVersion\|targetSdkVersion" \
  "$HOME/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
```

然后用 `sdkmanager` 装包。`cmake;3.30.5` 是 `android/app/build.gradle.kts` 里写死的版本（NDK r28 与 Flutter 默认的 CMake 3.22.1 不兼容）：

```bash
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
  "cmake;3.30.5" "ndk;<上一步 grep 出来的 ndkVersion>"
```

构建：

```bash
cd ~/code/AudioShelf
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter build apk --release
```

`android/settings.gradle.kts` 与 `android/gradle/wrapper/gradle-wrapper.properties` 已内置阿里云、腾讯镜像。腾讯的 Gradle 9.3.1 发行包已实测可下载（200）。

### 装到真机

WSL2 里用无线调试最省事。手机开「无线调试」后：

```bash
adb pair <手机IP>:<配对端口>
adb connect <手机IP>:<调试端口>
adb devices
flutter run -d <设备号>
```

`/dev/kvm` 存在，理论上能跑 Android 模拟器，但需要额外装 system image 且模拟器在 WSL2 里仍需图形加速，不如直接用真机。

## 6. WSL 专项注意

1. **项目必须留在 ext4 上。** 当前路径 `/home/hoshi/code/AudioShelf` 正确。放到 `/mnt/c` 下会让 `pub get`、Gradle、`flutter test` 慢几倍到几十倍。
2. **Flutter SDK 也放 ext4。** `~/flutter` 正确，不要放 `/mnt/c`。
3. **不要动 `/etc/wsl.conf`。** `systemd=true`、`appendWindowsPath=false`、默认用户 `hoshi` 都已配好。
4. **不要用 snap。** 用 apt 与官方 tarball。
5. **不要为了生效去重启 WSL。** 装完工具链后新开一个终端，或 `source ~/.zshenv` 即可。
6. **非交互式 bash 读不到 `~/.zshenv`。** 本机登录 shell 是 zsh（`SHELL=/usr/bin/zsh`，oh-my-zsh 装在 `~/.oh-my-zsh`），但 dsh 的 bash 工具跑的是 `bash -c`（Bash 5.3.9），它只继承父进程环境，不读 `~/.zshrc`、不读 `~/.zshenv`。所以让 agent 跑 flutter 命令时要先在命令里带上 PATH：

   ```bash
   export PATH="$HOME/flutter/bin:$PATH"
   ```

   或者在 `~/.bashrc` 里也加一行 `export PATH="$HOME/flutter/bin:$PATH"`，交互式 bash 与部分工具链会读它。

## 7. 装完后的验收清单

| 检查 | 命令 | 期望 |
|---|---|---|
| Flutter 版本 | `flutter --version` | 3.47.5 / Dart 3.13.4 |
| Linux 工具链 | `flutter doctor -v` | `[✓] Linux toolchain` |
| 依赖解析 | `flutter pub get` | 无报错 |
| 静态分析 | `flutter analyze` | 0 error（warning 记下来给我） |
| 单元测试 | `flutter test` | 全部通过 |

把 `flutter doctor -v`、`flutter pub get`、`flutter analyze`、`flutter test` 四段的完整输出贴回来，我再开始改代码。

---

## 8. 安装结果（2026-09-26 实测）

本机已按本指南装完，以下为实际结果，供核对。

### 版本

```text
Flutter 3.47.5 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 6a19cca564 (2026-09-17) • 14:13:22 -0400
Engine • revision af7e796e16
Tools • Dart 3.13.4 • DevTools 2.60.0
```

装在 `/home/hoshi/flutter`（2.3 G），`~/.pub-cache` 720 M，根分区余 946 G。

### 镜像必须换

同一文件（1,576,266,884 B）实测：

```text
storage.googleapis.com   25 秒下到 10,813,796 B   ≈ 0.43 MB/s
storage.flutter-io.cn    21 秒下完 1,576,266,884 B ≈ 68 MB/s
```

差 160 倍。镜像完整性已核对：`releases_linux.json` 与 `pub.flutter-io.cn/api/packages/just_audio` 都返回 200。`~/.zshenv` 里已设 `FLUTTER_STORAGE_BASE_URL` 与 `PUB_HOSTED_URL`；不想用镜像就注释掉那两行。

### 第 3 步的坑：libsqlite3.so

`flutter test` 里 `test/db_test.dart` 会失败，报：

```text
Failed to load dynamic library 'libsqlite3.so': libsqlite3.so: cannot open shared object file
```

原因是系统只装了 `libsqlite3-0`，提供 `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`，没有 `.so` 开发链接。免 sudo 修法：

```bash
mkdir -p "$HOME/.local/lib"
ln -sfn /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 "$HOME/.local/lib/libsqlite3.so"
export LD_LIBRARY_PATH="$HOME/.local/lib"
```

已写入 `~/.zshenv`。装 `libsqlite3-dev` 也能修，但要 sudo。

### 验收结果

```text
flutter pub get    exit 0
flutter analyze    exit 1，6 条 info，无 error/warning
flutter test       15/15 通过
```

`analyze` 报 info 时退出码也是 1，别把它当成失败。6 条 info 的位置：

- `lib/services/import_service.dart:43:9`、`:44:9`、`:45:9` `prefer_initializing_formals`
- `lib/services/subtitle_parser.dart:21:33` `unintended_html_in_doc_comment`
- `lib/widgets/cover_image.dart:34:27`、`:34:31` `unnecessary_underscores`

### 非交互 shell 注意

dsh 的 bash 工具跑 `bash -c`，读不到 `~/.zshenv`。agent 里跑 flutter 命令要显式带上：

```bash
export PATH="$HOME/flutter/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib"
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

用户自己的终端（zsh 登录 shell）什么都不用加。
