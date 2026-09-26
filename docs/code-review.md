# AudioShelf 代码质量审查报告

日期：2026-09-26。范围：`lib/` 与 `test/`。审查阶段为只读，未改动任何源码；随后按「建议修复顺序」分轮修复，修复状态见该节。
方法：逐行阅读源码 + `grep` 核对调用链。审查当时宿主未安装 Flutter/Dart SDK，下列结论均为静态阅读结论；2026-09-26 装好 Flutter 3.47.5 后补跑基线，结果见文末「实测基线」。

关注重点：与上一轮提交 `abfb1da`（音频冲突修复）同类的竞态、并发、状态不一致、资源泄漏缺陷。

## 严重度汇总

- P0 数据不可用：3 条（已修 3）
- P1 竞态与状态不一致：10 条（已修 10：第 4、5、6、7、8、9、10、11、12、13 条）
- P1 数据库 schema 与事务：7 条（已修 7：第 14 条随第 1 项修复，第 15 条随第 5 项修复，第 16、17、18、19、20 条分两轮修）
- P2 性能、边界、死码：7 条 + 其他轻微项与死码清单（已修 1：第 22 条随第 3 项修复）

---

## P0

### ✅ 1. 数据目录迁移非原子，且无回滚

- `lib/services/data_dir_service.dart:62-80`
- `migrateTo` 先 `_copyFileIfExists` 复制 `audioshelf.db`、`settings.json`、`covers/`，再 `File(p.join(def, '.datadir')).writeAsString(newD)`，最后 `_dataDir = newD`。全程无 try/catch，无 `.tmp` + rename。
- 后果：复制中途失败（磁盘满、权限）时指针已指向新目录。重启后加载残缺或空库，不回滚。

### ✅ 2. 迁移不复制 WAL 文件

- `lib/services/data_dir_service.dart:62`
- 只复制 `audioshelf.db`，不复制 `-wal` 与 `-shm`。`lib/db/database.dart:71` 已开启 `PRAGMA journal_mode=WAL`。
- 后果：迁移前若未 checkpoint，新目录的库丢掉最近写入。

### ✅ 3. `migrateDataDir` 无 try/catch、无互斥

- `lib/state/app_state.dart:860-864`
- `DatabaseManager.instance.close()` → `migrateTo(newDir)` → `DatabaseManager.instance.init()`，三步之间无 try/catch、无互斥标志。
- 后果：任一步失败即留在「库已关闭」状态。此后任何 DAO 访问抛 `StateError: Database not initialized`（`lib/db/database.dart:27-32`）。连点两次迁移可并发。
- 相关：`lib/state/player_controller.dart:104-112` 的 `catch (e)` 吞掉异常并置 `_playing = false`，迁移窗口内切歌表现为「点了没声音」，用户看不到报错。

---

## P1：竞态与状态不一致

### ✅ 4. `refresh()` 无代际保护，`setSearchQuery` 无防抖

- `lib/state/app_state.dart:164`（`refresh`）、`:173`（`_loadCenter`）、`:320-323`（`setSearchQuery`）
- 每次按键调用 `refresh()`，未 await、未防抖、无代际令牌。每个 refresh 各自 await `_workDao.listAll()`、`_folderDao.listUnassignedRoots()`、`_trackDao.listAll()` 后写 `_tracks`。
- 后果：后发起的 refresh 先完成时，`_tracks` 被旧查询结果覆盖。搜索框显示 `abc`，列表是 `ab` 的结果。
- 同类：`lib/state/player_controller.dart:89` 的 `final gen = ++_loadGen;` 与 `:92` 的 `if (gen != _loadGen) return;` 是正确写法，可作为修复模板。

### ✅ 5. `_loading` 标志被提前清除

- `lib/state/app_state.dart:173-221`（`_loadCenter`）
- `finally` 无条件执行 `_loading = false; notifyListeners();`。
- 后果：第 N 次 refresh 的 finally 清掉第 N+1 次 refresh 的 loading 状态。`lib/pages/home_page.dart:24` 的 `appState.loading` 分支随即切走整个中间内容区。

### ✅ 6. 设置保存无串行、无原子写

- `lib/services/settings_service.dart:35-39`
- `_save()` 直接 `await f.writeAsString(jsonEncode(_data))`，无写队列、无 `flush`、无临时文件。`:26-31` 的 `init` 在解析失败时静默 `_data = {}`。
- 后果：两次保存交错时后写者整体覆盖先写者，主题与排序同时改会丢一个。写入过程崩溃留空文件，下次启动全部设置重置为默认。

### ✅ 7. 导入守卫失效，可并发重复导入

