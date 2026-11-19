// Minimal Model Context Protocol server core: JSON-RPC 2.0 messages, the
// initialize handshake, ping, tools/list and tools/call, progress and
// cancellation. Pure Dart and transport independent: [McpServer.handleLine]
// takes one message and writes replies through a callback, [McpServer.serve]
// runs it over a byte stream (stdio: one JSON message per line, UTF-8).
//
// Written against MCP revision 2025-11-25 (see [kProtocolVersions]). Only
// the parts a tools-only server needs are implemented; nothing is sent to
// the client except responses and `notifications/progress`.

import 'dart:async';
import 'dart:convert';

/// Protocol revisions this server can speak, newest first. The differences
/// between them do not touch what is implemented here (structuredContent
/// and tool titles are simply ignored by older clients), except that
/// 2025-03-26 allowed JSON-RPC batches, which are answered one by one.
const List<String> kProtocolVersions = [
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// JSON-RPC error codes.
const int kParseError = -32700;
const int kInvalidRequest = -32600;
const int kMethodNotFound = -32601;
const int kInvalidParams = -32602;
const int kInternalError = -32603;

/// A failure the model should see and can react to (bad argument, missing
/// file, ffmpeg not installed...). Becomes a tool result with `isError`.
class ToolError implements Exception {
  ToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a tool returns.
class ToolResult {
  const ToolResult(this.text, {this.structured, this.isError = false});

  /// Human readable result (the `content` text block).
  final String text;

  /// The same information as a JSON object (`structuredContent`).
  final Map<String, dynamic>? structured;
  final bool isError;

  Map<String, dynamic> toJson() => {
        'content': [
          {'type': 'text', 'text': text},
        ],
        if (structured != null) 'structuredContent': structured,
        if (isError) 'isError': true,
      };
}

/// State of one running `tools/call`, handed to the tool.
class ToolCall {
  ToolCall._(this._sendProgress);

  /// A call nobody listens to (a tool run by another tool).
  ToolCall.silent() : _sendProgress = null;

  final void Function(double progress, double? total, String? message)?
      _sendProgress;
  final List<FutureOr<void> Function()> _onCancel = [];
  bool _cancelled = false;
  bool _abandoned = false;
  double _lastProgress = -1;

  /// True once the client sent `notifications/cancelled` for this call or
  /// went away.
  bool get isCancelled => _cancelled;

  /// True when the client asked for progress notifications.
  bool get wantsProgress => _sendProgress != null;

  /// Reports progress (ignored when the client gave no progress token).
  /// Values that do not increase are dropped, as the protocol requires.
  void progress(double value, {double? total, String? message}) {
    final send = _sendProgress;
    if (send == null || _cancelled || value <= _lastProgress) return;
    _lastProgress = value;
    send(value, total, message);
  }

  /// Runs [callback] when the call is cancelled (at once if it already is).
  void onCancel(FutureOr<void> Function() callback) {
    if (_cancelled || _abandoned) {
      _cancelled = true;
      callback();
    } else {
      _onCancel.add(callback);
    }
  }

  /// The client went away: long-running work (anything that registered or
  /// will register an [onCancel] callback) is stopped; quick calls finish.
  Future<void> _abandon() async {
    _abandoned = true;
    if (_onCancel.isNotEmpty) await _cancel();
  }

  Future<void> _cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    for (final c in List.of(_onCancel)) {
      try {
        await c();
      } catch (_) {}
    }
  }
}

typedef ToolHandler = Future<ToolResult> Function(
    Map<String, dynamic> arguments, ToolCall call);

/// One tool: what `tools/list` shows and the code behind it.
class ToolDef {
  const ToolDef({
    required this.name,
    required this.title,
    required this.description,
    required this.properties,
    this.required = const [],
    this.readOnly = false,
    this.destructive = false,
    this.idempotent = false,
    this.openWorld = false,
    required this.handler,
  });

  final String name;
  final String title;
  final String description;

  /// JSON Schema `properties` of the arguments object.
  final Map<String, Map<String, dynamic>> properties;
  final List<String> required;

  /// Behaviour hints for the client (`annotations`).
  final bool readOnly;
  final bool destructive;
  final bool idempotent;
  final bool openWorld;
  final ToolHandler handler;

  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
        'additionalProperties': false,
      };

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': {
          'title': title,
          'readOnlyHint': readOnly,
          'destructiveHint': destructive,
          'idempotentHint': idempotent,
          'openWorldHint': openWorld,
        },
      };

  /// Checks [arguments] against the schema: unknown names, missing required
  /// values and wrong basic types. Throws a [ToolError] that names the
  /// problem so that the model can correct the call.
  void validate(Map<String, dynamic> arguments) {
    for (final key in arguments.keys) {
      if (!properties.containsKey(key)) {
        throw ToolError('Unknown argument "$key" for $name. '
            'Allowed arguments: ${properties.keys.join(', ')}.');
      }
    }
    for (final key in required) {
      if (arguments[key] == null) {
        throw ToolError('Missing required argument "$key" for $name.');
      }
    }
    for (final e in arguments.entries) {
      final value = e.value;
      if (value == null) continue;
      final schema = properties[e.key]!;
      final problem = _typeProblem(value, schema);
      if (problem != null) {
        throw ToolError('Argument "${e.key}" of $name $problem.');
      }
    }
  }

  static String? _typeProblem(Object value, Map<String, dynamic> schema) {
    switch (schema['type']) {
      case 'string':
        if (value is! String) return 'must be a string';
        final allowed = schema['enum'];
        if (allowed is List && !allowed.contains(value)) {
          return 'must be one of: ${allowed.join(', ')} (got "$value")';
        }
      case 'integer':
        if (value is! num || !value.isFinite) return 'must be a whole number';
        if (value != value.roundToDouble()) {
          return 'must be a whole number (got $value)';
        }
      case 'number':
        if (value is! num || !value.isFinite) return 'must be a number';
      case 'boolean':
        if (value is! bool) return 'must be true or false';
      case 'array':
        if (value is! List) return 'must be a list';
        final items = schema['items'];
        if (items is Map<String, dynamic>) {
          for (final item in value) {
            if (item == null) return 'must not contain null';
            final p = _typeProblem(item as Object, items);
            if (p != null) return 'items: each $p';
          }
        }
        final min = schema['minItems'];
        if (min is int && value.length < min) {
          return 'must contain at least $min item${min == 1 ? '' : 's'}';
        }
    }
    return null;
  }
}

