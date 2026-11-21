import 'package:path/path.dart' as p;

/// `m:ss.t` — playhead style time with tenths of a second.
String formatTime(int ms) {
  if (ms < 0) ms = 0;
  final tenths = (ms ~/ 100) % 10;
  return '${formatDuration(ms)}.$tenths';
}

/// `m:ss` (or `h:mm:ss`), rounded down.
String formatDuration(int ms) {
  if (ms < 0) ms = 0;
  final totalSeconds = ms ~/ 1000;
  final s = totalSeconds % 60;
  final m = (totalSeconds ~/ 60) % 60;
  final h = totalSeconds ~/ 3600;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Short length label for a block on the timeline, e.g. `3.5s`.
String formatSeconds(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

/// A length of time in running text: `3.5 s`, `1 min 5 s`, `1 h 2 min`.
/// (Points in time use [formatTime].)
String formatLength(int ms) {
  if (ms < 0) ms = 0;
  if (ms < 59950) return '${(ms / 1000).toStringAsFixed(1)} s';
  final total = (ms / 1000).round();
  final s = total % 60;
  final m = (total ~/ 60) % 60;
  final h = total ~/ 3600;
  if (h > 0) return m == 0 ? '$h h' : '$h h $m min';
  return s == 0 ? '$m min' : '$m min $s s';
}

/// Playback speed as people say it: `2×`, `1.5×`, `0.25×`.
String formatSpeed(double speed) {
  var text = speed.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text×';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `15 Nov 2026, 14:02` in local time.
String formatDate(DateTime time) {
  final t = time.toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $hh:$mm';
}

const _imageExtensions = {
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif', //
};

/// Photos are recognised by file extension.
bool isImagePath(String path) =>
    _imageExtensions.contains(p.extension(path).toLowerCase());

String fileName(String path) => p.basename(path);

/// A project name turned into something safe to use as a file name.
String safeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? 'video' : cleaned;
}

/// The ending a saved file must have, from the name that was offered:
/// ".clipforge.zip" for a project file (two parts), else the last part
/// (".mp4", ".srt").
String fileEnding(String offeredName) {
  final lower = offeredName.toLowerCase();
  if (lower.endsWith('.clipforge.zip')) {
    return offeredName.substring(offeredName.length - '.clipforge.zip'.length);
  }
  return p.extension(offeredName);
}

/// The path to write to after a save window gave [chosen] for a file that
/// was offered as [offeredName]: always with the offered ending. A save
/// window only knows the LAST part of an ending, so a project file typed
/// as "My trip" came back as "My trip.zip" (1.17 on a Mac) instead of
/// "My trip.clipforge.zip"; that is put right here.
String savePathFor(String chosen, String offeredName) {
  final ending = fileEnding(offeredName);
  if (ending.isEmpty) return chosen;
  final lower = chosen.toLowerCase(), want = ending.toLowerCase();
  if (lower.endsWith(want)) return chosen;
  final last = p.extension(ending).toLowerCase(); // ".zip"
  if (last != want && lower.endsWith(last)) {
    return '${chosen.substring(0, chosen.length - last.length)}$ending';
  }
  return '$chosen$ending';
}