- `lib/services/import_service.dart`（`_isImporting` 为实例字段）与 `lib/state/app_state.dart:488,502`
- `_isImporting` 是**实例字段**，而 `_runImport` 每次 `ImportService.fromDB()` 新建实例，守卫永不生效。
- `lib/state/app_state.dart:498` 的 `_importing = true` 只驱动 UI，`_runImport` 入口没有 `if (_importing) return;`。
- `lib/widgets/folder_browser.dart:144-149` 的 `_addFolderToWork` 不检查 `appState.importing`（`lib/widgets/tag_panel.dart:96` 那条路径检查了）。
- 后果：侧栏导入进行中，再进作品点「添加文件夹」，两个 `_runImport` 并行。先完成者把 `_importing` 置 false，界面提前解禁。

### ✅ 8. 导入先建空作品，目录无音频时留垃圾

- `lib/state/app_state.dart:485-490`
- `importDirectory` 先 `_workDao.create(name)`，再调 `_runImport`。目录内无音频时 `import_service` 提前 return。
- 后果：导入没有音频的文件夹，曲库里多出一个空作品。

### ✅ 9. `toggleTagOnTrack` 共享 List 引用，且读改写跨越 await

- `lib/state/app_state.dart:539`
- `final current = _trackTags[trackId] ?? await _tagDao.getTagsForTrack(trackId);` 之后对 `current` 增删。缓存命中时两次调用共享同一 List 引用，增删发生在 await 之后。
- `lib/db/tag_dao.dart:125-127` 的插入用 `ConflictAlgorithm.ignore`，数据库不报错。
- 后果：快速双击同一标签，内存列表出现重复项，或状态与库相反（双击「关标签」变成打开）。

### ✅ 10. `coverForTrack` 用当前浏览作品的封面

- `lib/state/app_state.dart:846`
- 返回 `_currentWork?.coverPath`，不是曲目所属作品的封面。该值供 `lib/services/media_bridge.dart:98`（通知栏）、`lib/widgets/player_bar.dart:37`、`lib/pages/subtitle_page.dart:46` 使用。
- 后果：播放中切换浏览的作品，播放栏与通知栏封面跟着换。

### ✅ 11. 通知去重键不含封面

- `lib/services/media_bridge.dart:117`
- 键为 `'${track.path}|${player.playing}|${player.duration.inMilliseconds}|${player.position.inSeconds}'`。
- 后果：封面变了键不变，通知栏封面永不刷新。与前一条叠加。

### ✅ 12. `_onTrackStarted` 未 await、无代际

- `lib/state/app_state.dart:893-898`
- `unawaited(_trackDao.recordPlay(...).then((_) => loadRecentTracks()))`，无 `catchError`。
- 后果：快速切歌触发多个 recordPlay 与多个 loadRecentTracks 并发，「最近播放」被先发后到的结果覆盖；异常被 then 链吞掉。

### ✅ 13. 选中曲目集合跨上下文残留

- `lib/state/app_state.dart`（`_selectedTrackIds` 与 `_loadCenter`）
- `refresh()` 与 `_loadCenter()` 都不清理选中集合，只有用户主动 `clearTrackSelection()` 才清。
- 后果：在 A 文件夹勾选若干曲目，切到 B 作品后点「批量打标签」，操作落到看不见的 A 曲目上。

---

## P1：数据库 schema 与事务

### ✅ 14. 删除作品非原子，外键无 ON DELETE

- 已在第 1 轮随第 1 项修掉：`lib/db/tables.dart:26` 现在是 `work_id INTEGER REFERENCES works(id) ON DELETE SET NULL`；`lib/db/work_dao.dart:87-95` 的 `delete` 在单个 `_db.transaction` 里先把 folder 的 `work_id` 置空再删作品；`lib/state/app_state.dart` 的 `deleteWork` 只调这一个 DAO 方法。
- `lib/db/tables.dart:25`、`lib/db/work_dao.dart:84-88`、`lib/state/app_state.dart:428-430`（原始证据）
- `work_id INTEGER REFERENCES works(id)` 未声明 `ON DELETE`，默认 NO ACTION。`detachFolders` 与 `delete` 是两条独立语句，无事务。
- 后果：两步之间若有导入把文件夹重挂回该作品（`lib/services/import_service.dart:170` 的 `setWork`），`delete` 抛 `FOREIGN KEY constraint failed`。作品没删掉，文件夹已被置空，界面直接报错。

### ✅ 15. `UNIQUE(name, parent)` 对 NULL 不生效，`folder_paths` 无唯一约束

- `lib/db/tables.dart:26,32-37`
- SQLite 中 `UNIQUE` 索引对 NULL 互不相等。`folder_paths` 无主键、无 UNIQUE。`lib/db/folder_dao.dart:171` 的 `ConflictAlgorithm.ignore` 因此永不触发。
- 后果：并发导入可造出同名根文件夹，以及同一 path 的多条映射。
- 已修（分两处）：第 5 项给 `folder_paths` 加了 `idx_folder_paths_unique ON folder_paths(folder_id, path)`，同一路径的重复映射被数据库挡住；剩下的「同名根文件夹」在应用层挡住——`FolderDao.ensureByPath` 把「查、建、挂路径」收进一个事务（见第 17 项），数据库层面 `UNIQUE(name, parent)` 对 NULL 的漏洞仍在，靠单写者保证。

