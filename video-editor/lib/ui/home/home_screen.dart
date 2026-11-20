import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/project_store.dart';
import '../about.dart';
import '../app_menu.dart';
import '../app_prefs.dart';
import '../claude/claude_helper.dart';
import '../editor/editor_screen.dart';
import '../file_drop.dart';
import '../format.dart';
import '../feedback/feedback_screen.dart';
import '../help/help_screen.dart';
import '../help/tour.dart';
import '../help/whats_new.dart' show kWhatsNewId;
import '../help/what_moved.dart';
import '../app_settings.dart';
import '../settings/settings_screen.dart';
import 'dart:async';
import '../help/tour_sample.dart';
import '../services.dart';
import '../theme.dart';
import '../update/update_controller.dart';
import '../update/update_ui.dart';
import '../widgets.dart';

/// The list of saved projects.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<ProjectInfo>? _projects;
  List<DamagedProject> _damaged = const [];
  Object? _error;
  bool _busy = false;

  late final TourController _tour = ref.read(tourControllerProvider);
  late final TourHomeHooks _tourHooks = TourHomeHooks(
    makeSample: _makeTourSample,
    openSample: (id) => _open(id, tour: true),
    closeSample: _closeTourSample,
  );

  /// File > New project / Open project file in the menu bar, while no
  /// editor is open (and nothing covers the list).
  late final HomeMenuActions _menu = HomeMenuActions(
    newProject: () {
      if (_inFront) _create();
    },
    openProjectFile: () {
      if (_inFront) _openFile();
    },
  );

  bool get _inFront =>
      mounted && !_busy && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    appMenu.attachHome(this, _menu);
    _tour.attachHome(_tourHooks);
    _tour.addListener(_onTour);
    // The app's media folder is tidied once per run of the app.
    _reload().then((_) {
      if (!mounted) return;
      _offerTour();
      final once = ref.read(oncePerRunProvider);
      if (once.mediaCleaned) return;
      once.mediaCleaned = true;
      _cleanMedia();
      _startUpdatesAndClaude();
    });
  }

  /// Once per run of the app: say how an update that just ran went, look
  /// for a newer version (quietly; at most once a day) and refresh the
  /// Claude helper in its per-user folder (computers).
  Future<void> _startUpdatesAndClaude() async {
    final updates = ref.read(updateControllerProvider);
    final claude = ref.read(claudeHelperProvider);
    try {
      await updates.onAppStart();
      if (updates.lastResult != null && mounted) {
        // The quiet "Updated to X" line on the list says it already.
        await _updatedKnown.future
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        if (!mounted) return;
        await showUpdateOutcome(context, updates,
            quietSuccess: _updatedTo != null,
            whatsNew: () {
          _closeUpdatedLine();
          if (mounted) openHelp(context, articleId: kWhatsNewId);
        });
      }
      // Windows, once per version: the app runs from a folder an earlier
      // update unpacked into ("….update-new") - offer to tidy up.
      if (mounted) await offerTidyUp(context, updates);
    } catch (_) {
      // Updates are never in the way of using the app.
    }
    try {
      await claude.installAtStart();
    } catch (_) {}
  }

  @override
  void dispose() {
    appMenu.detachHome(this);
    _tour.removeListener(_onTour);
    _tour.detachHome(_tourHooks);
    super.dispose();
  }

  // The tour ------------------------------------------------------------------

  /// The very first time the app opens: "Would you like a quick tour?".
  /// Asked once; either answer is remembered.
  Future<void> _offerTour() async {
    final prefs = ref.read(appPrefsProvider);
    final once = ref.read(oncePerRunProvider);
    if (once.tourOffered) return;
    once.tourOffered = true;
    bool answered;
    try {
      answered = await prefs.tourAnswered();
    } catch (_) {
      answered = true;
    }
    await _versionNotes(existingUser: answered);
    if (answered || !mounted || _tour.active) return;
    final yes = await showFirstLaunchOffer(context);
    try {
      await prefs.setTourAnswered();
    } catch (_) {}
    if (!mounted) return;
    if (yes) {
      _startTour();
    } else {
      _say('You can take the tour any time: tap ? (Help) at the top, then '
          '"Show the tour".');
    }
  }

  /// The version that just started is not the one that ran last: say so
  /// in one quiet line ("Updated to 1.15.0 · What's new"), and, the first
  /// time a version from 1.15 on runs after an older one, show "What
  /// moved" once. A first install sees neither.
  String? _updatedTo;

  /// Done once it is known whether the "Updated to" line shows.
  final Completer<void> _updatedKnown = Completer<void>();

  Future<void> _versionNotes({required bool existingUser}) async {
    final prefs = ref.read(appPrefsProvider);
    final current = ref.read(buildInfoProvider).version;
    try {
      final previous = await prefs.text(kLastRunVersionText);
      if (previous != current) {
        await prefs.setText(kLastRunVersionText, current);
      }
      final updated = previous == null ? existingUser : previous != current;
      if (updated && await prefs.text(kUpdatedLineSeenText) != current) {
        if (mounted) setState(() => _updatedTo = current);
      }
      if (!_updatedKnown.isCompleted) _updatedKnown.complete();
      // 1.17: I and O changed their meaning. Said once to people who come
      // from 1.15 / 1.16 on a computer; from older versions the bigger
      // "What moved" below has the same line.
      final keysSeen = await prefs.flag(kKeysMovedSeenFlag);
      if (!keysSeen) await prefs.setFlag(kKeysMovedSeenFlag);
      final movedSeen = await prefs.flag(kWhatMovedSeenFlag);
      if (!movedSeen) await prefs.setFlag(kWhatMovedSeenFlag);
      if (!existingUser || !mounted || _tour.active) return;
      if (!movedSeen && olderThan115(previous) && !olderThan115(current)) {
        await showWhatMoved(context);
        return;
      }
      if (!keysSeen &&
          previous != null &&
          olderThanMinor(previous, 17) &&
          !olderThanMinor(current, 17) &&
          MediaQuery.sizeOf(context).width >= 700) {
        await showKeysMoved(context);
      }
    } catch (_) {
      // Notes are never in the way of using the app.
    } finally {
      if (!_updatedKnown.isCompleted) _updatedKnown.complete();
    }
  }

  void _closeUpdatedLine() {
    final version = _updatedTo;
    if (version == null) return;
    setState(() => _updatedTo = null);
    ref
        .read(appPrefsProvider)
        .setText(kUpdatedLineSeenText, version)
        .catchError((Object _) {});
  }

  void _startTour() {
    _tour.start(
      wide: MediaQuery.sizeOf(context).width >= kWideLayoutWidth,
      canDrop: ref.read(fileDropServiceProvider).supported,
    );
  }

  /// Help or the menu bar asked for the tour: start it once this screen is
  /// in front.
  void _onTour() {
    if (!mounted || !_tour.startRequested || _busy) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_tour.takeStartRequest()) _startTour();
  }

  Future<String?> _makeTourSample() async {
    try {
      final project = await ref.read(tourSampleProvider)(
          await _store, ref.read(documentServiceProvider));
      return project.id;
    } catch (e) {
      _say('The sample project could not be made ($e).');
      return null;
    }
  }

  Future<void> _closeTourSample(String id, {required bool keep}) async {
    if (!keep) {
      try {
        await (await _store).delete(id);
      } catch (_) {}
      await _cleanMedia();
    }
    await _reload();
    if (keep) _say('"$kTourSampleName" is in your projects to play with.');
  }

  /// Deletes the app's own copies of media that no project uses any more
  /// (see [cleanAppMedia]). Quietly: there is nothing for the user to do.
  Future<void> _cleanMedia() async {
    try {
      await ref.read(mediaCleanupProvider)(await _store);
    } catch (_) {
      // Tidying up is best effort.
    }
  }

  Future<ProjectStore> get _store => ref.read(projectStoreProvider.future);

  Future<void> _reload() async {
    try {
      final store = await _store;
      final list = await store.list();
      var damaged = const <DamagedProject>[];
      try {
        damaged = await ref
            .read(damagedProjectsProvider)(store, {for (final p in list) p.id});
      } catch (_) {
        // The list of good projects is what matters.
      }
      if (!mounted) return;
      setState(() {
        _projects = list;
        _damaged = damaged;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Runs a store action, then refreshes; shows a message if it fails.
  Future<void> _run(String failure, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say('$failure ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  Future<void> _open(String id, {FileDrop? drop, bool tour = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) =>
              EditorScreen(projectId: id, initialDrop: drop, tour: tour)),
    );
    await _reload();
    // A tour asked for while the editor was open starts now.
    _onTour();
  }

  /// Starts a new project and opens it; [drop]: files to put in it.
  Future<void> _create({FileDrop? drop}) =>
      _run('Could not create the project.', () async {
        final now = DateTime.now();
        final name = 'Video ${formatDate(now).split(',').first}';
        final project = await (await _store).create(name);
        if (mounted) await _open(project.id, drop: drop);
      });

  /// Files dragged onto the project list from the desktop: project files
  /// (.clipforge.zip) are opened as projects; videos, photos, music and
  /// subtitles start a new project that is opened with them in it, in the
  /// order they were dropped. Files that cannot be used are listed in the
  /// editor (or here, when nothing else came along).
  Future<void> _dropped(FileDrop drop) async {
    if (_busy) return;
    final sorted = SortedDrop(drop);
    for (final f in sorted.projects) {
      await _importBundle(f.path, f.name);
    }
    if (!mounted) return;
    if (sorted.hasEditable) {
      await _create(
          drop: FileDrop(
              files: [
                for (final f in drop.files)
                  if (dropKindOf(f.path) != DropKind.project) f,
              ],
              folders: drop.folders,
              globalPosition: drop.globalPosition));
      return;
    }
    final lines = sorted.unsupportedLines;
    if (lines.isNotEmpty) {
      await showDropProblems(
          context,
          lines.length == 1
              ? 'This file cannot be used'
              : 'These files cannot be used',
          lines,
          footer: 'Drop videos, photos or music to start a new video, or a '
              'project file (.clipforge.zip) to open it.');
    } else if (sorted.projects.isEmpty) {
      _say(drop.folders.isEmpty
          ? 'Nothing to add was found.'
          : 'No videos, photos or music were found directly inside '
              '${drop.folders.map((f) => '"$f"').join(', ')}.');
    }
  }

  Future<void> _rename(ProjectInfo info) async {
    final name = await promptText(context,
        title: 'Rename project', initial: info.name);
    if (name == null || name == info.name) return;
    String? given;
    await _run('Could not rename the project.', () async {
      final store = await _store;
      final project = await store.load(info.id);
      // Two projects with one name are hard to tell apart (also for
      // Claude): a taken name gets " (2)".
      given = await freeProjectName(store, name, exceptId: info.id);
      await store
          .save(project.copyWith(name: given, updatedAt: DateTime.now()));
    });
    if (given != null && given != name.trim()) {
      _say('Another project is already called "${name.trim()}", so this one '
          'is now "$given".');
    }
  }

  Future<void> _duplicate(ProjectInfo info) =>
      _run('Could not duplicate the project.',
          () async => (await _store).duplicate(info.id));

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Packs the project and its media into one file to carry to another
  /// device. On a computer the user chooses where it is saved; on a phone
  /// it goes to the share sheet.
  Future<void> _share(ProjectInfo info) async {
    final progress = ValueNotifier<double>(0);
    final documents = ref.read(documentServiceProvider);
    var dialogOpen = false;
    void closeProgress() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    String? where;
    bool? shared;
    var skipped = const <String>[];
    await _run('Could not make the project file.', () async {
      try {
        final project = await (await _store).load(info.id);
        final name = '${safeFileName(info.name)}.clipforge.zip';
        Future<void> pack(String path) async {
          // The place is chosen; packing the media can take a while.
          if (mounted) {
            dialogOpen = true;
            _showProgress('Packing "${info.name}"…', progress);
          }
          skipped = await ref.read(projectBundlesProvider).exportBundle(
              project, path,
              onProgress: (f) => progress.value = f.clamp(0.0, 1.0));
          // The share sheet comes next (phones); it needs the screen.
          closeProgress();
        }

        if (documents.sharesFiles) {
          shared = await documents.shareFile(name, pack);
        } else {
          where = await documents.saveFile(name, pack);
        }
      } finally {
        closeProgress();
      }
    });
    progress.dispose();
    if (!mounted) return;
    if (skipped.isNotEmpty && (where != null || shared != null)) {
      await _showSkipped(skipped);
    }
    if (where != null) {
      _say('Project file saved: $where');
    } else if (shared == false) {
      _say('The project file was not sent anywhere.');
    }
  }

  /// A project file was made without some of its media.
  Future<void> _showSkipped(List<String> paths) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paths.length == 1
            ? 'One file is not in the project file'
            : '${paths.length} files are not in the project file'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('They could not be found on this device, so the '
                    'other device will show them as missing:'),
                for (final path in paths)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(path,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Unpacks a project file made by [_share] into a new project.
  Future<void> _openFile() async {
    PickedFile? file;
    try {
      file = await ref.read(documentServiceProvider).pickFile(const ['zip']);
    } catch (e) {
      _say('Could not open the project file. ($e)');
      return;
    }
    if (file == null) return;
    await _importBundle(file.path, file.name);
  }

  /// Unpacks the project file at [path] into a new project.
  Future<void> _importBundle(String path, String fileName) async {
    String? name;
    var dialogOpen = false;
    await _run('Could not open the project file.', () async {
      final documents = ref.read(documentServiceProvider);
      if (mounted) {
        dialogOpen = true;
        _showProgress('Opening $fileName…', null);
      }
      try {
        final project = await ref.read(projectBundlesProvider).importBundle(
              path,
              store: await _store,
              mediaDir: await documents.mediaDir(),
            );
        name = project.name;
      } finally {
        if (dialogOpen && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });
    if (name != null) _say('"$name" was added to your projects.');
  }

  void _showProgress(String message, ValueListenable<double>? progress) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 16),
              if (progress == null)
                const LinearProgressIndicator(minHeight: 6)
              else
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (_, value, _) => LinearProgressIndicator(
                      value: value > 0 ? value : null, minHeight: 6),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(ProjectInfo info) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete project?',
      message: '"${info.name}" will be deleted. Copies the app made for it '
          '(media added on a phone, freeze frames, media that came in a '
          'project file) are deleted too, unless another project uses them. '
          'Files in your own folders and in your gallery are not touched.',
    );
    if (!ok) return;
    await _run('Could not delete the project.',
        () async => (await _store).delete(info.id));
    await _cleanMedia();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final Widget body;
    if (_error != null && projects == null) {
      body = _Message(
        icon: Icons.error_outline,
        title: 'Could not open your projects',
        detail: '$_error',
        action: FilledButton(onPressed: _reload, child: const Text('Try again')),
      );
    } else if (projects == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (projects.isEmpty && _damaged.isEmpty) {
      body = _Message(
        icon: Icons.movie_creation_outlined,
        title: 'No projects yet',
        detail: 'Start one to put your videos and photos together.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TourAnchor(
              id: TourIds.newProject,
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('New project'),
              ),
            ),
            const SizedBox(height: 8),
            TourAnchor(
              id: TourIds.openProjectFile,
              child: TextButton.icon(
                onPressed: _busy ? null : _openFile,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Open project file'),
              ),
            ),
          ],
        ),
      );
    } else {
      final thumbnails = ref.watch(thumbnailsProvider);
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460,
          mainAxisExtent: 88,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: projects.length + _damaged.length,
        itemBuilder: (context, i) {
          if (i >= projects.length) {
            return _DamagedCard(project: _damaged[i - projects.length]);
          }
          final info = projects[i];
          return _ProjectCard(
            info: info,
            thumbnails: thumbnails,
            onOpen: () => _open(info.id),
            onAction: (action) => switch (action) {
              _CardAction.rename => _rename(info),
              _CardAction.duplicate => _duplicate(info),
              _CardAction.share => _share(info),
              _CardAction.delete => _delete(info),
            },
          );
        },
      );
    }
    return FileDropZone(
      message: 'Drop to start a new video',
      enabled: !_busy,
      onDrop: _dropped,
      child: _scaffold(projects, body),
    );
  }

  Widget _scaffold(List<ProjectInfo>? projects, Widget body) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipForge',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (projects != null &&
              (projects.isNotEmpty || _damaged.isNotEmpty))
            TourAnchor(
              id: TourIds.openProjectFile,
              child: TextButton.icon(
                onPressed: _busy ? null : _openFile,
                icon: const Icon(Icons.folder_open, size: 20),
                label: const Text('Open project file'),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(right: aboutInMenuBar ? 8 : 0),
            child: IconButton(
              tooltip: 'Help',
              icon: const Icon(Icons.help_outline, semanticLabel: 'Help'),
              onPressed: () => openHelp(context),
            ),
          ),
          // Phones have no menu bar: About and Copy version info live here.
          if (!aboutInMenuBar)
            PopupMenuButton<_HomeMore>(
              key: const ValueKey('home-more'),
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, semanticLabel: 'More'),
              onSelected: (choice) => switch (choice) {
                _HomeMore.settings => openSettings(context),
                _HomeMore.whatsNew =>
                  openHelp(context, articleId: kWhatsNewId),
                _HomeMore.about => showAboutClipForge(context),
                _HomeMore.copyVersion => copyVersionInfo(context),
                _HomeMore.checkUpdates => checkForUpdatesNow(context),
                _HomeMore.feedback => openFeedback(context),
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    key: ValueKey('home-more-settings'),
                    value: _HomeMore.settings,
                    child: Text('Settings')),
                const PopupMenuItem(
                    value: _HomeMore.whatsNew, child: Text("What's new")),
                const PopupMenuItem(
                    value: _HomeMore.checkUpdates,
                    child: Text('Check for updates')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    key: ValueKey('home-more-feedback'),
                    value: _HomeMore.feedback,
                    child: Text('Send feedback')),
                const PopupMenuItem(
                    value: _HomeMore.about, child: Text('About ClipForge')),
                const PopupMenuItem(
                    value: _HomeMore.copyVersion,
                    child: Text('Copy version info')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // "Version X is available" (nothing when there is no update).
            const UpdateBanner(),
            // "Updated to 1.15.0 · What's new" (once per new version).
            if (_updatedTo != null)
              UpdatedLine(
                version: _updatedTo!,
                onWhatsNew: () {
                  _closeUpdatedLine();
                  openHelp(context, articleId: kWhatsNewId);
                },
                onClose: _closeUpdatedLine,
              ),
            Expanded(child: body),
          ],
        ),
      ),
      // Which build this is, small and out of the way (tap: About).
      bottomNavigationBar: const SafeArea(
        top: false,
        child: VersionLine(padding: EdgeInsets.fromLTRB(16, 4, 16, 6)),
      ),
      floatingActionButton:
          projects == null || (projects.isEmpty && _damaged.isEmpty)
              ? null
          : TourAnchor(
              id: TourIds.newProject,
              child: FloatingActionButton.extended(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('New project'),
              ),
            ),
    );
  }
}

