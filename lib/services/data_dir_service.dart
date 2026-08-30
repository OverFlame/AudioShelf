import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log_util.dart';

/// 数据目录服务：统一管理数据库 / 封面缓存 / 设置文件的根目录。
///
/// 目录结构：
/// ```
/// <dataDir>/audioshelf.db
/// <dataDir>/covers/
/// <dataDir>/settings.json
/// ```
class DataDirService {
  DataDirService._();

  static final DataDirService instance = DataDirService._();

  String? _dataDir;

  Future<String> defaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'AudioShelf');
  }

  Future<String> _pointerFile() async {
    return p.join(await defaultDir(), '.datadir');
  }

  Future<String> get dataDir async {
    if (_dataDir != null) return _dataDir!;

    final def = await defaultDir();
    var result = def;
    try {
      final pf = await _pointerFile();
      final f = File(pf);
      if (f.existsSync()) {
        final content = f.readAsStringSync().trim();
        if (content.isNotEmpty) {
          result = content;
        }
      }
    } catch (e) {
      logWarn('DataDir', '读取指针文件失败: $e');
    }

    _dataDir = result;
    await Directory(result).create(recursive: true);
    return result;
  }

  Future<void> init() async {
    final dir = await dataDir;
    logInfo('DataDir', 'Data dir: $dir');
  }

  Future<String> migrateTo(String newDir) async {
    final oldDir = await dataDir;
    final newD = p.normalize(newDir);
    await Directory(newD).create(recursive: true);

    await _copyFileIfExists(
        p.join(oldDir, 'audioshelf.db'), p.join(newD, 'audioshelf.db'));
    await _copyFileIfExists(
        p.join(oldDir, 'settings.json'), p.join(newD, 'settings.json'));
    await _copyDir(p.join(oldDir, 'covers'), p.join(newD, 'covers'));

    final def = await defaultDir();
    await Directory(def).create(recursive: true);
    await File(p.join(def, '.datadir')).writeAsString(newD);

    _dataDir = newD;
    logInfo('DataDir', 'Migrated data dir: $oldDir -> $newD');
    return newD;
  }

  Future<void> _copyFileIfExists(String src, String dst) async {
    final s = File(src);
    if (!s.existsSync()) return;
    await File(dst).parent.create(recursive: true);
    await s.copy(dst);
  }

  Future<void> _copyDir(String src, String dst) async {
    final s = Directory(src);
    if (!s.existsSync()) return;
    await for (final entity in s.list(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: src);
        final target = File(p.join(dst, rel));
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
  }
}
