import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../utils/log_util.dart';

/// Android 侧桥接：后台播放通知栏 + 「所有文件访问」授权。
/// 桌面端（Windows/Linux）自动退化为 no-op。
class MediaBridge {
  MediaBridge._();

  static final MediaBridge instance = MediaBridge._();

  static const MethodChannel _channel = MethodChannel('audioshelf/playback');

  PlayerController? _player;
  AppState? _appState;
  bool _serviceStarted = false;
  String _lastKey = '';

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> init(PlayerController player, AppState appState) async {
    _player = player;
    _appState = appState;
    if (!isAndroid) return;
    _channel.setMethodCallHandler(_onNativeCall);
    player.addListener(_onPlayerChanged);
    logInfo('MediaBridge', 'initialized (Android)');
  }

  // ═══════════════ 权限 ═══════════════

  /// 是否已获得「所有文件访问」授权
  Future<bool> hasAllFilesAccess() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('checkAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转到系统「所有文件访问」授权页
  Future<void> requestAllFilesAccess() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  /// 确保通知权限（Android 13+）
  Future<void> ensureNotificationPermission() async {
    if (!isAndroid) return;
    try {
      final ok = await _channel.invokeMethod<bool>('checkNotificationPermission') ??
          true;
      if (!ok) await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  // ═══════════════ 服务 / 通知 ═══════════════

  Future<void> _startService() async {
    if (!isAndroid || _serviceStarted) return;
    try {
      await _channel.invokeMethod('startPlaybackService');
      _serviceStarted = true;
    } catch (e) {
      logWarn('MediaBridge', 'startService: $e');
    }
  }

  Future<void> stopService() async {
    if (!isAndroid) return;
    _serviceStarted = false;
    try {
      await _channel.invokeMethod('stopPlaybackService');
    } catch (_) {}
  }

  Future<void> _updateNotification() async {
    final player = _player;
    final appState = _appState;
    if (!isAndroid || !_serviceStarted || player == null) return;
    final track = player.currentTrack;
    if (track == null) return;
    try {
      await _channel.invokeMethod('updateNotification', <String, dynamic>{
        'title': track.displayTitle,
        'artist': track.artist ?? track.album ?? '',
        'playing': player.playing,
        'positionMs': player.position.inMilliseconds,
        'durationMs': player.duration.inMilliseconds,
        'coverPath': appState?.coverForTrack(track),
      });
    } catch (_) {}
  }

  void _onPlayerChanged() {
    final player = _player;
    if (player == null) return;
    final track = player.currentTrack;

    if (track == null) {
      // 停止/清空队列 → 停掉前台服务
      if (_serviceStarted) {
        stopService();
        _lastKey = '';
      }
      return;
    }

    _startService();

    // 仅当标题/播放态/时长/进度秒数变化时才更新通知（避免每 250ms 都调用原生）
    final key =
        '${track.path}|${player.playing}|${player.duration.inMilliseconds}|${player.position.inSeconds}';
    if (key != _lastKey) {
      _lastKey = key;
      _updateNotification();
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final player = _player;
    if (player == null) return null;
    switch (call.method) {
      case 'onPlayPause':
        await player.togglePlay();
        break;
      case 'onNext':
        await player.next();
        break;
      case 'onPrevious':
        await player.previous();
        break;
      case 'onSeekTo':
        final ms = (call.arguments as num?)?.toInt() ?? 0;
        await player.seek(Duration(milliseconds: ms));
        break;
      case 'onStop':
        await player.stop();
        await stopService();
        break;
    }
    return null;
  }

  void dispose() {
    if (!isAndroid) return;
    _player?.removeListener(_onPlayerChanged);
  }
}
