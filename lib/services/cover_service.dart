import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../utils/log_util.dart';
import 'data_dir_service.dart';

/// 封面服务：内嵌图提取、自定义封面导入、封面文件定位
class CoverService {
  CoverService._();

  static Future<String> _coversDir() async {
    final dir = p.join(await DataDirService.instance.dataDir, 'covers');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// 将内嵌封面字节写入缓存，返回路径
  static Future<String?> writeEmbedded(
      int trackId, Uint8List bytes, String mime) async {
    try {
      final ext = _extFromMime(mime);
      final dir = await _coversDir();
      final file = File(p.join(dir, 'track_$trackId.$ext'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      logWarn('Cover', '写入内嵌封面失败: $e');
      return null;
    }
  }

  /// 导入自定义封面（拷贝到数据目录），返回新路径
  static Future<String?> importCover(String srcPath, int workId) async {
    try {
      final src = File(srcPath);
      if (!src.existsSync()) return null;
      final ext = p.extension(srcPath).toLowerCase();
      final safeExt = const {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}
              .contains(ext)
          ? ext
          : '.jpg';
      final dir = await _coversDir();
      final dest = File(p.join(dir, 'work_$workId$safeExt'));
      await src.copy(dest.path);
      logInfo('Cover', '导入封面: $srcPath → ${dest.path}');
      return dest.path;
    } catch (e) {
      logWarn('Cover', '导入封面失败: $e');
      return null;
    }
  }

  static String _extFromMime(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('bmp')) return 'bmp';
    return 'jpg';
  }
}
