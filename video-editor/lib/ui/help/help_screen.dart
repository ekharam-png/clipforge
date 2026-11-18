import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/build_info.dart';
import '../about.dart';
import '../theme.dart';
import 'help_content.dart';
import 'help_search.dart';
import 'tour.dart';
import 'whats_new.dart';

/// Width from which Help shows the list and the article side by side, and
/// a "?" opens its article in a dialog instead of a sheet.
const double kHelpWideWidth = 900;

/// The help file for [language] (`assets/help/help_<language>.md`).
String helpAssetFor(String language) => 'assets/help/help_$language.md';

final Map<String, HelpLibrary> _libraries = {};

/// The help articles, read once per run. English only for now; another
/// language is one more file (see help_content.dart).
///
/// The library itself is kept, not the future: a future belongs to the
/// zone it was made in (each widget test has its own).
Future<HelpLibrary> loadHelpLibrary({
  String language = 'en',
  AssetBundle? bundle,
}) async {
  final cached = _libraries[language];
  if (cached != null) return cached;
  // Read as bytes: loadString would decode a large file on another
  // isolate, which the widget tests cannot wait for.
  final assets = bundle ?? rootBundle;
  Future<String> read(String key) async {
    final data = await assets.load(key);
    return utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  var library = HelpLibrary.parse(await read(helpAssetFor(language)));
  // "What's new" comes from the release notes (CHANGELOG.md); Help still
  // works without them.
  try {
    library = withWhatsNew(library, await read(kChangelogAsset),
        currentVersion: BuildInfo.current.versionLabel);
  } catch (_) {}
  return _libraries[language] = library;
}

/// The help articles if they were read already.
HelpLibrary? loadedHelpLibrary({String language = 'en'}) =>
    _libraries[language];

/// Articles offered when a search finds nothing.
const List<String> kPopularHelp = [
  'getting-started',
  'importing',
  'timeline',
  'export',
  'clean-up-sound',
  'phone-and-computer',
];

/// Opens Help, optionally at [articleId].
Future<void> openHelp(BuildContext context, {String? articleId}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HelpScreen(initialArticle: articleId),
    ),
  );
}

/// Shows one article on its own: a sheet on a phone, a dialog on a
/// computer. Used by the "?" buttons next to settings.
Future<void> showHelpArticle(BuildContext context, String articleId) {
  final wide = MediaQuery.sizeOf(context).width >= kHelpWideWidth;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: _ArticlePopup(initial: articleId, inDialog: true),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: _ArticlePopup(initial: articleId, inDialog: false),
    ),
  );
}

/// A small "?" next to a setting that opens [articleId].
class HelpHint extends StatelessWidget {
  const HelpHint(this.articleId, {super.key, this.label});
  final String articleId;

  /// What it explains, for the tooltip ("About Clean up sound").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tip = label == null ? 'Help' : 'About $label';
    return IconButton(
      key: ValueKey('help-hint-$articleId'),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      // Small, so that it fits next to a label without making the row
      // taller.
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 22),
      iconSize: 18,
      color: AppColors.textDim,
      icon: Icon(Icons.help_outline, semanticLabel: tip),
      onPressed: () => showHelpArticle(context, articleId),
    );
  }
}

/// [HelpHint] after [text], for a setting's label.
class LabelWithHint extends StatelessWidget {
  const LabelWithHint(
    this.text, {
    super.key,
    required this.articleId,
    this.style,
  });
  final String text;
  final String articleId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text, style: style)),
        const SizedBox(width: 2),
        HelpHint(articleId, label: text),
      ],
    );
  }
}

class _ArticlePopup extends StatefulWidget {
  const _ArticlePopup({required this.initial, required this.inDialog});
  final String initial;
  final bool inDialog;

  @override
  State<_ArticlePopup> createState() => _ArticlePopupState();
}

