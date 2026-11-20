// "Export several…" (1.14): several destinations exported one after
// another as ONE job into one kit folder, with overall progress and
// cancel, plus the text file with the publishing notes. Used by the app's
// Export window and by Claude's export_kit (its worker process).
//
// The shape copies a destination needs (9:16 for Shorts, 4:5 for an
// Instagram post) are made in memory ([destinationVariant]) and never
// saved: the project list is not littered. Pure Dart.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import '../core/publish/chapters.dart';
import 'destinations.dart';
import 'media_api.dart';

/// One file of the kit.
class KitItem {
  KitItem({
    required this.choice,
    required this.project,
    required this.options,
    required this.fileName,
    this.warnings = const [],
    this.reshaped = false,
  });
  final KitChoice choice;

  /// The project as this file needs it (maybe a shape copy in memory).
  final Project project;
  final ExportOptions options;
  final String fileName;

  /// Length / size warnings of the destination, known up front.
  final List<String> warnings;

  /// [project] is a copy in another shape.
  final bool reshaped;

  String get label => choice.label;
}

class KitPlan {
  KitPlan(this.project, this.items);
  final Project project;
  final List<KitItem> items;

  String get textFileName => kitTextFileName(project.name);

  /// The text file's content ([kitText]) with a section per file.
  String text({String lineEnd = '\n'}) => kitText(project,
      sections: [
        for (final i in items)
          (
            heading: i.label,
            shortForm: i.choice.destination.shortForm,
            file: i.fileName,
          ),
      ],
      lineEnd: lineEnd);

  /// Name of the folder (or gallery album) the kit goes into.
  String get folderName => kitSafeName(project.name);
}

/// Plans the kit of [project] for [choices] (duplicates are dropped).
KitPlan planKit(
  Project project,
  List<KitChoice> choices, {
  int fps = 30,
  bool useHardwareEncoder = true,
  Map<String, String> processedSound = const {},
  Map<String, List<QuietRange>> gates = const {},
}) {
  final seen = <String>{};
  final items = <KitItem>[];
  for (final c in choices) {
    if (c.destination.custom || !seen.add(c.key)) continue;
    final variant = destinationVariant(project, c);
    items.add(KitItem(
      choice: c,
      project: variant,
      options: destinationOptions(c,
          fps: fps,
          useHardwareEncoder: useHardwareEncoder,
          // The processed sound belongs to the clips, whatever the shape.
          processedSound: processedSound,
          // "Only when speaking": by sound id, the same in every shape.
          gates: gates),
      fileName: kitFileName(project.name, c),
      warnings: destinationWarnings(project, c),
      reshaped: !identical(variant, project) &&
          variant.aspect != project.aspect,
    ));
  }
  return KitPlan(project, items);
}

class KitProgress {
  const KitProgress(this.index, this.count, this.itemFraction, this.overall,
      this.label);

  /// Which file is being made (0-based) of [count].
  final int index;
  final int count;
  final double itemFraction;

  /// 0..1 over the whole kit (files weighted by how long they take).
  final double overall;
  final String label;
}

/// A finished file of a kit.
class KitFile {
  const KitFile(this.item, this.path, this.encoder, this.warnings);
  final KitItem item;
  final String path;
  final VideoEncoder? encoder;

  /// Sound settings the export could not apply.
  final List<String> warnings;
}

class KitResult {
  const KitResult(this.folder, this.files, this.textPath);
  final String folder;
  final List<KitFile> files;

  /// The text file; null when it could not be written.
  final String? textPath;
}

/// A kit being exported.
class KitRun {
  KitRun._();
  final _progress = StreamController<KitProgress>.broadcast();
  final _done = Completer<KitResult>();
  ExportJob? _job;
  bool _cancelled = false;

  Stream<KitProgress> get progress => _progress.stream;

  /// Completes with the files, or throws [ExportException] (cancelled:
  /// with `cancelled` true). Files finished before a failure or a cancel
  /// stay in the folder.
  Future<KitResult> get done => _done.future;
  bool get isCancelled => _cancelled;

