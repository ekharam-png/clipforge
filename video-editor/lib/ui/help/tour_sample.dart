import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/editor/project_editor.dart';
import '../../core/model/project.dart';
import '../../core/storage/project_store.dart';
import '../services.dart';

/// Name of the project the tour makes.
const String kTourSampleName = 'Sample video (tour)';

/// The bundled 5-second video with stereo sound (640 x 360, ~85 KB), made
/// with ffmpeg; see README "Help and tour". Its facts are written into the
/// clip below, and a test checks them against the file.
const String kTourVideoAsset = 'assets/tour/sample.mp4';
const int kTourVideoMs = 5000;
const int kTourVideoWidth = 640;
const int kTourVideoHeight = 360;

/// Makes the project the tour walks through and saves it in [store]:
/// the bundled video plus two photos drawn here, so the editor has real
/// clips (and the video has Speed and Sound). The files go to the app's
/// own media folder, which is tidied once no project uses them.
typedef TourSampleMaker = Future<Project> Function(
  ProjectStore store,
  DocumentService documents,
);

final tourSampleProvider = Provider<TourSampleMaker>((ref) => makeTourSample);

Future<Project> makeTourSample(
  ProjectStore store,
  DocumentService documents,
) async {
  final dir = await documents.mediaDir();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final video = p.join(dir, 'tour_${stamp}_video.mp4');
  final data = await rootBundle.load(kTourVideoAsset);
  await File(video).writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  final photo1 = p.join(dir, 'tour_${stamp}_photo1.png');
  final photo2 = p.join(dir, 'tour_${stamp}_photo2.png');
  await writeTourPhoto(
    photo1,
    top: const Color(0xFFFF9A62),
    bottom: const Color(0xFF7B3FA0),
    label: 'Photo 1',
  );
  await writeTourPhoto(
    photo2,
    top: const Color(0xFF43C6AC),
    bottom: const Color(0xFF191654),
    label: 'Photo 2',
  );

  final created = await store.create(kTourSampleName);
  final project = buildTourSample(
    created,
    video: video,
    photo1: photo1,
    photo2: photo2,
  );
  await store.save(project);
  return project;
}

/// [created] (a new, empty project) filled with the tour's clips: the
/// video, then two photos (the first with a crossfade), and a title.
Project buildTourSample(
  Project created, {
  required String video,
  required String photo1,
  required String photo2,
}) {
  final editor = ProjectEditor(
    created.copyWith(aspect: CanvasAspect.landscape16x9),
  );
  Clip photo(String id, String path, TransitionType transition) => Clip(
    id: id,
    type: ClipType.photo,
    path: path,
    sourceDurationMs: 0,
    inMs: 0,
    outMs: 3000,
    width: 1280,
    height: 720,
    hasAudio: false,
    transition: transition,
    transitionMs: 500,
  );
  editor.transaction(() {
    editor.addClip(tourVideoClip('tour-video', video));
    editor.addClip(photo('tour-photo-1', photo1, TransitionType.crossfade));
    editor.addClip(photo('tour-photo-2', photo2, TransitionType.none));
    editor.addTitle(
      const TitleOverlay(
        id: 'tour-title',
        text: 'My first video',
        startMs: 0,
        endMs: 3000,
        y: 0.8,
        fontSize: 0.08,
        background: true,
      ),
    );
  });
  return editor.project.copyWith(updatedAt: DateTime.now());
}

/// The clip of the bundled video at [path].
Clip tourVideoClip(String id, String path) => Clip(
  id: id,
  type: ClipType.video,
  path: path,
  sourceDurationMs: kTourVideoMs,
  inMs: 0,
  outMs: kTourVideoMs,
  width: kTourVideoWidth,
  height: kTourVideoHeight,
  hasAudio: true,
  audioStreams: const [2],
);

/// Draws a 1280 x 720 picture (a gradient with a few circles and [label])
/// and writes it as a PNG to [path].
Future<void> writeTourPhoto(
  String path, {
  required Color top,
  required Color bottom,
  required String label,
}) async {
  const w = 1280.0, h = 720.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(w * 0.4, h), [
        top,
        bottom,
      ]),
  );
  final dots = Paint()..color = Colors.white.withValues(alpha: 0.12);
  for (final (x, y, r) in [
    (0.2, 0.3, 120.0),
    (0.75, 0.25, 70.0),
    (0.6, 0.75, 160.0),
    (0.12, 0.85, 50.0),
  ]) {
    canvas.drawCircle(Offset(w * x, h * y), r, dots);
  }
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.center,
            fontSize: 72,
            fontWeight: FontWeight.bold,
          ),
        )
        ..pushStyle(ui.TextStyle(color: Colors.white))
        ..addText(label);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: w));
  canvas.drawParagraph(paragraph, Offset(0, (h - paragraph.height) / 2));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