class _ArticlePopupState extends State<_ArticlePopup> {
  late final Future<HelpLibrary> _library = loadHelpLibrary();
  late String _id = widget.initial;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HelpLibrary>(
      future: _library,
      initialData: loadedHelpLibrary(),
      builder: (context, snap) {
        final library = snap.data;
        if (library == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final article = library.byId(_id);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.inDialog ? 24 : 0,
                  24,
                  8,
                ),
                child: article == null
                    ? const Text('This help page is missing.')
                    : HelpArticleView(
                        article: article,
                        library: library,
                        onOpen: (id) {
                          setState(() => _id = id);
                          _scroll.jumpTo(0);
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      openHelp(navigator.context, articleId: _id);
                    },
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('All help'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// The help screen ---------------------------------------------------------------

/// Searchable help: a list of articles (or search results) and the article
/// that is open. Side by side on a computer, one after the other on a
/// phone.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key, this.initialArticle});
  final String? initialArticle;

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  late final Future<HelpLibrary> _library = loadHelpLibrary();
  final _query = TextEditingController();
  late String? _open = widget.initialArticle;
  Set<String> _highlight = const {};
  HelpSearch? _search;
  final _articleScroll = ScrollController();
  late final TourController _tour = ref.read(tourControllerProvider);

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _tour.addListener(_onTour);
    // On a phone an article asked for straight away opens over the list.
    if (widget.initialArticle != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_wide(context)) _pushArticle(widget.initialArticle!);
      });
    }
  }

  @override
  void dispose() {
    _tour.removeListener(_onTour);
    _query.dispose();
    _articleScroll.dispose();
    super.dispose();
  }

