@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Talks LSP to a real server process, like an editor does.
final class _Client {
  _Client(this._process) {
    _process.stdout.listen(_onBytes);
    _process.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  final Process _process;
  final _buffer = <int>[];
  final _pending = <int, Completer<Object?>>{};
  final notifications = StreamController<Map<String, Object?>>.broadcast();
  var _nextId = 1;

  void _onBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    while (true) {
      final text = latin1.decode(_buffer);
      final headerEnd = text.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        return;
      }
      final length = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(text)!.group(1)!,
      );
      if (_buffer.length < headerEnd + 4 + length) {
        return;
      }
      final body = utf8.decode(
        _buffer.sublist(headerEnd + 4, headerEnd + 4 + length),
      );
      _buffer.removeRange(0, headerEnd + 4 + length);
      final message = jsonDecode(body) as Map<String, Object?>;
      if (message.containsKey('id') && !message.containsKey('method')) {
        _pending
            .remove(message['id'])!
            .complete(message['error'] ?? message['result']);
      } else {
        notifications.add(message);
      }
    }
  }

  void _write(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
    _process.stdin
      ..add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'))
      ..add(body);
  }

  Future<Object?> request(String method, Map<String, Object?> params) {
    final id = _nextId++;
    final completer = _pending[id] = Completer<Object?>();
    _write({'id': id, 'method': method, 'params': params});
    // The first request analyses the project, which takes a while when
    // several test processes share the machine.
    return completer.future.timeout(const Duration(seconds: 90));
  }

  void notify(String method, Map<String, Object?> params) =>
      _write({'method': method, 'params': params});
}

void main() {
  late Directory root;
  late _Client client;
  late Process process;
  late String path;
  const source = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Clock {}

@Service()
class SystemClock implements Clock {}

@Service()
class Shop {
  Shop(this.clock, @Value(r'${shop.name}') this.name);
  final Clock clock;
  final String name;

  @Value(r'#{2 * 60} ${shop.unknown}')
  late final String seconds;
}
''';

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('lsp_server_');
    path = '${root.path}/lib/shop.dart';
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
    File('${root.path}/lib/resources/application.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('shop.name=NEON\n');
    // The package directory, wherever the tests are run from.
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dart_spring_language_server/'),
    );
    final package = Directory.fromUri(lib!).parent.path;
    process = await Process.start(Platform.resolvedExecutable, [
      'run',
      '$package/bin/dart_spring_lsp.dart',
    ], workingDirectory: package);
    client = _Client(process);
  });

  tearDownAll(() {
    process.kill();
    root.deleteSync(recursive: true);
  });

  Map<String, int> position(String marker, [int shift = 2]) {
    final offset = source.indexOf(marker) + shift;
    final before = source.substring(0, offset).split('\n');
    return {'line': before.length - 1, 'character': before.last.length};
  }

  test('a full editor session', () async {
    final uri = Uri.file(path).toString();
    final init = await client.request('initialize', {
      'processId': pid,
      'rootUri': Uri.directory(root.path).toString(),
      'capabilities': <String, Object?>{},
    }) as Map;
    final capabilities = init['capabilities'] as Map;
    expect(capabilities['definitionProvider'], isTrue);
    expect(capabilities['semanticTokensProvider'], isNotNull);
    client.notify('initialized', {});

    final diagnostics = client.notifications.stream.firstWhere(
      (m) => m['method'] == 'textDocument/publishDiagnostics',
    );
    client.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': source,
      },
    });

    // Injection point → bean.
    final toBean = await client.request('textDocument/definition', {
      'textDocument': {'uri': uri},
      'position': position('Clock clock'),
    }) as List;
    expect((toBean.single as Map)['uri'], uri);
    expect(((toBean.single as Map)['range'] as Map)['start'], {
      'line': position('class SystemClock')['line'],
      'character': 6,
    });

    // @Value placeholder → properties file.
    final toProperty = await client.request('textDocument/definition', {
      'textDocument': {'uri': uri},
      'position': position(r'${shop.name}', 4),
    }) as List;
    expect(
      (toProperty.single as Map)['uri'],
      endsWith('lib/resources/application.properties'),
    );
    // Navigation only moves the cursor: nothing gets selected.
    for (final location in [...toBean, ...toProperty]) {
      final range = (location as Map)['range'] as Map;
      expect(range['end'], range['start']);
    }

    final hover = await client.request('textDocument/hover', {
      'textDocument': {'uri': uri},
      'position': position(r'${shop.name}', 4),
    }) as Map;
    expect((hover['contents'] as Map)['value'], contains('NEON'));

    final tokens = await client.request('textDocument/semanticTokens/full', {
      'textDocument': {'uri': uri},
    }) as Map;
    expect((tokens['data'] as List).length % 5, 0);
    expect(tokens['data'], isNotEmpty);

    final published = await diagnostics.timeout(const Duration(seconds: 10));
    final messages = [
      for (final d in (published['params'] as Map)['diagnostics'] as List)
        (d as Map)['message'],
    ];
    expect(messages, [
      "Cannot resolve property 'shop.unknown' in any properties file",
    ]);

    expect(
      await client.request('textDocument/definition', {
        'textDocument': {'uri': uri},
        'position': position('String name;'),
      }),
      isNull,
    );

    expect(await client.request('shutdown', {}), isNull);
    client.notify('exit', {});
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
  });
}
