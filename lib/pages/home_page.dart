import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
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
            color: AppColors.panel,
            child: const TagPanel(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: appState.loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : (appState.currentWork == null
                    ? const WorksGrid()
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
