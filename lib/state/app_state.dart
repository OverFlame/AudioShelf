import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/folder_dao.dart';
import '../db/tag_dao.dart';
import '../db/track_dao.dart';
import '../db/work_dao.dart';
import '../services/data_dir_service.dart';
import '../services/import_service.dart';
import '../services/settings_service.dart';
import '../services/subtitle_parser.dart';
import '../utils/filter_expression.dart';
import '../utils/log_util.dart';
import 'player_controller.dart';

/// 标签筛选规则
class TagFilter {
  final List<int> andTagIds;
  final List<int> orTagIds;
  final List<int> notTagIds;

  const TagFilter({
    this.andTagIds = const [],
    this.orTagIds = const [],
    this.notTagIds = const [],
  });

  bool get active =>
      andTagIds.isNotEmpty || orTagIds.isNotEmpty || notTagIds.isNotEmpty;
}

/// 应用状态 — 作品集 / 文件夹导航 / 曲目 / 标签 / 导入 / 播放
class AppState extends ChangeNotifier {
  final PlayerController player;

  // ── 作品集 ──
  List<Work> _works = [];
  List<Work> get works => _works;
  Work? _currentWork;
  Work? get currentWork => _currentWork;
  List<VirtualFolder> _unassignedFolders = [];
  List<VirtualFolder> get unassignedFolders => _unassignedFolders;

  // ── 文件夹导航 ──
  int? _currentFolderId;
  int? get currentFolderId => _currentFolderId;
  VirtualFolder? _currentFolder;
  VirtualFolder? get currentFolder => _currentFolder;
  String? _currentFolderPath;
  String? get currentFolderPath => _currentFolderPath;
  List<VirtualFolder> _breadcrumb = [];
  List<VirtualFolder> get breadcrumb => _breadcrumb;
  int _folderVersion = 0;
  int get folderVersion => _folderVersion;

  // ── 中间栏内容 ──
  List<VirtualFolder> _centerFolders = [];
  List<VirtualFolder> get centerFolders => _centerFolders;
  List<TrackItem> _tracks = [];
  List<TrackItem> get tracks => _tracks;
  bool _loading = false;
  bool get loading => _loading;

  // ── 搜索 ──
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ── 标签 ──
  List<Tag> _allTags = [];
  List<Tag> get allTags => _allTags;
  final Map<int, List<Tag>> _trackTags = {};
  TagFilter _tagFilter = const TagFilter();
  TagFilter get tagFilter => _tagFilter;
  String _advancedFilter = '';
  String get advancedFilter => _advancedFilter;
  bool get hasAdvancedFilter => _advancedFilter.trim().isNotEmpty;

  // ── 导入状态 ──
  bool _importing = false;
  bool get importing => _importing;
  double _importProgress = 0;
  double get importProgress => _importProgress;

  // ── 设置 ──
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  String _sortKey = 'filename';
  String get sortKey => _sortKey;
  bool _sortDescending = false;
  bool get sortDescending => _sortDescending;

  // ── 字幕缓存 ──
  final Map<String, List<LyricLine>> _subtitleCache = {};

  // ═══════════════ DAO 便捷访问 ═══════════════

  WorkDao get _workDao => WorkDao(DatabaseManager.instance.db);
  FolderDao get _folderDao => FolderDao(DatabaseManager.instance.db);
  TrackDao get _trackDao => TrackDao(DatabaseManager.instance.db);
  TagDao get _tagDao => TagDao(DatabaseManager.instance.db);

  AppState({required this.player});

  Future<void> init() async {
    logInfo('AppState', 'Initializing...');
    await loadSettings();
    await loadTags();
    await refresh();
    logInfo('AppState', 'Initialized OK');
  }

  // ═══════════════ 设置 ═══════════════

