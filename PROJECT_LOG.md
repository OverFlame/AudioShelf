# AudioShelf 项目日志

记录开发历程、关键技术决策与踩过的坑。新条目追加在「开发历程」末尾。

## 项目概述

本地音频播放器（Flutter，Windows / Linux / Android），以「作品集（专辑）＋虚拟文件夹」组织本地音频，
支持字幕模式、封面管理、标签筛选、播放历史、Android 后台播放通知栏。

技术栈：Flutter 3.47 + Provider + sqflite / sqflite_common_ffi + flutter_soloud（SoLoud）+ audio_metadata_reader。

## 分支策略

- **`master`**：开发分支。日常提交都推这里（`git push` 默认推 master）。
- **`main`**：稳定分支。**只能由维护者通过 PR 从 master 合并**，不直接推送。
- 助手/自动化约定：**只推送 `master`，不碰 `main`**。

## 环境与镜像约定

- 依赖一律优先中国镜像：
  - Flutter pub：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
  - Android Gradle：阿里云 + 腾讯 Maven 镜像
  - Gradle 发行包：腾讯镜像
  - Android SDK 组件：腾讯镜像 `https://mirrors.cloud.tencent.com/AndroidSDK/`
- `github.com`（443）与 `dl.google.com` 在目标网络不可达 → 所有需联网的构建步骤均做了镜像或规避。

## 开发历程

### 阶段一 · 项目搭建与核心功能（`f884b16`）

- 用 Flutter 搭建三端项目，以 PictureViewer2 的「虚拟文件夹」系统为蓝本适配到音频场景。
- 数据模型：`works`（作品集/专辑）+ `folders` / `folder_paths`（镜像磁盘目录树）+ `tracks` + `tags` / `track_tags` / `folder_tags`。
- 作品集独立于文件夹：默认「添加文件夹 = 一个同名作品」，可把多个文件夹归入同一作品（mp3 / wav 分版本）。
- 字幕智能匹配：`a.mp3` → `a.mp3.vtt` 优先 → `a.vtt`，并支持 `.srt` / `.lrc`。
- 字幕模式：模糊封面背景 + 逐行歌词、自动滚动高亮、滑动浏览、点击跳转乐句。
- 封面：自动读取内嵌封面 / 同目录 `cover.*`，支持自定义导入。
- 移植 PictureViewer2 的命名空间标签筛选（AND/OR/NOT + 高级布尔表达式）。
- 音频内核选 flutter_soloud（SoLoud 源码随包 CMake 编译）：因 GitHub 不可达，media_kit / just_audio 的桌面后端需从 GitHub 下载二进制。

### 阶段二 · 许可与发布准备

- `b1a6deb`：LICENSE 署名 Hoshikawa（MIT）。
- 清理可能引起纠纷的第三方模块：Catppuccin 主题 → 原创 `AppColors`（语义化命名 + 原创色值）；Flutter 默认 logo → 原创音符图标。
- 新增 `THIRD_PARTY_NOTICES.md`；审计确认全部依赖为宽松许可证（MIT / BSD / Apache / Zlib），无 GPL 类传染依赖。

### 阶段三 · 跨平台构建打通

- `c27fb70`：放宽 SDK 约束至 `^3.12.0`（兼容 Windows 上的旧 Flutter）；构建脚本加 `--no-version-check`（跳过 GitHub 版本检查）。
- `acb15ef`（Linux）：禁用 Xiph 库（`NO_XIPH_LIBS`），规避 flutter_soloud 打包的 libopus 需要 glibc 2.43（Ubuntu 24.04 仅 2.39）；native_assets install 加 `OPTIONAL`。
- 中国镜像落地：pub / Gradle / Gradle wrapper / Android SDK 组件（腾讯 AndroidSDK 镜像手动下载解压）。

### 阶段四 · 功能完善

