// web/_headers from spring.web.resources.cache.cachecontrol.*: the
// Cache-Control value built as Spring builds it, the block written into a
// new file, replaced among the app's own rules and removed when the keys
// go, by the page loader's builder too.
@Timeout(Duration(minutes: 2))
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart/core.dart'
    show MapPropertySource, StandardEnvironment;
import 'package:spring_core_dart_generator/src/flutter/web_cache_headers.dart';
import 'package:spring_core_dart_generator/src/flutter/web_page_loader_builder.dart';
import 'package:test/test.dart';

// The Cache-Control value of [keys] (below the prefix) and the problems.
({String? value, List<String> problems}) _value(Map<String, Object> keys) {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(
      MapPropertySource('test', {
        for (final MapEntry(:key, :value) in keys.entries)
          '${WebCacheHeaders.prefix}.$key': value,
      }),
    );
  final problems = <String>[];
  final value = WebCacheHeaders.cacheControl(
    environment,
    problem: problems.add,
  );
  return (value: value, problems: problems);
}

const _block = '''
# spring:cache:start
# Generated from spring.web.resources.cache.cachecontrol.* on every build: change the configuration, not these lines.
/*
  ! Cache-Control
  Cache-Control: no-cache
/assets/*
  ! Cache-Control
  Cache-Control: max-age=2592000, public
/assets/AssetManifest*
  ! Cache-Control
  Cache-Control: no-cache
/assets/FontManifest.json
  ! Cache-Control
  Cache-Control: no-cache
/assets/NOTICES
  ! Cache-Control
  Cache-Control: no-cache
/assets/*/manifest.json
  ! Cache-Control
  Cache-Control: no-cache
/assets/shaders/*
  ! Cache-Control
  Cache-Control: no-cache
/assets/fonts/MaterialIcons-Regular.otf
  ! Cache-Control
  Cache-Control: no-cache
/assets/packages/cupertino_icons/*
  ! Cache-Control
  Cache-Control: no-cache
/assets/lib/resources/*
  ! Cache-Control
  Cache-Control: no-cache
# spring:cache:end''';

const _before = '''
# The app's own rules.
/*
  X-Frame-Options: DENY
''';

const _after = '''
/fonts/*
  ! Cache-Control
  Cache-Control: max-age=31536000, immutable
''';

