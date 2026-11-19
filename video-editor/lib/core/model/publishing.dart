// Publishing notes and "good moment" markers (1.14): two small additions
// to the project model. Both are additive in project.json (keys
// `publishing` and `markers`, written only when there is something to
// write), so the schema version stays 2 and older versions simply ignore
// them. Pure Dart; exported by project.dart.

/// One line of a chapter list: where it starts in the finished video and
/// what it is called.
class Chapter {
  const Chapter(this.ms, this.title);

  /// Timeline time.
  final int ms;
  final String title;

  Map<String, dynamic> toJson() => {'ms': ms, 'title': title};

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
      (j['ms'] as num?)?.toInt() ?? 0, (j['title'] as String? ?? '').trim());

  @override
  bool operator ==(Object other) =>
      other is Chapter && other.ms == ms && other.title == title;

  @override
  int get hashCode => Object.hash(ms, title);

  @override
  String toString() => 'Chapter($ms, $title)';
}

/// The text that goes with the video when it is posted: one main set
/// (title, description, hashtags, chapters) and an optional shorter title
/// and description for Shorts / Reels / TikTok. ClipForge never posts
/// anything itself: these are copied or written into a text file next to
/// the exported videos.
class PublishingNotes {
  const PublishingNotes({
    this.title = '',
    this.description = '',
    this.hashtags = const [],
    this.chapters = const [],
    this.shortTitle = '',
    this.shortDescription = '',
  });

  static const PublishingNotes empty = PublishingNotes();

  final String title;
  final String description;

  /// Words without the "#" (also used as tags), in the order typed.
  final List<String> hashtags;

  /// In time order.
  final List<Chapter> chapters;

  /// For short-form posts; empty = use [title] / [description].
  final String shortTitle;
  final String shortDescription;

  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      hashtags.isEmpty &&
      chapters.isEmpty &&
      shortTitle.trim().isEmpty &&
      shortDescription.trim().isEmpty;

  /// "#bread #baking"
  String get hashtagLine => [for (final h in hashtags) '#$h'].join(' ');

  /// "bread, baking" (YouTube's tags box).
  String get tagLine => hashtags.join(', ');

  /// The title a short-form post gets.
  String get titleForShort => shortTitle.trim().isEmpty ? title : shortTitle;
  String get descriptionForShort =>
      shortDescription.trim().isEmpty ? description : shortDescription;

  PublishingNotes copyWith({
    String? title,
    String? description,
    List<String>? hashtags,
    List<Chapter>? chapters,
    String? shortTitle,
    String? shortDescription,
  }) =>
      PublishingNotes(
        title: title ?? this.title,
        description: description ?? this.description,
        hashtags: hashtags ?? this.hashtags,
        chapters: chapters ?? this.chapters,
        shortTitle: shortTitle ?? this.shortTitle,
        shortDescription: shortDescription ?? this.shortDescription,
      );

  Map<String, dynamic> toJson() => {
        if (title.isNotEmpty) 'title': title,
        if (description.isNotEmpty) 'description': description,
        if (hashtags.isNotEmpty) 'hashtags': hashtags,
        if (chapters.isNotEmpty)
          'chapters': [for (final c in chapters) c.toJson()],
        if (shortTitle.isNotEmpty) 'shortTitle': shortTitle,
        if (shortDescription.isNotEmpty) 'shortDescription': shortDescription,
      };

  factory PublishingNotes.fromJson(Map<String, dynamic> j) => PublishingNotes(
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        hashtags: parseHashtags(
            [for (final h in (j['hashtags'] as List? ?? const [])) '$h']
                .join(' ')),
        chapters: [
          for (final c in (j['chapters'] as List? ?? const []))
            if (c is Map) Chapter.fromJson(Map<String, dynamic>.from(c)),
        ]..sort((a, b) => a.ms.compareTo(b.ms)),
        shortTitle: j['shortTitle'] as String? ?? '',
        shortDescription: j['shortDescription'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is PublishingNotes &&
      other.title == title &&
      other.description == description &&
      other.shortTitle == shortTitle &&
      other.shortDescription == shortDescription &&
      _same(other.hashtags, hashtags) &&
      _same(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(title, description, shortTitle,
      shortDescription, Object.hashAll(hashtags), Object.hashAll(chapters));

  static bool _same(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Most hashtags kept (sites ignore or punish long lists).
const int kMaxHashtags = 30;

/// Reads hashtags as people type them: "#bread, baking  #Home-made" gives
/// bread, baking, Homemade. Separated by spaces, commas or line breaks;
/// the "#" is optional; signs a hashtag cannot hold are dropped; the same
/// word (whatever its case) is kept once; at most [kMaxHashtags].
List<String> parseHashtags(String text) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in text.split(RegExp(r'[\s,;]+'))) {
    final word = raw.replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
    if (word.isEmpty) continue;
    if (!seen.add(word.toLowerCase())) continue;
    out.add(word);
    if (out.length >= kMaxHashtags) break;
  }
  return List.unmodifiable(out);
}

/// A "good moment" the user marked while watching, to make a short around
/// later. Sits at a time of the finished video and follows the picture it
/// was dropped on when clips are cut or moved (see `retimeMarkers`).
class Marker {
  const Marker({required this.id, required this.ms, this.label = ''});
  final String id;

  /// Timeline time.
  final int ms;
  final String label;

  Marker copyWith({int? ms, String? label}) =>
      Marker(id: id, ms: ms ?? this.ms, label: label ?? this.label);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ms': ms,
        if (label.isNotEmpty) 'label': label,
      };

  factory Marker.fromJson(Map<String, dynamic> j) => Marker(
        id: '${j['id']}',
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        label: j['label'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is Marker && other.id == id && other.ms == ms && other.label == label;

  @override
  int get hashCode => Object.hash(id, ms, label);
}
