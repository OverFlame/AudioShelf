import 'package:sqflite/sqflite.dart';
import '../utils/log_util.dart';

/// 音频曲目
class TrackItem {
  final int? id;
  final String path;
  final String filename;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final String? format;
  final int? fileSize;
  final int? fileMtime;
  final String? subtitlePath;
  final String? coverPath;
  final int addedAt;

  const TrackItem({
    this.id,
    required this.path,
    required this.filename,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.format,
    this.fileSize,
    this.fileMtime,
    this.subtitlePath,
    this.coverPath,
    required this.addedAt,
  });

  /// 显示标题：直接显示源文件名（含扩展名）
  String get displayTitle => filename;

  TrackItem copyWith({
    String? subtitlePath,
    String? coverPath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    return TrackItem(
      id: id,
      path: path,
      filename: filename,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      format: format,
      fileSize: fileSize,
      fileMtime: fileMtime,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      coverPath: coverPath ?? this.coverPath,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'path': path,
        'filename': filename,
        'title': title,
        'artist': artist,
        'album': album,
        'duration_ms': durationMs,
        'format': format,
        'file_size': fileSize,
        'file_mtime': fileMtime,
        'subtitle_path': subtitlePath,
        'cover_path': coverPath,
        'added_at': addedAt,
      };

  factory TrackItem.fromMap(Map<String, dynamic> map) => TrackItem(
        id: map['id'] as int?,
        path: map['path'] as String,
        filename: map['filename'] as String,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        durationMs: map['duration_ms'] as int?,
        format: map['format'] as String?,
        fileSize: map['file_size'] as int?,
        fileMtime: map['file_mtime'] as int?,
        subtitlePath: map['subtitle_path'] as String?,
        coverPath: map['cover_path'] as String?,
        addedAt: map['added_at'] as int,
      );
}

class TrackDao {
  final Database _db;
  TrackDao(this._db);

  Future<int> insert(TrackItem track) async {
    return _db.insert('tracks', track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<TrackItem?> getById(int id) async {
    final rows = await _db.query('tracks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TrackItem.fromMap(rows.first);
  }

  Future<TrackItem?> getByPath(String path) async {
    final rows = await _db.query('tracks', where: 'path = ?', whereArgs: [path]);
    if (rows.isEmpty) return null;
    return TrackItem.fromMap(rows.first);
  }

  Future<int> update(TrackItem track) async {
    if (track.id == null) return 0;
    return _db.update('tracks', track.toMap(),
        where: 'id = ?', whereArgs: [track.id]);
  }

  Future<void> setSubtitlePath(int id, String? path) async {
    await _db.update('tracks', {'subtitle_path': path},
        where: 'id = ?', whereArgs: [id]);
    logDebug('TrackDao', 'setSubtitlePath id=$id -> $path');
  }

  Future<void> setCoverPath(int id, String? path) async {
    await _db.update('tracks', {'cover_path': path},
        where: 'id = ?', whereArgs: [id]);
    logDebug('TrackDao', 'setCoverPath id=$id -> $path');
  }

  /// 给定一批路径，返回已在数据库中的路径集合（用于导入去重）
  Future<Set<String>> existingPaths(List<String> paths) async {
    if (paths.isEmpty) return {};
    const batchSize = 500;
    final existing = <String>{};
    for (int i = 0; i < paths.length; i += batchSize) {
      final end =
          i + batchSize > paths.length ? paths.length : i + batchSize;
      final batch = paths.sublist(i, end);
      final placeholders = batch.map((_) => '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT path FROM tracks WHERE path IN ($placeholders)',
        batch,
      );
      for (final row in rows) {
        existing.add(row['path'] as String);
      }
    }
    return existing;
  }

  /// 某目录下「直接包含」的曲目（不含更深层子目录）
  Future<List<TrackItem>> queryDirectInDir(String dirPath,
      {String? search, String orderBy = 'filename'}) async {
    final (prefix, sep) = _directPrefix(dirPath);
    final conditions = <String>['path LIKE ?', 'path NOT LIKE ?'];
    final args = <dynamic>['$prefix%', '$prefix%$sep%'];
    if (search != null && search.isNotEmpty) {
      conditions.add('(filename LIKE ? OR title LIKE ?)');
      args.add('%$search%');
      args.add('%$search%');
    }
    final rows = await _db.query(
      'tracks',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: orderBy,
    );
    return rows.map(TrackItem.fromMap).toList();
  }

  /// 匹配多个路径前缀中的曲目（用于作品/文件夹递归）
  Future<List<TrackItem>> queryByDirs(List<String> dirPaths,
      {String orderBy = 'filename'}) async {
    if (dirPaths.isEmpty) return [];
    final conditions = dirPaths.map((_) => 'path LIKE ?').join(' OR ');
    final args = dirPaths.map((p) => '$p%').toList();
    final rows = await _db.query('tracks',
        where: conditions, whereArgs: args, orderBy: orderBy);
    return rows.map(TrackItem.fromMap).toList();
  }

  /// 按文件名/标题/艺术家模糊搜索
  Future<List<TrackItem>> searchByName(String q, {int limit = 100000}) async {
    final rows = await _db.query(
      'tracks',
      where: 'filename LIKE ? OR title LIKE ? OR artist LIKE ? OR album LIKE ?',
      whereArgs: ['%$q%', '%$q%', '%$q%', '%$q%'],
      orderBy: 'filename',
      limit: limit,
    );
    return rows.map(TrackItem.fromMap).toList();
  }

  /// 查询一批曲目 id 对应的路径
  Future<List<String>> pathsByIds(Set<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await _db.query('tracks',
        columns: ['path'],
        where: 'id IN ($placeholders)',
        whereArgs: ids.toList());
    return rows.map((r) => r['path'] as String).toList();
  }

  Future<List<TrackItem>> queryByIds(Set<int> ids,
      {String orderBy = 'filename'}) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await _db.query('tracks',
        where: 'id IN ($placeholders)',
        whereArgs: ids.toList(),
        orderBy: orderBy);
    return rows.map(TrackItem.fromMap).toList();
  }

  Future<List<TrackItem>> queryAll({String orderBy = 'filename'}) async {
    final rows = await _db.query('tracks', orderBy: orderBy);
    return rows.map(TrackItem.fromMap).toList();
  }

  Future<int> deleteByPaths(List<String> paths) async {
    if (paths.isEmpty) return 0;
    const batchSize = 500;
    int deleted = 0;
    for (int i = 0; i < paths.length; i += batchSize) {
      final end =
          i + batchSize > paths.length ? paths.length : i + batchSize;
      final batch = paths.sublist(i, end);
      final placeholders = batch.map((_) => '?').join(',');
      deleted += await _db.delete('tracks',
          where: 'path IN ($placeholders)', whereArgs: batch);
    }
    return deleted;
  }

  // ═══ 播放历史 ═══

  /// 记录一次播放（插入历史）
  Future<void> recordPlay(int trackId, int playedAt) async {
    await _db.insert('play_history',
        {'track_id': trackId, 'played_at': playedAt});
    // 仅保留最近 200 条，避免无限增长
    await _db.rawDelete(
        'DELETE FROM play_history WHERE id NOT IN '
        '(SELECT id FROM play_history ORDER BY played_at DESC LIMIT 200)');
  }

  /// 最近播放的曲目（按最后播放时间倒序，去重）
  Future<List<TrackItem>> recentPlayedTracks({int limit = 50}) async {
    final rows = await _db.rawQuery('''
      SELECT t.*, MAX(h.played_at) AS last_played
      FROM play_history h
      INNER JOIN tracks t ON t.id = h.track_id
      GROUP BY h.track_id
      ORDER BY last_played DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(TrackItem.fromMap).toList();
  }

  /// 归一化目录路径，返回 (带分隔符的前缀, 分隔符)
  static (String, String) _directPrefix(String dirPath) {
    var base = dirPath;
    if (base.endsWith('\\') || base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final sep = base.contains('\\') ? '\\' : '/';
    return ('$base$sep', sep);
  }
}
