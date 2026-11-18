// 1.10 in the Claude tools: add_voice (a voice recorded separately is
// lined up with the video by sound, linked, the camera muted), align_audio
// (line up / set the offset / nudge / unlink an existing sound), role /
// linked_clip / offset_ms in the listings, and remove_silences listening
// to the linked voice. Real files made by ffmpeg; skipped without it.

import 'dart:io';
import 'dart:typed_data';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clipforge/media/sound_align.dart' show kAlignRate;

import '../media/sound_align_test.dart' show speech;
import '../media/voice_align_integration_test.dart' show writeWav;
import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  late String camera, other, noAudio, mic, mic2, music;
  const lead = 1300; // the microphone started 1.3 s before the camera

  setUpAll(() {
    if (!ffmpegOk) return;
    b = Bench();
    c = b.client;
    final Float64List talk = speech(26, 5);
    // A 2 s pause at 9..11 s of the talk.
    for (var i = 9 * kAlignRate; i < 11 * kAlignRate; i++) {
      talk[i] = 0;
    }
    writeWav(b.file('talk.wav'), talk);
    writeWav(b.file('talk2.wav'), speech(26, 6));
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    camera = b.file('video1406335665.mp4');
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=25:d=20',
      '-ss', '${lead / 1000}', '-i', b.file('talk.wav'),
      '-f', 'lavfi', '-i', 'anoisesrc=c=white:r=48000:a=0.05:d=20',
      '-filter_complex',
      '[1:a]aresample=48000,aecho=0.8:0.5:40:0.3,volume=0.6[v];'
          '[v][2:a]amix=inputs=2:normalize=0[a]',
      '-map', '0:v', '-map', '[a]', ...x264, '-c:a', 'aac', '-t', '20', camera,
    ]);
    other = b.file('other.mp4');
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=25:d=12',
      '-i', b.file('talk2.wav'),
      '-map', '0:v', '-map', '1:a', ...x264, '-c:a', 'aac', '-t', '12', other,
    ]);
    noAudio = b.file('mute.mp4');
    ff(['-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=25:d=6', ...x264, '-an', noAudio]);
    mic = b.file('audioSamTaylor21406335665.m4a');
    ff(['-i', b.file('talk.wav'), '-af', 'highpass=f=250,lowpass=f=2500,volume=0.3',
        '-c:a', 'aac', mic]);
    mic2 = b.file('mic two.m4a');
    ff(['-ss', '0.5', '-i', b.file('talk.wav'), '-af', 'lowpass=f=1800,volume=0.5',
        '-c:a', 'aac', mic2]);
    music = b.file('song.m4a');
    makeMusic(music);
  });
  tearDownAll(() {
    if (ffmpegOk) b.dispose();
  });

  Future<String> project(String name, {List<String>? paths}) async {
    final id = (await c.ok('create_project', {'name': name})).project['id'] as String;
    await c.ok('add_media', {'project_id': id, 'paths': paths ?? [camera]});
    return id;
  }

  group('add_voice', () {
    test('lines up, links, own speech track named after the speaker, mutes',
        () async {
      final id = await project('Podcast');
      final r = await c.ok('add_voice', {'project_id': id, 'path': mic});
      expect(r.text, contains('Added and lined up'));
      expect(r.text, contains('"Sam Taylor"'));
      expect(r.data['lined_up'], isTrue);
      expect(r.data['offset_ms'], closeTo(lead, 20));
      expect(r.data['confidence'], greaterThan(0.8));
      expect(r.data['drift_ms'], 0);
      expect(r.data['warnings'], isEmpty);
      expect(r.data['cameraMuted'], isTrue);
      final a = r.audio.single;
      expect(a['role'], 'voice');
      expect(a['linked_clip'], r.clips.single['id']);
      expect(a['offset_ms'], r.data['offset_ms']);
      expect(a['followsClip'], isTrue);
      expect(a.containsKey('separatedFromClipId'), isFalse);
      expect(r.clips.single['muted'], isTrue);
      final saved = await b.store.load(id);
      final v = saved.audio.single;
      expect(v.linked && v.isVoice, isTrue);
      expect(v.inMs, closeTo(lead, 20));
      final track = saved.trackById(v.trackId)!;
      expect([track.name, track.speech], ['Sam Taylor', true]);

      // It follows a split and a trim, in the same step.
      final split = await c.ok('split_at', {'project_id': id, 'timeline_ms': 8000});
      expect(split.audio.length, 2);
      expect(split.audio.every((x) => x['linked_clip'] != null), isTrue);
      final first = split.clips.first['id'];
      final t = await c.ok('trim_clip', {'project_id': id, 'clip_id': first, 'in_ms': 2000});
      final mine = t.audio.firstWhere((x) => x['linked_clip'] == first);
      expect(mine['sourceInMs'], (r.data['offset_ms'] as int) + 2000);
      expect(mine['timelineStartMs'], 0);
      // The listing says it too.
      final g = await c.ok('get_project', {'project_id': id});
      expect(g.text, contains('role voice'));
      expect(g.text, contains('linked_clip=$first'));
      expect(g.text, contains('offset_ms=${r.data['offset_ms']}'));
      // One undo per step.
      await c.ok('undo', {'project_id': id});
      await c.ok('undo', {'project_id': id});
      final u = await c.ok('undo', {'project_id': id});
      expect(u.audio, isEmpty);
      expect(u.clips.single['muted'], isFalse);
    });

    test('several video files: the best match; a second speaker: own track',
        () async {
      final id = await project('Two', paths: [other, camera]);
      final r = await c.ok('add_voice', {'project_id': id, 'path': mic});
      final cam = r.clips.firstWhere((x) => x['file'] == 'video1406335665.mp4');
      expect(r.data['clipId'], cam['id']);
      expect(r.text, contains('matched best'));
      expect(cam['muted'], isTrue);
      expect(r.clips.first['muted'], isFalse);
      final two = await c.ok('add_voice',
          {'project_id': id, 'path': mic2, 'track_name': 'Guest', 'mute_clip': false});
      expect(two.data['offset_ms'], closeTo(lead - 500, 20));
      final tracks = (two.project['soundTracks'] as List).cast<Map>();
      expect([for (final t in tracks) t['name']], ['Sam Taylor', 'Guest']);
      expect(two.audio.map((x) => x['role']).toSet(), {'voice'});
      // Music is unchanged: role music, no link.
      final m = await c.ok('add_music', {'project_id': id, 'path': music});
      final song = m.audio.firstWhere((x) => x['id'] == m.data['audioId']);
      expect(song['role'], 'music');
      expect(song.containsKey('linked_clip'), isFalse);
      expect(song.containsKey('offset_ms'), isFalse);
      // A third voice has no track left.
      final no = await c.fails('add_voice', {'project_id': id, 'path': mic});
      expect(no, contains('at most 3 sound tracks'));
    });

    test('no match: at the start of the clip, camera on, a warning', () async {
      final id = await project('Wrong', paths: [other]);
      final r = await c.ok('add_voice', {'project_id': id, 'path': mic});
      expect(r.data['lined_up'], isFalse);
      expect(r.data['confidence'], lessThan(0.5));
      expect(r.data['cameraMuted'], isFalse);
      expect((r.data['warnings'] as List).single,
          contains('Could not line it up automatically'));
      expect(r.text, contains('align_audio'));
      expect(r.audio.single['offset_ms'], 0);
      expect(r.audio.single['timelineStartMs'], 0);
      expect(r.clips.single['muted'], isFalse);

      // A video without sound.
      final id2 = await project('Silent', paths: [noAudio]);
      final s = await c.ok('add_voice', {'project_id': id2, 'path': mic});
      expect(s.data['lined_up'], isFalse);
      expect((s.data['warnings'] as List).single, contains('no video clip has sound'));
    });

    test('align false with an offset; errors', () async {
      final id = await project('Manual');
      final r = await c.ok('add_voice',
          {'project_id': id, 'path': mic, 'align': false, 'offset_ms': -700});
      expect(r.data['offset_ms'], -700);
      expect(r.audio.single['timelineStartMs'], 700);
      expect(r.audio.single['sourceInMs'], 0);
      expect(r.data['cameraMuted'], isTrue);

      final empty = (await c.ok('create_project', {'name': 'Empty'})).project['id'];
      expect(await c.fails('add_voice', {'project_id': empty, 'path': mic}),
          contains('Add the video first'));
      expect(await c.fails('add_voice', {'project_id': id, 'path': b.file('nope.m4a')}),
          contains('nope.m4a'));
      expect(await c.fails('add_voice', {'project_id': id, 'path': noAudio}),
          contains('No sound was found'));
    });
  }, skip: skipWithoutFfmpeg);

  group('align_audio', () {
    test('music that is really a voice is lined up and linked', () async {
      final id = await project('Owner');
      // What the app did before 1.10: the voice landed on the Music track.
      final m = await c.ok('add_music', {'project_id': id, 'path': mic});
      expect(m.audio.single['role'], 'music');
      final r = await c.ok('align_audio',
          {'project_id': id, 'audio_id': m.data['audioId']});
      expect(r.text, contains('Lined up'));
      expect(r.data['offset_ms'], closeTo(lead, 20));
      expect(r.data['lined_up'], isTrue);
      expect(r.audio.single['role'], 'voice');
      expect(r.audio.single['linked_clip'], r.clips.single['id']);
      expect(r.clips.single['muted'], isTrue);
      final tracks = (r.project['soundTracks'] as List).cast<Map>();
      expect(tracks.any((t) => t['name'] == 'Sam Taylor'), isTrue);

      // Nudge, by hand, unlink.
      final voice = (r.data['audioIds'] as List).single;
      final n = await c.ok('align_audio',
          {'project_id': id, 'audio_id': voice, 'nudge_ms': 40});
      expect(n.data['offset_ms'], (r.data['offset_ms'] as int) - 40);
      final h = await c.ok('align_audio',
          {'project_id': id, 'audio_id': voice, 'offset_ms': 1234});
      expect(h.audio.single['offset_ms'], 1234);
      final hid = (h.data['audioIds'] as List).single;
      final u = await c.ok('align_audio', {
        'project_id': id,
        'audio_id': hid,
        'link': false,
        'mute_clip': false,
      });
      expect(u.audio.single.containsKey('linked_clip'), isFalse);
      expect(u.audio.single['offset_ms'], 1234);
      expect(u.audio.single['role'], 'voice');
      expect(u.clips.single['muted'], isFalse);
      expect(await c.fails('align_audio',
              {'project_id': id, 'audio_id': hid, 'nudge_ms': 10}),
          contains('not a linked voice'));
      expect(
          await c.fails('align_audio', {
            'project_id': id,
            'audio_id': hid,
            'nudge_ms': 10,
            'offset_ms': 3
          }),
          contains('only one of'));
    });

    test('sound that does not match: nothing changes', () async {
      final id = await project('NoMatch', paths: [other]);
      final m = await c.ok('add_music', {'project_id': id, 'path': mic});
      final before = File(b.projectFile(id).path).readAsStringSync();
      final r = await c.ok('align_audio',
          {'project_id': id, 'audio_id': m.data['audioId']});
      expect(r.text, contains('Could not line it up automatically'));
      expect(r.text, contains('Nothing was changed'));
      expect(r.data['lined_up'], isFalse);
      expect(File(b.projectFile(id).path).readAsStringSync(), before);
    });

    test('reattach_sound and separated sound say what to use instead',
        () async {
      final id = await project('Wrong tool');
      final r = await c.ok('add_voice', {'project_id': id, 'path': mic});
      final voice = (r.data['audioIds'] as List).single;
      expect(await c.fails('reattach_sound', {'project_id': id, 'audio_id': voice}),
          contains('align_audio with link false'));
    });
  }, skip: skipWithoutFfmpeg);

  test('remove_silences listens to the linked voice, not the muted camera',
      () async {
    // The camera hears constant noise under the talk; the microphone is
    // clean, with a 2 s pause at 9..11 s of the talk = 7.7..9.7 s of the
    // camera.
    final id = await project('Silences');
    final v = await c.ok('add_voice', {'project_id': id, 'path': mic});
    final dry = await c.ok('remove_silences', {'project_id': id, 'dry_run': true});
    expect(dry.text, contains('voice recorded separately'));
    final cuts = (dry.data['cuts'] as List).cast<Map>();
    final pause = cuts.where((x) =>
        (x['sourceStartMs'] as int) < 8500 && (x['sourceEndMs'] as int) > 8900);
    expect(pause, hasLength(1), reason: '$cuts');
    expect(pause.single['sourceStartMs'], closeTo(9000 - lead + 150, 250));
    expect(pause.single['sourceEndMs'], closeTo(11000 - lead - 150, 250));

    final r = await c.ok('remove_silences', {'project_id': id});
    expect(r.data['gapsRemoved'], greaterThanOrEqualTo(1));
    // Every piece has its part of the voice, in sync.
    final saved = await b.store.load(id);
    final offset = v.data['offset_ms'] as int;
    for (var i = 0; i < saved.clips.length; i++) {
      final clip = saved.clips[i];
      final a = saved.audio.singleWhere((x) => x.sourceClipId == clip.id);
      expect(a.inMs, clip.inMs + offset);
      expect(a.startMs, saved.clipStartMs(i));
      expect(a.outMs, clip.outMs + offset);
      expect(clip.muted, isTrue);
    }
    expect(saved.audio.length, saved.clips.length);
    expect(saved.clips.every((x) => x.type == ClipType.video), isTrue);
  }, skip: skipWithoutFfmpeg);

  test('two speakers on their own files: remove_silences cuts the picture '
      'and both voices together (the owner\'s Zoom report)', () async {
    // One video + one sound file per speaker, camera muted. Both
    // microphones are quiet at 9..11 s of the talk.
    final id = await project('Two speakers');
    final v1 = await c.ok('add_voice',
        {'project_id': id, 'path': mic, 'track_name': 'Sam'});
    final v2 = await c.ok('add_voice',
        {'project_id': id, 'path': mic2, 'track_name': 'Anna'});
    expect(v1.data['lined_up'], isTrue);
    expect(v2.data['lined_up'], isTrue);
    final offsets = {
      mic: v1.data['offset_ms'] as int,
      mic2: v2.data['offset_ms'] as int,
    };
    var saved = await b.store.load(id);
    expect(saved.clips.single.muted, isTrue);
    expect(saved.audio.length, 2);
    expect(saved.audio.map((a) => saved.trackById(a.trackId)!.speech), [true, true]);

    // Dry run: the pause is found on the SPEECH tracks (the muted camera
    // only has noise), nothing is saved.
    final dry = await c.ok('remove_silences', {'project_id': id, 'dry_run': true});
    expect(dry.text, startsWith('DRY RUN'));
    expect(dry.text, contains('voice recorded separately'));
    final cuts = (dry.data['cuts'] as List).cast<Map>();
    expect(
        cuts.where((x) =>
            (x['sourceStartMs'] as int) < 8500 && (x['sourceEndMs'] as int) > 8900),
        hasLength(1),
        reason: '$cuts');
    expect((await b.store.load(id)).clips.length, 1);
    expect(dry.data['warnings'] ?? const [], isEmpty);

    // For real: every piece of picture has its part of BOTH voices, at the
    // same offsets as before the cut.
    final real = await c.ok('remove_silences', {'project_id': id});
    expect(real.data['gapsRemoved'], greaterThanOrEqualTo(1));
    saved = await b.store.load(id);
    expect(saved.clips.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < saved.clips.length; i++) {
      final clip = saved.clips[i];
      expect(clip.muted, isTrue);
      final voices = saved.audio.where((x) => x.sourceClipId == clip.id).toList();
      expect(voices.map((x) => x.path).toSet(), {mic, mic2});
      for (final a in voices) {
        expect(a.linked, isTrue);
        expect(a.inMs, clip.inMs + offsets[a.path]!);
        expect(a.outMs, clip.outMs + offsets[a.path]!);
        expect(a.startMs, saved.clipStartMs(i));
      }
    }
    expect(saved.audio.length, 2 * saved.clips.length);
    expect(real.data['warnings'] ?? const [], isEmpty);
  }, skip: skipWithoutFfmpeg);

  test('unlinked sound on a speech track: a cut warns that it is now out of '
      'sync and says what to use', () async {
    final id = await project('Loose voice');
    // Added and linked, then unlinked: it stays on its speech track.
    final v = await c.ok('add_voice', {'project_id': id, 'path': mic});
    final voice = (v.data['audioIds'] as List).single;
    await c.ok('align_audio', {'project_id': id, 'audio_id': voice, 'link': false});
    final clipId = (await b.store.load(id)).clips.single.id;
    final dry = await c.ok('remove_silences', {'project_id': id, 'dry_run': true});
    final warning = (dry.data['warnings'] as List).join(' ');
    expect(warning, contains('NOT linked to a clip'));
    expect(warning, contains('OUT OF SYNC'));
    expect(warning, contains('add_voice'));
    expect(warning, contains('align_audio'));
    expect(dry.text, contains('OUT OF SYNC'));
    final trim = await c.ok('trim_clip',
        {'project_id': id, 'clip_id': clipId, 'in_ms': 3000});
    expect((trim.data['warnings'] as List).join(' '), contains('OUT OF SYNC'));
    // An edit that does not move the picture says nothing.
    final quiet = await c.ok('set_clip_properties',
        {'project_id': id, 'clip_id': clipId, 'volume': 0.5});
    expect('${quiet.data['warnings'] ?? ''}', isNot(contains('OUT OF SYNC')));
    // Linked again: no warning.
    await c.ok('align_audio', {'project_id': id, 'audio_id': voice, 'clip_id': clipId});
    final ok = await c.ok('trim_clip',
        {'project_id': id, 'clip_id': clipId, 'in_ms': 4000});
    expect('${ok.data['warnings'] ?? ''}', isNot(contains('OUT OF SYNC')));
  }, skip: skipWithoutFfmpeg);
}