### ✅ 16. `getByPath` 无 ORDER BY

- `lib/db/folder_dao.dart:196-206`（修后）
- 返回 `VirtualFolder.fromMap(rows.first)`。
- 后果：一个 path 有多条映射时结果不确定，后续导入挂到不同 folder id 上。
- 已修：查询尾部加 `ORDER BY f.id`，固定取 id 最小的那个文件夹。变异验证去掉 ORDER BY 后，用例实测返回 id 2（`Expected: <1> Actual: <2>`），确认扫描顺序确实会跳。

### ✅ 17. `_mirrorFolderTree` 跨语句 check-then-act

- `lib/db/folder_dao.dart:209-262`（新增的 `ensureByPath`）、`lib/services/import_service.dart:158-170`
- `getByPath(dir)` 为 null 时 `create(...)` 再 `addPath(...)`，无事务。
- 后果：并发下重复建树。
- 已修：新增 `FolderDao.ensureByPath(String path, {required String name, int? parentId, int? workId})`，「查映射 → 建文件夹 → 挂路径」以及已存在时的 `parent`/`work_id` 对齐全部在一个 `_db.transaction` 里；`_mirrorFolderTree` 改成只调它。变异验证把 `ensureByPath` 改回原来的三条语句后，并发的两条调用实测建出两个文件夹，用例拦住。
- 未覆盖：`ensureByPath` 里那个 `ORDER BY f.id` 没有区分用例（同一个路径本来就不该有两条映射，测试构造不出这个状态，只能靠第 16 项那条用例覆盖同类的 `getByPath`）。去掉它全量 48 例仍全绿，属防御性写法。

### ✅ 18. 导入非原子，异常被吞

- `lib/services/import_service.dart:75-125`、`lib/state/app_state.dart:100-107,594-605,646-655`
- 循环内逐条 `insert`，`_mirrorFolderTree` 在循环之后。`catch (e) { logError(...) }` 不 rethrow。
- 后果：建树失败时曲目已入库，而 `lib/state/app_state.dart:198-201` 作品层 `tracks = const [];` 不显示曲目。数据在库里但 UI 不可达，且 UI 呈现成功。
- 已修：`_mirrorFolderTree` 提到曲目循环之前，建树失败时一条曲目都没写；`AppState` 新增 `String? get importError`，`_runImport` 的 catch 把异常文本记进它（仍不 rethrow，因为调用方是按钮回调、没有错误边界），`importDirectory` 在 0 条落库时把失败原因写进日志；`lib/widgets/folder_browser.dart` 与 `lib/widgets/tag_panel.dart` 三处导入调用之后检查 `importError`，非空就弹 SnackBar。变异验证把镜像移回循环之后，用例实测曲目已落库（`建树失败时一条曲目都不落库` 失败）；去掉 `_importError` 赋值，同一个用例在「失败原因可见」这条断言上失败。
- 选择说明：没有改成 rethrow，而是「不抛 + 显式失败状态 + 界面呈现」。rethrow 会把异常丢进 `FlatButton` 的 async 回调里，变成无人接的异步异常。

### ✅ 19. 删文件夹只提升子级，不处理曲目

- `lib/db/folder_dao.dart:141-152`、`lib/state/app_state.dart` 的 `deleteFolder` 与 `_pruneTracksLeftBehind`
- 先把子级 `parent` 置 null，再删本行，无事务。tracks 表与文件夹无外键，只靠 `folder_paths` 路径映射。`lib/db/track_dao.dart:227` 的 `deleteByPaths` 零调用者。
- 后果：文件夹删掉后曲目仍在库里，仍出现在搜索与标签统计里，但树里再也进不去。
- 已修两处：`FolderDao.delete` 的两条语句放进一个事务；`AppState.deleteFolder` 先记下被删文件夹自己的路径，删除后调 `_pruneTracksLeftBehind`，把「落在被删路径下、又不再被任何存活文件夹路径覆盖」的曲目经 `deleteByPaths` 移除。子文件夹上移到根级后仍覆盖的曲目会保留。
- 顺带修掉一个更硬的后遗症：孤儿曲目会让同一个目录再导入时被第 8 项的「全部已入库」判为无新内容，那个目录再也挂不回来。

### ✅ 20. 批量写无事务，仅有的两个事务方法零调用者