/// A fixed text the client can read (`resources/list`, `resources/read`):
/// the sections of the guide.
class McpResource {
  const McpResource({
    required this.uri,
    required this.name,
    required this.text,
    this.title,
    this.description,
    this.mimeType = 'text/markdown',
  });
  final String uri;
  final String name;
  final String? title;
  final String? description;
  final String mimeType;
  final String text;

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        'title': ?title,
        'description': ?description,
        'mimeType': mimeType,
      };
}

/// The protocol state machine. Tool calls run one after another in the
/// order they arrive (they edit files); ping, cancellation and the other
/// requests are answered at once, also while a tool is running.
class McpServer {
  McpServer({
    required this.name,
    required this.version,
    required List<ToolDef> tools,
    this.title,
    this.instructions,
    List<McpResource> resources = const [],
    void Function(String message)? log,
    this.onClient,
    this.onToolCall,
  })  : tools = {for (final t in tools) t.name: t},
        resources = {for (final r in resources) r.uri: r},
        _log = log ?? ((_) {});

  final String name;
  final String version;
  final String? title;

  /// Told the client's name when it says hello (`initialize`), and every
  /// time a tool is called (1.14: the "in use" file of the helper).
  final void Function(String clientName)? onClient;
  final void Function()? onToolCall;

  /// Usage notes given to the client in the initialize result.
  final String? instructions;
  final Map<String, ToolDef> tools;

