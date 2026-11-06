// The editor against the example apps with their real metadata (the
// lib/spring_gen/spring_metadata.json of each app and of its dependencies):
// not one error or warning on their application*.yml / .properties files
// and theme files. When this fails, either the metadata misses a key (add
// it to a @ConfigurationProperties class of the package and run build_runner)
// or the editor is wrong.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

void main() {
  final examples = Directory('$_repository/example');
  const apps = [
    'server_guide',
    'flutter_guide',
    'themes/neon',
    'themes/material',
    'themes/cupertino',
  ];

  test('the check is not vacuous: a misspelled key is reported', () {
    final root = Directory(
      '${examples.path}/server_guide',
    ).resolveSymbolicLinksSync();
    final path = '$root/lib/resources/application.properties';
    final workspace = SpringWorkspace([root])
      ..setOverlay(path, 'server.prot=8080\nserver.port=8080\n')
      ..refresh(force: true);
    final found = [for (final p in workspace.problems(path)) p.message];
    expect(found, hasLength(1));
    expect(found.single, contains("Did you mean 'port'?"));
  });

  // Zed opens the repository, not the app: the starters' sources are in
  // the workspace too. A bean a starter declares with a BeanDefinition in
  // its auto-configuration file (ThemeSelection) lives in another file
  // than its class, and must still count.
  test(
    'injection points: no false "No bean" with the whole repository open',
    () {
      if (_unresolved('${examples.path}/themes/neon')) {
        return;
      }
      final repository = Directory('${examples.path}/..')
          .resolveSymbolicLinksSync();
      final workspace = SpringWorkspace([repository])..refresh(force: true);
      final sources = Directory(
        '${examples.path}/themes/neon/lib/src',
      ).resolveSymbolicLinksSync();
      final reported = <String>[];
      for (final entity in Directory(sources).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        for (final problem in workspace.problems(entity.path)) {
          if (problem.message.contains('bean')) {
            reported.add('${entity.path}: ${problem.message}');
          }
        }
      }
      expect(reported, isEmpty);
    },
  );

  // Many packages of the repository declare a `Book` (tests, examples):
  // the data example's derived queries must be checked against its own.
  test('data example: its own entity, its repositories are beans, '
      'whole repository open', () {
    final repository = Directory('${examples.path}/..')
        .resolveSymbolicLinksSync();
    final workspace = SpringWorkspace([repository])..refresh(force: true);
    final path = '$repository/spring_boot_starter_data/example/example.dart';
    final reported = [
      for (final problem in workspace.problems(path))
        if (problem.message.contains('property') ||
            problem.message.contains('bean'))
          problem.message,
    ];
    expect(reported, isEmpty);
  });

  for (final app in apps) {
    test('$app: no false diagnostics on its configuration', () {
      final root = Directory('${examples.path}/$app')
          .resolveSymbolicLinksSync();
      if (_unresolved(root)) {
        return;
      }
      final workspace = SpringWorkspace([root])..refresh(force: true);
      final resources = Directory('$root/lib/resources');
      final files = [
        for (final entity in resources.listSync(recursive: true))
          if (entity is File && _isConfig(entity.path)) entity.path,
      ];
      expect(files, isNotEmpty);
      final reported = <String>[];
      for (final file in files) {
        for (final problem in workspace.problems(file)) {
          reported.add(
            '${file.substring(root.length + 1)}:${problem.range.startLine + 1}'
            ': ${problem.message}',
          );
        }
      }
      expect(reported, isEmpty);
      // A package without metadata would be an info note.
      expect([
        for (final note in workspace.metadataNotes(files.first)) note.message,
      ], isEmpty);
    });
  }

  // The repositories of the data starter's example (spring_boot_starter_data/
  // example/example.dart): every derived query and the `@Query` joins, with
  // the metadata the generator writes for it (test/fixtures). server_guide
  // has no data layer yet.
  group('data starter example', () {
    late EditorFixture fixture;
    late String source;
    late String path;

    setUp(() {
      fixture = EditorFixture.create(withAppMetadata: false);
      // The generated file is not there: its import is left out.
      source =
          File(
            '$_repository/spring_boot_starter_data/example/'
            'example.dart',
          ).readAsStringSync().replaceAll(
            "import 'spring_gen/example.spring.dart';",
            '',
          );
      fixture.open(
        'lib/spring_gen/spring_metadata.json',
        File(
          '$_repository/extensions/language_server/test/fixtures/data_example_metadata.json',
        ).readAsStringSync().replaceAll('neon_data', 'app'),
      );
      path = fixture.open('lib/example.dart', source);
    });
    tearDown(() => fixture.dispose());

    test('no false diagnostics', () {
      expect(messages(fixture.workspace.problems(path)), isEmpty);
    });

    test('the check is not vacuous: a typo in the SQL is reported', () {
      final typo = source.replaceFirst('b.{Book.author}', 'b.{Book.autor}');
      fixture.open('lib/example.dart', typo);
      expect(
        messages(fixture.workspace.problems(path)),
        anyElement(contains("did you mean 'author'?")),
      );
      fixture.open(
        'lib/example.dart',
        source.replaceFirst('findByYearGreaterThan', 'findByYearGreterThan'),
      );
      expect(
        messages(fixture.workspace.problems(path)),
        anyElement(contains("'yearGreterThan'")),
      );
    });

    test('hovers and navigation work on the join', () {
      final join = at(source, 'join {Author} a on a.{Author.|id}');
      expect(fixture.workspace.hover(path, join), contains('**Author.id**'));
      final target = fixture.workspace.definition(path, join);
      expect(target, hasLength(1));
      expect(target.single.path, path);
    });
  });
}

// Configuration and theme files; message bundles are not properties.
bool _isConfig(String path) {
  final name = path.split('/').last;
  if (path.contains('/messages/') || name.startsWith('messages')) {
    return false;
  }
  return name.endsWith('.yml') ||
      name.endsWith('.yaml') ||
      name.endsWith('.properties');
}

// The repository's root, from the package's folder or from the workspace
// root (CI runs the tests from both).
final String _repository = () {
  var directory = Directory.current.absolute;
  while (true) {
    if (Directory('${directory.path}/extensions/language_server')
        .existsSync()) {
      return directory.resolveSymbolicLinksSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Not inside the repository: ${Directory.current.path}');
    }
    directory = parent;
  }
}();

// Whether the app at [root] has no `.dart_tool/package_config.json`: then
// the editor cannot find its dependencies and their metadata, so the test
// is skipped. That is the case of the Flutter apps in the Dart-only CI job
// (no Flutter SDK, no `flutter pub get`); the Flutter job runs this test
// after `flutter pub get` with REAL_APPS_REQUIRED=true, where a missing
// resolution fails instead.
bool _unresolved(String root) {
  // A package of the pub workspace has it at the workspace's root.
  for (
    var directory = Directory(root);
    directory.path.startsWith(_repository);
    directory = directory.parent
  ) {
    if (File('${directory.path}/.dart_tool/package_config.json').existsSync()) {
      final workspace = directory.path != root;
      // A Flutter app has its own resolution; the root one does not cover it.
      if (!workspace ||
          !File('$root/pubspec.yaml')
              .readAsStringSync()
              .contains('sdk: flutter')) {
        return false;
      }
      break;
    }
    if (directory.parent.path == directory.path) {
      break;
    }
  }
  final reason =
      '${root.split('/').last} is not resolved (run `flutter pub get` there)';
  if (Platform.environment['REAL_APPS_REQUIRED'] == 'true') {
    fail(reason);
  }
  markTestSkipped(reason);
  return true;
}