final class _Files implements WebPageFiles {
  _Files(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files[path];

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async => files[path] = content;

  @override
  Future<void> delete(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files.remove(path);
}

Future<List<String>> _build(_Files files, String yaml, {String? web}) async {
  final logs = <String>[];
  await testBuilder(
    WebPageLoaderBuilder(files: files),
    {
      'app|pubspec.yaml':
          'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
      'app|lib/app.dart': 'void main() {}',
      'app|lib/resources/application.yaml': yaml,
      'app|lib/resources/application-web.properties': ?web,
    },
    rootPackage: 'app',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return logs;
}

const _page = '<html>\n<head>\n</head>\n<body>\n</body>\n</html>\n';

const _cacheYaml = '''
spring.web.resources.cache.cachecontrol:
  max-age: 30d
  cache-public: true
''';

void main() {
  group('the Cache-Control value', () {
    test("built from the keys in the order of Spring's CacheControl", () {
      expect(
        _value({'max-age': '30d', 'cache-public': true}).value,
        'max-age=2592000, public',
      );
      expect(
        _value({
          'stale-while-revalidate': '1m',
          'proxy-revalidate': 'true',
          's-max-age': '1h',
          'cache-private': 'true',
          'no-transform': 'true',
          'stale-if-error': '1d',
          'must-revalidate': 'true',
          'max-age': '10m',
        }).value,
        'max-age=600, must-revalidate, no-transform, private, '
        'proxy-revalidate, s-maxage=3600, stale-if-error=86400, '
        'stale-while-revalidate=60',
      );
    });

    test('no-store wins over no-cache and max-age, no-cache over max-age', () {
      expect(
        _value({'no-store': true, 'no-cache': true, 'max-age': '1d'}).value,
        'no-store',
      );
      expect(
        _value({'no-cache': 'true', 'max-age': '1d', 'cache-public': true})
            .value,
        'no-cache, public',
      );
    });

    test('durations are seconds in the header, a plain number is seconds', () {
      expect(_value({'max-age': '3600'}).value, 'max-age=3600');
      expect(_value({'max-age': 3600}).value, 'max-age=3600');
      expect(_value({'max-age': '2h'}).value, 'max-age=7200');
      expect(_value({'max-age': 'PT1H30M'}).value, 'max-age=5400');
      expect(_value({'max-age': '1500ms'}).value, 'max-age=1');
      expect(_value({'s-max-age': '7d'}).value, 's-maxage=604800');
      expect(
        _value({'stale-while-revalidate': '90'}).value,
        'stale-while-revalidate=90',
      );
    });

    test('none set, or only false, makes no value', () {
      expect(_value({}).value, isNull);
      expect(
        _value({'no-cache': false, 'cache-public': 'false'}).value,
        isNull,
      );
    });

    test('a value it cannot read is a problem and counts as not set', () {
      final (:value, :problems) = _value({
        'max-age': '30 days',
        'cache-public': 'maybe',
        'no-transform': true,
      });
      expect(value, 'no-transform');
      const prefix = WebCacheHeaders.prefix;
      expect(problems, [
        '$prefix.max-age is a duration (30d, 3600, PT1H), not 30 days.',
        '$prefix.cache-public is true or false, not maybe.',
      ]);
    });
  });

  group('the block', () {
    test('everything no-cache, the assets the value, the assets that change '
        'with every build no-cache again', () {
      expect(WebCacheHeaders.block('max-age=2592000, public'), _block);
    });

    test('written into a new file, and written again unchanged', () {
      const value = 'max-age=2592000, public';
      final written = WebCacheHeaders.apply(null, value);
      expect(written, '$_block\n');
      expect(WebCacheHeaders.apply(written, value), written);
      expect(WebCacheHeaders.apply('', value), '$_block\n');
    });

    test("put after the app's own rules, which are kept", () {
      final written = WebCacheHeaders.apply(_before, 'no-cache');
      expect(written, startsWith(_before));
      expect(written, '$_before\n${WebCacheHeaders.block('no-cache')}\n');
      // Without a line break at the end of the file.
      expect(
        WebCacheHeaders.apply(_before.trimRight(), 'no-cache'),
        written,
      );
    });

    test("replaced where it is, the app's rules before and after it "
        'untouched', () {
      final file =
          '$_before\n${WebCacheHeaders.block('no-cache')}\n'
          '\n$_after';
      final replaced = WebCacheHeaders.apply(file, 'max-age=2592000, public');
      expect(replaced, '$_before\n$_block\n\n$_after');
      expect(
        WebCacheHeaders.apply(replaced, 'no-cache'),
        file,
        reason: 'and back',
      );
    });

    test('a second block in the file is removed', () {
      final old = WebCacheHeaders.block('no-cache');
      final file = '$_before\n$old\n\n$_after\n$old\n';
      expect(
        WebCacheHeaders.apply(file, 'max-age=2592000, public'),
        '$_before\n$_block\n\n$_after',
      );
    });

    test("removed when the keys go, the app's rules kept as they were", () {
      const value = 'max-age=2592000, public';
      final written = WebCacheHeaders.apply(_before, value);
      expect(WebCacheHeaders.apply(written, null), _before);
      const between = '$_before\n$_block\n\n$_after';
      expect(WebCacheHeaders.apply(between, null), '$_before\n$_after');
      const first = '$_block\n\n$_after';
      expect(WebCacheHeaders.apply(first, null), _after);
    });

    test('a file with only the block is left empty, so it can go; a file '
        'without the block is not touched', () {
      expect(WebCacheHeaders.apply('$_block\n', null), '');
      expect(WebCacheHeaders.apply(null, null), '');
      expect(WebCacheHeaders.apply(_after, null), _after);
      expect(WebCacheHeaders.apply('\n', null), '\n');
    });
  });

  group('the page loader builder', () {
    test('writes web/_headers from the keys, creating it', () async {
      final files = _Files({'web/index.html': _page});
      await _build(files, _cacheYaml);
      expect(files.files[WebCacheHeaders.path], '$_block\n');
    });

    test("replaces its block among the app's rules; removes it, and the "
        'file it alone made, when the keys go', () async {
      final files = _Files({
        'web/index.html': _page,
        WebCacheHeaders.path:
            '$_before\n'
            '${WebCacheHeaders.block('no-cache')}\n\n$_after',
      });
      await _build(files, _cacheYaml);
      expect(files.files[WebCacheHeaders.path], '$_before\n$_block\n\n$_after');
      await _build(files, 'spring.flutter.app.title: App\n');
      expect(files.files[WebCacheHeaders.path], '$_before\n$_after');

      final alone = _Files({
        'web/index.html': _page,
        WebCacheHeaders.path: '$_block\n',
      });
      await _build(alone, 'spring.flutter.app.title: App\n');
      expect(alone.files, isNot(contains(WebCacheHeaders.path)));
    });

    test("the web profile's values count", () async {
      final files = _Files({'web/index.html': _page});
      await _build(
        files,
        _cacheYaml,
        web: '${WebCacheHeaders.prefix}.max-age=1h\n',
      );
      expect(
        files.files[WebCacheHeaders.path],
        contains('  Cache-Control: max-age=3600, public\n'),
      );
    });

    test('a value it cannot read fails the build and leaves the file as it '
        'is', () async {
      final files = _Files({
        'web/index.html': _page,
        WebCacheHeaders.path: '$_block\n',
      });
      final logs = await _build(
        files,
        '${WebCacheHeaders.prefix}.max-age: thirty days\n',
      );
      expect(files.files[WebCacheHeaders.path], '$_block\n');
      expect(
        logs.join('\n'),
        contains(
          'The cache headers: ${WebCacheHeaders.prefix}.max-age is a '
          'duration (30d, 3600, PT1H), not thirty days.',
        ),
      );
      expect(logs, contains(startsWith('SEVERE: ')));
    });

    test('no keys and no file: no file', () async {
      final files = _Files({'web/index.html': _page});
      await _build(files, 'spring.flutter.app.title: App\n');
      expect(files.files, isNot(contains(WebCacheHeaders.path)));
    });
  });
}
