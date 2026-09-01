import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/folder_browser.dart';
import '../widgets/player_bar.dart';
import '../widgets/tag_panel.dart';
import '../widgets/works_grid.dart';
import 'settings_page.dart';

/// 主页面：左侧面板 + 中间内容 + 底部播放栏
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AudioShelf',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          _searchBox(appState),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 260,
            color: AppColors.panelOf(context),
            child: const TagPanel(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: appState.loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : (appState.currentWork == null
                    ? Column(
                        children: [
                          if (appState.recentTracks.isNotEmpty)
                            _RecentBar(appState: appState),
                          const Expanded(child: WorksGrid()),
                        ],
                      )
                    : const FolderBrowser()),
          ),
        ],
      ),
      bottomNavigationBar: const PlayerBar(),
    );
  }

  Widget _searchBox(AppState appState) {
    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextField(
          decoration: const InputDecoration(
            hintText: '搜索曲目...',
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: appState.setSearchQuery,
        ),
      ),
    );
  }
}

/// 最近播放横条
class _RecentBar extends StatelessWidget {
  final AppState appState;
  const _RecentBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    final tracks = appState.recentTracks;
    return SizedBox(
      height: 122,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('最近播放',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context))),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: tracks.length,
              itemBuilder: (ctx, i) {
                final t = tracks[i];
                return InkWell(
                  onTap: () => appState.playRecentTracks(i),
                  child: SizedBox(
                    width: 100,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverImage(
                              path: t.coverPath,
                              width: 72,
                              height: 72,
                              borderRadius: 8),
                          const SizedBox(height: 4),
                          Text(
                            t.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
