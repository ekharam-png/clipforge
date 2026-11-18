// The JSON-RPC / MCP layer on its own, with made-up tools.

import 'dart:async';
import 'dart:convert';

import 'package:clipforge/mcp/mcp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Client client;
  late McpServer server;
  late Completer<void> gate;
  late List<String> order;

  setUp(() {
    gate = Completer<void>();
    order = [];
    server = McpServer(
      name: 'test',
      title: 'Test server',
      version: '9.9.9',
      instructions: 'be nice',
      tools: [
        ToolDef(
          name: 'echo',
          title: 'Echo',
          description: 'Returns its text.',
          properties: {
            'text': {'type': 'string', 'description': 'What to say.'},
            'times': {'type': 'integer', 'description': 'Repeat.'},
            'loud': {'type': 'boolean', 'description': 'Upper case.'},
            'mode': {
              'type': 'string',
              'description': 'Mode.',
              'enum': ['a', 'b'],
            },
            'ratio': {'type': 'number', 'description': 'A number.'},
            'list': {
              'type': 'array',
              'description': 'Strings.',
              'minItems': 1,
              'items': {'type': 'string'},
            },
          },
          required: const ['text'],
          readOnly: true,
          handler: (a, call) async {
            order.add('echo ${a['text']}');
            return ToolResult('${a['text']}', structured: {'text': a['text']});
          },
        ),
        ToolDef(
          name: 'fail',
          title: 'Fail',
          description: 'Always fails.',
          properties: const {},
          handler: (a, call) async => throw ToolError('the file is missing'),
        ),
        ToolDef(
          name: 'crash',
          title: 'Crash',
          description: 'Throws something unexpected.',
          properties: const {},
          handler: (a, call) async => throw StateError('boom'),
        ),
        ToolDef(
          name: 'slow',
          title: 'Slow',
          description: 'Waits for the test, reporting progress.',
          properties: const {},
          handler: (a, call) async {
            order.add('slow start');
            call.progress(10, total: 100, message: 'ten');
            call.progress(5, total: 100); // not increasing: dropped
            call.progress(50, total: 100);
            final cancelled = Completer<void>();
            call.onCancel(cancelled.complete);
            await Future.any([gate.future, cancelled.future]);
            order.add(call.isCancelled ? 'slow cancelled' : 'slow end');
            return const ToolResult('done');
          },
        ),
      ],
    );
    client = Client(server);
  });

  Map<String, dynamic> initParams([String version = '2025-11-25']) => {
        'protocolVersion': version,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'tester', 'version': '1'},
      };

  group('lifecycle', () {
    test('initialize answers with the requested revision, capabilities and info', () async {
      final r = await client.request('initialize', initParams());
      expect(r['jsonrpc'], '2.0');
      final result = r['result'] as Map;
      expect(result['protocolVersion'], '2025-11-25');
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
      expect(result['serverInfo'], {'name': 'test', 'title': 'Test server', 'version': '9.9.9'});
      expect(result['instructions'], 'be nice');
      expect(server.negotiatedVersion, '2025-11-25');
    });

    test('an older supported revision is accepted as it is', () async {
      for (final v in ['2025-06-18', '2025-03-26', '2024-11-05']) {
        final r = await client.request('initialize', initParams(v));
        expect((r['result'] as Map)['protocolVersion'], v);
      }
    });

    test('an unknown revision gets the newest one this server speaks', () async {
      for (final v in ['2099-01-01', '1.0', 'DRAFT-2026-v1']) {
        final r = await client.request('initialize', initParams(v));
        expect((r['result'] as Map)['protocolVersion'], kProtocolVersions.first);
      }
      final r = await client.request('initialize', <String, dynamic>{});
      expect((r['result'] as Map)['protocolVersion'], kProtocolVersions.first);
    });

    test('notifications get no reply', () {
      expect(client.raw('{"jsonrpc":"2.0","method":"notifications/initialized"}'), isEmpty);
      expect(server.initialized, isTrue);
      expect(client.raw('{"jsonrpc":"2.0","method":"notifications/whatever","params":{}}'), isEmpty);
      expect(client.raw('{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":77}}'), isEmpty);
    });

    test('ping returns an empty result, also with a string id', () {
      final out = client.raw('{"jsonrpc":"2.0","id":"abc","method":"ping"}');
      expect(out.single, {'jsonrpc': '2.0', 'id': 'abc', 'result': <String, dynamic>{}});
    });

    test('responses from the client are ignored', () {
      expect(client.raw('{"jsonrpc":"2.0","id":5,"result":{}}'), isEmpty);
      expect(client.raw('{"jsonrpc":"2.0","id":5,"error":{"code":1,"message":"x"}}'), isEmpty);
    });
  });

  group('errors', () {
    Map<String, dynamic> error(String line) {
      final out = client.raw(line);
      expect(out, hasLength(1));
      return (out.single['error'] as Map).cast<String, dynamic>();
    }

    test('broken JSON is a parse error with a null id', () {
      final out = client.raw('{"jsonrpc": "2.0", "id": 1, "method": ');
      expect(out.single['id'], isNull);
      expect((out.single['error'] as Map)['code'], kParseError);
    });

    test('things that are not JSON-RPC 2.0 are invalid requests', () {
      expect(error('42')['code'], kInvalidRequest);
      expect(error('"hi"')['code'], kInvalidRequest);
      expect(error('{"id":1,"method":"ping"}')['code'], kInvalidRequest);
      expect(error('{"jsonrpc":"1.0","id":1,"method":"ping"}')['code'], kInvalidRequest);
      expect(error('{"jsonrpc":"2.0","id":1}')['code'], kInvalidRequest);
      expect(error('{"jsonrpc":"2.0","id":null,"method":"ping"}')['code'], kInvalidRequest);
      expect(error('{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}')['code'], kInvalidRequest);
      expect(error('[]')['code'], kInvalidRequest);
    });

    test('unknown methods and bad params', () {
      expect(error('{"jsonrpc":"2.0","id":1,"method":"resources/list"}')['code'], kMethodNotFound);
      expect(error('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[1]}')['code'], kInvalidParams);
      final unknown = error('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope"}}');
      expect(unknown['code'], kInvalidParams);
      expect(unknown['message'], contains('Unknown tool: nope'));
      expect(error('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}')['code'], kInvalidParams);
      expect(
          error('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":"x"}}')['code'],
          kInvalidParams);
    });

    test('a batch (revision 2025-03-26) is answered message by message', () {
      final out = client.raw('[{"jsonrpc":"2.0","id":1,"method":"ping"},'
          '{"jsonrpc":"2.0","method":"notifications/initialized"},'
          '{"jsonrpc":"2.0","id":2,"method":"ping"}]');
      expect(out.map((m) => m['id']), [1, 2]);
    });
  });

  group('tools', () {
    test('tools/list describes every tool with a schema and hints', () async {
      final r = await client.request('tools/list');
      final tools = ((r['result'] as Map)['tools'] as List).cast<Map>();
      expect(tools.map((t) => t['name']), ['echo', 'fail', 'crash', 'slow']);
      final echo = tools.first;
      expect(echo['title'], 'Echo');
      expect(echo['description'], 'Returns its text.');
      final schema = echo['inputSchema'] as Map;
      expect(schema['type'], 'object');
      expect(schema['required'], ['text']);
      expect(schema['additionalProperties'], isFalse);
      expect((schema['properties'] as Map).keys, containsAll(['text', 'times']));
      expect(echo['annotations'], containsPair('readOnlyHint', true));
      // No required list rather than an empty one.
      expect((tools[1]['inputSchema'] as Map).containsKey('required'), isFalse);
    });

    test('a call returns text and structured content', () async {
      final reply = await client.call('echo', {'text': 'héllo → мир'});
      expect(reply.isError, isFalse);
      expect(reply.text, 'héllo → мир');
      expect(reply.data, {'text': 'héllo → мир'});
      expect(reply.result.containsKey('isError'), isFalse);
    });

    test('missing arguments object means no arguments', () async {
      final r = await client.request('tools/call', {'name': 'fail'});
      expect(((r['result'] as Map)['content'] as List).single, {'type': 'text', 'text': 'the file is missing'});
    });

    test('a ToolError is a result with isError, not a protocol error', () async {
      expect(await client.fails('fail'), 'the file is missing');
    });

    test('an unexpected exception is reported as a tool error too', () async {
      expect(await client.fails('crash'), allOf(contains('Unexpected error in crash'), contains('boom')));
      // ...and the server keeps working.
      expect((await client.call('echo', {'text': 'still here'})).text, 'still here');
    });

    test('arguments are checked against the schema', () async {
      expect(await client.fails('echo'), contains('Missing required argument "text"'));
      expect(await client.fails('echo', {'text': null}), contains('Missing required argument "text"'));
      expect(await client.fails('echo', {'text': 'x', 'txt': 1}),
          allOf(contains('Unknown argument "txt"'), contains('Allowed arguments: text, times')));
      expect(await client.fails('echo', {'text': 5}), contains('"text" of echo must be a string'));
      expect(await client.fails('echo', {'text': 'x', 'times': 1.5}), contains('whole number'));
      expect(await client.fails('echo', {'text': 'x', 'times': '3'}), contains('whole number'));
      expect(await client.fails('echo', {'text': 'x', 'loud': 'yes'}), contains('true or false'));
      expect(await client.fails('echo', {'text': 'x', 'ratio': 'big'}), contains('must be a number'));
      expect(await client.fails('echo', {'text': 'x', 'mode': 'c'}), contains('must be one of: a, b'));
      expect(await client.fails('echo', {'text': 'x', 'list': 'a'}), contains('must be a list'));
      expect(await client.fails('echo', {'text': 'x', 'list': <String>[]}), contains('at least 1 item'));
      expect(await client.fails('echo', {'text': 'x', 'list': ['a', 3]}), contains('must be a string'));
      // Accepted: whole numbers written as 2.0, optional values left null.
      final ok = await client.call(
          'echo', {'text': 'x', 'times': 2.0, 'loud': null, 'ratio': 1, 'mode': 'b', 'list': ['a']});
      expect(ok.isError, isFalse);
    });

    test('calls run one at a time, in order; ping is answered meanwhile', () async {
      final slow = client.call('slow');
      final echo = client.call('echo', {'text': 'second'});
      await pumpEventQueue();
      expect(order, ['slow start']);
      expect(client.raw('{"jsonrpc":"2.0","id":"p","method":"ping"}').single['id'], 'p');
      gate.complete();
      expect((await slow).text, 'done');
      expect((await echo).text, 'second');
      expect(order, ['slow start', 'slow end', 'echo second']);
      await server.whenIdle();
    });

    test('progress notifications carry the token and only increase', () async {
      final slow = client.call('slow', const {}, 'tok-1');
      await pumpEventQueue();
      expect(client.notifications.map((n) => n['method']).toSet(), {'notifications/progress'});
      expect(client.notifications.map((n) => (n['params'] as Map)['progress']), [10, 50]);
      expect(client.notifications.first['params'],
          {'progressToken': 'tok-1', 'progress': 10, 'total': 100, 'message': 'ten'});
      expect(client.notifications.first.containsKey('id'), isFalse);
      gate.complete();
      await slow;
    });

    test('no progress token, no notifications', () async {
      final slow = client.call('slow');
      await pumpEventQueue();
      gate.complete();
      await slow;
      expect(client.notifications, isEmpty);
    });

    test('notifications/cancelled stops the running call; it gets no response', () async {
      var answered = false;
      final slow = client.call('slow').then((_) => answered = true);
      final queued = client.call('echo', {'text': 'after'});
      await pumpEventQueue();
      client.notify('notifications/cancelled', {'requestId': client.lastId - 1, 'reason': 'user'});
      expect((await queued).text, 'after');
      expect(order, ['slow start', 'slow cancelled', 'echo after']);
      await pumpEventQueue();
      expect(answered, isFalse);
      expect(client.sent.where((m) => m['id'] == client.lastId - 1), isEmpty);
      slow.ignore();
    });

    test('a call cancelled while it waits in the queue never runs', () async {
      final slow = client.call('slow');
      client.call('echo', {'text': 'never'}).ignore();
      await pumpEventQueue();
      client.notify('notifications/cancelled', {'requestId': client.lastId});
      gate.complete();
      await slow;
      await server.whenIdle();
      expect(order, ['slow start', 'slow end']);
    });
  });

  group('serve', () {
    test('reads one message per line (LF or CRLF, UTF-8 split across chunks) and stops at the end', () async {
      final input = StreamController<List<int>>();
      final lines = <String>[];
      final done = server.serve(input.stream, lines.add);
      final bytes = utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}\r\n\n'
          '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"text":"привет"}}}\n'
          '{"jsonrpc":"2.0","id":3,"method":"ping"}');
      // Cut inside a multi-byte character.
      final cut = bytes.indexOf(0xD0) + 1;
      input.add(bytes.sublist(0, cut));
      await pumpEventQueue();
      input.add(bytes.sublist(cut));
      await input.close();
      await done;
      final replies = [for (final l in lines) jsonDecode(l) as Map];
      expect(replies.map((m) => m['id']), unorderedEquals([1, 2, 3]));
      final echo = replies.firstWhere((m) => m['id'] == 2);
      expect((((echo['result'] as Map)['content'] as List).single as Map)['text'], 'привет');
      for (final l in lines) {
        expect(l, isNot(contains('\n')));
      }
    });

    test('the end of the input stops long-running calls and lets quick ones answer', () async {
      final input = StreamController<List<int>>();
      final lines = <String>[];
      final done = server.serve(input.stream, lines.add);
      input.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"slow"}}\n'
          '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"text":"quick"}}}\n'
          '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"slow"}}\n'));
      await pumpEventQueue();
      expect(order, ['slow start']);
      await input.close();
      await done;
      // The second slow call is stopped as soon as it becomes cancellable.
      expect(order, ['slow start', 'slow cancelled', 'echo quick', 'slow start', 'slow cancelled']);
      expect([for (final l in lines) (jsonDecode(l) as Map)['id']], [2]);
    });
  });
}
