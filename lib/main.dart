import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db/database.dart';
import 'pages/home_page.dart';
import 'services/data_dir_service.dart';
import 'services/media_bridge.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'state/player_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataDirService.instance.init();
  await SettingsService.instance.init();
  await DatabaseManager.instance.init();

  final player = PlayerController();
  final appState = AppState(player: player);
  await appState.init();

  await MediaBridge.instance.init(player, appState);
  unawaited(MediaBridge.instance.ensureNotificationPermission());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: player),
      ],
      child: const AudioShelfApp(),
    ),
  );
}

class AudioShelfApp extends StatelessWidget {
  const AudioShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<AppState>().themeMode;
    return MaterialApp(
      title: 'AudioShelf',
      debugShowCheckedModeBanner: false,
      theme: AppColors.lightThemeData,
      darkTheme: AppColors.darkThemeData,
      themeMode: themeMode,
      home: const HomePage(),
    );
  }
}
