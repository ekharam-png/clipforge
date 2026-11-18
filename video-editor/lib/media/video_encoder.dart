// Which H.264 encoder an export uses, and the ffmpeg arguments for it.
//
// Pure Dart (no dart:io, no Flutter): the choice is a function of the
// platform, the encoders the FFmpeg in use contains and the export quality,
// so it is unit-tested without any hardware. The runtime part (asking
// FFmpeg which encoders it has, trying them once, falling back to libx264)
// is in hardware_encoding.dart.
//
// What the bundled FFmpeg builds contain (ffmpeg_kit_flutter_new 4.6.8,
// FFmpeg n8.1.2 full-gpl; checked in the downloaded libraries):
//   macOS   (arm64 + x86_64): h264_videotoolbox
//   Windows (x86_64):         h264_mf (Media Foundation) only - no nvenc,
//                             qsv or amf (not configured in)
//   Android (all ABIs):       h264_mediacodec (--enable-mediacodec)
//   Linux plugin bundle:      none (h264_v4l2m2m only); the Linux app runs
//                             the system ffmpeg anyway.
// A system ffmpeg (Linux app, Claude control) may contain more, e.g.
// h264_nvenc / h264_qsv / h264_amf on Windows; those are tried first there.

import 'media_api.dart' show ExportQuality;

/// The platform an export runs on, as far as the encoder choice cares.
enum EncoderPlatform {
  /// macOS on Apple silicon: VideoToolbox supports constant quality.
  macosAppleSilicon,

  /// macOS on an Intel processor: VideoToolbox needs a bitrate.
  macosIntel,
  windows,
  android,
  linux,
  other,
}

/// The H.264 encoders ClipForge knows how to drive.
enum VideoEncoder {
  /// The processor (x264). Always available, the fallback for all others.
  libx264('libx264', hardware: false),
  videotoolbox('h264_videotoolbox'),
  nvenc('h264_nvenc'),
  qsv('h264_qsv'),
  amf('h264_amf'),
  mediaFoundation('h264_mf'),
  mediacodec('h264_mediacodec');

  const VideoEncoder(this.ffmpegName, {this.hardware = true});

  /// The name ffmpeg knows it by (`-c:v <name>`, `ffmpeg -encoders`).
  final String ffmpegName;

  /// True for encoders that run on the graphics card / media engine.
  final bool hardware;

  /// The encoder called [name] by ffmpeg; null for one we do not drive.
  static VideoEncoder? byName(String name) {
    for (final e in values) {
      if (e.ffmpegName == name) return e;
    }
    return null;
  }
}

/// Hardware encoders worth trying on [platform], best first.
List<VideoEncoder> hardwareEncoderCandidates(EncoderPlatform platform) =>
    switch (platform) {
      EncoderPlatform.macosAppleSilicon ||
      EncoderPlatform.macosIntel =>
        const [VideoEncoder.videotoolbox],
      // Vendor encoders first (better quality per bit, more settings); the
      // Media Foundation one works through any vendor's driver.
      EncoderPlatform.windows => const [
          VideoEncoder.nvenc,
          VideoEncoder.qsv,
          VideoEncoder.amf,
          VideoEncoder.mediaFoundation,
        ],
      EncoderPlatform.android => const [VideoEncoder.mediacodec],
      // Development machines: an NVIDIA or Intel card with a system ffmpeg
      // that has the encoder. (VAAPI needs frames uploaded to the card,
      // which the export graph does not do.)
      EncoderPlatform.linux => const [VideoEncoder.nvenc, VideoEncoder.qsv],
      EncoderPlatform.other => const [],
    };

/// The encoders an export on [platform] may use, in the order to try them:
/// the hardware ones FFmpeg has ([available]: names from `ffmpeg
/// -encoders`; null when the list could not be read, in which case every
/// candidate is worth a try), then always libx264. With [hardware] false
/// only libx264.
List<VideoEncoder> encoderCandidates({
  required EncoderPlatform platform,
  required Set<String>? available,
  bool hardware = true,
}) =>
    [
      if (hardware)
        for (final e in hardwareEncoderCandidates(platform))
          if (available == null || available.contains(e.ffmpegName)) e,
      VideoEncoder.libx264,
    ];

