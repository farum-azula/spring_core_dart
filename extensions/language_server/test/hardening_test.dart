// What a workspace or an editor can send that must not stop, slow down or
// widen the server: broken LSP frames, YAML alias bombs and deep nesting,
// links leading out of a package.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_spring_language_server/src/config/theme_loaders.dart';
import 'package:dart_spring_language_server/src/config/yaml_entries.dart';
import 'package:dart_spring_language_server/src/flutter_assets.dart';
import 'package:dart_spring_language_server/src/index/confined_files.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/protocol/message_channel.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

List<int> _framed(String body) {
  final bytes = utf8.encode(body);
  return [...ascii.encode('Content-Length: ${bytes.length}\r\n\r\n'), ...bytes];
}

/// The messages a server sends back for [messages] (after `initialize`),
/// fed in [chunk]-byte pieces.
Future<List<Map<String, Object?>>> _serve(
  List<int> messages, {
  int chunk = 1 << 16,
  int maxContentLength = 64 << 20,
}) async {
  final output = StreamController<List<int>>();
  final sent = <int>[];
  final done = output.stream.listen(sent.addAll).asFuture<void>();
  final sink = IOSink(output);
  final input = [
    ..._framed('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'),
    ...messages,
  ];
  final channel = MessageChannel(
    Stream.fromIterable([
      for (var i = 0; i < input.length; i += chunk)
        input.sublist(i, i + chunk > input.length ? input.length : i + chunk),
    ]),
    sink,
    maxContentLength: maxContentLength,
  );
  await LanguageServer('test', channel, (_, _) => [_Echo()]).serve();
  await sink.close();
  await done;
  final replies = <Map<String, Object?>>[];
  final text = latin1.decode(sent);
  var at = 0;
  while (true) {
    final header = text.indexOf('\r\n\r\n', at);
    if (header < 0) {
      break;
    }
    final length = int.parse(
      RegExp(r'Content-Length: (\d+)')
          .firstMatch(text.substring(at))!
          .group(1)!,
    );
    replies.add(
      jsonDecode(utf8.decode(sent.sublist(header + 4, header + 4 + length)))
          as Map<String, Object?>,
    );
    at = header + 4 + length;
  }
  return replies.skip(1).toList();
}

final class _Echo extends ServerFeature {
  @override
  Map<String, RequestHandler> get requests => {'echo': (params) => params};
}

const _echo = '{"jsonrpc":"2.0","id":9,"method":"echo","params":{"a":1}}';

