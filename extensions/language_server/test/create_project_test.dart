@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_spring_language_server/src/create_project.dart';
import 'package:dart_spring_language_server/src/project_template.dart';
// ignore: implementation_imports
import 'package:spring_boot_dart/src/version.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late List<String> commands;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('spring_boot_cli_');
    commands = [];
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<(int, String, String)> cli(List<String> args, {int exit = 0}) async {
    final out = _Capture();
    final err = _Capture();
    final code = await createProject(
      args,
      out: out.sink,
      err: err.sink,
      run: (executable, arguments, directory) async {
        commands.add('$executable ${arguments.join(' ')} @ $directory');
        return exit;
      },
    );
    await out.sink.flush();
    await err.sink.flush();
    await Future<void>.delayed(Duration.zero);
    return (code, out.text, err.text);
  }

  group('create', () {
    test('writes a Spring Boot project and prepares it', () async {
      final target = '${temp.path}/My-Shop';
      final (code, out, _) = await cli([target]);
      expect(code, 0);
      String read(String path) => File('$target/$path').readAsStringSync();
      expect(read('pubspec.yaml'), contains('name: my_shop'));
      expect(
        read('pubspec.yaml'),
        contains('spring_boot_dart: ^$springBootVersion'),
      );
      expect(read('bin/main.dart'), contains('@SpringBootApplication()'));
      expect(
        read('lib/src/greeting/greeting_service.dart'),
        contains("import 'package:my_shop/src/greeting/app_properties.dart';"),
      );
      expect(
        read('lib/resources/application.properties'),
        contains('spring.application.name=my_shop'),
      );
      expect(
        File('$target/test/resources/application-test.properties').existsSync(),
        isTrue,
      );
      expect(
        read('lib/src/greeting/greeting_runner.dart'),
        isNot(contains('__')),
      );
      expect(commands, [
        'dart pub get @ ${Directory(target).absolute.path}',
        'dart run build_runner build @ ${Directory(target).absolute.path}',
      ]);
      expect(out, contains('dart run bin/main.dart'));
    });

    test('--name, --no-pub and the current directory', () async {
      final target = Directory('${temp.path}/here')..createSync();
      Directory('${target.path}/.git').createSync(); // hidden entries are fine
      final previous = Directory.current;
      Directory.current = target;
      try {
        final (code, _, _) = await cli(['.', '--name=shop', '--no-pub']);
        expect(code, 0);
      } finally {
        Directory.current = previous;
      }
      expect(
        File('${target.path}/pubspec.yaml').readAsStringSync(),
        contains('name: shop'),
      );
      expect(commands, isEmpty);
    });

    test('refuses a non-empty directory unless --force', () async {
      final target = Directory('${temp.path}/busy')..createSync();
      File('${target.path}/notes.txt').writeAsStringSync('mine');
      final (code, _, err) = await cli([target.path, '--no-pub']);
      expect(code, isNot(0));
      expect(err, contains('not empty (notes.txt)'));
      expect(File('${target.path}/pubspec.yaml').existsSync(), isFalse);

      final (forced, _, _) = await cli([target.path, '--no-pub', '--force']);
      expect(forced, 0);
      expect(File('${target.path}/notes.txt').readAsStringSync(), 'mine');
    });

    test('invalid names and a failing pub get', () async {
      final (code, _, err) = await cli(['${temp.path}/x', '--name=Bad-Name']);
      expect(code, isNot(0));
      expect(err, contains('not a valid package name'));

      final (failed, _, failure) = await cli(['${temp.path}/y'], exit: 1);
      expect(failed, 1);
      expect(failure, contains('dart pub get failed'));
    });

    test('--help prints the options', () async {
      final (code, out, _) = await cli(['--help']);
      expect(code, 0);
      expect(out, contains('--no-pub'));
      expect(commands, isEmpty);
    });

    test('package names from directory names', () {
      expect(packageNameFrom('My-App'), 'my_app');
      expect(packageNameFrom('2048'), 'app_2048');
      expect(packageNameFrom('class'), 'class_app');
      expect(packageNameProblem('my_app'), isNull);
      expect(packageNameProblem('switch'), contains('keyword'));
    });
  });
}

final class _Capture {
  final _bytes = <int>[];
  late final IOSink sink = IOSink(
    StreamController<List<int>>()..stream.listen(_bytes.addAll),
  );

  String get text => utf8.decode(_bytes);
}