  /// Stops after the file being made (which is thrown away).
  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _job?.cancel();
    } catch (_) {}
  }
}

double _weight(KitItem i) {
  final seconds = i.project.durationMs / 1000 + 1;
  if (i.options.format.audioOnly) return seconds * 0.05;
  final c = i.project.canvasSize;
  final small = i.options.quality == ExportQuality.small;
  return seconds * (c.width * c.height / 1e6) * (small ? 0.45 : 1);
}

/// Exports every item of [plan] into [folder], one after another, then
/// writes the text file. Each file is rendered as `<name>.part.<ext>` and
/// renamed when complete (replacing an older file of that name), so a
/// cancelled or failed kit never leaves a half file under a real name.
/// [onFile] is told about each finished file (the phone puts it into the
/// gallery album there).
KitRun runExportKit(
  MediaEngine engine,
  KitPlan plan,
  String folder, {
  Future<void> Function(KitFile file)? onFile,
  bool writeText = true,
  String lineEnd = '\n',
}) {
  final run = KitRun._();
  () async {
    final files = <KitFile>[];
    final weights = [for (final i in plan.items) _weight(i)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var doneWeight = 0.0;
    try {
      // (Plain, blocking file calls for the few small things done here:
      // the wait for each export is the only real waiting.)
      Directory(folder).createSync(recursive: true);
      for (var n = 0; n < plan.items.length; n++) {
        final item = plan.items[n];
        if (run._cancelled) {
          throw ExportException('Export cancelled', cancelled: true);
        }
        final target = p.join(folder, item.fileName);
        final ext = p.extension(item.fileName);
        final part = p.join(folder,
            '${p.basenameWithoutExtension(item.fileName)}.part$ext');
        void report(double f) {
          if (run._progress.isClosed) return;
          run._progress.add(KitProgress(
              n,
              plan.items.length,
              f,
              total <= 0 ? 0 : (doneWeight + weights[n] * f) / total,
              item.label));
        }

        report(0);
        final job = engine.export(item.project, part, options: item.options);
        run._job = job;
        final sub = job.progress
            .listen((pr) => report(pr.fraction.clamp(0.0, 1.0)), onError: (_) {});
        try {
          await job.done;
        } catch (e) {
          try {
            final f = File(part);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
          if (run._cancelled) {
            throw ExportException('Export cancelled', cancelled: true);
          }
          if (e is ExportException) {
            throw ExportException('${item.label}: ${e.message}',
                log: e.log, missingPaths: e.missingPaths);
          }
          throw ExportException('${item.label}: the export stopped ($e)');
        } finally {
          unawaited(sub.cancel());
          run._job = null;
        }
        try {
          final partFile = File(part);
          // An engine that only pretends (tests) writes nothing.
          if (partFile.existsSync()) {
            final old = File(target);
            if (old.existsSync()) old.deleteSync();
            partFile.renameSync(target);
          }
        } on FileSystemException catch (e) {
          throw ExportException(
              '${item.label}: the file could not be put in place '
              '(${e.message}).');
        }
        report(1);
        doneWeight += weights[n];
        final file = KitFile(item, target, job.videoEncoder, job.warnings);
        files.add(file);
        if (onFile != null) await onFile(file);
      }
      String? textPath;
      if (writeText) {
        try {
          final f = File(p.join(folder, plan.textFileName));
          f.writeAsStringSync(plan.text(lineEnd: lineEnd), flush: true);
          textPath = f.path;
        } on FileSystemException {
          textPath = null;
        }
      }
      run._done.complete(KitResult(folder, files, textPath));
    } on ExportException catch (e) {
      run._done.completeError(e);
    } catch (e) {
      run._done.completeError(ExportException('The export stopped: $e'));
    } finally {
      unawaited(run._progress.close());
    }
  }();
  // The caller listens when it is ready.
  run._done.future.ignore();
  return run;
}
