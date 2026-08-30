import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../db/folder_dao.dart';
import '../db/track_dao.dart';
import '../db/work_dao.dart';
import '../utils/log_util.dart';
import 'cover_service.dart';
import 'file_scanner.dart';
import 'metadata_service.dart';

/// 导入进度事件
class ImportProgress {
  final int current;
  final int total;
  final String currentFile;

  ImportProgress({
    required this.current,
    required this.total,
    required this.currentFile,
  });

  double get percent => total > 0 ? current / total : 0;
}

/// 批量导入服务
/// 流程：扫描目录 → 读取元数据/内嵌封面 → 写入 DB → 镜像目录树 → 自动封面
class ImportService {
  final WorkDao _workDao;
  final FolderDao _folderDao;
  final TrackDao _trackDao;

  bool _isImporting = false;
  bool get isImporting => _isImporting;

  ImportService({
    required WorkDao workDao,
    required FolderDao folderDao,
    required TrackDao trackDao,
  })  : _workDao = workDao,
        _folderDao = folderDao,
        _trackDao = trackDao;

  factory ImportService.fromDB() {
    final db = DatabaseManager.instance.db;
    return ImportService(
      workDao: WorkDao(db),
      folderDao: FolderDao(db),
      trackDao: TrackDao(db),
    );
  }

  /// 导入目录到指定作品 [workId]。
  Stream<ImportProgress> importDirectory(String dirPath,
      {required int workId}) async* {
    if (_isImporting) return;
    _isImporting = true;
    try {
      final scan = await FileScanner.scanDirectory(dirPath);
      if (scan.audioPaths.isEmpty) {
        logInfo('Import', 'importDirectory: 目录内无音频 "$dirPath"');
        return;
      }

      final existing = await _trackDao.existingPaths(scan.audioPaths);
      final newPaths =
          scan.audioPaths.where((p) => !existing.contains(p)).toList();
      final total = newPaths.length;
      logInfo('Import',
          'scanned ${scan.audioPaths.length} total, $total new, ${scan.audioPaths.length - total} dupes');

      for (int i = 0; i < newPaths.length; i++) {
        final path = newPaths[i];
        final file = File(path);

        int sizeBytes = 0;
        try {
          sizeBytes = await file.length();
        } catch (_) {}
        int mtime = 0;
        try {
          mtime = file.lastModifiedSync().millisecondsSinceEpoch;
        } catch (_) {}

        final ext = p.extension(path).toLowerCase();
        final filename = p.basename(path);
        final now = DateTime.now().millisecondsSinceEpoch;
        final meta = MetadataService.read(path);

        final item = TrackItem(
          path: path,
          filename: filename,
          title: meta.title,
          artist: meta.artist,
          album: meta.album,
          durationMs: meta.durationMs,
          format: ext.isNotEmpty ? ext.substring(1) : 'unknown',
          fileSize: sizeBytes > 0 ? sizeBytes : null,
          fileMtime: mtime > 0 ? mtime : null,
          subtitlePath: scan.subtitleByAudio[path],
          addedAt: now,
        );

        final id = await _trackDao.insert(item);
        if (id > 0 && meta.pictureBytes != null) {
          final coverPath = await CoverService.writeEmbedded(
              id, meta.pictureBytes!, meta.pictureMimetype ?? 'image/jpeg');
          if (coverPath != null) await _trackDao.setCoverPath(id, coverPath);
        }

        yield ImportProgress(current: i + 1, total: total, currentFile: path);
      }

      // 镜像物理目录树
      await _mirrorFolderTree(dirPath, scan.audioPaths, workId);
      // 自动封面
      await _ensureWorkCover(workId, scan.coverFiles, dirPath, scan.audioPaths);
      logInfo('Import', 'importDirectory done for work=$workId');
    } finally {
      _isImporting = false;
    }
  }

  // ═══ 目录树镜像 ═══

  /// 按物理磁盘目录镜像建立文件夹父子层级，全部归属 [workId]。
  Future<void> _mirrorFolderTree(
      String root, List<String> audioPaths, int workId) async {
    final rootNorm = _normPath(root);
    if (rootNorm.isEmpty) return;

    final dirs = <String>{};
    for (final a in audioPaths) {
      final aNorm = _normPath(a);
      if (!_isUnder(aNorm, rootNorm)) continue;
      var dir = _normPath(p.dirname(aNorm));
      while (true) {
        dir = _normPath(dir);
        dirs.add(dir);
        if (dir == rootNorm) break;
        final parent = _normPath(p.dirname(dir));
        if (parent == dir) break; // 文件系统根
        dir = parent;
      }
    }

    final sorted = dirs.toList()
      ..sort((a, b) => _dirDepth(a).compareTo(_dirDepth(b)));

    final map = <String, VirtualFolder>{};
    for (final dir in sorted) {
      final parentDir = _normPath(p.dirname(dir));
      final expectedParentId = map[parentDir]?.id;

      var folder = await _folderDao.getByPath(dir);
      if (folder == null) {
        final name = p.basename(dir);
        final displayName = name.isEmpty ? dir : name;
        folder = await _folderDao.create(displayName,
            parentId: expectedParentId, workId: workId);
        await _folderDao.addPath(folder.id!, dir, recursive: false);
      } else {
        if (folder.parentId != expectedParentId) {
          await _folderDao.move(folder.id!, expectedParentId);
        }
        if (folder.workId != workId) {
          await _folderDao.setWork(folder.id!, workId);
        }
        folder = VirtualFolder(
            id: folder.id,
            name: folder.name,
            parentId: expectedParentId,
            workId: workId);
      }
      map[dir] = folder;
    }
  }

  /// 作品尚无封面时，自动设置：优先根目录下 cover 图，否则第一首内嵌封面
  Future<void> _ensureWorkCover(
      int workId, List<String> coverFiles, String root, List<String> audioPaths) async {
    final work = await _workDao.getById(workId);
    if (work == null) return;
    if (work.coverPath != null && File(work.coverPath!).existsSync()) return;

    if (coverFiles.isNotEmpty) {
      final rootNorm = _normPath(root);
      final rootCover = coverFiles.firstWhere(
        (c) => _normPath(p.dirname(c)) == rootNorm,
        orElse: () => coverFiles.first,
      );
      await _workDao.setCover(workId, rootCover);
      return;
    }

    for (final ap in audioPaths) {
      final t = await _trackDao.getByPath(ap);
      if (t != null && t.coverPath != null && File(t.coverPath!).existsSync()) {
        await _workDao.setCover(workId, t.coverPath);
        return;
      }
    }
  }

  // ═══ 路径工具 ═══

  static String _normPath(String s) {
    var x = s;
    while (x.endsWith('\\') || x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  static bool _isUnder(String path, String dir) {
    final a = path.toLowerCase();
    final b = dir.toLowerCase();
    if (a == b) return false;
    return a.startsWith('$b\\') || a.startsWith('$b/');
  }

  static int _dirDepth(String dir) {
    return dir.split(RegExp(r'[\\/]')).length;
  }
}
