import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 设置页
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('外观'),
          SwitchListTile(
            title: const Text('深色主题'),
            subtitle: const Text('关闭后跟随系统或使用浅色'),
            value: appState.themeMode == ThemeMode.dark,
            onChanged: (v) => appState
                .setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          const Divider(height: 1),
          const _SectionHeader('高级筛选'),
          ListTile(
            leading: const Icon(Icons.history, size: 18),
            title: const Text('清除表达式历史'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () async {
              await SettingsService.instance.clearExpressionHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除表达式历史')));
              }
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.folder_outlined, size: 18),
            title: const Text('数据目录'),
            subtitle: FutureBuilder<String>(
              future: appState.getDataDir(),
              builder: (context, snap) => Text(
                snap.data ?? '...',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline, size: 18),
            title: Text('AudioShelf'),
            subtitle: Text('本地音频播放器 · Windows / Linux / Android'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent)),
    );
  }
}
