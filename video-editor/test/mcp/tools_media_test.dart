// The tools that read or write media, with real files made by ffmpeg.
// Skipped (with a message) when ffmpeg / ffprobe are not installed.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  late String video, talk, photo, music;

  setUpAll(() {
    if (!ffmpegOk) return;
    b = Bench();
    c = b.client;
    video = b.file('clip one.mp4');
    talk = b.file('talk.mp4');
    photo = b.file('photo.png');
    music = b.file('music.m4a');
    makeVideo(video);
    makeTalk(talk);
    makePhoto(photo);
    makeMusic(music);
  });
  tearDownAll(() {
    if (ffmpegOk) b.dispose();
  });

  Future<String> newProject(String name) async =>
      (await c.ok('create_project', {'name': name})).project['id'] as String;

  group('add_media', () {
    test('probes videos and photos and appends them in order', () async {
      final id = await newProject('Add');
      final r = await c.ok('add_media', {'project_id': id, 'paths': [video, photo]});
      expect(r.text, contains('Added 2 clip(s)'));
      expect(r.data['addedClipIds'], hasLength(2));
      expect(r.clips.map((x) => x['id']), r.data['addedClipIds']);
      expect(r.clips[0], containsPair('type', 'video'));
      expect(r.clips[0], containsPair('file', 'clip one.mp4'));
      expect(r.clips[0], containsPair('width', 640));
      expect(r.clips[0], containsPair('height', 360));
      expect(r.clips[0], containsPair('hasAudio', true));
      expect(r.clips[0]['sourceDurationMs'], closeTo(2000, 60));
      expect(r.clips[0]['sourceOutMs'], r.clips[0]['sourceDurationMs']);
      expect(r.clips[1], containsPair('type', 'photo'));
      expect(r.clips[1], containsPair('durationMs', 3000));
      expect(r.clips[1], containsPair('width', 400));
      expect(r.project['canvasWidth'], 640);
      final saved = await b.store.load(id);
      expect(saved.clips.map((x) => x.path), [video, photo]);
      expect(saved.clips[1].type, ClipType.photo);
    });

    test('inserts at an index and takes the photo time', () async {
      final id = await newProject('Insert');
      await c.ok('add_media', {'project_id': id, 'paths': [video]});
      final r = await c.ok('add_media',
          {'project_id': id, 'paths': [photo, talk], 'index': 0, 'photo_duration_ms': 1500});
      expect(r.clips.map((x) => x['file']), ['photo.png', 'talk.mp4', 'clip one.mp4']);
      expect(r.clips[0]['durationMs'], 1500);
      // The shape stays that of the first clip that was ever added.
      expect([r.project['canvasWidth'], r.project['canvasHeight']], [640, 360]);
    });

    test('adds what it can and names what it cannot', () async {
      final id = await newProject('Mixed');
      final junk = b.file('notes.mp4');
      File(junk).writeAsStringSync('this is not a video');
      final r = await c.ok('add_media', {'project_id': id, 'paths': [junk, video, music]});
      expect(r.clips, hasLength(1));
      expect(r.text, contains('Added 1 clip(s)'));
      expect(r.text, contains('NOT added: notes.mp4: the file could not be read as media'));
      expect(r.text, contains('music.m4a: this is a sound file without a picture; add it with add_music'));
      expect(r.data['problems'], hasLength(2));
      final none = await c.fails('add_media', {'project_id': id, 'paths': [junk]});
      expect(none, startsWith('Nothing was added.'));
      expect((await b.store.load(id)).clips, hasLength(1));
    });
  }, skip: skipWithoutFfmpeg);

  group('add_music', () {
    test('adds the whole file at 0 by default, or as asked', () async {
      final id = await newProject('Music');
      await c.ok('add_media', {'project_id': id, 'paths': [video]});
      final r = await c.ok('add_music', {'project_id': id, 'path': music});
      final audioId = r.data['audioId'] as String;
      expect(r.audio.single['id'], audioId);
      expect(r.audio.single['timelineStartMs'], 0);
      expect(r.audio.single['sourceDurationMs'], closeTo(5000, 80));
      expect(r.text, contains('audio_id=$audioId "music.m4a"'));
      final second = await c.ok('add_music', {
        'project_id': id, 'path': music, 'start_ms': 500, 'in_ms': 1000, 'out_ms': 2000,
        'volume': 0.4, 'fade_in_ms': 200, 'fade_out_ms': 300, //
      });
      final a = (await b.store.load(id)).audio.last;
      expect(a.id, second.data['audioId']);
      expect([a.startMs, a.inMs, a.outMs, a.volume, a.fadeInMs, a.fadeOutMs], [500, 1000, 2000, 0.4, 200, 300]);      // The Music track was busy at 500: it went on a new track.
      expect(a.trackId, isNot(kMusicTrackId));
      final voice = await c.ok('add_music', {'project_id': id, 'path': music, 'track_id': 'Voice', 'start_ms': 9000});
      expect(voice.text, contains('on the "Voice" track'));
      final p = await b.store.load(id);
      expect(p.trackById(voice.data['trackId'] as String)!.speech, isTrue);
      expect(await c.fails('add_music', {'project_id': id, 'path': music, 'track_id': 'Crowd'}),
          contains('no sound track "Crowd"'));
    });

    test('refuses files without sound', () async {
      final id = await newProject('NoSound');
      expect(await c.fails('add_music', {'project_id': id, 'path': photo}), contains('No sound was found'));
    });
  }, skip: skipWithoutFfmpeg);

  group('remove_silences', () {
    test('cuts the known gap, keeping 150 ms of quiet on each side', () async {
      final id = await newProject('Talk');
      final clipId =
          ((await c.ok('add_media', {'project_id': id, 'paths': [talk]})).data['addedClipIds'] as List).single;
      // A caption on the speech after the gap must move with it.
      await c.ok('add_caption', {'project_id': id, 'text': 'After the pause', 'start_ms': 3200, 'end_ms': 3800});
      // A dry run lists the cut and saves nothing.
      final saved = (await b.store.load(id)).toJson();
      final dry = await c.ok('remove_silences', {'project_id': id, 'dry_run': true});
      expect(dry.text, allOf(startsWith('DRY RUN'), contains('Would remove 1 silent gap(s)'), contains('Cuts (timeline position now')));
      final cut = (dry.data['cuts'] as List).single as Map;
      expect(cut['timelineStartMs'], closeTo(1650, 60));
      expect(cut['removedMs'], closeTo(1200, 100));
      expect(dry.data['removedMs'], closeTo(1200, 100));
      expect((await b.store.load(id)).toJson(), saved);
      final r = await c.ok('remove_silences', {'project_id': id});
      expect(r.data['gapsRemoved'], 1);
      expect(r.text, contains('Removed 1 silent gap(s)'));
      expect(r.text, contains('Titles and captions moved with their picture'));
      expect(r.clips, hasLength(2));
      expect(r.clips[0]['id'], clipId);
      // Silence 1500..3000 -> cut 1650..2850 (silencedetect is exact to a few ms).
      expect(r.clips[0]['sourceInMs'], 0);
      expect(r.clips[0]['sourceOutMs'], closeTo(1650, 60));
      expect(r.clips[1]['sourceInMs'], closeTo(2850, 60));
      expect(r.clips[1]['sourceOutMs'], closeTo(4000, 60));
      expect(r.data['removedMs'], closeTo(1200, 100));
      expect(r.project['durationMs'], closeTo(2800, 120));
      expect(r.titles.single['startMs'], closeTo(3200 - 1200, 100));

      // Nothing left to cut.
      final again = await c.ok('remove_silences', {'project_id': id});
      expect(again.data['gapsRemoved'], 0);
      expect(again.data['changed'], isFalse);
      expect(again.text, contains('No silent gaps were found'));
    });

    test('one clip only; gaps under the minimum are left alone', () async {
      final id = await newProject('Talk twice');
      final ids =
          (await c.ok('add_media', {'project_id': id, 'paths': [talk, talk, video]})).data['addedClipIds'] as List;
      final none = await c.ok('remove_silences', {'project_id': id, 'min_silence_ms': 2500});
      expect(none.data['gapsRemoved'], 0);
      final r = await c.ok('remove_silences', {'project_id': id, 'clip_id': ids[1]});
      expect(r.data['gapsRemoved'], 1);
      expect(r.clips.map((x) => x['file']), ['talk.mp4', 'talk.mp4', 'talk.mp4', 'clip one.mp4']);
      expect(r.clips[0]['durationMs'], closeTo(4000, 60));
      final all = await c.ok('remove_silences', {'project_id': id});
      expect(all.data['gapsRemoved'], 1, reason: 'only the first clip still had its gap');
      expect(all.clips, hasLength(5));
    });
  }, skip: skipWithoutFfmpeg);

  group('sound source', () {
    late String tracks;
    setUpAll(() {
      if (!ffmpegOk) return;
      // #1 mono 440 Hz; #2 stereo: 1000 Hz on the left (quiet 1..2.5 s),
      // 660 Hz on the right.
      tracks = b.file('two tracks.mp4');
      ff([
        '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=4',
        '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=4',
        '-f', 'lavfi', '-i',
        "aevalsrc='0.3*sin(2*PI*1000*t)*not(between(t,1,2.5))|0.3*sin(2*PI*660*t)'"
            ':s=48000:d=4:c=stereo',
        '-map', '0:v', '-map', '1:a', '-map', '2:a', '-c:v', 'libx264',
        '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-t', '4', tracks,
      ]);
    });

    test('add_media records the tracks; set_clip_properties picks track and side', () async {
      final id = await newProject('Interview');
      final added = await c.ok('add_media', {'project_id': id, 'paths': [tracks]});
      final clipId = (added.data['addedClipIds'] as List).single as String;
      expect(added.clips.single, containsPair('audioTracks', 2));
      expect(added.clips.single, containsPair('audioChannels', 1));
      // Track 1 is mono: no side.
      final mono = await c.ok('set_clip_properties',
          {'project_id': id, 'clip_id': clipId, 'audio_channel': 'left'});
      expect(mono.text, contains('only applies to a stereo sound track'));
      expect(mono.clips.single, containsPair('audioChannel', 'both'));
      final r = await c.ok('set_clip_properties', {
        'project_id': id, 'clip_id': clipId, 'audio_track': 2, 'audio_channel': 'left',
        'voice_focus': 40,
      });
      expect(r.clips.single, containsPair('audioTrack', 2));
      expect(r.clips.single, containsPair('audioChannel', 'left'));
      expect(r.clips.single, containsPair('voiceFocusPercent', 40));
      expect(r.text, contains('sound track 2 of 2, left channel only'));
      expect(r.text, contains('voice focus 40%'));
      final far = await c.ok('set_clip_properties',
          {'project_id': id, 'clip_id': clipId, 'audio_track': 5});
      expect(far.text, contains('has 2 sound track(s); it uses track'));
      // Remove silences listens to track 2, left: the 1..2.5 s gap.
      await c.ok('set_clip_properties',
          {'project_id': id, 'clip_id': clipId, 'audio_track': 2, 'audio_channel': 'left'});
      final cut = await c.ok('remove_silences', {'project_id': id});
      expect(cut.data['gapsRemoved'], 1);
      expect(cut.clips, hasLength(2));
      expect(cut.clips[0]['sourceOutMs'], closeTo(1150, 80));
      expect(cut.clips[1]['sourceInMs'], closeTo(2350, 80));
      for (final x in cut.clips) {
        expect(x, containsPair('audioTrack', 2));
        expect(x, containsPair('audioChannel', 'left'));
      }
    });

    test('a clip from an older version is probed when a track is chosen', () async {
      final old = Clip(
          id: 'old', type: ClipType.video, path: tracks, sourceDurationMs: 4000,
          inMs: 0, outMs: 4000, width: 320, height: 180);
      await b.seed('older', clips: [old]);
      final r = await c.ok('set_clip_properties',
          {'project_id': 'older', 'clip_id': 'old', 'audio_track': 2, 'audio_channel': 'right'});
      expect(r.clips.single, containsPair('audioTracks', 2));
      expect(r.clips.single, containsPair('audioTrack', 2));
      expect(r.clips.single, containsPair('audioChannel', 'right'));
      final saved = (await b.store.load('older')).clips.single;
      expect(saved.audioStreams, [1, 2]);
    });
  }, skip: skipWithoutFfmpeg);

  group('export_video', () {
    late String id;
    setUpAll(() async {
      if (!ffmpegOk) return;
      id = await newProject('Show: "final" cut?');
      await c.ok('add_media', {'project_id': id, 'paths': [video, photo], 'photo_duration_ms': 1000});
      await c.ok('add_title', {'project_id': id, 'text': 'Hello', 'start_ms': 0, 'end_ms': 1000});
    });

    test('renders to the default place, with progress, and reports the file', () async {
      final r = await c.call('export_video', {'project_id': id}, 'export-1');
      expect(r.isError, isFalse, reason: r.text);
      final out = r.data['outputPath'] as String;
      expect(out, p.join(b.tmp.path, 'ClipForge', 'exports', 'Show final cut.mp4'));
      expect(File(out).lengthSync(), r.data['sizeBytes']);
      expect(r.data['durationMs'], closeTo(3000, 150));
      expect(r.data['projectDurationMs'], closeTo(3000, 60));
      expect([r.data['width'], r.data['height'], r.data['hasVideo'], r.data['hasAudio']], [640, 360, true, true]);
      expect(r.text, contains('Exported "Show: "final" cut?" to:\n$out'));
      final probe = ffprobeJson(out);
      expect(probedDurationMs(probe), closeTo(3000, 150));
      expect(probedHas(probe, 'video'), isTrue);
      expect(probedHas(probe, 'audio'), isTrue);

      final progress = [
        for (final n in c.notifications)
          if ((n['params'] as Map)['progressToken'] == 'export-1') (n['params'] as Map)['progress'] as num,
      ];
      expect(progress, isNotEmpty);
      expect(progress.last, 100);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThan(progress[i - 1]));
      }
      expect((c.notifications.last['params'] as Map)['total'], 100);
      // No leftovers next to the result.
      expect(Directory(p.dirname(out)).listSync().map((f) => p.basename(f.path)), ['Show final cut.mp4']);

      // The next default export does not overwrite it.
      final second = await c.ok('export_video', {'project_id': id, 'quality': 'small'});
      expect(second.data['outputPath'], p.join(p.dirname(out), 'Show final cut (2).mp4'));
      expect(second.data['quality'], 'small');

      // Which encoder made it is reported; hardware false is the processor.
      expect(r.data['videoEncoder'], isA<String>());
      expect(r.text, contains(r.data['hardwareEncoder'] == true
          ? 'Made with the graphics card'
          : 'Made with the processor (libx264)'));
      final cpu = await c.ok('export_video', {'project_id': id, 'quality': 'small', 'hardware': false});
      expect(cpu.data['videoEncoder'], 'libx264');
      expect(cpu.data['hardwareEncoder'], isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('writes where asked and never replaces a file unasked', () async {
      final out = b.file(p.join('my exports', 'result'));
      final r = await c.ok('export_video', {'project_id': id, 'output_path': out});
      expect(r.data['outputPath'], '$out.mp4');
      File('$out.mp4').writeAsStringSync('precious');
      expect(await c.fails('export_video', {'project_id': id, 'output_path': '$out.mp4'}), contains('already exists'));
      expect(File('$out.mp4').readAsStringSync(), 'precious');
      await c.ok('export_video', {'project_id': id, 'output_path': '$out.mp4', 'overwrite': true});
      expect(File('$out.mp4').lengthSync(), greaterThan(1000));
      // A folder: the default name inside it.
      final dir = await c.ok('export_video', {'project_id': id, 'output_path': p.dirname(out)});
      expect(dir.data['outputPath'], p.join(p.dirname(out), 'Show final cut.mp4'));

      expect(await c.fails('export_video', {'project_id': id, 'output_path': b.file('x.mov')}), contains('.mp4'));
      expect(await c.fails('export_video', {'project_id': id, 'output_path': 'out.mp4'}), contains('full path'));
      expect(await c.fails('export_video', {'project_id': id, 'output_path': video, 'overwrite': true}),
          contains("one of the project's own media files"));
      expect(File(video).lengthSync(), greaterThan(1000));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a failed export keeps the file that was there and reports the log', () async {
      final broken = b.file('broken.mp4');
      File(video).copySync(broken);
      final pid = await newProject('Broken');
      await c.ok('add_media', {'project_id': pid, 'paths': [broken]});
      File(broken).writeAsStringSync('no longer a video');
      final out = b.file('keep.mp4');
      File(out).writeAsStringSync('precious');
      final message = await c.fails('export_video', {'project_id': pid, 'output_path': out, 'overwrite': true});
      expect(message, contains('The export failed'));
      expect(File(out).readAsStringSync(), 'precious');
      expect(Directory(b.tmp.path).listSync().map((f) => p.basename(f.path)).where((n) => n.contains('.part')),
          isEmpty);
    });

    test('titles need the fonts; without titles the export works without them', () async {
      final bare = Bench(fonts: false);
      addTearDown(bare.dispose);
      final clip = Clip(
          id: 'a', type: ClipType.video, path: video, sourceDurationMs: 2000,
          inMs: 0, outMs: 1000, width: 640, height: 360);
      await bare.seed('plain', clips: [clip]);
      await bare.seed('titled',
          clips: [clip], titles: const [TitleOverlay(id: 't', text: 'Hi', startMs: 0, endMs: 500)]);
      final message = await bare.client.fails('export_video', {'project_id': 'titled'});
      expect(message, allOf(contains('DejaVuSans.ttf'), contains('--fonts-dir')));
      final ok = await bare.client.ok('export_video', {'project_id': 'plain'});
      expect(ok.data['durationMs'], closeTo(1000, 150));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('cancel_export stops ffmpeg and leaves no file', () async {
      final pid = await newProject('Long');
      await c.ok('add_media', {'project_id': pid, 'paths': [video, video, video, video, video, video]});
      await c.ok('set_clip_properties', {'project_id': pid, 'clip_id': 'all', 'speed': 0.25});
      final out = b.file(p.join('cancelled', 'long.mp4'));
      final started = await c.ok('export_video', {'project_id': pid, 'output_path': out, 'wait_seconds': 0});
      expect(started.data['status'], anyOf('starting', 'running'));
      final job = started.data['jobId'] as String;
      expect(started.text, contains('get_export_status'));
      final stopped = await c.ok('cancel_export', {'job_id': job});
      expect(stopped.data['status'], 'cancelled');
      expect(File(out).existsSync(), isFalse);
      final dir = Directory(p.dirname(out));
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty, reason: 'no .part file is left');
      expect((await c.ok('get_export_status', {'job_id': job})).data['status'], 'cancelled');
      // The server carries on.
      expect((await c.ok('get_project', {'project_id': pid})).clips, hasLength(6));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a client that gives up on the call does not stop the export', () async {
      final pid = await newProject('Patient');
      await c.ok('add_media', {'project_id': pid, 'paths': [video, video]});
      final out = b.file(p.join('patient', 'p.mp4'));
      var answered = false;
      c.call('export_video', {'project_id': pid, 'output_path': out}, 'give-up').then((_) => answered = true).ignore();
      final requestId = c.lastId;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!c.notifications.any((n) => (n['params'] as Map)['progressToken'] == 'give-up')) {
        expect(DateTime.now().isBefore(deadline), isTrue, reason: 'the export never started');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      c.notify('notifications/cancelled', {'requestId': requestId, 'reason': 'timeout'});
      await c.server.whenIdle();
      expect(answered, isFalse, reason: 'a cancelled request gets no response');
      final list = await c.ok('get_export_status');
      final job = ((list.data['jobs'] as List).first as Map)['jobId'] as String;
      final done = await c.ok('get_export_status', {'job_id': job, 'wait_seconds': 45});
      expect(done.data['status'], 'finished', reason: done.text);
      expect(File(out).existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: skipWithoutFfmpeg);
}
