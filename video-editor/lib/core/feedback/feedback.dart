// "Send feedback" (1.16): what is sent, and the one request that sends it.
//
// The message goes to the website's feedback address (lib/core/links.dart)
// as ONE https POST of JSON, schema v1 (web/lib/feedback.ts is the other
// end; test/core/fixtures/feedback_payloads.json is checked by the tests of
// both, so the two cannot drift apart):
//
//   {"v":1,"kind":"problem","message":"...","email":"you@example.org",
//    "app":{"version":"1.16.0","build":"160","os":"Windows 11 ..."},
//    "source":"app"}
//
// Nothing else is ever put in: no project, no file name, no media, no
// device name. It is sent only when the user presses Send; there is no
// second try and nothing in the background.
//
// Pure Dart (dart:io for the request).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What kind of message it is; [name] is what is sent (the words the
/// page shows are in lib/ui/feedback/feedback_screen.dart).
enum FeedbackKind {
  problem,
  idea,
  praise,
  question;

  static FeedbackKind? byName(Object? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// The longest message the website accepts.
const int kFeedbackMaxMessage = 5000;

/// The longest e-mail address.
const int kFeedbackMaxEmail = 254;

/// Version, build and system are cut to this (the website refuses longer).
const int kFeedbackMaxShort = 60;

/// How long the one request may take.
const Duration kFeedbackTimeout = Duration(seconds: 15);

/// At most this many messages ...
const int kFeedbackMaxPerWindow = 5;

/// ... in this time, from one device.
const Duration kFeedbackWindow = Duration(minutes: 10);

/// What comes between the message and the update log lines.
const String kFeedbackLogHeading = 'Last lines of the update log:';

final RegExp _email =
    RegExp(r'''^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[^\s@<>(),;:"\\.]{2,}$''');

/// What is being written (also what is kept as the draft).
class FeedbackDraft {
  const FeedbackDraft({
    this.kind = FeedbackKind.idea,
    this.message = '',
    this.email = '',
  });
  final FeedbackKind kind;
  final String message;
  final String email;

  bool get isEmpty => message.trim().isEmpty && email.trim().isEmpty;

  String encode() =>
      jsonEncode({'kind': kind.name, 'message': message, 'email': email});

  /// The draft in [text], or null when there is none (or it is damaged).
  static FeedbackDraft? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final message = json['message'], email = json['email'];
      return FeedbackDraft(
        kind: FeedbackKind.byName(json['kind']) ?? FeedbackKind.idea,
        message: message is String ? message : '',
        email: email is String ? email : '',
      );
    } catch (_) {
      return null;
    }
  }
}

String _short(String value) {
  final clean = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F\s]+'), ' ').trim();
  return clean.length <= kFeedbackMaxShort
      ? clean
      : clean.substring(0, kFeedbackMaxShort).trimRight();
}

/// The message as it is sent: [message], and under it the [logLines] of
/// the update log when the user ticked them. Older lines are left out
/// first when everything together would pass [kFeedbackMaxMessage].
String feedbackMessage(String message, {List<String> logLines = const []}) {
  final text = message.trim();
  if (logLines.isEmpty) return text;
  var lines = [for (final l in logLines) l.trimRight()];
  String build() => '$text\n\n$kFeedbackLogHeading\n${lines.join('\n')}';
  while (lines.length > 1 && build().length > kFeedbackMaxMessage) {
    lines = lines.sublist(1);
  }
  final all = build();
  return all.length <= kFeedbackMaxMessage
      ? all
      : all.substring(0, kFeedbackMaxMessage);
}

/// Why this cannot be sent as it is (plain words), or null.
String? feedbackProblem({required String message, String email = ''}) {
  if (message.trim().isEmpty) return 'Please write a message first.';
  if (message.trim().length > kFeedbackMaxMessage) {
    return 'The message is too long (at most $kFeedbackMaxMessage characters).';
  }
  final address = email.trim();
  if (address.isNotEmpty &&
      (address.length > kFeedbackMaxEmail || !_email.hasMatch(address))) {
    return 'The e-mail address does not look right. Leave it empty if you '
        'do not want a reply.';
  }
  return null;
}

/// Exactly what is sent. [version] and [build] are the app's ("1.16.0",
/// "160"; no build number for a copy made on someone's own computer),
/// [system] the system's name and version. Keys with nothing in them are
/// left out.
Map<String, Object?> buildFeedbackPayload({
  required FeedbackKind kind,
  required String message,
  String email = '',
  required String version,
  String? build,
  required String system,
  List<String> logLines = const [],
}) {
  final address = email.trim();
  final number = build == null ? '' : _short(build);
  return {
    'v': 1,
    'kind': kind.name,
    'message': feedbackMessage(message, logLines: logLines),
    if (address.isNotEmpty) 'email': address,
    'app': {
      'version': _short(version),
      if (number.isNotEmpty) 'build': number,
      'os': _short(system),
    },
    'source': 'app',
  };
}

