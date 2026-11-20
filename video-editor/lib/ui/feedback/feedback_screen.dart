import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/build_info.dart';
import '../../core/feedback/feedback.dart';
import '../../core/links.dart';
import '../../core/update/update_log.dart';
import '../about.dart';
import '../app_prefs.dart';
import '../links.dart';
import '../theme.dart';
import '../update/update_controller.dart' show UpdatePlatform, updatePlatformProvider;

// "Send feedback" (1.16). Help > Send feedback… on computers; the three
// dots on phones; a link in About ClipForge, in Help and on the message of
// an update that did not work.
//
// One page: what kind of message, the message, an optional e-mail address
// for a reply, and a box that shows exactly what will be sent. Nothing is
// sent until Send is pressed, there is one request and no second try
// (lib/core/feedback/feedback.dart). What was written is kept as a draft
// in settings.json until it has been sent.

/// [AppPrefs.text]: the message being written (kind, message, e-mail).
const String kFeedbackDraftText = 'feedbackDraft';

/// [AppPrefs.text]: when the last messages were sent (ms, comma separated).
const String kFeedbackSentText = 'feedbackSent';

/// How many lines of the update log can be sent along.
const int kFeedbackLogLines = 12;

/// The word the page shows for each kind of message.
String feedbackKindLabel(FeedbackKind kind) => switch (kind) {
      FeedbackKind.problem => 'Problem',
      FeedbackKind.idea => 'Idea',
      FeedbackKind.praise => 'Praise',
      FeedbackKind.question => 'Question',
    };

/// Sends one message. Tests put a stand-in (or a local server) here.
typedef FeedbackSender = Future<FeedbackOutcome> Function(
    Uri api, Map<String, Object?> payload);

final feedbackSenderProvider =
    Provider<FeedbackSender>((ref) => (api, payload) => sendFeedback(api, payload));

/// How many feedback pages are on screen (0 or 1).
int _feedbackShown = 0;

/// Opens "Send feedback": a window on a wide screen, a page on a phone.
/// [updateFailed]: opened from the message of an update that did not work
/// (the kind starts as Problem, [problem] starts the message, and the last
/// lines of the update log can be ticked to go along).
Future<void> openFeedback(BuildContext context,
    {bool updateFailed = false, String? problem}) async {
  if (_feedbackShown > 0) return;
  {
    if (MediaQuery.sizeOf(context).width >= 700) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          key: const ValueKey('feedback-dialog'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Send feedback',
                            style: Theme.of(dialog).textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, semanticLabel: 'Close'),
                        onPressed: () => Navigator.of(dialog).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: FeedbackBody(
                        updateFailed: updateFailed,
                        problem: problem,
                        onClose: () => Navigator.of(dialog).pop()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (page) => Scaffold(
          key: const ValueKey('feedback-page'),
          appBar: AppBar(title: const Text('Send feedback')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: FeedbackBody(
                  updateFailed: updateFailed,
                  problem: problem,
                  onClose: () => Navigator.of(page).pop()),
            ),
          ),
        ),
      ));
    }
  }
}

class FeedbackBody extends ConsumerStatefulWidget {
  const FeedbackBody(
      {super.key, this.updateFailed = false, this.problem, required this.onClose});
  final bool updateFailed;
  final String? problem;
  final VoidCallback onClose;

  @override
  ConsumerState<FeedbackBody> createState() => _FeedbackBodyState();
}

