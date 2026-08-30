/// 数据库 DDL 建表语句 & 迁移
class Tables {
  Tables._();

  static const int version = 1;

  static const List<String> createStatements = [
    // 作品集（专辑）
    '''
    CREATE TABLE works (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT    NOT NULL,
      cover_path  TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    )
    ''',

    // 虚拟文件夹（镜像磁盘目录树）
    '''
    CREATE TABLE folders (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      name    TEXT    NOT NULL,
      parent  INTEGER REFERENCES folders(id),
      work_id INTEGER REFERENCES works(id),
      UNIQUE(name, parent)
    )
    ''',

    // 文件夹路径映射
    '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path)',

    // 音频曲目
    '''
    CREATE TABLE tracks (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      path          TEXT    NOT NULL UNIQUE,
      filename      TEXT    NOT NULL,
      title         TEXT,
      artist        TEXT,
      album         TEXT,
      duration_ms   INTEGER,
      format        TEXT,
      file_size     INTEGER,
      file_mtime    INTEGER,
      subtitle_path TEXT,
      cover_path    TEXT,
      added_at      INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tracks_path ON tracks(path)',

    // 标签
    '''
    CREATE TABLE tags (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace  TEXT    NOT NULL DEFAULT 'general',
      name       TEXT    NOT NULL,
      color      TEXT    NOT NULL DEFAULT '#cba6f7',
      UNIQUE(namespace, name)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tags_namespace ON tags(namespace)',
    'CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)',

    // 曲目↔标签 多对多
    '''
    CREATE TABLE track_tags (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (track_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_track_tags_tag ON track_tags(tag_id)',

    // 文件夹↔标签 多对多
    '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',
  ];

  /// 迁移脚本（按 version 递增）
  static const Map<int, List<String>> migrations = {};
}
