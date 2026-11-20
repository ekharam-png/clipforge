// "Send feedback" (1.16), the part without a screen: what is sent
// (checked against the fixture the website's tests read too), and the one
// request, against a real local server: sent, refused with a reason, a
// server error, no answer in time, no connection.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A local "website": answers every POST with [answer] and records it.
class Site {
  Site(this.server);
  final HttpServer server;
  final List<({String method, String path, String? type, String? agent, String body})> requests = [];
  Future<void> Function(HttpRequest request, String body) answer =
      (request, body) async => reply(request, 200, {'ok': true});

  Uri get api => Uri.parse('http://127.0.0.1:${server.port}/api/feedback');

  static Future<void> reply(HttpRequest request, int status, Object? json) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(json is String ? json : jsonEncode(json));
    await request.response.close();
  }

  static Future<Site> start() async {
    final site = Site(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    site.server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      site.requests.add((
        method: request.method,
        path: request.uri.path,
        type: request.headers.contentType?.mimeType,
        agent: request.headers.value(HttpHeaders.userAgentHeader),
        body: body,
      ));
      try {
        await site.answer(request, body);
      } catch (_) {}
    });
    addTearDown(() => site.server.close(force: true));
    return site;
  }
}

void main() {
  final fixture = jsonDecode(
      File(p.join('test', 'core', 'fixtures', 'feedback_payloads.json'))
          .readAsStringSync()) as Map<String, Object?>;
  final cases = (fixture['cases'] as List).cast<Map<String, Object?>>();

  group('what is sent', () {
    test('the fixture has every kind and the special cases', () {
      expect(cases.length, greaterThanOrEqualTo(5));
      expect({for (final c in cases) (c['payload'] as Map)['kind']},
          {for (final k in FeedbackKind.values) k.name});
    });

    for (final c in cases) {
      test('fixture: ${c['name']}', () {
        final input = c['input'] as Map<String, Object?>;
        final payload = buildFeedbackPayload(
          kind: FeedbackKind.byName(input['kind'])!,
          message: input['message'] as String,
          email: input['email'] as String,
          version: input['version'] as String,
          build: input['build'] as String?,
          system: input['system'] as String,
          logLines: (input['logLines'] as List).cast<String>(),
        );
        // The same keys in the same order with the same values: the text
        // that goes over the wire is the fixture's.
        expect(jsonEncode(payload), jsonEncode(c['payload']));
        // Never anything but these.
        expect(payload.keys.toSet().difference({'v', 'kind', 'message', 'email', 'app', 'source'}), isEmpty);
        expect((payload['app'] as Map).keys.toSet().difference({'version', 'build', 'os'}), isEmpty);
        expect(payload['source'], 'app');
        expect(payload['v'], 1);
      });
    }

    test('the message and the update log lines stay inside the limit', () {
      expect(feedbackMessage('  hello \n'), 'hello');
      final lines = [for (var i = 0; i < 400; i++) 'line $i ${'x' * 40}'];
      final text = feedbackMessage('It stopped.', logLines: lines);
      expect(text.length, lessThanOrEqualTo(kFeedbackMaxMessage));
      expect(text, startsWith('It stopped.\n\n$kFeedbackLogHeading\n'));
      // The newest lines are the ones that stay.
      expect(text, endsWith(lines.last));
      expect(text, isNot(contains('line 0 ')));
    });

    test('what cannot be sent is said before anything is sent', () {
      expect(feedbackProblem(message: '   '), 'Please write a message first.');
      expect(feedbackProblem(message: 'x' * (kFeedbackMaxMessage + 1)), contains('too long'));
      expect(feedbackProblem(message: 'Hi', email: 'not an address'), contains('e-mail address'));
      expect(feedbackProblem(message: 'Hi', email: 'a@b'), contains('e-mail address'));
      expect(feedbackProblem(message: 'Hi', email: ' me@example.org '), isNull);
      expect(feedbackProblem(message: 'Hi'), isNull);
    });

    test('the draft survives being written down, and a damaged one is nothing', () {
      const draft = FeedbackDraft(kind: FeedbackKind.question, message: 'Why "x"?\nLine 2', email: 'me@example.org');
      final back = FeedbackDraft.decode(draft.encode())!;
      expect((back.kind, back.message, back.email), (draft.kind, draft.message, draft.email));
      expect(FeedbackDraft.decode(null), isNull);
      expect(FeedbackDraft.decode('{nonsense'), isNull);
      expect(FeedbackDraft.decode('[1]'), isNull);
      expect(FeedbackDraft.decode('{"kind":"unknown","message":3}')!.kind, FeedbackKind.idea);
      expect(const FeedbackDraft().isEmpty, isTrue);
    });

    test('the page on the website gets the kind, version and system, never the message', () {
      final uri = feedbackPageUri('https://example.org/feedback',
          kind: FeedbackKind.problem, version: '1.16.0', build: '160', operatingSystem: 'macos');
      expect(uri.toString(), startsWith('https://example.org/feedback?'));
      expect(uri.queryParameters, {
        'source': 'app',
        'kind': 'problem',
        'version': '1.16.0 (build 160)',
        'os': 'Mac',
      });
      expect(
          feedbackPageUri('https://example.org/feedback',
                  kind: FeedbackKind.idea, version: '1.16.0', operatingSystem: 'linux')
              .queryParameters,
          {'source': 'app', 'kind': 'idea', 'version': '1.16.0', 'os': 'Other'});
      expect([for (final os in ['windows', 'android', 'ios']) feedbackFormSystem(os)],
          ['Windows', 'Android', 'Other']);
    });

    test('at most 5 in 10 minutes', () {
      final now = DateTime(2026, 11, 20, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      final text = [
        ago(const Duration(minutes: 30)), // too old to count
        ago(const Duration(minutes: 9)),
        ago(const Duration(minutes: 5)),
        ago(const Duration(minutes: 4)),
        ago(const Duration(minutes: 1)),
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch, // clock changed
        'junk',
      ].join(',');
      final recent = feedbackRecentSends(text, now);
      expect(recent.length, 4);
      expect(feedbackLimitNote(recent, now), isNull);
      final five = [...recent, ago(Duration.zero)];
      expect(feedbackLimitNote(five, now),
          'You have sent 5 messages in the last 10 minutes. Please wait about 1 minute and try again.');
      expect(feedbackLimitNote(five, now.subtract(const Duration(minutes: 0))), contains('wait'));
      // Ten minutes after the oldest one, the way is free again.
      final later = now.add(const Duration(minutes: 1, seconds: 1));
      expect(feedbackLimitNote(feedbackRecentSends(five.join(','), later), later), isNull);
      expect(feedbackRecentSends(null, now), isEmpty);
    });
  });

  group('the one request (a real local server)', () {
    final payload = buildFeedbackPayload(
        kind: FeedbackKind.idea,
        message: 'Привет — "hello"',
        email: 'me@example.org',
        version: '1.16.0',
        build: '160',
        system: 'TestOS 1.0');

    test('sent: one POST of exactly the payload, as JSON', () async {
      final site = await Site.start();
      final outcome = await sendFeedback(site.api, payload);
      expect((outcome.kind, outcome.sent, outcome.status, outcome.answered), ('sent', true, 200, true));
      expect(outcome.message, 'Sent. Thank you!');
      expect(site.requests.length, 1);
      final r = site.requests.single;
      expect((r.method, r.path, r.type), ('POST', '/api/feedback', 'application/json'));
      expect(r.agent, 'ClipForge (feedback)');
      expect(r.body, jsonEncode(payload));
      expect(jsonDecode(r.body), payload);
    });

    test('refused (400): the website\'s own words are shown, nothing is retried', () async {
      final site = await Site.start()
        ..answer = (request, body) => Site.reply(request, 400,
            {'ok': false, 'error': 'The e-mail address does not look right.\nLeave it empty.'});
      final outcome = await sendFeedback(site.api, payload);
      expect((outcome.kind, outcome.sent, outcome.status), ('refused', false, 400));
      expect(outcome.message, 'The e-mail address does not look right. Leave it empty.');
      expect(site.requests.length, 1);
    });

    test('too many (429) and an answer without words', () async {
      final site = await Site.start()
        ..answer = (request, body) => Site.reply(request, 429,
            {'ok': false, 'error': 'That is a lot of messages in a short time.'});
      var outcome = await sendFeedback(site.api, payload);
      expect((outcome.kind, outcome.message), ('refused', 'That is a lot of messages in a short time.'));
      site.answer = (request, body) => Site.reply(request, 404, '<html>not here</html>');
      outcome = await sendFeedback(site.api, payload);
      expect(outcome.kind, 'refused');
      expect(outcome.message, contains('answered 404'));
    });

    test('server errors (502 with words, 500 without, 200 that is not ok)', () async {
      final site = await Site.start()
        ..answer = (request, body) => Site.reply(request, 502,
            {'ok': false, 'error': 'The message could not be sent just now. Please try again later.'});
      var outcome = await sendFeedback(site.api, payload);
      expect((outcome.kind, outcome.sent, outcome.status), ('failed', false, 502));
      expect(outcome.message, 'The message could not be sent just now. Please try again later.');
      site.answer = (request, body) => Site.reply(request, 500, 'Internal Server Error');
      outcome = await sendFeedback(site.api, payload);
      expect(outcome.kind, 'failed');
      expect(outcome.message, contains('answered 500'));
      // A page that says 200 but is not the feedback service (a captive
      // portal, a parked domain) is not "sent".
      site.answer = (request, body) => Site.reply(request, 200, '<html>Welcome</html>');
      outcome = await sendFeedback(site.api, payload);
      expect((outcome.kind, outcome.sent), ('failed', false));
      // A redirect is not followed.
      site.answer = (request, body) async {
        request.response
          ..statusCode = 302
          ..headers.set(HttpHeaders.locationHeader, 'http://127.0.0.1:${site.server.port}/elsewhere');
        await request.response.close();
      };
      final before = site.requests.length;
      outcome = await sendFeedback(site.api, payload);
      expect(outcome.sent, isFalse);
      expect(site.requests.length, before + 1);
    });

    test('no answer in time: given up after the timeout, said plainly', () async {
      final never = Completer<void>();
      final site = await Site.start()..answer = (request, body) => never.future;
      addTearDown(never.complete);
      final watch = Stopwatch()..start();
      final outcome =
          await sendFeedback(site.api, payload, timeout: const Duration(milliseconds: 400));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect((outcome.kind, outcome.sent, outcome.status, outcome.answered), ('offline', false, null, false));
      expect(outcome.message, contains('did not answer in time'));
      expect(site.requests.length, 1);
      expect(kFeedbackTimeout, const Duration(seconds: 15));
    });

    test('offline: nothing listens there', () async {
      // A port that was just closed.
      final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = gone.port;
      await gone.close(force: true);
      final outcome = await sendFeedback(
          Uri.parse('http://127.0.0.1:$port/api/feedback'), payload,
          timeout: const Duration(seconds: 5));
      expect((outcome.kind, outcome.sent, outcome.answered), ('offline', false, false));
      expect(outcome.message, contains('Check the internet connection'));
      // A name that does not exist behaves the same.
      final nowhere = await sendFeedback(
          Uri.parse('https://feedback.invalid/api/feedback'), payload,
          timeout: const Duration(seconds: 5));
      expect(nowhere.kind, 'offline');
    });
  });
}