- `lib/db/tag_dao.dart:149-179`（新增的两个批量事务方法）、`lib/db/folder_dao.dart:153-161`（`setWorkMany`）
- `setTrackTags`/`setFolderTags` 是全库仅有的两处 `_db.transaction`，grep 零调用者。实际批量路径是双重循环逐条 await。
- 后果：中途失败留半截标签且不回滚；N×M 次串行往返，批量打标签明显卡。
- 已修：新增 `TagDao.addTagsToTracks` / `removeTagsFromTracks` 与 `FolderDao.setWorkMany`，各自在一个事务里循环；`AppState` 的 `addTagsToTracks`、`removeTagsFromTracks`、`addTagsToFolder(recursive: true)`、`removeTagsFromFolder(recursive: true)`、`moveFolderToWork` 全部改走这三个方法。变异验证把 `addTagsToTracks` 改回逐条提交后，用例实测留下 `{'track_id': 1, 'tag_id': 1}` 这半条，确认回滚真的由事务提供。

---

## P2：性能、边界、资源、死码

### 21. 封面写入非原子，淘汰不保护正在播放的封面

- `lib/services/cover_service.dart:20-32,35-53`
- `writeEmbedded` 直接 `await file.writeAsBytes(bytes, flush: true)`，无临时文件与 rename。`enforceLimit` 按 `lastModifiedSync()` 升序删除。`lib/services/import_service.dart:195-203` 会把 `work.coverPath` 指向 `covers/track_<id>.*`。
- 后果：并发写同名文件可留半截图片并长期命中；超限淘汰删掉播放中的封面；`work.coverPath` 指向 `track_` 前缀文件时被清理后不再重建。

### 22. `DatabaseManager.close/init` 无重入保护

- `lib/db/database.dart:34,75-79`
- `close()` 里 `await _db?.close()` 期间 `_db` 仍非空，`db` getter 返回已关闭连接；`init()` 无 `if (_db != null) return;`。`lib/services/import_service.dart:47-54` 把当时拿到的 `db` 固化进 DAO。
- 后果：迁移窗口内导入继续往旧库写。

### 23. LIKE 通配符未转义，根路径边界未处理

- `lib/db/track_dao.dart:161-162,268-275`
- 前缀查询用 `path LIKE '$prefix%'`，未转义 `%` 与 `_`。`_directPrefix` 用 `base.contains('\\') ? '\\' : '/'` 猜分隔符。
- 后果：目录名含 `_` 时（如 `my_songs`）误命中 `myXsongs`。根目录 `/` 或 `C:\` 被削成空串，直属文件全被 `path NOT LIKE` 排除。

### 24. 占位符全量拼接，无分批

- `lib/db/track_dao.dart:181-182,203,214`、`lib/db/tag_dao.dart:157,288`
- 同文件 `:139` 的 `const batchSize = 500` 只在 `existingPaths`/`deleteByPaths` 用了。
- 后果：`lib/state/app_state.dart:593-607` 把作品全部后代路径喂进 `queryByDirs`。Android 自带 SQLite 变量上限 999，会抛 `too many SQL variables`。

### 25. 主 isolate 同步 IO，导入卡界面

- `lib/services/import_service.dart:62`、`lib/services/file_scanner.dart:48`
- 递归遍历与逐文件元数据解析（`MetadataService.read`）都在主 isolate 同步执行，`file.lastModifiedSync()` 亦然。
- 后果：导入数千文件时界面冻结，进度条不刷新。

### 26. 媒体服务启动未 await，首次通知丢失

- `lib/services/media_bridge.dart:117`
- `_startService();` 未 await，紧接着的 `_updateNotification()` 在 `_serviceStarted` 为 false 时直接 return。
- 后果：首次通知被丢弃，直到下一次状态变化才补上。平台通道调用也无超时。

### 27. `recordPlay` 两条语句无事务

- `lib/db/track_dao.dart:246-251`
- insert 后 `DELETE FROM play_history WHERE id NOT IN (SELECT id ... ORDER BY played_at DESC LIMIT 200)`。
- 后果：快速切歌并发触发；同毫秒并列时可能删掉刚插入的行，最近播放缺项。排序补 `, id DESC` 可缓解。

### 其他轻微项

- `lib/db/tag_dao.dart:60`：`return Tag(id: id, namespace: ..., name: ...)` 丢了 `color`，而 `:57` 的 insert 已把调用方的 color 写库。返回对象是默认色 `#cba6f7`。
- `lib/db/work_dao.dart:46,53`：两次取 `DateTime.now()`，返回对象可能与库行差 1ms。
- `lib/db/database.dart:60-61`：`if (migrations == null) continue;`，将来漏写 `migrations[3]` 不会报错，但版本号已升。
- `lib/db/database.dart:71`：丢弃 `PRAGMA journal_mode=WAL` 的返回行，未校验是否真为 `wal`。
- `lib/widgets/player_bar.dart`、`lib/pages/subtitle_page.dart`：进度条 `Slider.onChanged` 直接调 `player.seek(...)`，拖动期间每帧一次。
- `test/db_test.dart:17-27`：测试库未设 `onConfigure`，外键默认关闭；也未接 `onUpgrade`。`lib/db/tables.dart` 里 4 处 `ON DELETE CASCADE` 与 `lib/db/database.dart:57-66` 的 v1→v2 迁移零覆盖。`:66-67` 的临时目录在断言失败时不清理。
- `test/` 共 5 个文件 231 行：`filter_expression_test.dart`（6 个用例）、`db_test.dart`（1 个）、`file_scanner_test.dart`（2 个）、`widget_test.dart`（1 个占位）、`subtitle_parser_test.dart`（5 个）。实测 15/15 通过，但全是正常路径，并发与失败路径零覆盖。

