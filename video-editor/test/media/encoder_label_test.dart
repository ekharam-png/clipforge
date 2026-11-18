// "Is the graphics card used?": the words the export dialog shows, and the
// encoder it names before an export (HardwareEncoders.current).

import 'package:clipforge/media/hardware_encoding.dart';
import 'package:clipforge/media/media_common.dart';
import 'package:clipforge/media/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every encoder has words for the export dialog', () {
    expect(encoderLabel(VideoEncoder.mediaFoundation),
        'Graphics card — Media Foundation (Windows)');
    expect(encoderLabel(VideoEncoder.videotoolbox),
        'Graphics card — VideoToolbox (Mac)');
    expect(encoderLabel(VideoEncoder.libx264), 'Processor');
    for (final e in VideoEncoder.values) {
      expect(encoderLabel(e).startsWith('Graphics') == e.hardware, isTrue,
          reason: e.name);
    }
  });

  test('Windows bundle: h264_mf is found in the FFmpegKit listing, named '
      'before the export, and dropped after it failed', () async {
    // FFmpegKit (--enable-small) prints the table through its log with
    // empty descriptions; this is the bundled Windows build's H.264 part.
    const listing = ' V....D libx264              (codec h264)\n'
        ' V....D libx264rgb           (codec h264)\n'
        ' V....D h264_mf              (codec h264)\n'
        ' V....D hevc_mf              (codec hevc)\n';
    expect(parseEncoderList(listing), containsAll(['libx264', 'h264_mf']));
    final tried = <String>[];
    final h = HardwareEncoders(
      platform: EncoderPlatform.windows,
      listEncoders: () async => listing,
      run: (args) async {
        tried.add(args[args.indexOf('-c:v') + 1]);
        return const FfmpegRun(true, '');
      },
    );
    expect(await h.current(), VideoEncoder.mediaFoundation);
    // Only the encoder the build has was test-encoded.
    expect(tried, ['h264_mf']);
    h.markFailed(VideoEncoder.mediaFoundation);
    expect(await h.current(), isNull);
    expect(await h.available(), isFalse);
  });
}