/// The encoder names in the output of `ffmpeg -encoders` (video encoders
/// only). Lines look like ` V....D libx264   libx264 H.264 / AVC ...`.
Set<String> parseEncoderList(String output) {
  final names = <String>{};
  final line = RegExp(r'^\s*V[A-Z.]{5}\s+(\S+)', multiLine: true);
  for (final m in line.allMatches(output)) {
    final name = m.group(1)!;
    if (name != '=') names.add(name);
  }
  return names;
}

/// Constant quality of the processor encoder (x264 CRF): full / small.
const int kCrfFull = 21;
const int kCrfSmall = 27;

/// Small files are capped at this rate (and a buffer of twice it), so that
/// messaging apps take them.
const int kSmallMaxRateKbps = 2500;

/// Average bitrate (kbit/s) for hardware encoders that need one, for a
/// [width] x [height] picture at [fps]. About 0.12 bits per pixel: 1080p30
/// gets ~7.5 Mbit/s, 4K30 ~30 Mbit/s, which is what x264 at CRF 21 gives
/// for typical phone footage; hardware encoders need a little more than
/// x264 for the same look, so this errs on the generous side. Small files
/// stay under [kSmallMaxRateKbps].
int hardwareBitrateKbps({
  required int width,
  required int height,
  required int fps,
  required ExportQuality quality,
}) {
  final pixelsPerSecond = width * height * (fps < 1 ? 30 : fps);
  var kbps = (pixelsPerSecond * 0.12 / 1000).round();
  if (kbps < 1500) kbps = 1500;
  if (kbps > 60000) kbps = 60000;
  if (quality == ExportQuality.small) {
    const smallTarget = kSmallMaxRateKbps * 4 ~/ 5;
    if (kbps > smallTarget) kbps = smallTarget;
  }
  return kbps;
}

/// VideoToolbox constant quality (`-q:v`, 1..100) for full / small.
/// Apple silicon only. 65 is about x264 CRF 20-22 in size and look; 55
/// about CRF 26-28.
const int kVideoToolboxQualityFull = 65;
const int kVideoToolboxQualitySmall = 55;

/// Constant-quality level for NVENC (`-cq`) and Quick Sync
/// (`-global_quality`, ICQ): a couple of steps above the x264 CRF, as
/// their scales give a little more detail at the same number.
const int kHardwareCqFull = 23;
const int kHardwareCqSmall = 28;