### 死码清单（grep 全库零调用者）

`lib/db/track_dao.dart:227` `deleteByPaths`、`lib/db/tag_dao.dart:305` `deleteOrphanTags`、`lib/db/folder_dao.dart:222` `getAllPaths`、`:213` `getPathsByWork`、`:133` `countChildren`、`lib/db/tag_dao.dart:97` `listWithCount`、`lib/db/folder_dao.dart:189` `insert`。
批量化的 `getAllPaths` 没人用，调用方反而走 N+1（`lib/state/app_state.dart:248`、`:598`）。

---

## 已排除的可能

- 符号链接成环：`lib/services/file_scanner.dart:48` 已用 `followLinks: false`。
- SQL 注入：DAO 全部参数化；`lib/db/track_dao.dart:159/179/212/222` 的 `orderBy` 调用方全用默认值；`lib/utils/filter_expression.dart:262` 只拼已解析的整型 id。
- 切歌加载竞态：`lib/state/player_controller.dart:89-121` 的 `_loadGen` 校验与 `disposeSource` 已覆盖上一轮的缺陷。
- `SubtitleParser` 编码异常：有 `latin1` 兜底，不抛错。
- `FolderDao.move` 成环：唯一调用点 `lib/services/import_service.dart:167` 的 parent 取自按深度排序的真实磁盘祖先。
- getter 缓存污染：`lib/db/` 内无实例级集合缓存，返回值均新建 List/Map。

## 未验证项

装好 Flutter 3.47.5 后已实测：`flutter pub get` 成功，`flutter analyze` 只报 6 条 info，`flutter test` 15/15 通过。完成「建议修复顺序」第 1–5 项后再测：`flutter test` **22/22 通过**（新增 7 例：`test/db_migration_test.dart` 2 例、`test/data_dir_migration_test.dart` 4 例、`test/app_state_refresh_test.dart` 1 例），`flutter analyze` 仍只有那 6 条 info，无新增。

完成第 9、10、11、12、13 项后再测：`flutter test` **29/29 通过**（新增 7 例：`test/app_state_race_test.dart`），`flutter analyze` 仍只有那 6 条 info，无新增。

完成第 6 项后再测：`flutter test` **32/32 通过**（新增 3 例：`test/settings_service_test.dart`），`flutter analyze` 仍只有那 6 条 info，无新增。

完成第 7、8 项后再测：`flutter test` **37/37 通过**（新增 5 例：`test/import_guard_test.dart`），`flutter analyze` 仍只有那 6 条 info，无新增。

完成第 16、19、20 项后再测：`flutter test` **44/44 通过**（新增 7 例：`test/db_consistency_test.dart`），`flutter analyze` 仍只有那 6 条 info，无新增。

完成第 17、18 项后再测：`flutter test` **48/48 通过**（新增 4 例：`test/import_atomic_test.dart`），`flutter analyze` 仍只有那 6 条 info、0 error，仅 `import_service.dart` 那 3 条的行号从 43/44/45 变成 45/46/47。

仍未实测：sqflite 的锁语义、`insert` + `ConflictAlgorithm.ignore` 在真机上是否返回 0、Android 的 `too many SQL variables` 实际阈值、WAL checkpoint 是否在 `close()` 时必然执行、真机上的并发导入复现。这些都需要写针对性测试才能定论。

没有区分用例的改动（改动本身有价值，但没有能区分旧实现的用例，故不计入已验收）：`FolderDao.delete` 与 `FolderDao.setWorkMany` 的事务包裹。要区分「逐条 commit」和「一个事务」，需要在第二个文件夹上制造外键失败；而 `work_id` 指向不存在的作品时第一条就会失败，两条路径的结果一样。`setWorkMany` 还只是把 N 次 DAO 调用收成一次，行为与 `moveFolderToWork` 原循环等价。第 17 项里 `ensureByPath` 的 `ORDER BY f.id` 同样没有用例：同一个路径本来就不该有两条映射，测试构造不出这个状态；去掉后全量 48 例仍全绿，它是防御性写法而不是被验证的行为。

