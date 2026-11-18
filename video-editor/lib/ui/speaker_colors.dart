import 'package:material_ui/material_ui.dart';

import '../core/model/project.dart';

/// One colour per speaker, shared by the timeline (speech tracks) and the
/// Text window (speaker names): readable on the dark panels and apart
/// from each other also for the common kinds of colour blindness.
const List<Color> kSpeakerColors = [
  Color(0xFF5B9BFF), // blue
  Color(0xFFF0A04B), // orange
  Color(0xFF3FC79A), // green
  Color(0xFFE77FB3), // pink
  Color(0xFFA98BF5), // violet
  Color(0xFFE3C44F), // yellow
];

String _plain(String name) => name.trim().toLowerCase();

/// The speech tracks of [p] in order: the n-th gets the n-th colour.
List<SoundTrack> speechTracksOf(Project p) => [
      for (final t in p.soundTracks)
        if (t.speech) t,
    ];

/// Colour of the speech track [trackId]; null when it is not one.
Color? speechTrackColor(Project p, String trackId) {
  final tracks = speechTracksOf(p);
  final i = tracks.indexWhere((t) => t.id == trackId);
  return i < 0 ? null : kSpeakerColors[i % kSpeakerColors.length];
}

/// Colours for [speakers] (names as they appear in the text): a name that
/// is also a speech track's name gets that track's colour; the others the
/// next colours no track uses, in order of appearance.
Map<String, Color> speakerColors(Project p, Iterable<String> speakers) {
  final tracks = speechTracksOf(p);
  final byTrack = {
    for (var i = 0; i < tracks.length; i++)
      _plain(tracks[i].name): kSpeakerColors[i % kSpeakerColors.length],
  };
  final names = speakers.toList();
  final taken = <Color>{
    for (final n in names)
      if (byTrack[_plain(n)] != null) byTrack[_plain(n)]!,
  };
  final free = [
    for (final c in kSpeakerColors)
      if (!taken.contains(c)) c,
  ];
  final out = <String, Color>{};
  var next = 0;
  for (final n in names) {
    if (out.containsKey(n)) continue;
    final fromTrack = byTrack[_plain(n)];
    if (fromTrack != null) {
      out[n] = fromTrack;
    } else {
      final pool = free.isEmpty ? kSpeakerColors : free;
      out[n] = pool[next++ % pool.length];
    }
  }
  return out;
}