enum _HomeMore { settings, whatsNew, about, copyVersion, checkUpdates, feedback }

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textDim),
            const SizedBox(height: 16),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              detail,
              style: text.bodyMedium?.copyWith(color: AppColors.textDim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            action,
          ],
        ),
      ),
    );
  }
}

/// A project whose file cannot be read: shown, so that it does not just
/// vanish, but there is nothing to open.
class _DamagedCard extends StatelessWidget {
  const _DamagedCard({required this.project});
  final DamagedProject project;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final modified = project.modified;
    return Semantics(
      enabled: false,
      label: "Can't open (damaged file)",
      child: Opacity(
        opacity: 0.6,
        child: Material(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              const SizedBox(
                width: 124,
                height: double.infinity,
                child: ColoredBox(
                  color: AppColors.panelHigh,
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.textDim, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Can't open (damaged file)",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${modified == null ? '' : '${formatDate(modified)}  ·  '}'
                      'folder ${project.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.bodySmall?.copyWith(color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardAction { rename, duplicate, share, delete }

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.info,
    required this.thumbnails,
    required this.onOpen,
    required this.onAction,
  });
  final ProjectInfo info;
  final ThumbnailCache thumbnails;
  final VoidCallback onOpen;
  final ValueChanged<_CardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final source = info.thumbnailSourcePath;
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          children: [
            SizedBox(
              width: 124,
              height: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(
                    color: AppColors.panelHigh,
                    child: Icon(Icons.movie_outlined,
                        color: AppColors.textDim, size: 28),
                  ),
                  if (source != null)
                    MediaThumb(path: source, thumbnails: thumbnails),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatDuration(info.durationMs)}  ·  '
                    '${formatDate(info.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textDim),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_CardAction>(
              tooltip: 'Project options',
              // Its own name, not only a tooltip: assistive tools list
              // icon-only buttons by name.
              icon: Icon(Icons.adaptive.more,
                  semanticLabel: 'Project options'),
              onSelected: onAction,
              itemBuilder: (context) => const [
                PopupMenuItem(value: _CardAction.rename, child: Text('Rename')),
                PopupMenuItem(
                    value: _CardAction.duplicate, child: Text('Duplicate')),
                PopupMenuItem(
                    value: _CardAction.share,
                    child: Text('Share project file')),
                PopupMenuDivider(),
                PopupMenuItem(value: _CardAction.delete, child: Text('Delete')),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// The first-launch question. True for "Show me around".
Future<bool> showFirstLaunchOffer(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.waving_hand_outlined, size: 32),
      title: const Text('Welcome to ClipForge!'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: const Text(
          'Would you like a quick tour? It takes about a minute and shows '
          'you the main buttons, using a sample project.\n\n'
          'You can also take it later: it is in Help (the ? at the top) any '
          'time.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Show me around'),
        ),
      ],
    ),
  );
  return yes ?? false;
}