  Future<void> loadSettings() async {
    final ss = SettingsService.instance;
    _themeMode = ss.themeMode;
    _sortKey = ss.sortKey;
    _sortDescending = ss.sortDescending;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.instance.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setSortKey(String key) async {
    _sortKey = key;
    await SettingsService.instance.setSortKey(key);
    await refresh();
  }

  Future<void> setSortDescending(bool desc) async {
    _sortDescending = desc;
    await SettingsService.instance.setSortDescending(desc);
    await refresh();
  }

  // ═══════════════ 刷新 / 中间栏加载 ═══════════════

  Future<void> refresh() async {
    logInfo('AppState', 'refresh()');
    _subtitleCache.clear();
    _works = await _workDao.listAll();
    _unassignedFolders = await _folderDao.listUnassignedRoots();
    notifyListeners();
    await _loadCenter();
  }

  Future<void> _loadCenter() async {
    _loading = true;
    notifyListeners();
    try {
      final search = _searchQuery.trim();
      final filterActive = hasAdvancedFilter || _tagFilter.active;

      if (search.isNotEmpty) {
        _centerFolders = [];
        var list = await _trackDao.searchByName(search);
        if (filterActive) {
          final ids = await _computeMatchingIds();
          list = list.where((t) => ids.contains(t.id)).toList();
        }
        _tracks = _sortTracks(list);
        return;
      }

      List<VirtualFolder> folders;
      List<TrackItem> tracks;
      if (_currentWork != null && _currentFolderId != null) {
        folders = await _folderDao.listChildren(_currentFolderId!);
        tracks = _currentFolderPath == null
            ? <TrackItem>[]
            : await _trackDao.queryDirectInDir(_currentFolderPath!);
      } else if (_currentWork != null) {
        // 严格按文件夹树：作品层只显示入口子文件夹，不直接平铺曲目
        folders = await _folderDao.listRootsByWork(_currentWork!.id!);
        tracks = const [];
      } else {
        folders = const [];
        tracks = const [];
      }

      if (filterActive) {
        final ids = await _computeMatchingIds();
        tracks = tracks.where((t) => ids.contains(t.id)).toList();
        folders = await _filterFolders(folders, ids);
      }

      _centerFolders = _sortFolders(folders);
      _tracks = _sortTracks(tracks);
      logInfo('AppState',
          'Center loaded: ${_centerFolders.length} folders, ${_tracks.length} tracks');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Set<int>> _computeMatchingIds() async {
    if (hasAdvancedFilter) {
      return _tagDao.getTrackIdsByExpression(_advancedFilter, _allTags);
    }
    return _tagDao.getTrackIdsByTags(
      andTagIds: _tagFilter.andTagIds,
      orTagIds: _tagFilter.orTagIds,
      notTagIds: _tagFilter.notTagIds,
    );
  }

  Future<List<VirtualFolder>> _filterFolders(
      List<VirtualFolder> folders, Set<int> matchingIds) async {
    if (folders.isEmpty) return [];
    final matchingPaths =
        matchingIds.isEmpty ? <String>[] : await _trackDao.pathsByIds(matchingIds);

    Map<int, List<Tag>> folderTags = {};
    if (!hasAdvancedFilter && _tagFilter.active) {
      folderTags =
          await _tagDao.getTagsForFolders(folders.map((f) => f.id!).toList());
    }

    final result = <VirtualFolder>[];
    for (final f in folders) {
      final paths = await _folderDao.getPaths(f.id!);
      final containsTrack =
          paths.any((p) => matchingPaths.any((mp) => _isUnderPath(mp, p.path)));
      if (containsTrack) {
        result.add(f);
        continue;
      }
      if (!hasAdvancedFilter && _tagFilter.active) {
        final tags = folderTags[f.id] ?? const <Tag>[];
        if (_folderTagsMatch(tags)) result.add(f);
      }
    }
    return result;
  }

  bool _folderTagsMatch(List<Tag> tags) {
    final ids = tags.map((t) => t.id).whereType<int>().toSet();
    if (_tagFilter.andTagIds.any((id) => !ids.contains(id))) return false;
    if (_tagFilter.orTagIds.isNotEmpty &&
        !_tagFilter.orTagIds.any((id) => ids.contains(id))) {
      return false;
    }
    if (_tagFilter.notTagIds.any((id) => ids.contains(id))) return false;
    return true;
  }

  bool _isUnderPath(String path, String dir) {
    final a = path.toLowerCase();
    var b = dir.toLowerCase();
    if (b.endsWith('\\') || b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (a == b) return false;
    return a.startsWith('$b\\') || a.startsWith('$b/');
  }

  List<VirtualFolder> _sortFolders(List<VirtualFolder> list) {
    // 先复制：入参可能是 const []（不可变），直接 sort 会抛 Unsupported operation
    final sorted = List<VirtualFolder>.from(list);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<TrackItem> _sortTracks(List<TrackItem> list) {
    final sorted = List<TrackItem>.from(list);
    final dir = _sortDescending ? -1 : 1;
    sorted.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'title':
          cmp = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          break;
        case 'duration':
          cmp = (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
          break;
        case 'added_at':
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
        default:
          cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
          break;
      }
      if (cmp == 0) {
        cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      }
      return cmp * dir;
    });
    return sorted;
  }

  // ═══════════════ 搜索 ═══════════════

  void setSearchQuery(String q) {
    _searchQuery = q;
    refresh();
  }

  // ═══════════════ 导航 ═══════════════

  Future<void> goHome() async {
    _currentWork = null;
    _currentFolderId = null;
    _currentFolder = null;
    _currentFolderPath = null;
    _breadcrumb = [];
    await refresh();
  }

  Future<void> enterWork(int workId) async {
    final work = await _workDao.getById(workId);
    if (work == null) return;
    _currentWork = work;
    _currentFolderId = null;
    _currentFolder = null;
    _currentFolderPath = null;
    _breadcrumb = [VirtualFolder(id: -1, name: work.name, workId: work.id)];
    await refresh();
  }

  Future<void> enterFolder(int folderId) async {
    final folder = await _folderDao.getById(folderId);
    if (folder == null) return;
    _currentFolderId = folderId;
    _currentFolder = folder;
    final paths = await _folderDao.getPaths(folderId);
    _currentFolderPath = paths.isEmpty ? null : paths.first.path;
    // 若文件夹属于某作品，确保 currentWork 一致
    if (folder.workId != null && _currentWork?.id != folder.workId) {
      final w = await _workDao.getById(folder.workId!);
      if (w != null) _currentWork = w;
    }
    _breadcrumb = await _buildBreadcrumb();
    await refresh();
  }

  Future<void> goUp() async {
    if (_currentFolderId == null) {
      await enterWorkOrHome();
      return;
    }
    final parent = _currentFolder?.parentId;
    if (parent == null) {
      // 回到作品层
      if (_currentWork != null) {
        await enterWork(_currentWork!.id!);
      } else {
        await goHome();
      }
      return;
    }
    await enterFolder(parent);
  }

  Future<void> enterWorkOrHome() async {
    if (_currentWork != null) {
      await enterWork(_currentWork!.id!);
    } else {
      await goHome();
    }
  }

  Future<List<VirtualFolder>> _buildBreadcrumb() async {
    final work = _currentWork;
    final chain = <VirtualFolder>[];
    var cur = _currentFolder;
    while (cur != null) {
      chain.insert(0, cur);
      if (cur.parentId == null) break;
      cur = await _folderDao.getById(cur.parentId!);
    }
    // work 作为首层标记
    if (work != null) {
      chain.insert(
          0,
          VirtualFolder(
              id: -1, name: work.name, parentId: null, workId: work.id));
    }
    return chain;
  }

  // ═══════════════ 作品集操作 ═══════════════

  Future<Work> createWork(String name) async {
    final work = await _workDao.create(name);
    await refresh();
    return work;
  }

  Future<void> renameWork(int id, String name) async {
    await _workDao.rename(id, name);
    if (_currentWork?.id == id) {
      _currentWork = Work(
          id: id,
          name: name,
          coverPath: _currentWork!.coverPath,
          createdAt: _currentWork!.createdAt);
    }
    await refresh();
  }

  Future<void> deleteWork(int id) async {
    await _workDao.detachFolders(id);
    await _workDao.delete(id);
    if (_currentWork?.id == id) {
      await goHome();
    } else {
      await refresh();
    }
  }

  Future<void> setWorkCover(int id, String? coverPath) async {
    await _workDao.setCover(id, coverPath);
    if (_currentWork?.id == id) {
      _currentWork = Work(
          id: id,
          name: _currentWork!.name,
          coverPath: coverPath,
          createdAt: _currentWork!.createdAt);
    }
    notifyListeners();
    await refresh();
  }

  // ═══════════════ 文件夹操作 ═══════════════

  Future<void> renameFolder(int id, String newName) async {
    await _folderDao.rename(id, newName);
    _folderVersion++;
    await refresh();
  }

  Future<void> deleteFolder(int id) async {
    await _folderDao.delete(id);
    _folderVersion++;
    if (_currentFolderId == id) {
      _currentFolderId = null;
      _currentFolder = null;
      _currentFolderPath = null;
    }
    await refresh();
  }

  /// 把文件夹（及其后代）移动到另一作品
  Future<void> moveFolderToWork(int folderId, int? workId) async {
    final ids = await _folderDao.collectDescendants(folderId);
    for (final id in ids) {
      await _folderDao.setWork(id, workId);
    }
    _folderVersion++;
    await refresh();
  }

  Future<List<Work>> loadWorks() => _workDao.listAll();

  // ═══════════════ 导入 ═══════════════

  /// 导入目录（自动创建同名作品）
  Future<Work?> importDirectory(String dirPath) async {
    final name = _baseName(dirPath);
    final work = await _workDao.create(name);
    await _runImport(dirPath, work.id!);
    return work;
  }

  /// 导入目录到指定作品（合并）
  Future<void> importDirectoryIntoWork(String dirPath, int workId) async {
    await _runImport(dirPath, workId);
  }

  Future<void> _runImport(String dirPath, int workId) async {
    _importing = true;
    _importProgress = 0;
    notifyListeners();
    try {
      final importService = ImportService.fromDB();
      await for (final p in importService.importDirectory(dirPath, workId: workId)) {
        _importProgress = p.percent;
        notifyListeners();
      }
    } catch (e) {
      logError('AppState', '导入失败', e.toString());
    } finally {
      _importing = false;
      _importProgress = 0;
      notifyListeners();
      _folderVersion++;
      await refresh();
    }
  }

  String _baseName(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    final base = idx >= 0 ? path.substring(idx + 1) : path;
    return base.isEmpty ? path : base;
  }

  // ═══════════════ 标签 ═══════════════

  Future<void> loadTags() async {
    _allTags = await _tagDao.getAll();
    notifyListeners();
  }

  Future<List<Tag>> getTrackTags(int trackId) async {
    if (_trackTags.containsKey(trackId)) return _trackTags[trackId]!;
    final tags = await _tagDao.getTagsForTrack(trackId);
    _trackTags[trackId] = tags;
    return tags;
  }

  Future<void> toggleTagOnTrack(int trackId, Tag tag) async {
    final current = _trackTags[trackId] ?? await _tagDao.getTagsForTrack(trackId);
    final has = current.any((t) => t.id == tag.id);
    if (has) {
      await _tagDao.removeTagFromTrack(trackId, tag.id!);
      current.removeWhere((t) => t.id == tag.id);
    } else {
      await _tagDao.addTagToTrack(trackId, tag.id!);
      current.add(tag);
    }
    _trackTags[trackId] = current;
    notifyListeners();
  }

  Future<void> addTagToFolder(int folderId, Tag tag) async {
    await _tagDao.addTagToFolder(folderId, tag.id!);
    _folderVersion++;
    notifyListeners();
  }

  Future<List<Tag>> getFolderTags(int folderId) =>
      _tagDao.getTagsForFolder(folderId);

  Future<Tag> createTag(String name,
      {String namespace = '', String color = '#cba6f7'}) async {
    final ns = namespace.isEmpty ? 'general' : namespace;
    final match = _allTags.where((t) =>
        t.name.toLowerCase() == name.toLowerCase() && t.namespace == ns);
    if (match.isNotEmpty) return match.first;
    final tag = await _tagDao.insert(Tag(name: name, namespace: ns, color: color));
    await loadTags();
    return tag;
  }

  Future<void> deleteTag(int tagId) async {
    await _tagDao.delete(tagId);
    _trackTags.clear();
    _removeFromFilter(tagId);
    await loadTags();
    await refresh();
  }

  void _removeFromFilter(int tagId) {
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
  }

  // 标签筛选
  void toggleAndFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.andTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: list,
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
    refresh();
  }

  void toggleOrFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.orTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: list,
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
    refresh();
  }

  void toggleNotFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.notTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: list,
    );
    refresh();
  }

  void clearTagFilters() {
    _tagFilter = const TagFilter();
    refresh();
  }

  Future<void> setAdvancedFilter(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) {
      await clearAdvancedFilter();
      return;
    }
    FilterExpressionParser.parse(expr);
    _advancedFilter = expr;
    _tagFilter = const TagFilter();
    await SettingsService.instance.addExpression(expr);
    await refresh();
  }

  Future<void> clearAdvancedFilter() async {
    if (!hasAdvancedFilter) return;
    _advancedFilter = '';
    await refresh();
  }

  // ═══════════════ 播放 ═══════════════

  /// 播放当前列表从 [startIndex] 开始
  Future<void> playTracks(List<TrackItem> list, int startIndex) async {
    await player.playQueue(list, startIndex: startIndex);
  }

  Future<void> playAllCurrent() async {
    if (_tracks.isEmpty) return;
    await player.playQueue(_tracks, startIndex: 0);
  }

  Future<void> playTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await player.playQueue(_tracks, startIndex: index);
  }

  // ═══════════════ 字幕 / 封面 ═══════════════

  List<LyricLine> getSubtitleLines(TrackItem track) {
    final p = track.subtitlePath;
    if (p == null || p.isEmpty) return const [];
    return _subtitleCache.putIfAbsent(
        track.path, () => SubtitleParser.parseFile(p));
  }

  Future<void> replaceSubtitle(int trackId, String newPath) async {
    await _trackDao.setSubtitlePath(trackId, newPath);
    _subtitleCache.clear();
    // 更新内存中的曲目
    _tracks = _tracks
        .map((t) => t.id == trackId
            ? t.copyWith(subtitlePath: newPath)
            : t)
        .toList();
    notifyListeners();
  }

  Future<void> clearSubtitle(int trackId) async {
    await _trackDao.setSubtitlePath(trackId, null);
    _subtitleCache.clear();
    _tracks = _tracks
        .map((t) => t.id == trackId ? t.copyWith(subtitlePath: null) : t)
        .toList();
    notifyListeners();
  }

  /// 当前曲目封面：优先作品封面，否则曲目内嵌封面
  String? coverForTrack(TrackItem track) {
    final wc = _currentWork?.coverPath;
    if (wc != null && File(wc).existsSync()) return wc;
    if (track.coverPath != null && File(track.coverPath!).existsSync()) {
      return track.coverPath;
    }
    return null;
  }

  // ═══════════════ 数据目录 ═══════════════

  Future<String> getDataDir() => DataDirService.instance.dataDir;
}
