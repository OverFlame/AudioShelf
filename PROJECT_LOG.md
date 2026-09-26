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

### 阶段七 · 代码质量审查与竞态修复

- 审查：对 `lib/` 与 `test/` 做只读审查，产出 `docs/code-review.md`（27 条，P0 三条、P1 十七条、P2 七条 + 轻微项与死码清单）。审查重点是与阶段六同类的竞态、状态不一致与资源泄漏。
- 环境：宿主无 Flutter/Dart SDK，先按 `docs/wsl-flutter-setup.md` 在 WSL 装好 Flutter 3.47.5 / Dart 3.13.4。国内镜像（`storage.flutter-io.cn`）实测约 70 MB/s，官方源约 0.43 MB/s。`flutter analyze` 基线 6 条 info，`flutter test` 基线 15/15。
- 修复节奏：按报告里的「建议修复顺序」分轮推进，每轮都跑 `flutter analyze` + `flutter test`，并对新增用例做**变异验证**（改坏实现必须让用例失败，否则该用例没有区分力）。

| 轮次 | 修的条目 | 关键改动 |
| --- | --- | --- |
| 一 | 1、2、3 | 删作品改单事务 + `folders.work_id` 加 `ON DELETE SET NULL`（`migrations[3]` 重建表）；`DataDirService.migrateTo` 改成先复制校验、最后写指针，并复制 `-wal`；`migrateDataDir` 加互斥与失败重开库 |
| 二 | 4、5 | `refresh()` / `_loadCenter` 加 `_refreshGeneration` 代际，`finally` 只让最新一代清 `_loading`；`tables` 升 v4，给 `folder_paths` 加 `(folder_id, path)` 唯一索引并先去重 |
| 三 | 9、10、11、12、13 | `toggleTagOnTrack` 按曲目串行排队（`_tagToggleChains`）+ 标签列表一律 `List.of` / `unmodifiable`；`coverForTrack` 改用队列建立时记下的 `_playingWorkCover`，通知去重键追加封面；`_onTrackStarted` 的最近播放重载加代际；`_loadCenter` 写完 `_tracks` 后收窄选中集合 |
| 四 | 6 | `SettingsService._save` 按 `_saveChain` 串行排队，写文件改为「写 `settings.json.tmp`（`flush: true`）再改名」；`init()` 补 `_data = {}` |
| 五 | 7、8 | `AppState` 新增 `_beginImport` / `_endImport`，两个导入入口在第一个 `await` 之前同步置位标志，重复请求记 `logWarn` 后返回；`ImportService._isImporting` 改 `static`；「添加文件夹」按钮按 `appState.importing` 禁用；`importDirectory` 改为先扫描再建作品，无音频或全是旧曲目就不建，建完若 0 条落库则删除作品 |
| 六 | 16、19、20 | `FolderDao.getByPath` 加 `ORDER BY f.id`，`delete` 两条语句包进一个事务，新增 `setWorkMany`；`TagDao` 新增 `addTagsToTracks` / `removeTagsFromTracks`（各自一个事务）；`AppState.deleteFolder` 删除后调 `_pruneTracksLeftBehind`，用 `TrackDao.deleteByPaths` 清掉「在被删路径下、又无存活文件夹覆盖」的曲目；`moveFolderToWork` 等五处批量写改走新方法；删除确认文案改成说明曲目会移出曲库 |
| 七 | 17、18 | 新增 `FolderDao.ensureByPath`（「查映射、建文件夹、挂路径、对齐 parent/work」全在一个事务里），`_mirrorFolderTree` 只调它；整棵目录树的镜像提到曲目循环**之前**，建树失败时一条曲目都不写；`AppState` 新增 `importError`（`_beginImport` 清空、`_runImport` 的 catch 写入，仍不 rethrow），`folder_browser` 与 `tag_panel` 的三处导入调用后按它弹 SnackBar |

- 测试从 15 例增到 48 例（`test/db_migration_test.dart`、`test/data_dir_migration_test.dart`、`test/app_state_refresh_test.dart`、`test/app_state_race_test.dart`、`test/settings_service_test.dart`、`test/import_guard_test.dart`、`test/import_atomic_test.dart`、`test/db_consistency_test.dart`），`flutter analyze` 始终只有那 6 条 info、0 error。
- 教训一：并发刷新的「结果内容」断言没有区分力。`_loadCenter` 是在 `refresh()` 的两个 `await` 之后才读 `_searchQuery`，且 `sqflite_common_ffi` 的查询走 FIFO 串行队列，旧代码最后写入的仍是正确结果。改成断言 `notifyListeners` 次数（旧实现 20 次刷新重建 60 次，新实现常数级）才有区分力。
- 教训二：设置保存的「文件内容」断言同样没有区分力。`jsonEncode(_data)` 在写的那一刻才求值，两次并发保存编码出的都是最终状态，字节完全相同，交错也看不出坏。改用 POSIX 硬链接区分「改名」与「就地截断」：保存前把旧 inode 挂一个硬链接，保存后该链接必须仍读到旧内容。串行链也顺带被证成必需品——去掉后两个并发保存共用同一个 `settings.json.tmp`，第二个 `rename` 直接 `PathNotFoundException`。
- 教训三：导入守卫有三处（AppState 入口的拒绝分支、`ImportService` 的静态标志、事后删空作品），互为冗余。变异验证时单独去掉任一处，5 个用例仍全绿——是另一处接的手（第二次导入拿到 0 条事件 → 事后兜底把刚建的作品删掉）。测试断言的是「最终只有一个作品」这个行为，不是某一处代码；要证明每处都必需，得两处一起改。
- 教训四：删文件夹留下的孤儿曲目有个更硬的后遗症。曲目只在 `folder_paths` 的路径前缀下可见，孤儿行既搜得到、树里又进不去，而且会让那个目录再导入时被第 8 项的「全部已入库」判为无新内容——目录从此挂不回来。所以「删文件夹」必须顺手清理，不能留给用户手动收拾。
- 教训五：变异脚本的替换锚点必须唯一，否则「拦住了」是编译失败的假信号。第一版脚本用 `return _db.transaction((txn) async {` 当锚点，`folder_dao.dart` 里 `delete` 与 `ensureByPath` 都匹配，切片删掉了大半个类和 `getByPath`，测试「失败」其实根本没编译过。改法：锚点用方法签名那么长的唯一串，并在跑测试之前先跑一次 `flutter analyze`，有 error 就判「变异无效」，不算验证结果。
- 另外，把「事务包裹」和「加 ORDER BY」这类改动的区分力也要如实记账：`FolderDao.delete`、`setWorkMany` 的事务，以及 `ensureByPath` 里的 ORDER BY，都构造不出能区分旧实现的用例（要区分「逐条 commit」和「一个事务」得让第二个文件夹失败，而 `work_id` 指向不存在的作品时第一条就失败；同一个路径本不该有两条映射，构造不出 ORDER BY 生效的状态）。这三处已写进报告的「没有区分用例的改动」。
- 未做：报告第 21–27 项。

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
