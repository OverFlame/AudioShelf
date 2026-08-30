import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../utils/log_util.dart';

/// 解析后的曲目元数据
class TrackMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final Uint8List? pictureBytes;
  final String? pictureMimetype;

  const TrackMetadata({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.pictureBytes,
    this.pictureMimetype,
  });

  static const empty = TrackMetadata();
}

/// 元数据读取服务（基于 audio_metadata_reader，支持 mp3 / wav）
class MetadataService {
  MetadataService._();

  static TrackMetadata read(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return TrackMetadata.empty;
      final m = readMetadata(f, getImage: true);
      int? durationMs;
      if (m.duration != null) {
        durationMs = m.duration!.inMilliseconds;
      }
      Uint8List? pic;
      String? mime;
      if (m.pictures.isNotEmpty) {
        pic = m.pictures.first.bytes;
        mime = m.pictures.first.mimetype;
      }
      return TrackMetadata(
        title: m.title,
        artist: m.artist,
        album: m.album,
        durationMs: durationMs,
        pictureBytes: pic,
        pictureMimetype: mime,
      );
    } catch (e) {
      logDebug('Metadata', '读取元数据失败 $path: $e');
      return TrackMetadata.empty;
    }
  }
}