  /// The tour was asked for (menu bar): make way for the project list.
  void _onTour() {
    if (_tour.startRequested && mounted && !_leaving) {
      _leaving = true;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= kHelpWideWidth;

  /// True once this screen is on its way out for the tour.
  bool _leaving = false;

  void _showTour() {
    _leaving = true;
    Navigator.of(context).pop();
    _tour.requestStart();
  }

  void _select(String id, Set<String> highlight) {
    setState(() {
      _open = id;
      _highlight = highlight;
    });
    if (_wide(context)) {
      if (_articleScroll.hasClients) _articleScroll.jumpTo(0);
    } else {
      _pushArticle(id, highlight: highlight);
    }
  }

  void _pushArticle(String id, {Set<String> highlight = const {}}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArticlePage(initial: id, highlight: highlight),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _showTour,
              icon: const Icon(Icons.tour_outlined, size: 20),
              label: const Text('Show the tour'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<HelpLibrary>(
          future: _library,
          initialData: loadedHelpLibrary(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text('Help could not be loaded (${snap.error}).'),
              );
            }
            final library = snap.data;
            if (library == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final search = _search ??= HelpSearch(library);
            final list = _ArticleList(
              library: library,
              search: search,
              query: _query,
              selected: wide ? _open : null,
              autofocus: wide,
              onSelect: _select,
            );
            if (!wide) return list;
            final open = _open == null ? null : library.byId(_open!);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 380, child: list),
                const VerticalDivider(width: 1),
                Expanded(
                  child: open == null
                      ? const _Placeholder()
                      : Align(
                          alignment: Alignment.topLeft,
                          child: SingleChildScrollView(
                            controller: _articleScroll,
                            padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: HelpArticleView(
                                article: open,
                                library: library,
                                highlight: _highlight,
                                onOpen: (id) => _select(id, const {}),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bottom of the topic list: which build this is, About ClipForge and
/// Copy version info.
class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('help-version-footer'),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: [
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: VersionLine(textAlign: TextAlign.start),
              ),
            ),
            IconButton(
              tooltip: 'Copy version info',
              icon: const Icon(Icons.copy, size: 18,
                  semanticLabel: 'Copy version info'),
              onPressed: () => copyVersionInfo(context),
            ),
            TextButton(
              onPressed: () => showAboutClipForge(context),
              child: const Text('About ClipForge'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: AppColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              'Pick a topic on the left, or type what you are looking for.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticlePage extends StatefulWidget {
  const _ArticlePage({required this.initial, required this.highlight});
  final String initial;
  final Set<String> highlight;

  @override
  State<_ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<_ArticlePage> {
  late final Future<HelpLibrary> _library = loadHelpLibrary();
  late String _id = widget.initial;
  late Set<String> _highlight = widget.highlight;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: FutureBuilder<HelpLibrary>(
          future: _library,
          initialData: loadedHelpLibrary(),
          builder: (context, snap) {
            final library = snap.data;
            if (library == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final article = library.byId(_id);
            return SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: article == null
                  ? const Text('This help page is missing.')
                  : HelpArticleView(
                      article: article,
                      library: library,
                      highlight: _highlight,
                      onOpen: (id) {
                        setState(() {
                          _id = id;
                          _highlight = const {};
                        });
                        _scroll.jumpTo(0);
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// The search field and the list of articles or results.
class _ArticleList extends StatelessWidget {
  const _ArticleList({
    required this.library,
    required this.search,
    required this.query,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
  });
  final HelpLibrary library;
  final HelpSearch search;
  final TextEditingController query;
  final String? selected;
  final bool autofocus;
  final void Function(String id, Set<String> highlight) onSelect;

  @override
  Widget build(BuildContext context) {
    final text = query.text.trim();
    final hits = text.isEmpty ? null : search.search(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const ValueKey('help-search'),
            controller: query,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search help, e.g. "music" or "slow motion"',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, semanticLabel: 'Clear'),
                      onPressed: query.clear,
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: hits == null
              ? _sections(context)
              : hits.isEmpty
              ? _noResults(context, text)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        hits.length == 1
                            ? '1 topic found'
                            : '${hits.length} topics found',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    for (final h in hits)
                      _ResultTile(
                        hit: h,
                        selected: h.article.id == selected,
                        onTap: () => onSelect(h.article.id, h.matchedWords),
                      ),
                  ],
                ),
        ),
        const _VersionFooter(),
      ],
    );
  }

  Widget _sections(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: AppColors.accent, letterSpacing: 0.4);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final section in library.sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(section, style: style),
          ),
          for (final a in library.articles)
            if (a.section == section)
              ListTile(
                dense: true,
                selected: a.id == selected,
                title: Text(a.title, style: const TextStyle(fontSize: 15)),
                trailing: a.comingLater ? const _LaterChip() : null,
                onTap: () => onSelect(a.id, const {}),
              ),
        ],
      ],
    );
  }

  Widget _noResults(BuildContext context, String text) {
    final ideas = search.suggestions(text);
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Nothing found for "$text".', style: textTheme.titleSmall),
        const SizedBox(height: 6),
        const Text(
          'Try another word, or check the spelling.',
          style: TextStyle(color: AppColors.textDim),
        ),
        if (ideas.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Did you mean:'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in ideas)
                ActionChip(
                  label: Text(w),
                  onPressed: () {
                    query.text = w;
                    query.selection = TextSelection.collapsed(offset: w.length);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const Text('Popular topics:'),
        const SizedBox(height: 4),
        for (final id in kPopularHelp)
          if (library.byId(id) case final a?)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined, size: 20),
              title: Text(a.title),
              onTap: () => onSelect(a.id, const {}),
            ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.hit,
    required this.selected,
    required this.onTap,
  });
  final HelpHit hit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final words = hit.matchedWords;
    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Text.rich(
        TextSpan(
          children: highlightSpans(hit.article.title, words, highlight: _mark),
        ),
        style: const TextStyle(fontSize: 15, color: Colors.white),
      ),
      subtitle: Text.rich(
        TextSpan(
          children: highlightSpans(
            HelpSearch.snippet(hit.article, words),
            words,
            highlight: _mark,
          ),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.textDim),
      ),
      trailing: hit.article.comingLater ? const _LaterChip() : null,
    );
  }
}

/// How a matched word looks.
const TextStyle _mark = TextStyle(
  backgroundColor: Color(0x667C9BFF),
  color: Colors.white,
);

class _LaterChip extends StatelessWidget {
  const _LaterChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Coming later',
        style: TextStyle(fontSize: 11, color: Color(0xFFFFC56B)),
      ),
    );
  }
}

/// [text] as spans, with the words in [words] (lower case) in [highlight]
/// and the character ranges [bold] in bold.
List<InlineSpan> highlightSpans(
  String text,
  Set<String> words, {
  required TextStyle highlight,
  List<(int, int)> bold = const [],
}) {
  if (text.isEmpty) return const [];
  final marked = List<bool>.filled(text.length, false);
  if (words.isNotEmpty) {
    for (final m in RegExp(
      r'[\p{L}\p{N}’'
      "'"
      r']+',
      unicode: true,
    ).allMatches(text)) {
      final word = m.group(0)!.toLowerCase().replaceAll(RegExp("['’]"), '');
      if (words.contains(word)) {
        for (var i = m.start; i < m.end; i++) {
          marked[i] = true;
        }
      }
    }
  }
  final strong = List<bool>.filled(text.length, false);
  for (final (from, to) in bold) {
    for (var i = from; i < to && i < text.length; i++) {
      strong[i] = true;
    }
  }
  final spans = <InlineSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i < text.length &&
        marked[i] == marked[start] &&
        strong[i] == strong[start]) {
      continue;
    }
    var style = marked[start] ? highlight : null;
    if (strong[start]) {
      style = (style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );
    }
    spans.add(TextSpan(text: text.substring(start, i), style: style));
    start = i;
  }
  return spans;
}

/// One article: title, text and links to related ones.
class HelpArticleView extends StatelessWidget {
  const HelpArticleView({
    super.key,
    required this.article,
    required this.library,
    required this.onOpen,
    this.highlight = const {},
  });
  final HelpArticle article;
  final HelpLibrary library;
  final ValueChanged<String> onOpen;
  final Set<String> highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyLarge?.copyWith(height: 1.45, fontSize: 16);
    Widget rich(HelpBlock b, TextStyle? style) => Text.rich(
      TextSpan(
        children: highlightSpans(
          b.text,
          highlight,
          highlight: _mark,
          bold: b.boldRanges,
        ),
      ),
      style: style,
    );
    final related = [for (final id in article.related) ?library.byId(id)];
    return Column(
      key: ValueKey('help-article-${article.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          article.section.toUpperCase(),
          style: theme.labelSmall?.copyWith(
            color: AppColors.accent,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: highlightSpans(
              article.title,
              highlight,
              highlight: _mark,
            ),
          ),
          style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (article.comingLater) ...[
          const SizedBox(height: 8),
          const _LaterChip(),
        ],
        const SizedBox(height: 14),
        for (final b in article.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: switch (b.kind) {
              HelpBlockKind.paragraph => rich(b, body),
              HelpBlockKind.heading => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: rich(b, theme.titleMedium),
              ),
              HelpBlockKind.bullet || HelpBlockKind.step => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      b.kind == HelpBlockKind.step ? '${b.number}.' : '•',
                      style: body?.copyWith(color: AppColors.accent),
                    ),
                  ),
                  Expanded(child: rich(b, body)),
                ],
              ),
            },
          ),
        if (related.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Related', style: theme.titleSmall),
          const SizedBox(height: 4),
          for (final a in related)
            ListTile(
              key: ValueKey('help-related-${a.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined, size: 20),
              title: Text(a.title, style: const TextStyle(fontSize: 15)),
              trailing: a.comingLater
                  ? const _LaterChip()
                  : const Icon(Icons.chevron_right),
              onTap: () => onOpen(a.id),
            ),
        ],
      ],
    );
  }
}