  /// Fixed texts offered as MCP resources (none: the capability is not
  /// announced).
  final Map<String, McpResource> resources;
  final void Function(String message) _log;

  /// Protocol revision agreed in `initialize` (null before that).
  String? negotiatedVersion;

  /// True after the client's `notifications/initialized`.
  bool initialized = false;

  void Function(String line) _write = (_) {};
  Future<void> _queue = Future<void>.value();
  final Map<Object, ToolCall> _running = {};
  int _pending = 0;
  Completer<void>? _idle;

  /// Reads newline-delimited JSON-RPC from [input] and writes each outgoing
  /// message (without the newline) with [write]. Completes when the input
  /// has ended and the calls received so far are finished (see [shutdown]).
  Future<void> serve(
      Stream<List<int>> input, void Function(String line) write) async {
    _write = write;
    final lines = input
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      handleLine(line);
    }
    await shutdown();
  }

  /// Called when the client is gone: stops long-running tool calls (an
  /// export), lets quick ones that were already sent finish and answer, and
  /// waits until nothing is running.
  Future<void> shutdown() async {
    for (final call in List.of(_running.values)) {
      await call._abandon();
    }
    await whenIdle();
  }

  /// Completes when no tool call is running or queued.
  Future<void> whenIdle() {
    if (_pending == 0) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Handles one incoming message. Replies go to [write] (or to the writer
  /// given to [serve]); tool results arrive later, in call order.
  void handleLine(String line, {void Function(String line)? write}) {
    if (write != null) _write = write;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      _send(_error(null, kParseError, 'Parse error: ${e.message}'));
      return;
    }
    if (message is List) {
      // JSON-RPC batch (only part of revision 2025-03-26).
      if (message.isEmpty) {
        _send(_error(null, kInvalidRequest, 'Empty batch'));
      }
      for (final m in message) {
        _handleMessage(m);
      }
      return;
    }
    _handleMessage(message);
  }

  void _handleMessage(Object? message) {
    if (message is! Map || message['jsonrpc'] != '2.0') {
      _send(_error(null, kInvalidRequest,
          'Invalid Request: expected a JSON-RPC 2.0 object'));
      return;
    }
    final method = message['method'];
    final hasId = message.containsKey('id');
    final id = message['id'];
    if (method is! String) {
      // A response to a request of ours; this server sends none.
      if (message.containsKey('result') || message.containsKey('error')) return;
      _send(_error(_validId(id) ? id : null, kInvalidRequest,
          'Invalid Request: no method'));
      return;
    }
    final rawParams = message['params'];
    if (rawParams != null && rawParams is! Map) {
      if (hasId) {
        _send(_error(id, kInvalidParams, 'Invalid params: expected an object'));
      }
      return;
    }
    final params = rawParams == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rawParams as Map);

    if (!hasId) {
      _notification(method, params);
      return;
    }
    if (!_validId(id)) {
      _send(_error(null, kInvalidRequest,
          'Invalid Request: id must be a string or a number'));
      return;
    }
    _request(id as Object, method, params);
  }

  static bool _validId(Object? id) => id is String || id is num;

  void _notification(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'notifications/initialized':
        initialized = true;
      case 'notifications/cancelled':
        final target = params['requestId'];
        final call = target == null ? null : _running[target];
        if (call != null) {
          _log('cancelling request $target'
              '${params['reason'] == null ? '' : ' (${params['reason']})'}');
          call._cancel();
        }
      default:
        // Unknown notifications are ignored, as JSON-RPC requires.
        break;
    }
  }

  void _request(Object id, String method, Map<String, dynamic> params) {
    switch (method) {
      case 'initialize':
        _send(_result(id, _initialize(params)));
      case 'ping':
        _send(_result(id, const <String, dynamic>{}));
      case 'tools/list':
        _send(_result(id, {
          'tools': [for (final t in tools.values) t.toJson()],
        }));
      case 'tools/call':
        try {
          onToolCall?.call();
        } catch (_) {}
        _callTool(id, params);
      case 'resources/list' when resources.isNotEmpty:
        _send(_result(id, {
          'resources': [for (final r in resources.values) r.toJson()],
        }));
      case 'resources/templates/list' when resources.isNotEmpty:
        _send(_result(id, const {'resourceTemplates': <Object>[]}));
      case 'resources/read' when resources.isNotEmpty:
        final r = resources[params['uri']];
        if (r == null) {
          // -32002: resource not found (MCP).
          _send(_error(id, -32002, 'Resource not found: ${params['uri']}'));
        } else {
          _send(_result(id, {
            'contents': [
              {'uri': r.uri, 'mimeType': r.mimeType, 'text': r.text},
            ],
          }));
        }
      default:
        _send(_error(id, kMethodNotFound, 'Method not found: $method'));
    }
  }

  Map<String, dynamic> _initialize(Map<String, dynamic> params) {
    final requested = params['protocolVersion'];
    // Same revision when we know it, otherwise our newest; the client
    // disconnects if it cannot work with that.
    final agreed = kProtocolVersions.contains(requested)
        ? requested as String
        : kProtocolVersions.first;
    negotiatedVersion = agreed;
    final client = params['clientInfo'];
    try {
      onClient?.call(client is Map ? '${client['name'] ?? ''}' : '');
    } catch (_) {}
    _log('initialize: client '
        '${client is Map ? '${client['name']} ${client['version']}' : 'unknown'}'
        ', requested protocol $requested, using $agreed');
    return {
      'protocolVersion': agreed,
      'capabilities': {
        'tools': {'listChanged': false},
        if (resources.isNotEmpty)
          'resources': {'subscribe': false, 'listChanged': false},
      },
      'serverInfo': {
        'name': name,
        if (title != null) 'title': title,
        'version': version,
      },
      if (instructions != null) 'instructions': instructions,
    };
  }

  void _callTool(Object id, Map<String, dynamic> params) {
    final toolName = params['name'];
    final tool = toolName is String ? tools[toolName] : null;
    if (tool == null) {
      _send(_error(id, kInvalidParams, 'Unknown tool: $toolName'));
      return;
    }
    final rawArgs = params['arguments'];
    if (rawArgs != null && rawArgs is! Map) {
      _send(_error(id, kInvalidParams,
          'Invalid params: "arguments" must be an object'));
      return;
    }
    final arguments = rawArgs == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rawArgs as Map);

    final meta = params['_meta'];
    final token = meta is Map ? meta['progressToken'] : null;
    final call = ToolCall._(token is String || token is num
        ? (progress, total, message) => _send({
              'jsonrpc': '2.0',
              'method': 'notifications/progress',
              'params': {
                'progressToken': token,
                'progress': progress,
                'total': ?total,
                'message': ?message,
              },
            })
        : null);
    _running[id] = call;
    _pending++;

    _queue = _queue.then((_) async {
      try {
        // A cancelled request gets no response.
        if (call.isCancelled) return;
        ToolResult result;
        try {
          tool.validate(arguments);
          result = await tool.handler(arguments, call);
        } on ToolError catch (e) {
          result = ToolResult(e.message, isError: true);
        } catch (e, st) {
          _log('tool ${tool.name} failed unexpectedly: $e\n$st');
          result = ToolResult('Unexpected error in ${tool.name}: $e',
              isError: true);
        }
        if (call.isCancelled) return;
        _send(_result(id, result.toJson()));
      } finally {
        _running.remove(id);
        _pending--;
        if (_pending == 0) {
          _idle?.complete();
          _idle = null;
        }
      }
    });
  }

  void _send(Map<String, dynamic> message) => _write(jsonEncode(message));

  static Map<String, dynamic> _result(Object id, Map<String, dynamic> result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, dynamic> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
}