void main() {
  group('framing', () {
    Future<void> survives(List<int> bad, Object? code) async {
      final replies = await _serve([...bad, ..._framed(_echo)]);
      expect(replies.last, containsPair('id', 9));
      expect(replies.last['result'], {'a': 1});
      if (code != null) {
        expect(
          replies.map((reply) => (reply['error'] as Map?)?['code']),
          contains(code),
        );
      }
    }

    test('a body that is not JSON gets a parse error', () async {
      await survives(_framed('{"jsonrpc":"2.0",'), MessageChannel.parseError);
    });

    test('invalid UTF-8 gets a parse error', () async {
      await survives([
        ...ascii.encode('Content-Length: 2\r\n\r\n'),
        0xff,
        0xfe,
      ], MessageChannel.parseError);
    });

    test('a body that is not an object is an invalid request', () async {
      await survives(_framed('[1,2,3]'), MessageChannel.invalidRequest);
    });

    test('params that are not an object are invalid params', () async {
      await survives(
        _framed('{"jsonrpc":"2.0","id":7,"method":"echo","params":[1]}'),
        -32602,
      );
    });

    test('a method that is not a string is an invalid request', () async {
      await survives(
        _framed('{"jsonrpc":"2.0","id":7,"method":3}'),
        MessageChannel.invalidRequest,
      );
    });

    test('a negative length is a header without a length', () async {
      final replies = await _serve([
        ...ascii.encode('Content-Length: -5\r\n\r\n'),
        ..._framed(_echo),
      ]);
      expect(replies.last['result'], {'a': 1});
    });

    test('a body over the limit is skipped, not buffered', () async {
      final replies = await _serve(
        [
          ...ascii.encode('Content-Length: 200\r\n\r\n'),
          ...List.filled(200, 0x20),
          ..._framed(_echo),
        ],
        chunk: 7,
        maxContentLength: 80,
      );
      expect(replies.first['error'], containsPair('code', -32600));
      expect(replies.last['result'], {'a': 1});
    });

    test('a length that overflows ends reading, not the server', () async {
      final replies = await _serve(
        ascii.encode('Content-Length: 99999999999999999999999\r\n\r\n{}'),
      );
      expect(replies.single['error'], containsPair('code', -32600));
    });

    test(
      'framing is linear: 8 MB without a header end, in small chunks',
      () async {
        final watch = Stopwatch()..start();
        await _serve([
          ...List.filled(8 << 20, 0x41),
          ...ascii.encode('\r\n\r\n'),
          ..._framed(_echo),
        ], chunk: 4096);
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );

    test('many messages in one chunk and one message over many', () async {
      final many = [for (var i = 0; i < 2000; i++) ..._framed(_echo)];
      final watch = Stopwatch()..start();
      expect(await _serve(many), hasLength(2000));
      expect(await _serve(_framed(_echo), chunk: 1), hasLength(1));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('YAML', () {
    String bomb(int levels, int fanout) {
      final b = StringBuffer('a0: &a0 [x]\n');
      for (var i = 1; i <= levels; i++) {
        b.writeln(
          'a$i: &a$i [${List.filled(fanout, '*a${i - 1}').join(', ')}]',
        );
      }
      return b.toString();
    }

    test('an alias bomb stops its document within a time bound', () {
      final watch = Stopwatch()..start();
      final entries = parseYamlProperties(
        'application.yaml',
        '${bomb(9, 10)}---\nshop.name: x\n',
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(entries.map((e) => e.key), ['shop.name']);
    });

    test('aliases within the limit are still expanded', () {
      final entries = parseYamlProperties(
        'application.yaml',
        'base: &b { host: h }\nshop: *b\n',
      );
      expect(entries.map((e) => e.key), ['base.host', 'shop.host']);
    });

    test('deep flow nesting leaves only that document out', () {
      final watch = Stopwatch()..start();
      final entries = parseYamlProperties(
        'application.yaml',
        '${'[' * 50000}${']' * 50000}\n---\nshop.name: x\n',
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      expect(entries.map((e) => e.key), ['shop.name']);
    });

    test('deep block nesting stops at the depth limit', () {
      final text = [for (var i = 0; i < 500; i++) '${' ' * i}k$i:'].join('\n');
      expect(parseYamlProperties('application.yaml', text), isEmpty);
    });

    test('a deeply nested pubspec gives no assets', () {
      expect(flutterAssets('${'[' * 50000}${']' * 50000}\n'), isEmpty);
    });
  });

  group('links', () {
    late Directory temp;
    late String outside;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('confined');
      outside = '${temp.path}/home';
      File('$outside/notes/application.properties')
        ..createSync(recursive: true)
        ..writeAsStringSync('bank.pin=4242\n');
      Link('$outside/loop').createSync(outside);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('a directory linked out of its package is not listed', () {
      final root = '${temp.path}/evil';
      Directory('$root/lib').createSync(recursive: true);
      Link('$root/lib/resources').createSync(outside);
      expect(ConfinedFiles(root, '$root/lib/resources').files(), isEmpty);
    });

    test('links below a directory are not followed', () {
      final root = '${temp.path}/pkg';
      File('$root/lib/resources/application.yml')
        ..createSync(recursive: true)
        ..writeAsStringSync('a: 1\n');
      Link('$root/lib/resources/home').createSync(outside);
      Link('$root/lib/resources/loop').createSync('$root/lib');
      final files = ConfinedFiles(root, '$root/lib/resources').files();
      expect(files.map((f) => f.path), ['$root/lib/resources/application.yml']);
    });

    test('the listing stops at its limit', () {
      final root = '${temp.path}/many';
      for (var i = 0; i < 30; i++) {
        File('$root/web/$i.html').createSync(recursive: true);
      }
      expect(
        ConfinedFiles(root, '$root/web', limit: 10).files(),
        hasLength(10),
      );
    });

    test('a listing is kept until a directory changes', () async {
      final root = '${temp.path}/watched';
      File('$root/web/a.html').createSync(recursive: true);
      final listing = ConfinedFiles(root, '$root/web');
      expect(listing.files(), hasLength(1));
      final file = listing.files().single;
      expect(listing.changed(file), isTrue);
      expect(listing.changed(file), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      File('$root/web/b.html').createSync();
      expect(listing.files(), hasLength(2));
    });

    group('in a workspace', () {
      late EditorFixture fixture;

      setUp(() => fixture = EditorFixture.create());
      tearDown(() => fixture.dispose());

      test('a dependency config linked out of the package is not read', () {
        Link(
          '${fixture.root.path}/neon_ui/lib/resources/secrets',
        ).createSync(outside);
        final path = fixture.open('lib/resources/application.yml', 'a: 1\n');
        final keys = ProjectModel(['${fixture.root.path}/app']).properties
            .configEntries(path)
            .map((e) => e.key);
        expect(keys, isNot(contains('bank.pin')));
        expect(
          keys,
          contains('spring.flutter.theme.themes.neon.colors.primary'),
        );
      });

      test('web files come only from web/ and stay inside packages', () {
        File(fixture.app('web/loaders/mine.html')).createSync(recursive: true);
        File(fixture.app('build/web/old.html')).createSync(recursive: true);
        File(fixture.app('docs/page.html')).createSync(recursive: true);
        File('$outside/secret.html').createSync();
        Link(fixture.app('web/home')).createSync(outside);
        final model = ProjectModel(['${fixture.root.path}/app']);
        final loaders = ThemeLoaders(model);
        final path = fixture.app('lib/resources/application.yml');
        expect(loaders.webFiles(path), [
          'web/loaders/mine.html',
          'web/loaders/neon-doors.html',
        ]);
        expect(loaders.webFile(path, 'web/home/secret.html'), isNull);
        expect(
          loaders.webFile(path, '../../${temp.path}/home/secret.html'),
          isNull,
        );
      });
    });
  });
}
