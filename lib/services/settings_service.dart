import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/log_util.dart';
import 'data_dir_service.dart';

/// 持久化设置服务（JSON 文件，位于数据目录 settings.json）。
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  Map<String, dynamic> _data = {};

  Future<File> _file() async {
    return File(p.join(await DataDirService.instance.dataDir, 'settings.json'));
  }

  Future<void> init() async {
    final f = await _file();
    if (f.existsSync()) {
      try {
        _data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        logWarn('Settings', '解析 settings.json 失败: $e');
        _data = {};
      }
    }
    logInfo('Settings', 'Initialized OK');
  }

  Future<void> _save() async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(_data));
  }

  // ── 主题 ──
  ThemeMode get themeMode {
    final v = _data['theme_mode'] as String? ?? 'dark';
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _data['theme_mode'] = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _save();
  }

  // ── 曲目排序 ──
  String get sortKey => (_data['sort_key'] as String?) ?? 'filename';

  Future<void> setSortKey(String key) async {
    _data['sort_key'] = key;
    await _save();
  }

  bool get sortDescending => (_data['sort_desc'] as bool?) ?? false;

  Future<void> setSortDescending(bool desc) async {
    _data['sort_desc'] = desc;
    await _save();
  }

  // ── 高级筛选表达式历史 ──
  List<String> get expressionHistory {
    final raw = _data['expr_history'];
    if (raw is List) return raw.whereType<String>().toList();
    return const [];
  }

  int get maxExprCacheCount => (_data['expr_cache_count'] as int?) ?? 10;

  Future<void> setMaxExprCacheCount(int count) async {
    _data['expr_cache_count'] = count.clamp(0, 100);
    await _save();
    final list = expressionHistory;
    final cap = _data['expr_cache_count'] as int;
    if (list.length > cap) {
      _data['expr_history'] = list.sublist(0, cap);
      await _save();
    }
  }

  Future<void> addExpression(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) return;
    final list = expressionHistory.where((e) => e != expr).toList();
    list.insert(0, expr);
    final cap = maxExprCacheCount;
    _data['expr_history'] = cap <= 0 ? const <String>[] : list.take(cap).toList();
    await _save();
  }

  Future<void> clearExpressionHistory() async {
    _data['expr_history'] = const <String>[];
    await _save();
  }
}