class _FeedbackBodyState extends ConsumerState<FeedbackBody> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  late final AppPrefs _prefs;
  late final BuildInfo _build;
  late final UpdatePlatform _platform;
  FeedbackKind _kind = FeedbackKind.idea;
  AppLinks _links = AppLinks.builtIn;
  String _system = '';
  List<String> _logLines = const [];
  bool _includeLog = false;

  /// The performance log (core/perf_log.dart) as it was when the page
  /// opened: sent only when ticked, and shown before it is.
  List<String> _detailLines = const [];
  bool _includeDetails = false;
  bool _sending = false;
  bool _sent = false;
  bool _touched = false;

  /// What went wrong with the last Send, in plain words.
  String? _problem;

  /// With [_problem]: the website's form and "Copy my message" are offered.
  bool _offerOtherWays = false;
  Timer? _saveSoon;

  @override
  void initState() {
    super.initState();
    _feedbackShown++;
    _prefs = ref.read(appPrefsProvider);
    _build = ref.read(buildInfoProvider);
    _platform = ref.read(updatePlatformProvider);
    if (widget.updateFailed) _kind = FeedbackKind.problem;
    try {
      _detailLines = ref.read(perfLogProvider).shared().split('\n');
    } catch (_) {}
    _message.addListener(_changed);
    _email.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    final links = await ref.read(linksProvider).ready();
    FeedbackDraft? draft;
    try {
      draft = FeedbackDraft.decode(await _prefs.text(kFeedbackDraftText));
    } catch (_) {}
    var system = '';
    try {
      system = (await ref.read(deviceDetailsProvider)()).system;
    } catch (_) {}
    var lines = const <String>[];
    if (widget.updateFailed) {
      try {
        lines = UpdateLog.inDir(await _platform.stateDir()).tail(kFeedbackLogLines);
      } catch (_) {}
    }
    if (!mounted) return;
    _links = links;
    _system = system;
    _logLines = lines;
    // What was being written comes back, unless typing already began.
    if (!_touched) {
      if (draft != null && !draft.isEmpty) {
        if (!widget.updateFailed) _kind = draft.kind;
        _message.text = draft.message;
        _email.text = draft.email;
      }
      final problem = widget.problem?.trim() ?? '';
      if (widget.updateFailed && _message.text.trim().isEmpty && problem.isNotEmpty) {
        _message.text = 'The update did not work: $problem';
      }
      // Putting it back is not typing: nothing new to save.
      _saveSoon?.cancel();
      _saveSoon = null;
      _touched = false;
    }
    setState(() {});
  }

  void _changed() {
    _touched = true;
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 400), _saveDraft);
    if (mounted) setState(() {});
  }

  void _saveDraft() {
    _saveSoon?.cancel();
    _saveSoon = null;
    if (_sent) return;
    final draft =
        FeedbackDraft(kind: _kind, message: _message.text, email: _email.text);
    // Nothing written: nothing kept.
    _prefs
        .setText(kFeedbackDraftText, draft.isEmpty ? null : draft.encode())
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _feedbackShown--;
    if (_saveSoon != null) _saveDraft();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _withLog => _includeLog && _logLines.isNotEmpty;

  Map<String, Object?> _payload() => buildFeedbackPayload(
        kind: _kind,
        message: _message.text,
        email: _email.text,
        version: _build.version,
        build: _build.buildNumber,
        system: _system.isEmpty ? _platform.os : _system,
        logLines: _withLog ? _logLines : const [],
        detailLines: _includeDetails ? _detailLines : const [],
      );

  Future<void> _send() async {
    if (_sending) return;
    final problem =
        feedbackProblem(message: _message.text, email: _email.text);
    if (problem != null) {
      setState(() {
        _problem = problem;
        _offerOtherWays = false;
      });
      return;
    }
    final now = DateTime.now();
    var recent = const <int>[];
    try {
      recent = feedbackRecentSends(await _prefs.text(kFeedbackSentText), now);
    } catch (_) {}
    final wait = feedbackLimitNote(recent, now);
    if (wait != null) {
      if (!mounted) return;
      setState(() {
        _problem = wait;
        _offerOtherWays = false;
      });
      return;
    }
    final payload = _payload();
    final send = ref.read(feedbackSenderProvider);
    setState(() {
      _sending = true;
      _problem = null;
    });
    FeedbackOutcome outcome;
    try {
      outcome = await send(Uri.parse(_links.feedbackApi), payload);
    } catch (_) {
      outcome = const FeedbackOutcome('offline',
          'The message could not be sent. Check the internet connection and try again.');
    }
    if (outcome.answered) {
      try {
        await _prefs.setText(kFeedbackSentText,
            [...recent, now.millisecondsSinceEpoch].join(','));
      } catch (_) {}
    }
    if (outcome.sent) {
      // Sent: the draft has done its work (also when the page was closed
      // while the message was on its way).
      _saveSoon?.cancel();
      _saveSoon = null;
      _sent = true;
      try {
        await _prefs.setText(kFeedbackDraftText, null);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _problem = outcome.sent ? null : outcome.message;
      _offerOtherWays = !outcome.sent;
    });
  }

  Future<void> _openPage() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = feedbackPageUri(
      _links.feedbackPage,
      kind: _kind,
      version: _build.version,
      build: _build.buildNumber,
      operatingSystem: _platform.os,
    ).toString();
    try {
      await _platform.openUrl(url);
    } catch (_) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('The page could not be opened. Its address is: '
                '${_links.feedbackPage}')));
    }
  }

  Future<void> _copyMessage() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(
        ClipboardData(text: '${_payload()['message'] ?? ''}'));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Message copied. Paste it into the form on the website.')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const dim = TextStyle(color: AppColors.textDim);
    if (_sent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Sent. Thank you!',
                      key: const ValueKey('feedback-sent'),
                      style: text.titleMedium),
                ),
              ],
            ),
            if (_email.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('If your message needs an answer, it will come by e-mail.',
                  style: dim),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('feedback-close'),
                onPressed: widget.onClose,
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    }
    final payload = _payload();
    final app = payload['app'] as Map<String, Object?>;
    final host = Uri.tryParse(_links.feedbackApi)?.host ?? _links.siteLabel;
    Widget row(String label, String value, {Key? key, bool faint = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 76, child: Text(label, style: dim)),
              Expanded(
                child: Text(value,
                    key: key,
                    style: faint ? dim : null),
              ),
            ],
          ),
        );
    final message = '${payload['message']}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('A problem, an idea, something you liked, a question: all '
            'welcome. A person reads every message.', style: dim),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final k in FeedbackKind.values)
              ChoiceChip(
                key: ValueKey('feedback-kind-${k.name}'),
                label: Text(feedbackKindLabel(k)),
                selected: _kind == k,
                onSelected: _sending
                    ? null
                    : (_) {
                        setState(() => _kind = k);
                        _changed();
                      },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('feedback-message'),
          controller: _message,
          enabled: !_sending,
          minLines: 4,
          maxLines: 10,
          maxLength: kFeedbackMaxMessage,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Your message',
            alignLabelWithHint: true,
            helperText: _kind == FeedbackKind.problem
                ? 'What did you do, what did you expect, and what happened instead?'
                : 'Any language you like.',
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('feedback-email'),
          controller: _email,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          maxLength: kFeedbackMaxEmail,
          decoration: const InputDecoration(
            labelText: 'Your e-mail address (optional)',
            helperText: 'Only used to answer you. Leave it empty if you want no reply.',
            helperMaxLines: 2,
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
        if (widget.updateFailed && _logLines.isNotEmpty) ...[
          const SizedBox(height: 4),
          CheckboxListTile(
            key: const ValueKey('feedback-include-log'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeLog,
            onChanged: _sending
                ? null
                : (v) => setState(() => _includeLog = v ?? false),
            title: const Text('Include the last update log lines'),
            subtitle: const Text(
                'They show at which step the update stopped. They can name the '
                'folder ClipForge is installed in. You see them below before '
                'they are sent.'),
          ),
        ],
        if (_detailLines.length > 1)
          CheckboxListTile(
            key: const ValueKey('feedback-include-details'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeDetails,
            onChanged: _sending
                ? null
                : (v) => setState(() => _includeDetails = v ?? false),
            title: const Text('Include details about how ClipForge ran'),
            subtitle: const Text(
                'The performance log: when ClipForge opened a project, saved, '
                'drew sound waves, and when it could not respond. No file '
                'names, no project names, nothing you typed. Useful when '
                'ClipForge was slow or stopped answering. You see the lines '
                'below before they are sent.'),
          ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('feedback-what-is-sent'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.panelHigh,
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What is sent', style: text.titleSmall),
              const SizedBox(height: 2),
              row('Kind', feedbackKindLabel(FeedbackKind.byName(payload['kind'])!),
                  key: const ValueKey('feedback-sent-kind')),
              row('Message', message.isEmpty ? '(nothing written yet)' : message,
                  key: const ValueKey('feedback-sent-message'),
                  faint: message.isEmpty),
              row('E-mail', '${payload['email'] ?? 'not included'}',
                  key: const ValueKey('feedback-sent-email'),
                  faint: payload['email'] == null),
              row(
                  'Version',
                  '${app['version']}'
                      '${app['build'] == null ? '' : ' (build ${app['build']})'}',
                  key: const ValueKey('feedback-sent-version')),
              row('System', '${app['os']}',
                  key: const ValueKey('feedback-sent-system')),
              const SizedBox(height: 10),
              Text(
                  'Only this is sent, to $host, and only when you press Send. '
                  'Nothing about your projects, file names, videos, photos '
                  'or music is ever included.',
                  key: const ValueKey('feedback-never-included'),
                  style: text.bodySmall?.copyWith(color: AppColors.textDim)),
            ],
          ),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          Text(_problem!,
              key: const ValueKey('feedback-problem'),
              style: const TextStyle(color: AppColors.danger)),
          if (_offerOtherWays) ...[
            const SizedBox(height: 4),
            const Text(
                'Your message is kept here. You can try again later, or use '
                'the form on the website.',
                style: dim),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const ValueKey('feedback-open-page'),
                  onPressed: _openPage,
                  child: const Text('Open the feedback page in the browser'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('feedback-copy'),
                  onPressed: _copyMessage,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy my message'),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('feedback-send'),
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Sending…' : 'Send'),
          ),
        ),
      ],
    );
  }
}