## 建议修复顺序

1. ✅ 已完成（2026-09-26）`lib/db/tables.dart` 升到 v3，`folders.work_id` 改 `ON DELETE SET NULL`，新增 `migrations[3]` 用 backup/restore 重建 folders（旧写法会级联清空 `folder_paths` / `folder_tags`）；`lib/db/work_dao.dart` 的 `delete` 改成单事务（先摘归属再删作品），删掉 `detachFolders`；`lib/state/app_state.dart` 的 `deleteWork` 只调 DAO。新增 `test/db_migration_test.dart`（2 例）。
2. ✅ 已完成（2026-09-26）`lib/services/data_dir_service.dart` 的 `migrateTo` 改为「先复制校验、最后写指针」，指针写 `.datadir.tmp` 后 rename；目标已有不同内容的同名文件直接拒绝覆盖；顺带复制 `audioshelf.db-wal`。新增 `test/data_dir_migration_test.dart`（4 例）。
3. ✅ 已完成（2026-09-26）`lib/state/app_state.dart` 的 `migrateDataDir` 加 `_migrating` 互斥、失败时按指针重开数据库再 rethrow；`_rewriteCoverPaths` 的字符串前缀匹配改成 `p.isWithin` / `p.relative`（原来 `/a/b` 会误匹配 `/a/bc/...`）；`lib/db/database.dart` 的 `init` 加幂等、`close` 先置 null 再关；`lib/pages/settings_page.dart` 的迁移失败改为弹 SnackBar，不再静默吞掉。
4. ✅ 已完成（2026-09-26）`lib/state/app_state.dart:165` 的 `refresh` 加递增代际 `_refreshGeneration`：两个 await 之后、以及 `_loadCenter` 唯一的赋值点之前都查代际，被新一代取代就丢弃结果；`finally` 只在代际匹配时清 `_loading`。新增 `test/app_state_refresh_test.dart`（1 例，断言 20 次并发刷新只产生常数级重建）。变异验证：把两处代际判断改成永真 / 永假后该用例失败（`Actual: <60>`，断言上限 12）。
5. ✅ 已完成（2026-09-26）`lib/db/tables.dart` 升到 v4：`createStatements` 与 `migrations[4]` 都建 `idx_folder_paths_unique ON folder_paths(folder_id, path)`，用唯一索引而非表级 `UNIQUE`，老库只需去重再加索引、不必重建表；`migrations[4]` 先按 `MIN(rowid)` 去重。`lib/db/folder_dao.dart:201` 的 `getPaths` 加 `orderBy: 'rowid'`。`test/db_migration_test.dart` 补了去重与唯一索引断言。变异验证：把 `migrations[4]` 改成空操作后该用例失败（`Expected: <2> Actual: <3>`）。
6. ✅ 已完成（2026-09-26）第 9 项：`lib/state/app_state.dart` 的 `getTrackTags` 返回 `List<Tag>.unmodifiable(...)`、缓存写入用 `List<Tag>.of(...)`；`toggleTagOnTrack` 不再直接读改写，改为按 `trackId` 用 `_tagToggleChains` 串行排队，真正干活的是 `_applyTagToggle`（先 `List<Tag>.of(...)` 取副本再增删）。`selectedTrackIds` 改为返回 `UnmodifiableSetView`。新增 `test/app_state_race_test.dart`（标签部分 3 例）。变异验证：把串行链去掉后「连点两次」用例失败（`Expected: empty Actual: [Tag:纯音乐]`）；把 `getTrackTags` 缓存命中分支改回返回内部 List 后不可变用例失败（`Expected: throws UnsupportedError`）。
7. ✅ 已完成（2026-09-26）第 10 + 11 项：`coverForTrack` 改用新字段 `_playingWorkCover`（队列建立时由 `_rememberQueueCover()` 记下当时作品的封面），不再读 `_currentWork`；`playTracks` / `playAllCurrent` / `playTrackAt` 在调 `player.playQueue` 之前记录，`playRecentTracks` 置空以回退到曲目自身封面；`lib/services/media_bridge.dart` 的通知去重键追加封面路径，封面变了就重建通知。变异验证：把 `_playingWorkCover` 换回 `_currentWork?.coverPath` 后两个封面用例都失败（`Expected: coverA Actual: coverB`）。
8. ✅ 已完成（2026-09-26）第 12 项：`_onTrackStarted` 加 `_recentLoadGeneration` 代际，`recordPlay` 之后只让最新一代的重载写回，并补 `catchError` 记日志；`loadRecentTracks()` 转调 `_reloadRecentTracks(gen)`。变异验证：把代际检查改成永假后「快速切歌」用例失败（`Expected: a value less than <3> Actual: <3>`）。
9. ✅ 已完成（2026-09-26）第 13 项：`_loadCenter` 唯一赋值点在写完 `_tracks` 之后收窄选中集合（`_selectedTrackIds.retainAll(visibleIds)`），不可见的锚点清空，集合空了就退出多选模式。UI 侧 `lib/widgets/folder_browser.dart:152-162` 的批量打标签在弹窗之前就固化 `ids`，不受影响。变异验证：去掉 `retainAll` 后用例失败（`Expected: empty Actual: Set:[1]`）。

