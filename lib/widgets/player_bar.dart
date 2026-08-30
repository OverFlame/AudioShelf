import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../pages/subtitle_page.dart';
import 'cover_image.dart';

/// 底部播放栏
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final track = player.currentTrack;

    if (track == null) {
      return Container(
        height: 72,
        color: AppColors.panel,
        child: Center(
          child: Text('未在播放',
              style: TextStyle(color: AppColors.mutedLight, fontSize: 13)),
        ),
      );
    }

    final maxMs = player.duration.inMilliseconds;
    final posMs = player.position.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 0);
    final cover = appState.coverForTrack(track);

    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.surfaceAlt, width: 0.5)),
      ),
      child: Column(
        children: [
          // 进度条
          SizedBox(
            height: 18,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: maxMs > 0 ? posMs.toDouble() : 0,
                max: maxMs > 0 ? maxMs.toDouble() : 1,
                activeColor: AppColors.accent,
                inactiveColor: AppColors.surfaceAlt,
                onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          // 信息 + 控制
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  CoverImage(path: cover, width: 48, height: 48, borderRadius: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist ?? track.album ?? track.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${formatDuration(player.position)} / ${formatDuration(player.duration)}',
                    style: TextStyle(color: AppColors.mutedLight, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(
                      player.shuffle ? Icons.shuffle : Icons.shuffle_on_outlined,
                      size: 18,
                      color: player.shuffle
                          ? AppColors.accent
                          : AppColors.mutedLight,
                    ),
                    tooltip: '随机播放',
                    onPressed: player.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 26,
                        color: AppColors.textPrimary),
                    tooltip: '上一首',
                    onPressed: () => player.previous(),
                  ),
                  IconButton(
                    icon: Icon(
                      player.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 38,
                      color: AppColors.accent,
                    ),
                    tooltip: player.playing ? '暂停' : '播放',
                    onPressed: () => player.togglePlay(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 26,
                        color: AppColors.textPrimary),
                    tooltip: '下一首',
                    onPressed: () => player.next(),
                  ),
                  IconButton(
                    icon: Icon(
                      _repeatIcon(player.repeatMode),
                      size: 18,
                      color: player.repeatMode != RepeatMode.off
                          ? AppColors.accent
                          : AppColors.mutedLight,
                    ),
                    tooltip: '循环模式',
                    onPressed: () => _cycleRepeat(player),
                  ),
                  IconButton(
                    icon: const Icon(Icons.subtitles_outlined,
                        size: 20, color: AppColors.teal),
                    tooltip: '字幕模式',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SubtitlePage()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _repeatIcon(RepeatMode m) => switch (m) {
        RepeatMode.off => Icons.repeat,
        RepeatMode.all => Icons.repeat,
        RepeatMode.one => Icons.repeat_one,
      };

  void _cycleRepeat(PlayerController player) {
    final next = switch (player.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    player.setRepeatMode(next);
  }
}
