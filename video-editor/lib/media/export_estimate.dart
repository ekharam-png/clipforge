// How big an export will be, and whether a disk has room for it.
// Pure Dart (no Flutter).

import '../core/model/project.dart';
import 'ffmpeg_command.dart' show exportSize;
import 'media_api.dart';
import 'video_encoder.dart';

/// Expected size of an export, in bytes.
class ExportSizeEstimate {
  const ExportSizeEstimate({required this.typicalBytes, required this.maxBytes});

  /// What it usually comes to (phone footage at the export's quality).
  final int typicalBytes;

  /// What busy, detailed footage can come to (the encoder's rate cap).
  final int maxBytes;
}

/// The size [project] exported with [options] will have: the video at
/// about 0.12 bits per pixel (what x264 at the export's quality gives for
/// typical phone footage, the same rate the graphics card encoders are
/// given; small files at their rate cap) plus the sound.
ExportSizeEstimate estimateExportSize(Project project, ExportOptions options) {
  if (options.format.audioOnly) {
    // 192 kbit/s of sound and nothing else.
    final bytes = (192 * 1000 / 8 * project.durationMs / 1000).round();
    return ExportSizeEstimate(typicalBytes: bytes, maxBytes: bytes);
  }
  final size = exportSize(project, options.quality);
  final small = options.quality == ExportQuality.small;
  final videoKbps = small
      ? kSmallMaxRateKbps * 4 ~/ 5
      : hardwareBitrateKbps(
          width: size.width,
          height: size.height,
          fps: options.fps,
          quality: options.quality);
  final maxVideoKbps = small ? kSmallMaxRateKbps : videoKbps * 2;
  final audioKbps = small ? 128 : 192;
  final seconds = project.durationMs / 1000;
  int bytes(int kbps) => (kbps * 1000 / 8 * seconds).round();
  return ExportSizeEstimate(
    typicalBytes: bytes(videoKbps + audioKbps),
    maxBytes: bytes(maxVideoKbps + audioKbps),
  );
}

/// What the free space of the target disk means for an export.
enum DiskRoom {
  /// Room for even the largest likely size, with some to spare.
  enough,

  /// It may run out of space with detailed footage.
  tight,

  /// Not even half of the usual size fits: it would surely fail.
  notEnough,
}

/// Space kept free beyond the export (the system and other apps need some).
const int kDiskReserveBytes = 200 * 1000 * 1000;

DiskRoom diskRoomFor(ExportSizeEstimate estimate, int freeBytes) {
  if (freeBytes < estimate.typicalBytes ~/ 2 + kDiskReserveBytes ~/ 4) {
    return DiskRoom.notEnough;
  }
  if (freeBytes < estimate.maxBytes + kDiskReserveBytes) return DiskRoom.tight;
  return DiskRoom.enough;
}

/// "About 1.2 GB", "About 45 MB" (decimal units, as phones and computers
/// show free space).
String formatBytes(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) {
    final gb = bytes / 1e9;
    return '${gb >= 10 ? gb.round() : gb.toStringAsFixed(1)} GB';
  }
  final mb = (bytes / 1e6).round();
  return '${mb < 1 ? 1 : mb} MB';
}