10. ✅ 已完成（2026-09-26）第 6 项：`lib/services/settings_service.dart` 的 `_save` 改为按 `_saveChain` 串行排队，实际写文件交给新方法 `_writeSettingsFile`：写 `settings.json.tmp`（`flush: true`）后改名，链尾只留不会失败的 future，一次写失败不卡住后续保存；`init()` 补 `_data = {}`，避免文件不存在时沿用上次的内存状态。新增 `test/settings_service_test.dart`（3 例）。变异验证两处都拦住：去掉串行链后「并发保存」用例失败（`PathNotFoundException: Cannot rename file to '.../settings.json', path = '.../settings.json.tmp'`，两个并发保存共用同一个临时文件名）；改回 `f.writeAsString(...)` 就地写后「不就地截断旧文件」用例失败（`Expected: contains 'first' Actual: '{"sort_key":"second"}'`）。

11. ✅ 已完成（2026-09-26）第 7、8 项：`lib/state/app_state.dart` 新增 `_beginImport(caller)` / `_endImport()`，`importDirectory` 与 `importDirectoryIntoWork` 在**第一个 await 之前**同步置位导入标志，重复请求记 `logWarn` 后直接返回 null；`lib/services/import_service.dart:38` 的 `_isImporting` 从实例字段改成 `static`，兜住绕过 AppState 的直接调用；`lib/widgets/folder_browser.dart:112` 的「添加文件夹」按钮按 `appState.importing` 禁用。第 8 项：`importDirectory` 改为先 `FileScanner.scanDirectory`，无音频或音频都已入库时不建作品（新增 `_hasNewAudio`），建完作品后若 `_runImport` 返回 0 条新曲目则把作品删掉；`importDirectoryIntoWork` 也接受预扫描结果，避免重复扫盘。新增 `test/import_guard_test.dart`（5 例）。变异验证：去掉 `_beginImport` 的拒绝分支后「导入进行中再调 importDirectoryIntoWork」失败（`Expected: <2> Actual: <1>`）；`static` 退回实例字段后静态守卫用例失败（`Expected: true Actual: <false>`）；前置检查与事后兜底互为冗余，单独去掉任一处都被另一处挡住（测试仍全绿），两处同时去掉后「目录内没有音频」与「同目录导入两次」两个用例一起失败（`Expected: null Actual: <Instance of 'Work'>`）。

12. ✅ 已完成（2026-09-26）第 16、19、20 项：`lib/db/folder_dao.dart` 的 `getByPath` 加 `ORDER BY f.id`，`delete` 的两条语句包进一个事务，新增 `setWorkMany`；`lib/db/tag_dao.dart` 新增 `addTagsToTracks` / `removeTagsFromTracks`（各自一个事务）；`lib/state/app_state.dart` 的 `deleteFolder` 删除后调新方法 `_pruneTracksLeftBehind`，用 `TrackDao.deleteByPaths` 清掉失联曲目，`moveFolderToWork`、`addTagsToTracks`、`removeTagsFromTracks`、`addTagsToFolder(recursive)`、`removeTagsFromFolder(recursive)` 全改走批量事务方法；`lib/widgets/folder_browser.dart` 的删除确认文案改成说明曲目会移出曲库。新增 `test/db_consistency_test.dart`（7 例）。变异验证三处全部拦住：去掉 `ORDER BY f.id` 后 `getByPath` 用例返回 id 2（`Expected: <1> Actual: <2>`）；去掉 `_pruneTracksLeftBehind` 调用后两个清理用例失败（`Actual: ['/m/album/1.mp3', '/m/album/sub/2.mp3']`）；把 `addTagsToTracks` 拆回逐条提交后回滚用例留下 `{'track_id': 1, 'tag_id': 1}`。

13. 第 14 项已在第 1 轮随第 1 项修掉，标记更正见上文第 14 条；本轮无新增改动。