/// How the one request ended.
class FeedbackOutcome {
  const FeedbackOutcome(this.kind, this.message, {this.status});

  /// "sent", "offline" (no connection or no answer in time), "refused"
  /// (the website said what is wrong with the message, or "too many") or
  /// "failed" (the website could not pass it on).
  final String kind;

  /// For the user, in plain words.
  final String message;

  /// The website's answer code, when it answered.
  final int? status;

  bool get sent => kind == 'sent';

  /// The website answered (counts for the limit of
  /// [kFeedbackMaxPerWindow]).
  bool get answered => status != null;
}

String _plain(Object? error) {
  if (error is! String) return '';
  final text = error.replaceAll(RegExp(r'[\u0000-\u001F\u007F\s]+'), ' ').trim();
  return text.length <= 300 ? text : '${text.substring(0, 300)}…';
}

/// Sends [payload] to [api]: one POST, at most [timeout] for all of it.
/// Never throws and never tries twice.
Future<FeedbackOutcome> sendFeedback(
  Uri api,
  Map<String, Object?> payload, {
  Duration timeout = kFeedbackTimeout,
  HttpClient Function()? client,
}) async {
  const offline = FeedbackOutcome(
      'offline',
      'The message could not be sent: ClipForge could not reach the '
          'feedback service. Check the internet connection and try again.');
  final http = (client ?? HttpClient.new)();
  http.userAgent = 'ClipForge (feedback)';
  http.connectionTimeout = timeout;
  Future<FeedbackOutcome> run() async {
    final body = utf8.encode(jsonEncode(payload));
    final request = await http.postUrl(api);
    request.followRedirects = false;
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      // The real answer is a few dozen bytes.
      if (bytes.length < 16 * 1024) bytes.addAll(chunk);
    }
    final status = response.statusCode;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {}
    final said = json is Map ? _plain(json['error']) : '';
    if (status == HttpStatus.ok && json is Map && json['ok'] == true) {
      return FeedbackOutcome('sent', 'Sent. Thank you!', status: status);
    }
    if (status >= 400 && status < 500) {
      return FeedbackOutcome(
          'refused',
          said.isNotEmpty
              ? said
              : 'The feedback service did not accept the message (it '
                  'answered $status).',
          status: status);
    }
    return FeedbackOutcome(
        'failed',
        said.isNotEmpty
            ? said
            : 'The feedback service could not take the message just now '
                '(it answered $status). Please try again later.',
        status: status);
  }

  try {
    return await run().timeout(timeout);
  } on TimeoutException {
    return const FeedbackOutcome(
        'offline',
        'The message could not be sent: the feedback service did not '
            'answer in time. Check the internet connection and try again.');
  } on IOException {
    return offline;
  } catch (_) {
    return offline;
  } finally {
    http.close(force: true);
  }
}

/// "Windows", "Mac", "Android" or "Other": the systems the website's form
/// knows, from Dart's name of this one.
String feedbackFormSystem(String operatingSystem) => switch (operatingSystem) {
      'windows' => 'Windows',
      'macos' => 'Mac',
      'android' => 'Android',
      _ => 'Other',
    };

/// The feedback form on the website with the kind, version and system
/// filled in ([page] is its address). The message and the e-mail address
/// are NOT put into the address: addresses end up in histories and logs.
Uri feedbackPageUri(
  String page, {
  required FeedbackKind kind,
  required String version,
  String? build,
  required String operatingSystem,
}) {
  final uri = Uri.parse(page);
  final number = build == null || build.isEmpty ? '' : ' (build $build)';
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'source': 'app',
    'kind': kind.name,
    'version': _short('$version$number'),
    'os': feedbackFormSystem(operatingSystem),
  });
}

/// The times (ms since 1970) of the last sends still inside
/// [kFeedbackWindow], from the text the app keeps.
List<int> feedbackRecentSends(String? text, DateTime now) {
  final from = now.millisecondsSinceEpoch - kFeedbackWindow.inMilliseconds;
  return [
    for (final part in (text ?? '').split(','))
      if (int.tryParse(part.trim()) case final t?
          when t > from && t <= now.millisecondsSinceEpoch)
        t,
  ];
}

/// Null when another message may be sent now; else the plain sentence
/// that says to wait, and for how long.
String? feedbackLimitNote(List<int> recent, DateTime now) {
  if (recent.length < kFeedbackMaxPerWindow) return null;
  final oldest = recent.reduce((a, b) => a < b ? a : b);
  final wait = Duration(
      milliseconds:
          oldest + kFeedbackWindow.inMilliseconds - now.millisecondsSinceEpoch);
  final minutes = (wait.inSeconds / 60).ceil().clamp(1, kFeedbackWindow.inMinutes);
  return 'You have sent $kFeedbackMaxPerWindow messages in the last '
      '${kFeedbackWindow.inMinutes} minutes. Please wait about $minutes '
      '${minutes == 1 ? 'minute' : 'minutes'} and try again.';
}