- `e0f906d`：修复主页加载 `unmodifiable list` 崩溃（排序前复制列表）。
- `6965c84`：作品层严格按文件夹树（只显示子文件夹，不递归平铺曲目）；曲目显示源文件名。
- `28a3666`：音量调节；标签面板补全（搜索 / 新建含颜色 / 删除 / 色点 / AND-OR-NOT 菜单 / 活跃筛选 chips）；浅色主题适配（所有面板色改走主题）。
- `08b8bad`：数据目录整体迁移（设置页）；默认数据目录改为应用私有目录（`getApplicationSupportDirectory`）。
- `ebb8d23`：曲目多选（Ctrl / Shift）+ 批量打标签；标签重命名 / 改色。
- `0446c04`：播放历史 / 最近播放；封面缓存管理（大小上限 / 清理）。
- `552e4b4`：长按进入多选（Android 批量打标签）。

### 阶段五 · Android 与 Windows 实机问题排查

- `76d7b87`：build 脚本中文改英文（UTF-8 / GBK 乱码导致 `'er' 不是内部或外部命令`）；关闭 Kotlin 增量编译（pub 缓存 C 盘 / 项目 D 盘跨盘符报错）。
- `baf326f`：指定 CMake 3.30.5（NDK r28 的 clang 与 CMake 3.22.1 不兼容，编译器检测 broken）。
- `3ee27c6`：SoLoud 延迟初始化（构造时加载原生库失败导致启动白屏）；`main()` 加启动异常兜底页。
- `eb16ff9`：`PRAGMA journal_mode=WAL` 改用 `rawQuery`（Android `execSQL` 不允许返回结果的语句）。
- `9055f6c`：响应式布局（手机竖屏用抽屉 + 播放栏窄屏简化）。
- `f49054f`：sqlite3 改用 `winsqlite3.dll`（Windows 无 `sqlite3.dll`）。

### 阶段六 · 运行时缺陷修复

- `abfb1da`：修复**快速连续点击切歌导致多轨同时播放**（`_loadAndPlay` 竞态）。
  - 现象：快速点多个曲目会同时出声，且只能停止最后一个。
  - 原因：`_loadAndPlay()` 内 `disposeCurrent()` / `loadFile()` 两处 `await` 让出控制权，多次调用交错执行，先前的 `play()` 句柄被后一次覆盖丢失，旧音轨无法停止。
  - 修复：
    1. 引入**加载代际 token**（`_loadGen`）：每次加载自增；`await` 之后若代际已变化，说明被更新的请求取代 → 丢弃本次已加载的 `AudioSource`（`disposeSource`）而不播放。
    2. `init()` 改为共享 Future（`_initFuture ??= _doInit()`），并发调用只初始化一次。
    3. `_disposeCurrent()` 改为**先摘除字段再异步释放**，避免并发调用重复释放同一句柄/音源。
    4. `stop()` 自增代际，使进行中的加载失效，避免停止后又冒出声音。

## 跨平台差异与规避（踩坑速查）

| 问题 | 现象 | 规避 |
| --- | --- | --- |
| GitHub 不可达 | sqlite3 构建时下载预编译库失败 | `hooks.user_defines.sqlite3.source: system` |
| Windows 无 sqlite3.dll | 启动报 `Failed to load dynamic library 'sqlite3.dll'` | 加 `name_windows: winsqlite3` |
| glibc 2.43 | Linux 运行加载 libopus 失败 | `NO_XIPH_LIBS=1` 禁用 Xiph 库（只需 mp3/wav） |
| Android execSQL | `PRAGMA journal_mode=WAL` 报错 | 改用 `rawQuery` |
| NDK r28 + CMake 3.22.1 | clang 编译器检测 broken | 指定 CMake 3.30.5 |
| 跨盘符 Kotlin 增量编译 | pub 缓存 C 盘 / 项目 D 盘 | `kotlin.incremental=false` |
| `.bat` 编码 | 中文在 GBK 下乱码 | 构建脚本用纯英文 |
| 启动白屏 | release 下异常静默 | `main()` 加 try-catch + 错误页 |

## 待办 / 已知限制

- Android「所有文件访问」授权后的真实路径扫描，仍建议实机完整验证。
- 封面缓存上限只覆盖内嵌封面（`track_*.jpg`），自定义封面（`work_*.jpg`）不自动清理。
- 多选模式暂无「全选当前文件夹」。
- Android 多选暂无「连选」（Shift+点击的等价操作）。