14. ✅ 已完成（2026-09-26）第 17、18 项：`lib/db/folder_dao.dart` 新增 `ensureByPath(path, {name, parentId, workId})`，「查映射 → 建文件夹 → 挂路径」以及已存在时 `parent`/`work_id` 的对齐全在一个事务里；`lib/services/import_service.dart` 的 `_mirrorFolderTree` 只调它，并把整棵树的镜像提到曲目循环之前；`lib/state/app_state.dart` 新增 `importError` 字段（`_beginImport` 清空、`_runImport` 的 catch 写入，仍不 rethrow），`importDirectory` 的 0 条分支把失败原因写进日志；`lib/widgets/folder_browser.dart` 与 `lib/widgets/tag_panel.dart` 三处导入调用之后检查 `importError`，非空弹 SnackBar。新增 `test/import_atomic_test.dart`（4 例）。变异验证全部拦住：`ensureByPath` 拆回三条独立语句后并发用例建出两个文件夹；镜像移回循环之后后「建树失败时一条曲目都不落库」失败（曲目已落库）；去掉 `_importError` 赋值后该用例在「失败原因可见」断言上失败；`getByPath` 的 ORDER BY 复验仍被第 16 项用例拦住。`ensureByPath` 的 ORDER BY 去掉后全绿，已如实记入「没有区分用例的改动」。

仍待修复（未开始）：第 21–27 项。

---

## 实测基线（2026-09-26，Flutter 3.47.5 / Dart 3.13.4）

命令与环境：`PATH=$HOME/flutter/bin:$PATH`、`LD_LIBRARY_PATH=$HOME/.local/lib`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。

### flutter analyze

退出码 1，6 条**全部是 info**，无 error、无 warning：

- `lib/services/import_service.dart:45:9` `prefer_initializing_formals`
- `lib/services/import_service.dart:46:9` `prefer_initializing_formals`
- `lib/services/import_service.dart:47:9` `prefer_initializing_formals`
- `lib/services/subtitle_parser.dart:21:33` `unintended_html_in_doc_comment`
- `lib/widgets/cover_image.dart:34:27` `unnecessary_underscores`
- `lib/widgets/cover_image.dart:34:31` `unnecessary_underscores`

前三条正是第 7 条缺陷（`_isImporting` 守卫失效）所在构造函数的写法问题，顺手可改。

### flutter test

15/15 通过：

```text
00:00 +15: All tests passed!
```

第一次跑时 `test/db_test.dart` 失败，原因是环境而非代码：

```text
SqfliteFfiException(error, Invalid argument(s): Couldn't resolve native function
'sqlite3_initialize' in 'package:sqlite3/src/ffi/libsqlite3.g.dart' :
Failed to load dynamic library 'libsqlite3.so': libsqlite3.so: cannot open
shared object file: No such file or directory.)
```

系统只装了 `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`（属 `libsqlite3-0`），没有 `.so` 开发符号链接。无需 sudo，建一个用户级 shim 即可：

```bash
mkdir -p "$HOME/.local/lib"
ln -sfn /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 "$HOME/.local/lib/libsqlite3.so"
export LD_LIBRARY_PATH="$HOME/.local/lib"
```

已写入 `~/.zshenv`。

### 覆盖缺口

审查时 15 个用例全部走正常路径，本报告里的竞态类缺陷（第 4、5、6、7、9、10、12、13 条）没有一条被测试覆盖。现已补齐第 4、5、6、7、8、9、10、12、13、16、17、18、19、20 条：`test/app_state_refresh_test.dart`、`test/app_state_race_test.dart`、`test/settings_service_test.dart`、`test/import_guard_test.dart`、`test/import_atomic_test.dart`、`test/db_consistency_test.dart`、`test/db_migration_test.dart`、`test/data_dir_migration_test.dart` 合计 48 个用例，每个新用例都做过变异验证（改坏实现必须能让它失败）。第 6 条的原子写靠 POSIX 硬链接区分「改名」与「就地截断」：保存前的 inode 挂一个硬链接，保存后该链接仍应读到旧内容。第 20 条的事务靠外键失败区分：`track_tags.tag_id` 指向不存在的标签时插入抛错，逐条提交会留下前半条，一个事务则整体回滚。第 18 项也靠外键失败：`folders.work_id` 指向不存在的作品，镜像目录树必然抛错，旧顺序下曲目已经入库。

第 7、8 项的守卫有冗余，变异验证暴露了这一点：前置检查（无音频、无新音频不建作品）与事后兜底（0 条落库就删作品）单独去掉任一处，5 个用例仍全绿；两处同时去掉才有 2 个用例失败。并发导入同理：AppState 的入口守卫被去掉后，是 `ImportService` 的静态守卫接的手（第二次导入 0 条事件 → 事后兜底删掉空作品），所以「同时发起两次导入」这个用例当时仍然通过。冗余本身是可接受的防御，但断言覆盖的是行为而不是某一处代码。

仍未覆盖：第 21–27 项，以及上文「没有区分用例的改动」里列出的三处（`FolderDao.delete`、`setWorkMany` 的事务包裹，`ensureByPath` 的 ORDER BY）。
