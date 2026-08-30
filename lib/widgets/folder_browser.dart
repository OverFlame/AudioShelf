import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/folder_dao.dart';
import '../db/track_dao.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'dialogs.dart';

/// 中间栏：作品/文件夹浏览（面包屑 + 子文件夹 + 曲目列表）
class FolderBrowser extends StatelessWidget {
  const FolderBrowser({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        _breadcrumbBar(context, appState),
        _toolbar(context, appState),
        const Divider(height: 1),
        Expanded(child: _content(context, appState)),
      ],
    );
  }

  Widget _breadcrumbBar(BuildContext context, AppState appState) {
    final crumbs = appState.breadcrumb;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.panel,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.mutedLight),
            tooltip: '返回上一级',
            onPressed: () => appState.goUp(),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int i = 0; i < crumbs.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right,
                          size: 16, color: AppColors.muted),
                    ),
                  InkWell(
                    onTap: () => _onCrumbTap(appState, crumbs[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      child: Text(
                        crumbs[i].name,
                        style: TextStyle(
                          color: i == crumbs.length - 1
                              ? AppColors.textPrimary
                              : AppColors.mutedLight,
                          fontSize: 13,
                          fontWeight: i == crumbs.length - 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onCrumbTap(AppState appState, VirtualFolder crumb) {
    if (crumb.id == -1) {
      // 作品标记
      if (crumb.workId != null) appState.enterWork(crumb.workId!);
    } else {
      appState.enterFolder(crumb.id!);
    }
  }

  Widget _toolbar(BuildContext context, AppState appState) {
    final isWorkLevel = appState.currentFolderId == null;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.background,
      child: Row(
        children: [
          FilledButton.icon(
            onPressed:
                appState.tracks.isEmpty ? null : () => appState.playAllCurrent(),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text(isWorkLevel ? '播放全部' : '播放本文件夹'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          if (isWorkLevel && appState.currentWork != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _addFolderToWork(context, appState),
              icon: const Icon(Icons.create_new_folder_outlined, size: 15),
              label: const Text('添加文件夹到本作品'),
            ),
          ],
          const Spacer(),
          Text('${appState.tracks.length} 首',
              style: TextStyle(color: AppColors.mutedLight, fontSize: 12)),
          const SizedBox(width: 8),
          _sortMenu(appState),
        ],
      ),
    );
  }

  Future<void> _addFolderToWork(BuildContext context, AppState appState) async {
    final work = appState.currentWork;
    if (work == null) return;
    final path = await pickDirectoryPath(title: '选择要加入「${work.name}」的文件夹');
    if (path == null) return;
    await appState.importDirectoryIntoWork(path, work.id!);
  }

  Widget _sortMenu(AppState appState) {
    return PopupMenuButton<String>(
      tooltip: '排序',
      icon: const Icon(Icons.sort, size: 18, color: AppColors.mutedLight),
      onSelected: (v) {
        if (v == 'toggle') {
          appState.setSortDescending(!appState.sortDescending);
        } else {
          appState.setSortKey(v);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'filename',
          checked: appState.sortKey == 'filename',
          child: const Text('按文件名', style: TextStyle(fontSize: 13)),
        ),
        CheckedPopupMenuItem(
          value: 'title',
          checked: appState.sortKey == 'title',
          child: const Text('按标题', style: TextStyle(fontSize: 13)),
        ),
        CheckedPopupMenuItem(
          value: 'duration',
          checked: appState.sortKey == 'duration',
          child: const Text('按时长', style: TextStyle(fontSize: 13)),
        ),
        CheckedPopupMenuItem(
          value: 'added_at',
          checked: appState.sortKey == 'added_at',
          child: const Text('按导入时间', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: Text(
            appState.sortDescending ? '切换为升序' : '切换为降序',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, AppState appState) {
    final folders = appState.centerFolders;
    final tracks = appState.tracks;

    if (folders.isEmpty && tracks.isEmpty) {
      return Center(
        child: Text(
          appState.currentFolderId == null ? '该作品暂无内容' : '该文件夹为空',
          style: const TextStyle(color: AppColors.mutedLight, fontSize: 13),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final f in folders) _FolderTile(folder: f),
        if (folders.isNotEmpty && tracks.isNotEmpty)
          const Divider(height: 1),
        for (int i = 0; i < tracks.length; i++)
          _TrackTile(track: tracks[i], index: i),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final VirtualFolder folder;
  const _FolderTile({required this.folder});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return InkWell(
      onTap: () => appState.enterFolder(folder.id!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.folder, size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16, color: AppColors.muted),
              onSelected: (v) => _onMenu(context, appState, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('打开', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'move', child: Text('移动到作品...', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'tags', child: Text('添加标签...', style: TextStyle(fontSize: 13))),
                PopupMenuDivider(),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('删除（虚拟）', style: TextStyle(fontSize: 13, color: AppColors.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, AppState appState, String v) async {
    switch (v) {
      case 'open':
        await appState.enterFolder(folder.id!);
        break;
      case 'rename':
        final name = await promptText(context,
            title: '重命名文件夹', initial: folder.name);
        if (name != null && name.isNotEmpty) {
          await appState.renameFolder(folder.id!, name);
        }
        break;
      case 'move':
        final target = await showWorkPicker(context);
        if (target == null) return;
        await appState.moveFolderToWork(
            folder.id!, target == kUnassignedWork ? null : target);
        break;
      case 'tags':
        final tags = await showTagPickerDialog(context, title: '为文件夹添加标签');
        if (tags == null || tags.isEmpty) return;
        for (final t in tags) {
          await appState.addTagToFolder(folder.id!, t);
        }
        break;
      case 'delete':
        final ok = await confirmDialog(context,
            title: '删除文件夹「${folder.name}」？',
            content: '仅删除虚拟文件夹记录，磁盘文件保留。');
        if (ok == true) {
          await appState.deleteFolder(folder.id!);
        }
        break;
    }
  }
}

class _TrackTile extends StatelessWidget {
  final TrackItem track;
  final int index;
  const _TrackTile({required this.track, required this.index});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // 用 select 只监听当前曲目/播放态，避免随进度 tick 全量重建列表
    final isCurrent = context.select<PlayerController, bool>(
        (p) => p.currentTrack?.path == track.path);
    final isPlaying =
        context.select<PlayerController, bool>((p) => p.playing);

    return InkWell(
      onTap: () => appState.playTrackAt(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: isCurrent ? AppColors.surface : null,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: isCurrent
                  ? (isPlaying
                      ? const Icon(Icons.graphic_eq, size: 16, color: AppColors.accent)
                      : const Icon(Icons.play_arrow, size: 16, color: AppColors.accent))
                  : Text('${index + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [track.artist, track.album, track.format?.toUpperCase()]
                        .where((e) => e != null && e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (track.subtitlePath != null)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.subtitles, size: 15, color: AppColors.teal),
              ),
            if (track.durationMs != null)
              Text(
                formatDuration(Duration(milliseconds: track.durationMs!)),
                style: TextStyle(color: AppColors.mutedLight, fontSize: 12),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16, color: AppColors.muted),
              onSelected: (v) => _onMenu(context, appState, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'play', child: Text('播放', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'subtitle', child: Text('替换字幕...', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'clear_subtitle', child: Text('清除字幕', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'tags', child: Text('添加标签...', style: TextStyle(fontSize: 13))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, AppState appState, String v) async {
    switch (v) {
      case 'play':
        await appState.playTrackAt(index);
        break;
      case 'subtitle':
        if (track.id != null) {
          await showReplaceSubtitleDialog(context, track.id!);
        }
        break;
      case 'clear_subtitle':
        if (track.id != null) {
          await appState.clearSubtitle(track.id!);
        }
        break;
      case 'tags':
        if (track.id == null) return;
        final existing = (await appState.getTrackTags(track.id!))
            .map((t) => t.id)
            .whereType<int>()
            .toSet();
        if (!context.mounted) return;
        final tags =
            await showTagPickerDialog(context, title: '为曲目添加标签', selectedTagIds: existing);
        if (tags == null) return;
        for (final t in tags) {
          await appState.toggleTagOnTrack(track.id!, t);
        }
        break;
    }
  }
}