/// The ffmpeg output arguments that pick and configure [encoder] (from
/// `-c:v` up to and including `-pix_fmt`), for a [width] x [height]
/// export at [fps]. [preset] is the x264 preset.
///
/// Every encoder gets 8-bit 4:2:0 (yuv420p for x264; nv12, the same
/// samples in the layout hardware encoders take, for the others) and the
/// High profile. Range (`-color_range tv`), GOP, audio and `+faststart` are
/// the same for every encoder and stay in the caller.
List<String> videoEncoderArgs(
  VideoEncoder encoder, {
  required EncoderPlatform platform,
  required ExportQuality quality,
  required int width,
  required int height,
  required int fps,
  String preset = 'veryfast',
}) {
  final small = quality == ExportQuality.small;
  final kbps = hardwareBitrateKbps(
      width: width, height: height, fps: fps, quality: quality);
  final maxKbps = small ? kSmallMaxRateKbps : kbps * 2;
  final cap = ['-maxrate', '${maxKbps}k', '-bufsize', '${maxKbps * 2}k'];
  final bitrate = ['-b:v', '${kbps}k', ...cap];
  final smallCap = small
      ? ['-maxrate', '${kSmallMaxRateKbps}k', '-bufsize', '${kSmallMaxRateKbps * 2}k']
      : const <String>[];
  final cq = small ? kHardwareCqSmall : kHardwareCqFull;
  return switch (encoder) {
    VideoEncoder.libx264 => [
        '-c:v', 'libx264',
        '-preset', preset,
        '-crf', '${small ? kCrfSmall : kCrfFull}',
        ...smallCap,
        '-profile:v', 'high',
        '-pix_fmt', 'yuv420p',
      ],
    // Constant quality (-q:v) exists only on Apple silicon; FFmpeg refuses
    // it elsewhere ("-q:v qscale not available for encoder"). The rate cap
    // becomes VideoToolbox's DataRateLimits. allow_sw 0 (the default) keeps
    // it on the media engine: no silent software path.
    VideoEncoder.videotoolbox => [
        '-c:v', 'h264_videotoolbox',
        if (platform == EncoderPlatform.macosAppleSilicon) ...[
          '-q:v',
          '${small ? kVideoToolboxQualitySmall : kVideoToolboxQualityFull}',
          ...smallCap,
        ] else
          ...bitrate,
        '-allow_sw', '0',
        '-profile:v', 'high',
        '-pix_fmt', 'nv12',
      ],
    VideoEncoder.nvenc => [
        '-c:v', 'h264_nvenc',
        '-preset', 'p5',
        '-tune', 'hq',
        '-rc', 'vbr',
        '-cq', '$cq',
        '-b:v', '0',
        ...smallCap,
        '-profile:v', 'high',
        '-pix_fmt', 'nv12',
      ],
    // Without a bitrate, global_quality selects ICQ (constant quality).
    VideoEncoder.qsv => [
        '-c:v', 'h264_qsv',
        '-preset', 'medium',
        if (small) ...bitrate else ...['-global_quality', '$cq'],
        '-profile:v', 'high',
        '-pix_fmt', 'nv12',
      ],
    VideoEncoder.amf => [
        '-c:v', 'h264_amf',
        '-quality', 'quality',
        '-rc', 'vbr_peak',
        ...bitrate,
        '-profile:v', 'high',
        '-pix_fmt', 'nv12',
      ],
    // Media Foundation reads the generic profile number (100 = High; it
    // has no "high" name) and defaults to Baseline without it.
    // hw_encoding 1 refuses the software MFT, so a machine without a
    // hardware encoder falls back to x264 rather than to a slow encoder.
    VideoEncoder.mediaFoundation => [
        '-c:v', 'h264_mf',
        '-hw_encoding', '1',
        '-rate_control', 'pc_vbr',
        ...bitrate,
        '-profile:v', '100',
        '-pix_fmt', 'nv12',
      ],
    VideoEncoder.mediacodec => [
        '-c:v', 'h264_mediacodec',
        '-bitrate_mode', 'vbr',
        ...bitrate,
        '-profile:v', 'high',
        '-pix_fmt', 'nv12',
      ],
  };
}

/// Which part of the device [encoder] is, in the owner's words, with the
/// technology's name so that "is the GPU used?" has a clear answer:
/// `Graphics card — Media Foundation (Windows)`, `Processor`.
String encoderLabel(VideoEncoder encoder) => switch (encoder) {
      VideoEncoder.libx264 => 'Processor',
      VideoEncoder.videotoolbox => 'Graphics card — VideoToolbox (Mac)',
      VideoEncoder.mediaFoundation =>
        'Graphics card — Media Foundation (Windows)',
      VideoEncoder.nvenc => 'Graphics card — NVIDIA NVENC',
      VideoEncoder.qsv => 'Graphics card — Intel Quick Sync',
      VideoEncoder.amf => 'Graphics card — AMD AMF',
      VideoEncoder.mediacodec => 'Graphics chip — MediaCodec (Android)',
    };

/// The words for the export result: which part of the computer made it.
String encoderDescription(VideoEncoder encoder) => encoder.hardware
    ? 'Made with the graphics card'
    : 'Made with the processor';

/// Arguments (no program name) for a short test encode with [encoder]:
/// ten black frames, encoded with the same settings an export uses and
/// thrown away. Succeeds only when the encoder really works here (a listed
/// hardware encoder may lack the card, the driver or the OS support).
/// Uses only the `color` filter, so it needs no input device.
List<String> encoderTestArgs(VideoEncoder encoder, EncoderPlatform platform) => [
      '-loglevel', 'error',
      '-filter_complex', 'color=c=black:s=256x256:r=30:d=1,format=yuv420p[v]',
      '-map', '[v]',
      '-frames:v', '10',
      ...videoEncoderArgs(encoder,
          platform: platform,
          quality: ExportQuality.full,
          width: 256,
          height: 256,
          fps: 30),
      '-f', 'null', '-',
    ];
