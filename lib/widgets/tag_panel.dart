import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../services/media_bridge.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'dialogs.dart';

/// 左侧面板：导入 + 作品集 + 标签筛选
class TagPanel extends StatefulWidget {
  const TagPanel({super.key});

  @override
  State<TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<TagPanel> {
  final _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        _importSection(appState),
        const Divider(height: 1),
        _librarySection(appState),
        const Divider(height: 1),
        Expanded(child: _tagSection(appState)),
      ],
    );
  }

  // ── 导入 ──
  Widget _importSection(AppState appState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _pathController,
                    enabled: !appState.importing,
                    onSubmitted: (_) => _addFromPath(appState),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '输入文件夹路径，回车添加',
                      hintStyle:
                          TextStyle(fontSize: 11, color: AppColors.mutedLight),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 32,
                child: IconButton(
                  onPressed:
                      appState.importing ? null : () => _addFromPath(appState),
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: '从路径添加',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    backgroundColor: AppColors.surface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed:
                  appState.importing ? null : () => _pickFolder(appState),
              icon: Icon(
                appState.importing ? Icons.hourglass_empty : Icons.create_new_folder,
                size: 14,
              ),
              label: Text(
                appState.importing ? '导入中...' : '添加文件夹',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
          if (appState.importing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: appState.importProgress,
                backgroundColor: AppColors.surface,
                color: AppColors.accent,
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addFromPath(AppState appState) async {
    if (!await _ensureAllFilesAccess()) return;
    final text = _pathController.text.trim();
    if (text.isEmpty) return;
    _pathController.clear();
    await appState.importDirectory(text);
  }

  Future<void> _pickFolder(AppState appState) async {
    if (!await _ensureAllFilesAccess()) return;
    final result = await pickDirectoryPath(title: '选择包含音频的文件夹');
    if (result != null) {
      await appState.importDirectory(result);
    }
  }

  /// Android 上导入前检查「所有文件访问」授权；未授权则跳转系统设置并提示
  Future<bool> _ensureAllFilesAccess() async {
    final bridge = MediaBridge.instance;
    if (!bridge.isAndroid) return true;
    if (await bridge.hasAllFilesAccess()) return true;
    await bridge.requestAllFilesAccess();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请在系统设置中授予「所有文件访问」权限后重试')),
      );
    }
    return false;
  }

  // ── 作品集 ──
  Widget _librarySection(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
          child: Row(
            children: [
              const Text('作品集',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedLight)),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => _createWork(appState),
                icon: const Icon(Icons.add_circle_outline,
                    size: 15, color: AppColors.muted),
                tooltip: '新建空作品',
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              _navEntry(
                selected: appState.currentWork == null,
                icon: Icons.home_outlined,
                label: '全部作品',
                onTap: () => appState.goHome(),
              ),
              for (final w in appState.works)
                _navEntry(
                  selected: appState.currentWork?.id == w.id,
                  icon: Icons.album_outlined,
                  label: w.name,
                  onTap: () => appState.enterWork(w.id!),
                ),
              for (final f in appState.unassignedFolders)
                _navEntry(
                  selected: appState.currentFolderId == f.id,
                  icon: Icons.folder_outlined,
                  label: '未归类 · ${f.name}',
                  onTap: () => appState.enterFolder(f.id!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createWork(AppState appState) async {
    final name = await promptText(context, title: '新建空作品');
    if (name != null && name.isNotEmpty) {
      await appState.createWork(name);
    }
  }

  Widget _navEntry({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.surface : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: selected ? AppColors.accent : AppColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 标签筛选 ──
  Widget _tagSection(AppState appState) {
    final tags = appState.allTags;
    final groups = <String, List<Tag>>{};
    for (final t in tags) {
      groups.putIfAbsent(t.namespace, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 2),
          child: Row(
            children: [
              const Text('标签筛选',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedLight)),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                tooltip: '高级筛选表达式',
                onPressed: () => _advancedFilter(appState),
                icon: Icon(Icons.functions,
                    size: 15,
                    color: appState.hasAdvancedFilter
                        ? AppColors.accent
                        : AppColors.muted),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                tooltip: '清除筛选',
                onPressed: () {
                  appState.clearTagFilters();
                  appState.clearAdvancedFilter();
                },
                icon: const Icon(Icons.clear_all,
                    size: 15, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 2),
                  child: Text(entry.key,
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.namespaceColor(entry.key))),
                ),
                for (final t in entry.value) _tagRow(appState, t),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagRow(AppState appState, Tag tag) {
    final id = tag.id;
    final inAnd = id != null && appState.tagFilter.andTagIds.contains(id);
    final inOr = id != null && appState.tagFilter.orTagIds.contains(id);
    final inNot = id != null && appState.tagFilter.notTagIds.contains(id);

    IconData icon;
    Color color;
    if (inAnd) {
      icon = Icons.check_circle;
      color = AppColors.success;
    } else if (inOr) {
      icon = Icons.add_circle;
      color = AppColors.blue;
    } else if (inNot) {
      icon = Icons.cancel;
      color = AppColors.danger;
    } else {
      icon = Icons.circle_outlined;
      color = AppColors.muted;
    }

    return InkWell(
      onTap: () {
        if (id == null) return;
        if (inAnd) {
          appState.toggleOrFilter(id);
        } else if (inOr) {
          appState.toggleNotFilter(id);
        } else if (inNot) {
          appState.clearTagFilters();
        } else {
          appState.toggleAndFilter(id);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: (inAnd || inOr || inNot)
                          ? AppColors.textPrimary
                          : AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _advancedFilter(AppState appState) async {
    final expr = await promptText(context,
        title: '高级筛选表达式',
        initial: appState.advancedFilter,
        hint: '例如 (A||B)&&!C');
    if (expr == null) return;
    try {
      await appState.setAdvancedFilter(expr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('表达式错误：$e')));
      }
    }
  }
}
