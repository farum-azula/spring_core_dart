// Several in-memory builds per test; the machine may be busy with other
// test processes.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// web_dev_config.yaml held in memory instead of the package directory.
final class _Files implements WebDevConfigFiles {
  _Files([this.content]);

  String? content;
  int writes = 0;

  @override
  Future<String?> read(BuildStep buildStep, String package) async => content;

  @override
  Future<void> write(BuildStep buildStep, String package, String text) async {
    content = text;
    writes++;
  }

  @override
  Future<void> delete(BuildStep buildStep, String package) async =>
      content = null;
}

/// Runs the builder over [resources] (paths below `lib/resources/`, text
/// or bytes); returns the log records as `LEVEL: message`.
Future<List<String>> _build(
  _Files files,
  Map<String, Object> resources,
) async {
  final logs = <String>[];
  await testBuilder(
    WebDevConfigBuilder(files: files),
    {
      'app|lib/app.dart': 'void main() {}',
      for (final MapEntry(:key, :value) in resources.entries)
        'app|lib/resources/$key': value,
    },
    rootPackage: 'app',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return logs;
}

Iterable<String> _severe(List<String> logs) =>
    logs.where((log) => log.startsWith('SEVERE: '));

Iterable<String> _warnings(List<String> logs) =>
    logs.where((log) => log.startsWith('WARNING: '));

// The message of a log record of [_build], without the builder's line.
String _message(String log) => log.substring(log.indexOf('\n') + 1);

// The warnings and errors of [logs].
Iterable<String> _problems(List<String> logs) =>
    logs.where((log) => !log.startsWith('INFO: ') && !log.startsWith('FINE'));

// The generated file's content without the header line.
String _body(_Files files) {
  final content = files.content!;
  expect(content, startsWith('${WebDevConfigBuilder.header}\n'));
  return content.substring(WebDevConfigBuilder.header.length + 1);
}

void main() {
  test('no spring.flutter.web.* property: no file', () async {
    final files = _Files();
    final logs = await _build(files, {
      'application.properties': 'spring.flutter.app.title=Shop\n',
      'application-ios.properties': 'spring.flutter.web.port=5050\n',
    });
    expect(files.content, isNull);
    expect(files.writes, 0);
    expect(_severe(logs), isEmpty);
  });

  test('the port of application.yaml', () async {
    final files = _Files();
    await _build(files, {
      'application.yaml': 'spring:\n  flutter:\n    web:\n      port: 5050\n',
    });
    expect(_body(files), 'server:\n  port: 5050\n');
  });

  test('application-web.* wins over application.*; other profiles do not '
      'count; names are relaxed', () async {
    final files = _Files();
    await _build(files, {
      'application.properties':
          'spring.flutter.web.port=4000\n'
          'spring.flutter.web.host=0.0.0.0\n',
      'application-web.yaml':
          'spring:\n  flutter:\n    web:\n      port: 5050\n'
          '      baseHref: /shop/\n',
      'application-android.properties': 'spring.flutter.web.port=1\n',
    });
    expect(
      _body(files),
      'server:\n'
      '  host: "0.0.0.0"\n'
      '  port: 5050\n'
      '  base-href: "/shop/"\n',
    );
  });

  test('a profile activated in the config files counts', () async {
    final files = _Files();
    await _build(files, {
      'application.properties': 'spring.profiles.active=dev\n',
      'application-dev.properties': 'spring.flutter.web.port=5051\n',
    });
    expect(_body(files), 'server:\n  port: 5051\n');
  });

  // A classpath: import was read from lib/resources/ on disk below the
  // working directory, and a property set only in an imported file was
  // not seen at all.
  test('spring.config.import: classpath: and relative imports read the '
      "build's own files", () async {
    final files = _Files();
    await _build(files, {
      'application.yaml':
          'spring:\n'
          '  config:\n'
          '    import:\n'
          '      - classpath:web/dev-server.yaml\n'
          '      - optional:classpath:/web/missing.yaml\n',
      'web/dev-server.yaml':
          'spring:\n'
          '  config:\n'
          '    import: proxy.properties\n'
          '  flutter:\n'
          '    web:\n'
          '      port: 5053\n',
      'web/proxy.properties':
          'spring.flutter.web.proxy[0].prefix=/api/\n'
          'spring.flutter.web.proxy[0].target=http://localhost:8080\n',
    });
    expect(
      _body(files),
      'server:\n'
      '  port: 5053\n'
      '  proxy:\n'
      '    - prefix: "/api/"\n'
      '      target: "http://localhost:8080"\n',
    );
  });

  test(
    'spring.config.import from application-web.*: only for the web',
    () async {
      final files = _Files();
      await _build(files, {
        'application-web.properties':
            'spring.config.import=classpath:dev/web.properties\n',
        'application-ios.properties':
            'spring.config.import=classpath:dev/ios.properties\n',
        'dev/web.properties': 'spring.flutter.web.port=5054\n',
        'dev/ios.properties': 'spring.flutter.web.host=0.0.0.0\n',
      });
      expect(_body(files), 'server:\n  port: 5054\n');
    },
  );

  // The early check skipped the files when no .properties or .yaml file
  // set spring.flutter.web.*: a file imported with an extension hint was
  // never read, and a generated web_dev_config.yaml was deleted.
  test('an import with an extension hint is followed', () async {
    for (final resources in [
      {
        'application.yaml': 'spring.config.import: classpath:dev.conf[.yaml]\n',
        'dev.conf': 'spring:\n  flutter:\n    web:\n      port: 5057\n',
      },
      {
        'application.properties':
            'spring.config.import[0]=classpath:web/dev.conf[.properties]\n',
        'web/dev.conf': 'spring.flutter.web.port=5057\n',
      },
    ]) {
      final files = _Files('${WebDevConfigBuilder.marker}\nold');
      final logs = await _build(files, resources);
      expect(_severe(logs), isEmpty, reason: '$resources');
      expect(_body(files), 'server:\n  port: 5057\n', reason: '$resources');
    }
  });

  // Only a single trailing extension hint was known: an import also
  // naming an encoding (Spring Boot 4.1) was not followed, and a file that
  // is not UTF-8 never read.
  test('an import with file hints is followed as the app reads it', () async {
    for (final resources in <Map<String, Object>>[
      {
        'application.yaml':
            'spring.config.import: classpath:dev.conf[.yaml][encoding=utf-8]\n',
        'dev.conf': 'spring:\n  flutter:\n    web:\n      port: 5057\n',
      },
      {
        'application.yaml':
            'spring.config.import: "optional:dev.conf[encoding=UTF8][.yaml]"\n',
        'dev.conf': 'spring.flutter.web.port: 5057\n',
      },
      // ISO-8859-1, not UTF-8: read only as the import says.
      {
        'application.properties':
            'spring.config.import='
            'classpath:web/dev.conf[.properties][encoding=iso-8859-1]\n',
        'web/dev.conf': latin1.encode(
          '# café\nspring.flutter.web.port=5057\n',
        ),
      },
      {
        'application.properties':
            'spring.config.import=web.properties[encoding=latin1]\n',
        'web.properties': latin1.encode(
          'spring.flutter.web.port=5057\nspring.flutter.web.host=café\n',
        ),
      },
    ]) {
      final files = _Files();
      final logs = await _build(files, resources);
      expect(_severe(logs), isEmpty, reason: '$resources');
      expect(_body(files), contains('  port: 5057\n'), reason: '$resources');
    }
    final files = _Files();
    await _build(files, {
      'application.properties':
          'spring.config.import=web.properties[encoding=latin1]\n',
      'web.properties': latin1.encode('spring.flutter.web.host=café\n'),
    });
    expect(_body(files), 'server:\n  host: "café"\n');
  });

  test('an import naming a charset the app cannot read', () async {
    // Not the business of an app without a key.
    final none = _Files();
    final quiet = await _build(none, {
      'application.yaml':
          'spring.config.import: classpath:dev.conf[.yaml][encoding=utf-16]\n',
      'dev.conf': 'spring.flutter.web.port: 5057\n',
    });
    expect(none.content, isNull);
    expect(_problems(quiet), isEmpty);
    // With one, it fails as the app's start does.
    final logs = await _build(_Files(), {
      'application.yaml':
          'spring.flutter.web.port: 5050\n'
          'spring.config.import: classpath:dev.conf[.yaml][encoding=utf-16]\n',
      'dev.conf': 'spring.flutter.web.host: devhost\n',
    });
    expect(_severe(logs).single, contains("unsupported charset 'utf-16'"));
  });

  // These were read from the build machine's disk, which the app in a
  // browser does not have.
  group('imports of the file system', () {
    late String root;

    setUp(() {
      final temp = Directory.systemTemp.createTempSync('web_dev_config_');
      addTearDown(() => temp.deleteSync(recursive: true));
      root = temp.path.replaceAll(r'\', '/');
      for (final MapEntry(key: path, value: content) in {
        'dev.yaml': 'spring.flutter.web.port: 7001\n',
        'conf/application.yaml': 'spring.flutter.web.port: 7002\n',
        'tree/spring/flutter/web/port': '7003',
        'mounts/a/spring/flutter/web/host': '0.0.0.0',
      }.entries) {
        File('$root/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }
    });

    // file:, a plain absolute path, a directory, wildcards, configtree:
    // and package:; with an extension hint, in a `;` group. The warning
    // names each as written: it named `file:…/dev` for `file:…/dev[.yaml]`,
    // which prefixed with `optional:` loads nothing anywhere.
    List<String> locations() => [
      'file:$root/dev.yaml',
      'file:$root/dev[.yaml]',
      'classpath:web.yaml;file:$root/dev.yaml',
      '$root/dev.yaml',
      'file:$root/conf/',
      'file:$root/*/',
      'file:$root/*/application.yaml',
      'configtree:$root/tree/',
      'configtree:$root/mounts/*/',
      'package:app/dev.yaml',
    ];

    test('optional: skipped, as in a browser', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml':
            'spring:\n'
            '  config:\n'
            '    import:\n'
            '${[for (final l in locations()) '      - "optional:$l"\n'].join()}'
            '  flutter:\n'
            '    web:\n'
            '      port: 5055\n',
      });
      expect(_severe(logs), isEmpty);
      expect(_body(files), 'server:\n  port: 5055\n');
    });

    // A required wildcard (`configtree:dir/*/`, `file:dir/*/name.yaml`)
    // that finds nothing fails the app's start as in Boot; both were
    // skipped without a word. A required one was a build error, also for
    // a package with nothing to write: every pure Dart server whose config
    // imported a file failed to build.
    test('required, with a file to write: skipped with a warning (the web '
        'version would fail to start), the file is written', () async {
      for (final location in locations()) {
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, {
          'application.yaml':
              'spring.config.import: "$location"\n'
              'spring.flutter.web.port: 5055\n',
        });
        expect(_severe(logs), isEmpty, reason: location);
        expect(
          _warnings(logs).single,
          allOf(
            contains(
              "spring.config.import: '$location' is read from the file "
              'system',
            ),
            contains('the web version would fail to start'),
            contains("'optional:$location'"),
            contains('${WebDevConfigBuilder.fileName} is written without it'),
          ),
          reason: location,
        );
        expect(_body(files), 'server:\n  port: 5055\n', reason: location);
      }
    });

    // The builder runs for every package that depends on the generator.
    test('required, with nothing to write: no error, no warning, no file '
        '(a pure Dart app builds)', () async {
      for (final location in [
        ...locations(),
        'package:other/defaults.yml',
      ]) {
        for (final resources in [
          {'application.properties': 'x=1\nspring.config.import=$location\n'},
          {
            'application.yaml':
                'spring:\n'
                '  config:\n'
                '    import:\n'
                '      - "$location"\n'
                '      - optional:file:./local.yml\n',
          },
          {
            'application.properties': 'spring.profiles.active=prod\n',
            'application-prod.properties': 'spring.config.import=$location\n',
          },
        ]) {
          final files = _Files();
          final logs = await _build(files, resources);
          expect(_problems(logs), isEmpty, reason: '$resources');
          expect(files.content, isNull, reason: '$resources');
          // A file generated before the properties were removed still goes.
          final stale = _Files('${WebDevConfigBuilder.marker}\nold');
          expect(
            _severe(await _build(stale, resources)),
            isEmpty,
            reason: '$resources',
          );
          expect(stale.content, isNull, reason: '$resources');
        }
      }
    });

    test("the imports of docs/configuration.md's example build", () async {
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml':
            'spring:\n'
            '  config:\n'
            '    import:\n'
            '      - classpath:themes/ocean.yml\n'
            '      - optional:file:./local.yml\n'
            '      - configtree:/run/secrets/\n',
      });
      expect(_problems(logs), isEmpty);
      expect(files.content, isNull);
    });
  });

  // The builder runs for every package that depends on the generator. It
  // loaded the config whenever a file imported another, and failed the
  // build on whatever the load did not like: a placeholder only the
  // running app resolves in spring.profiles.active (the sixth review's
  // srv_cur: `${APP_PROFILE}` and an optional file: import), an unknown
  // extension, a broken imported file... The third High of this kind: the
  // config of an app without a key the builder writes is not loaded at
  // all.
  group('an app without a spring.flutter.web.* key', () {
    const extra = 'optional:file:/etc/srv/extra.yaml';
    // A pure Dart server's config: every import kind, every position of a
    // placeholder only the running app resolves, broken imported files,
    // cycles. Each must build with no file, no warning and no error.
    final configs = <String, Map<String, String>>{
      'srv_cur: a runtime profile and an optional import': {
        'application.yaml':
            'server:\n  port: 8080\nspring:\n  profiles:\n'
            '    active: \${APP_PROFILE}\n  config:\n    import: $extra\n',
      },
      'spring.profiles.include': {
        'application.properties':
            'spring.profiles.include=base,\${EXTRA_PROFILES}\n'
            'spring.config.import=$extra\n',
      },
      'spring.profiles.default': {
        'application.properties':
            'spring.profiles.default=\${DEFAULT_PROFILE}\n'
            'spring.config.import=$extra\n',
      },
      'spring.profiles.group.*': {
        'application.yaml':
            'spring:\n  profiles:\n    active: prod\n'
            '    group:\n      prod: \${PROD_GROUP}\n'
            '  config:\n    import: $extra\n',
      },
      'spring.profiles.validate': {
        'application.properties':
            'spring.profiles.validate=\${VALIDATE}\n'
            'spring.config.import=$extra\n',
      },
      'spring.config.activate.on-profile': {
        'application.yaml':
            'spring.config.import: $extra\n---\n'
            'spring.config.activate.on-profile: \${PROFILE}\nx: 1\n',
      },
      'spring.config.activate.on-cloud-platform': {
        'application.properties':
            'spring.config.import=$extra\n#---\n'
            'spring.config.activate.on-cloud-platform=\${PLATFORM}\nx=1\n',
      },
      'spring.main.cloud-platform': {
        'application.properties':
            'spring.main.cloud-platform=\${PLATFORM}\n'
            'spring.config.import=$extra\n',
      },
      'a bare import': {
        'application.yaml': 'spring.config.import: \${CONFIG_FILE}\n',
      },
      'imports with placeholders': {
        'application.properties':
            r'spring.config.import=classpath:${ENV}.yaml,'
            'file:\${HOME}/app.yaml,optional:\${DIR}/\n',
      },
      'a runtime profile in a profile file': {
        'application.properties': 'spring.profiles.active=prod\n',
        'application-prod.properties':
            'spring.config.import=\${SECRETS},file:/etc/prod.yaml\n',
      },
      'every import kind, required': {
        'application.yaml':
            'spring:\n  config:\n    import:\n'
            '      - file:/etc/myapp/secrets.yaml\n'
            '      - configtree:/run/secrets/\n'
            '      - configtree:/run/*/\n'
            '      - package:other/x.yaml\n'
            '      - /abs/path/app.yaml\n'
            '      - file:./conf/*/app.yaml\n'
            '      - classpath:missing.yaml\n'
            '      - classpath:/nodir/\n'
            '      - asset:config/app.yaml\n'
            '      - https://config.example/app.yaml\n'
            '      - x[.yml]\n'
            '      - file:./local[.yml]\n'
            '      - "classpath:a.yaml;file:/etc/b.yaml"\n'
            '      - "optional:nodir/;file:/etc/c.yaml"\n',
        'a.yaml': 'a: 1\n',
      },
      'an extension no loader reads': {
        'application.properties': 'spring.config.import=file:./app.conf\n',
      },
      'a directory without a trailing slash': {
        'application.properties': 'spring.config.import=classpath:conf\n',
      },
      'an import cycle': {
        'application.yaml': 'spring.config.import: a.yaml\n',
        'a.yaml': 'spring.config.import: b.yaml\na: 1\n',
        'b.yaml': 'spring.config.import: classpath:a.yaml\nb: 1\n',
      },
      'a hinted import cycle': {
        'application.yaml': 'spring.config.import: a.conf[.yaml]\n',
        'a.conf': 'spring.config.import: application.yaml\n',
      },
      'the legacy spring.profiles': {
        'application.properties':
            'spring.profiles=dev\nspring.config.import=$extra\n',
      },
      'an invalid on-cloud-platform': {
        'application.properties':
            'spring.config.import=$extra\n#---\n'
            'spring.config.activate.on-cloud-platform=moon\n',
      },
      'an invalid profile name': {
        'application.properties':
            'spring.profiles.active=-bad\nspring.config.import=$extra\n',
      },
      'a profile key in a profile file': {
        'application.properties': 'spring.profiles.active=dev\n',
        'application-dev.properties':
            'spring.profiles.Include=x\nspring.config.import=$extra\n',
      },
      // Not the builder's business: the app fails to start with it.
      'a broken imported file': {
        'application.yaml': 'spring.config.import: broken.yaml\n',
        'broken.yaml': 'x: [\n',
      },
      'a broken hinted import': {
        'application.properties': 'spring.config.import=dev.conf[.yaml]\n',
        'dev.conf': 'spring:\n  flutter: [\n',
      },
      'a broken application.yaml': {
        'application.yaml': 'spring.config.import: a.yaml\nx: [\n',
      },
    };
    // The configs with a config file that does not parse.
    const broken = {
      'a broken imported file',
      'a broken hinted import',
      'a broken application.yaml',
    };

    test('builds with no file, no warning, no error', () async {
      for (final MapEntry(key: name, value: resources) in configs.entries) {
        final files = _Files();
        final logs = await _build(files, resources);
        expect(_problems(logs), isEmpty, reason: name);
        expect(files.content, isNull, reason: name);
        expect(files.writes, 0, reason: name);
      }
    });

    test('a file generated before is deleted', () async {
      for (final MapEntry(key: name, value: resources) in configs.entries) {
        if (broken.contains(name)) {
          continue;
        }
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, resources);
        expect(_problems(logs), isEmpty, reason: name);
        expect(files.content, isNull, reason: name);
      }
    });

    // The fourth review's fix: the broken file may be the one with the
    // keys, so the generated file is kept and the build says why.
    test('with a file generated before, a broken config file the app reads '
        'fails the build and keeps it; one it does not read does not '
        'count', () async {
      for (final name in broken) {
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, configs[name]!);
        expect(
          _severe(logs).single,
          allOf(contains('cannot be read'), contains('is left as it is')),
          reason: name,
        );
        expect(files.content, '${WebDevConfigBuilder.marker}\nold');
      }
      final files = _Files('${WebDevConfigBuilder.marker}\nold');
      final logs = await _build(files, {
        'application.yaml': 'spring.profiles.active: \${APP_PROFILE}\n',
        'application-ios.yaml': 'x: [\n',
      });
      expect(_problems(logs), isEmpty);
      expect(files.content, isNull);
    });

    test('a key in any config file counts, also one an import names with '
        'an extension hint', () async {
      for (final resources in [
        {
          'application.yaml': 'spring.profiles.active: \${APP_PROFILE}\n',
          'web/dev.properties': 'spring.flutter.web.port=5070\n',
        },
        {
          'application.yaml':
              'spring.profiles.active: \${APP_PROFILE}\n'
              'spring.config.import: optional:classpath:web/dev.conf[.yaml]\n',
          'web/dev.conf': 'spring.flutter.web.port: 5070\n',
        },
      ]) {
        final logs = await _build(_Files(), resources);
        expect(
          _warnings(logs).single,
          contains(
            'spring.profiles.active (in lib/resources/application.yaml): '
            r"'${APP_PROFILE}' cannot be resolved at build time",
          ),
          reason: '$resources',
        );
      }
    });
  });

  // An app that uses the dev server's file is told what the build cannot
  // know, and gets the file written with what it can.
  group('an app with a spring.flutter.web.* key', () {
    const port = 'spring.flutter.web.port: 5050\n';

    test('a placeholder only the running app resolves is warned about and '
        'read as unset, never a build error', () async {
      // Each config with the warnings (by property) and the file's port.
      for (final (resources, warned, expected) in [
        (
          {
            'application.yaml':
                '${port}spring:\n  profiles:\n    active: \${APP_PROFILE}\n'
                '  config:\n    import: optional:file:/etc/srv/extra.yaml\n',
          },
          ['spring.profiles.active'],
          5050,
        ),
        // What is known still counts: dev stays active.
        (
          {
            'application.properties': 'spring.profiles.active=dev,\${EXTRA}\n',
            'application-dev.properties': 'spring.flutter.web.port=5051\n',
          },
          ['spring.profiles.active'],
          5051,
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.active: ["\${EXTRA}", dev]\n',
            'application-dev.yaml': 'spring.flutter.web.port: 5051\n',
          },
          ['spring.profiles.active[0]'],
          5051,
        ),
        (
          {
            'application.properties':
                'spring.flutter.web.port=5050\n'
                'spring.profiles.include=\${A}\n'
                'spring.profiles.default=\${B}\n'
                'spring.profiles.validate=\${C}\n'
                'spring.main.cloud-platform=\${D}\n'
                'spring.profiles.active=dev\n'
                'spring.profiles.group.dev=\${E}\n',
          },
          [
            'spring.profiles.include',
            'spring.profiles.default',
            'spring.profiles.validate',
            'spring.main.cloud-platform',
            'spring.profiles.group.dev',
          ],
          5050,
        ),
        // A guard with one: the document is skipped.
        (
          {
            'application.yaml':
                '$port---\nspring.config.activate.on-profile: \${PROFILE}\n'
                'spring.flutter.web.port: 1\n'
                '---\nspring.config.activate.on-cloud-platform: \${CLOUD}\n'
                'spring.flutter.web.port: 2\n',
          },
          [
            'spring.config.activate.on-profile',
            'spring.config.activate.on-cloud-platform',
          ],
          5050,
        ),
        // An import with one is not read; the rest of its value is.
        (
          {
            'application.properties':
                r'spring.config.import=${CONFIG},'
                'classpath:\${ENV}.yaml;classpath:web.yaml\n',
            'web.yaml': port,
          },
          ['spring.config.import'],
          5050,
        ),
        // In application-web.*, in an imported file.
        (
          {
            'application-web.properties':
                'spring.config.import=classpath:web/dev.yaml\n',
            'web/dev.yaml':
                '${port}spring.config.import: file:\${HOME}/web.yaml\n',
          },
          ['spring.config.import'],
          5050,
        ),
        // Set in a file the app does not read (only on iOS): unknown too.
        (
          {
            'application.yaml': '${port}spring.profiles.active: \${p}\n',
            'application-ios.properties': 'p=dev\n',
            'application-dev.yaml': 'spring.flutter.web.port: 1\n',
          },
          ['spring.profiles.active'],
          5050,
        ),
        // Through another property.
        (
          {
            'application.yaml':
                '${port}profile: \${APP_PROFILE}\n'
                'spring.profiles.active: \${profile}\n',
          },
          ['spring.profiles.active'],
          5050,
        ),
      ]) {
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, resources);
        expect(_severe(logs), isEmpty, reason: '$resources');
        expect(
          [
            for (final warning in _warnings(logs))
              _message(warning).substring(0, _message(warning).indexOf(' ')),
          ],
          warned,
          reason: '$resources',
        );
        for (final warning in _warnings(logs)) {
          expect(
            warning,
            allOf(
              contains('cannot be resolved at build time'),
              contains('--dart-define'),
              contains('Give it a default'),
            ),
          );
        }
        expect(
          _body(files),
          'server:\n  port: $expected\n',
          reason: '$resources',
        );
      }
    });

    test('the warning names the placeholder and what is done', () async {
      final logs = await _build(_Files(), {
        'application.yaml':
            '${port}spring.profiles.active: \${profile}\n'
            'profile: \${APP_PROFILE}\n'
            'spring.config.import: \${CONFIG}\n'
            '---\nspring.config.activate.on-profile: \${PROFILE}\n',
      });
      expect(_warnings(logs).map(_message), [
        equals(
          'spring.profiles.active (in lib/resources/application.yaml): '
          r"'${profile}' cannot be resolved at build time: only the running "
          r'app knows ${APP_PROFILE} (an environment variable or a '
          '--dart-define, which web_dev_config.yaml cannot depend on), so the '
          r"profile '${profile}' is left out. Give it a default in the config "
          r"files ('${APP_PROFILE:...}') to have web_dev_config.yaml use "
          'that.',
        ),
        contains(
          'spring.config.import (in lib/resources/application.yaml): '
          r"'${CONFIG}' cannot be resolved at build time: only the running "
          r'app knows ${CONFIG} (',
        ),
        allOf(
          contains(
            'spring.config.activate.on-profile (in '
            r"lib/resources/application.yaml): '${PROFILE}'",
          ),
          contains('so the document is skipped'),
        ),
      ]);
    });

    test('a default is used, without a warning', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml':
            'spring.profiles.active: \${APP_PROFILE:dev}\n'
            'spring.config.import: classpath:\${ENV:web}.yaml\n',
        'application-dev.yaml': port,
        'web.yaml': 'spring.flutter.web.host: 0.0.0.0\n',
      });
      expect(_problems(logs), isEmpty);
      expect(_body(files), 'server:\n  host: "0.0.0.0"\n  port: 5050\n');
    });

    test('a config the app cannot start with fails the build, the file is '
        'left as it is', () async {
      for (final resources in [
        {'application.properties': '${port}spring.profiles.active=-bad\n'},
        {'application.yaml': '${port}spring.profiles: dev\n'},
        {'application.yaml': '${port}spring.config.import: app.conf\n'},
      ]) {
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, resources);
        expect(
          _severe(logs).single,
          allOf(contains('cannot be read'), contains('is left as it is')),
          reason: '$resources',
        );
        expect(files.content, '${WebDevConfigBuilder.marker}\nold');
      }
    });

    test('a broken config file the app reads fails the build, also without '
        'a generated file', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application.properties': 'spring.flutter.web.port=5050\n',
        'application-web.yml': 'spring:\n  flutter: [\n',
      });
      expect(
        _severe(logs).single,
        allOf(contains('application-web.yml'), contains('is left as it is')),
      );
      expect(files.content, isNull);
    });
  });

  // A required location that finds nothing in lib/resources/ was warned
  // about as one of the file system.
  test('a classpath: directory without config files is skipped silently, '
      'as a classpath: file missing from lib/resources/ is', () async {
    final files = _Files();
    final logs = await _build(files, {
      'application.yaml':
          'spring.config.import: classpath:/web/, classpath:missing.yaml\n'
          'spring.flutter.web.port: 5056\n',
    });
    expect(_problems(logs), isEmpty);
    expect(_body(files), 'server:\n  port: 5056\n');
  });

  test('an import the build cannot read (asset:, http:) is skipped, even a '
      'required one: it may exist at run time', () async {
    final files = _Files();
    final logs = await _build(files, {
      'application.yaml':
          'spring.config.import: asset:config/web.yaml, '
          'optional:https://config.example/web.yaml, '
          'http://127.0.0.1:9/web.yaml\n'
          'spring.flutter.web.port: 5056\n',
    });
    expect(_severe(logs), isEmpty);
    expect(_body(files), 'server:\n  port: 5056\n');
  });

  test('placeholders resolve from the config files, never from the '
      'environment', () async {
    final files = _Files();
    await _build(files, {
      'application.properties':
          'web.port=5052\n'
          'spring.flutter.web.port=\${web.port}\n'
          'spring.flutter.web.host=\${HOME:localhost}\n',
    });
    expect(
      _body(files),
      'server:\n  host: "localhost"\n  port: 5052\n',
    );
  });

  test('https, headers merged across files, proxy rules', () async {
    final files = _Files();
    await _build(files, {
      'application.properties':
          'spring.flutter.web.headers.X-Frame-Options=DENY\n'
          'spring.flutter.web.headers.Cross-Origin-Opener-Policy=unsafe-none\n'
          'spring.flutter.web.proxy[0].prefix=/ignored/\n'
          'spring.flutter.web.proxy[0].target=http://ignored\n',
      'application-web.yaml': r'''
spring:
  flutter:
    web:
      port: 5050
      https:
        cert-path: certs/localhost.pem
        cert-key-path: certs/localhost-key.pem
      headers:
        Cross-Origin-Opener-Policy: same-origin
      proxy:
        - prefix: /api/
          target: http://localhost:8080
        - regex: ^/auth/(.*)
          target: http://localhost:9000
          replace: /oauth2/$1
''',
    });
    final body = _body(files);
    expect(
      body,
      'server:\n'
      '  port: 5050\n'
      '  https:\n'
      '    cert-path: "certs/localhost.pem"\n'
      '    cert-key-path: "certs/localhost-key.pem"\n'
      '  headers:\n'
      '    - name: "Cross-Origin-Opener-Policy"\n'
      '      value: "same-origin"\n'
      '    - name: "X-Frame-Options"\n'
      '      value: "DENY"\n'
      '  proxy:\n'
      '    - prefix: "/api/"\n'
      '      target: "http://localhost:8080"\n'
      '    - regex: "^/auth/(.*)"\n'
      '      target: "http://localhost:9000"\n'
      '      replace: "/oauth2/\$1"\n',
    );
    // The shape the Flutter tool reads.
    final server = (loadYaml(files.content!) as YamlMap)['server'] as YamlMap;
    expect(server['port'], 5050);
    expect((server['proxy'] as YamlList).length, 2);
  });

  test('values are quoted for YAML', () async {
    final files = _Files();
    await _build(files, {
      'application.properties':
          'spring.flutter.web.headers.X-Note=a: "b" # c\n',
    });
    final server = (loadYaml(files.content!) as YamlMap)['server'] as YamlMap;
    expect((server['headers'] as YamlList).single, {
      'name': 'X-Note',
      'value': 'a: "b" # c',
    });
  });

  group('invalid values fail the build and name the property', () {
    final cases = {
      'port not a number': (
        'spring.flutter.web.port=abc\n',
        "spring.flutter.web.port: 'abc' is not a port",
      ),
      'port out of range': (
        'spring.flutter.web.port=70000\n',
        "spring.flutter.web.port: '70000' is not a port",
      ),
      'empty host': (
        'spring.flutter.web.host=\n',
        'spring.flutter.web.host is empty',
      ),
      'base-href without slashes': (
        'spring.flutter.web.base-href=app\n',
        "spring.flutter.web.base-href: 'app' must start and end with '/'",
      ),
      'https without the key': (
        'spring.flutter.web.https.cert-path=a.pem\n',
        'spring.flutter.web.https.cert-key-path is not set',
      ),
      'proxy without target': (
        'spring.flutter.web.proxy[0].prefix=/api/\n',
        'spring.flutter.web.proxy[0].target is not set '
            '(in lib/resources/application.properties)',
      ),
      'proxy target not a URL': (
        'spring.flutter.web.proxy[0].prefix=/api/\n'
            'spring.flutter.web.proxy[0].target=localhost\n',
        'spring.flutter.web.proxy[0].target '
            "(in lib/resources/application.properties): 'localhost' is not "
            'an absolute URL',
      ),
      'proxy with prefix and regex': (
        'spring.flutter.web.proxy[0].target=http://localhost:8080\n'
            'spring.flutter.web.proxy[0].prefix=/api/\n'
            'spring.flutter.web.proxy[0].regex=^/api/\n',
        'set exactly one of spring.flutter.web.proxy[0].prefix',
      ),
      'proxy with neither prefix nor regex': (
        'spring.flutter.web.proxy[0].target=http://localhost:8080\n',
        'set exactly one of spring.flutter.web.proxy[0].prefix',
      ),
      'proxy with a broken regex': (
        'spring.flutter.web.proxy[0].target=http://localhost:8080\n'
            'spring.flutter.web.proxy[0].regex=(\n',
        'spring.flutter.web.proxy[0].regex '
            "(in lib/resources/application.properties): '(' is not a valid "
            'regular expression',
      ),
      'unresolvable placeholder': (
        'spring.flutter.web.port=\${WEB_PORT}\n',
        'spring.flutter.web.port (in lib/resources/application.properties): '
            r"'${WEB_PORT}' cannot be resolved at build time",
      ),
    };
    for (final MapEntry(key: name, value: (properties, message))
        in cases.entries) {
      test(name, () async {
        // A generated file stays as it was.
        const previous = '${WebDevConfigBuilder.header}\nserver:\n  port: 1\n';
        final files = _Files(previous);
        final logs = await _build(files, {
          'application.properties': properties,
        });
        expect(_severe(logs).single, contains(message));
        expect(files.content, previous);
      });
    }
  });

  group('the Content Security Policy', () {
    // The header the generated file sends.
    Map<String, String> headers(_Files files) {
      final server = (loadYaml(files.content!) as YamlMap)['server'] as YamlMap;
      return {
        for (final header in (server['headers'] as YamlList? ?? YamlList()))
          (header as YamlMap)['name'] as String: header['value'] as String,
      };
    }

    test('the property becomes the header', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application-web.properties':
            "spring.flutter.web.content-security-policy=default-src 'self'\n",
      });
      expect(logs.where((log) => log.startsWith('WARNING: ')), isEmpty);
      expect(headers(files), {'Content-Security-Policy': "default-src 'self'"});
    });

    test('report-only sends the report-only header', () async {
      final files = _Files();
      await _build(files, {
        'application-web.properties':
            "spring.flutter.web.content-security-policy=default-src 'self'\n"
            'spring.flutter.web.content-security-policy-report-only=true\n',
      });
      expect(headers(files), {
        'Content-Security-Policy-Report-Only': "default-src 'self'",
      });
    });

    test('spa mode gets a ready policy with the providers', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application-web.properties':
            'spring.flutter.security.web.mode=spa\n'
            // A property line: kept whole for readability.
            // ignore: lines_longer_than_80_chars
            'spring.security.oauth2.client.registration.keycloak.client-id=neon-web\n'
            'spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon\n'
            'spring.security.oauth2.client.provider.partner.token-uri=https://id.partner.example/oauth2/token\n'
            'spring.security.oauth2.client.provider.partner.authorization-uri=https://login.partner.example/authorize\n',
      });
      expect(_severe(logs), isEmpty);
      final policy = headers(files)['Content-Security-Policy']!;
      expect(
        policy,
        WebDevServerSettings.spaContentSecurityPolicy([
          'http://localhost:8180',
          'https://id.partner.example',
        ]),
      );
      final directives = {
        for (final directive in policy.split('; '))
          directive.split(' ').first: directive.split(' ').skip(1).toList(),
      };
      expect(directives['script-src'], [
        "'self'",
        "'wasm-unsafe-eval'",
        'https://www.gstatic.com',
      ]);
      expect(directives['script-src'], isNot(contains("'unsafe-eval'")));
      expect(directives['connect-src'], contains('http://localhost:8180'));
      // The login page is navigated to, never fetched.
      expect(
        directives['connect-src'],
        isNot(contains('https://login.partner.example')),
      );
      expect(directives['frame-ancestors'], ["'none'"]);
      expect(directives['object-src'], ["'none'"]);
    });

    // The connect-src of the spa policy the files give, after Flutter's
    // own entries.
    Future<List<String>> connectSrc(Map<String, String> resources) async {
      final files = _Files();
      final logs = await _build(files, resources);
      expect(_severe(logs), isEmpty);
      final policy = headers(files)['Content-Security-Policy']!;
      return policy
          .split('; ')
          .singleWhere((directive) => directive.startsWith('connect-src '))
          .split(' ')
          .skip(4) // connect-src, 'self' and Flutter's two hosts
          .toList();
    }

    test('spa mode: a common provider without a provider section gets its '
        'built-in endpoints', () async {
      expect(
        await connectSrc({
          'application-web.yaml': '''
spring:
  flutter.security.web.mode: spa
  security.oauth2.client.registration:
    google:
      client-id: neon-web
    login-with-github:
      provider: GitHub
      client-id: neon-web
    apple:
      client-id: neon-web
''',
        }),
        [
          'https://api.github.com',
          'https://appleid.apple.com',
          'https://github.com',
          'https://www.googleapis.com',
        ],
      );
    });

    test('spa mode: a provider section replaces the built-in endpoints it '
        'sets', () async {
      expect(
        await connectSrc({
          'application-web.properties':
              'spring.flutter.security.web.mode=spa\n'
              'spring.security.oauth2.client.registration.github.client-id=x\n'
              'spring.security.oauth2.client.provider.github.token-uri='
              'https://token.example\n',
        }),
        // GitHub's user info stays; its token endpoint is replaced.
        ['https://api.github.com', 'https://token.example'],
      );
    });

    test('spa mode: a discovered issuer adds what its discovery document '
        'names on other origins, when well known', () async {
      expect(
        await connectSrc({
          'application-web.yaml': '''
spring:
  flutter.security.web.mode: spa
  security.oauth2.client:
    registration:
      google:
        client-id: neon-web
      microsoft:
        client-id: neon-web
      github:
        client-id: neon-web
    provider:
      google:
        issuer-uri: https://accounts.google.com
      microsoft:
        issuer-uri: https://login.microsoftonline.com/neon/v2.0
      github:
        issuer-uri: https://github.neon.example
''',
        }),
        // No built-in GitHub endpoints: its issuer is discovered.
        [
          'https://accounts.google.com',
          'https://github.neon.example',
          'https://graph.microsoft.com',
          'https://login.microsoftonline.com',
          'https://oauth2.googleapis.com',
          'https://openidconnect.googleapis.com',
          'https://www.googleapis.com',
        ],
      );
    });

    group('content-security-policy-connect-src', () {
      test('adds origins to the spa policy: a YAML list or comma-separated, '
          'the list of the most specific file', () async {
        expect(
          await connectSrc({
            'application.yaml': '''
spring.flutter.web.content-security-policy-connect-src:
  - https://ignored.example
''',
            'application-web.yaml': '''
spring:
  flutter:
    security.web.mode: spa
    web.content-security-policy-connect-src:
      - https://api.neon.books
      - wss://api.neon.books
''',
          }),
          ['https://api.neon.books', 'wss://api.neon.books'],
        );
        expect(
          await connectSrc({
            'application-web.properties':
                'spring.flutter.security.web.mode=spa\n'
                'spring.flutter.web.content-security-policy-connect-src='
                'https://a.example, https://*.b.example:8443/v1/\n',
          }),
          ['https://a.example', 'https://*.b.example:8443/v1/'],
        );
      });

      test('an entry that is no origin fails the build', () async {
        for (final entry in ["'unsafe-eval'", 'https://a.example;x', '*']) {
          final files = _Files();
          final logs = await _build(files, {
            'application-web.yaml':
                'spring.flutter.security.web.mode: spa\n'
                'spring.flutter.web.content-security-policy-connect-src:\n'
                '  - "$entry"\n',
          });
          expect(
            _severe(logs).single,
            contains('content-security-policy-connect-src'),
            reason: entry,
          );
          expect(files.content, isNull);
        }
      });

      test("with the app's own policy is an error", () async {
        final files = _Files();
        final logs = await _build(files, {
          'application-web.properties':
              'spring.flutter.security.web.mode=spa\n'
              "spring.flutter.web.content-security-policy=default-src 'self'\n"
              'spring.flutter.web.content-security-policy-connect-src='
              'https://api.neon.books\n',
        });
        expect(
          _severe(logs).single,
          contains("put the origins into that policy's connect-src"),
        );
        expect(files.content, isNull);
      });

      test('without spa mode is a warning', () async {
        final files = _Files();
        final logs = await _build(files, {
          'application-web.properties':
              'spring.flutter.web.port=5050\n'
              'spring.flutter.web.content-security-policy-connect-src='
              'https://api.neon.books\n',
        });
        expect(
          logs.where((log) => log.startsWith('WARNING: ')).single,
          contains('content-security-policy-connect-src is ignored'),
        );
        expect(_body(files), 'server:\n  port: 5050\n');
      });
    });

    test("an app's own policy wins over spa mode's", () async {
      final files = _Files();
      await _build(files, {
        'application-web.properties':
            'spring.flutter.security.web.mode=spa\n'
            'spring.flutter.web.port=5050\n'
            // A property line: kept whole for readability.
            // ignore: lines_longer_than_80_chars
            "spring.flutter.web.headers.Content-Security-Policy=default-src 'self'\n",
      });
      expect(headers(files), {'Content-Security-Policy': "default-src 'self'"});
    });

    test('server mode gets none by itself', () async {
      final files = _Files();
      await _build(files, {
        'application-web.properties':
            'spring.flutter.security.web.mode=server\n',
      });
      expect(files.content, isNull);
    });

    test('the property and the header both set is an error', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application-web.properties':
            "spring.flutter.web.content-security-policy=default-src 'self'\n"
            // A property line: kept whole for readability.
            // ignore: lines_longer_than_80_chars
            "spring.flutter.web.headers.Content-Security-Policy=default-src 'none'\n",
      });
      expect(_severe(logs).single, contains('keep one of them'));
      expect(files.content, isNull);
    });

    test('report-only must be a boolean', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application-web.properties':
            "spring.flutter.web.content-security-policy=default-src 'self'\n"
            'spring.flutter.web.content-security-policy-report-only=yes\n',
      });
      expect(_severe(logs).single, contains('is not true or false'));
    });
  });

  test('an unknown property is a warning', () async {
    final files = _Files();
    final logs = await _build(files, {
      'application.properties':
          'spring.flutter.web.port=5050\nspring.flutter.web.prot=5050\n',
    });
    expect(
      logs.where((log) => log.startsWith('WARNING: ')).single,
      contains('spring.flutter.web.prot (in lib/resources/'),
    );
    expect(_body(files), 'server:\n  port: 5050\n');
  });

  group('a hand-written web_dev_config.yaml', () {
    const handWritten = 'server:\n  port: 4040\n';

    test('is never changed: with the properties set it is an error', () async {
      final files = _Files(handWritten);
      final logs = await _build(files, {
        'application.properties': 'spring.flutter.web.port=5050\n',
      });
      expect(
        _severe(logs).single,
        contains('web_dev_config.yaml exists and was not generated'),
      );
      expect(files.content, handWritten);
      expect(files.writes, 0);
    });

    test('is left alone without the properties', () async {
      final files = _Files(handWritten);
      final logs = await _build(files, {
        'application.properties': 'spring.flutter.app.title=Shop\n',
      });
      expect(_severe(logs), isEmpty);
      expect(files.content, handWritten);
    });
  });

  group('a generated web_dev_config.yaml', () {
    test('is deleted when the properties are removed', () async {
      final files = _Files('${WebDevConfigBuilder.header}\nserver:\n');
      await _build(files, {'application.properties': 'a=1\n'});
      expect(files.content, isNull);
    });

    // The scan that skips loading the files when none mentions the
    // properties skipped a file that does not parse too: it saw no
    // property and deleted the file.
    test(
      'is kept, with a build error, when a config file does not parse',
      () async {
        for (final broken in {
          'application.yaml':
              'spring.flutter.web.port: 5061\n'
              'spring.flutter.web.headers: {X-A: [\n',
          'application-web.yml': 'spring:\n  flutter: [\n',
        }.entries) {
          const generated =
              '${WebDevConfigBuilder.header}\nserver:\n  port: 5061\n';
          final files = _Files(generated);
          final logs = await _build(files, {broken.key: broken.value});
          expect(
            _severe(logs).single,
            allOf(contains(broken.key), contains('is left as it is')),
            reason: broken.key,
          );
          expect(files.content, generated, reason: broken.key);
        }
      },
    );

    test('a YAML file that is no config file does not count', () async {
      final files = _Files('${WebDevConfigBuilder.header}\nserver:\n');
      final logs = await _build(files, {
        'application.properties': 'a=1\n',
        'data/broken.yaml': 'x: [\n',
      });
      expect(_severe(logs), isEmpty);
      expect(files.content, isNull);
    });

    test('is not rewritten when unchanged', () async {
      final files = _Files(
        '${WebDevConfigBuilder.header}\nserver:\n  port: 5050\n',
      );
      await _build(files, {
        'application.properties': 'spring.flutter.web.port=5050\n',
      });
      expect(files.writes, 0);
    });

    test('is updated when the properties change', () async {
      final files = _Files(
        '${WebDevConfigBuilder.header}\nserver:\n  port: 5050\n',
      );
      await _build(files, {
        'application.properties': 'spring.flutter.web.port=5060\n',
      });
      expect(_body(files), 'server:\n  port: 5060\n');
    });
  });

  // The seventh review.
  group('a placeholder only the running app resolves', () {
    const port = 'spring.flutter.web.port: 5050\n';

    // Only the placeholder was cut out, so `${ENV}-eu` was read as `-eu`,
    // an invalid profile name that failed the build ("never a build
    // error"), and `prod${X}` as `prod`.
    test('leaves out each profile name with one, whatever else it holds; a '
        'single value is read as unset', () async {
      for (final (resources, body, left) in [
        (
          {'application.yaml': '${port}spring.profiles.active: \${ENV}-eu\n'},
          'server:\n  port: 5050\n',
          r"the profile '${ENV}-eu' is left out",
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.active: dev,\${ENV}-eu\n',
            'application-dev.yaml': 'spring.flutter.web.host: devhost\n',
          },
          'server:\n  host: "devhost"\n  port: 5050\n',
          r"the profile '${ENV}-eu' is left out",
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.include: secrets-\${CLOUD}\n',
          },
          'server:\n  port: 5050\n',
          r"the profile 'secrets-${CLOUD}' is left out",
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.active: prod\n'
                'spring.profiles.group.prod: db,\${REGION}_cache\n',
            'application-db.yaml': 'spring.flutter.web.host: db\n',
          },
          'server:\n  host: "db"\n  port: 5050\n',
          r"the profile '${REGION}_cache' is left out",
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.default: \${USER}-local\n',
          },
          'server:\n  port: 5050\n',
          r"the profile '${USER}-local' is left out",
        ),
        (
          {'application.yaml': '${port}spring.profiles.validate: \${V}e\n'},
          'server:\n  port: 5050\n',
          'it is read as if it were not set',
        ),
        // At the end: prod is not read.
        (
          {
            'application.yaml': '${port}spring.profiles.active: prod\${X}\n',
            'application-prod.yaml': 'spring.flutter.web.port: 1\n',
          },
          'server:\n  port: 5050\n',
          r"the profile 'prod${X}' is left out",
        ),
        // A comma in a default stays in its placeholder.
        (
          {
            'application.yaml':
                '${port}spring.profiles.include: \${A:a,b},\${X}\n',
            'application-b.yaml': 'spring.flutter.web.host: b\n',
          },
          'server:\n  host: "b"\n  port: 5050\n',
          r"the profile '${X}' is left out",
        ),
      ]) {
        final files = _Files();
        final logs = await _build(files, resources);
        expect(_severe(logs), isEmpty, reason: '$resources');
        expect(_body(files), body, reason: '$resources');
        expect(
          _warnings(logs).single,
          allOf(contains('cannot be resolved at build time'), contains(left)),
          reason: '$resources',
        );
      }
    });

    // `\${X}` is the text `${X}`, which the app refuses as a profile name.
    test('an escaped one is no placeholder', () async {
      final logs = await _build(_Files(), {
        'application.yaml': '${port}spring.profiles.active: \\\${X}\n',
      });
      expect(_severe(logs).single, contains(r"Profile '${X}' must"));
    });

    // Any bracketed last element was taken for a list index, so a group
    // written `spring.profiles.group[prod]` (or a key such as
    // `spring.profiles[active]`, which the app reads as `active`) was not
    // seen as a profile key, and its placeholder failed the build with a
    // PlaceholderResolutionException.
    test('in the bracket form of a profile key or group name', () async {
      const dev = {'application-dev.yaml': 'spring.flutter.web.port: 5051\n'};
      for (final (resources, key) in [
        (
          {
            'application.properties':
                'spring.flutter.web.port=5050\n'
                'spring.profiles.active=prod\n'
                'spring.profiles.group[prod]=dev,\${X}\n',
          },
          'spring.profiles.group[prod]',
        ),
        (
          {
            'application.yaml':
                '${port}spring:\n  profiles:\n    active: prod\n'
                '    group:\n      "[prod]": "dev,\${X}"\n',
          },
          'spring.profiles.group[prod]',
        ),
        (
          {
            'application.yaml':
                '${port}spring.profiles.active: my.prod\n'
                'spring.profiles.group[my.prod]: "dev,\${X}"\n',
          },
          'spring.profiles.group[my.prod]',
        ),
        // The group of the web platform profile.
        (
          {
            'application.yaml':
                '${port}spring.profiles.group[web]: "dev,\${X}"\n',
          },
          'spring.profiles.group[web]',
        ),
        (
          {'application.yaml': '${port}spring.profiles[active]: "dev,\${X}"\n'},
          'spring.profiles[active]',
        ),
        (
          {
            'application.properties':
                'spring.flutter.web.port=5050\n'
                'spring[profiles].include=dev,\${X}\n',
          },
          'spring[profiles].include',
        ),
      ]) {
        final files = _Files();
        final logs = await _build(files, {...resources, ...dev});
        expect(_severe(logs), isEmpty, reason: '$resources');
        expect(_body(files), 'server:\n  port: 5051\n', reason: '$resources');
        expect(
          _message(_warnings(logs).single),
          allOf(startsWith(key), contains(r"the profile '${X}' is left out")),
          reason: '$resources',
        );
      }
      // A guard in the bracket form skips its document (`[onprofile]`:
      // a bracketed element is compared as written, `[on-profile]` is
      // another key, in Boot too).
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml':
            '$port---\nspring.config.activate[onprofile]: \${X}\n'
            'spring.flutter.web.port: 1\n',
      });
      expect(_severe(logs), isEmpty);
      expect(_body(files), 'server:\n  port: 5050\n');
      expect(_warnings(logs).single, contains('the document is skipped'));
    });

    // The key was removed with its placeholder, so a profile file setting
    // spring.profiles.active (which the app refuses) got a file written
    // with a "give it a default" warning, and following it failed.
    test('in a key not allowed where it is fails the build, as a literal '
        'value does', () async {
      for (final value in [r'${X}', r'${X:dev}', 'dev']) {
        for (final resources in [
          {
            'application.yaml': port,
            'application-web.yaml': 'spring.profiles.active: $value\n',
          },
          {
            'application.yaml':
                '$port---\nspring.config.activate.on-profile: web\n'
                'spring.profiles.include: $value\n',
          },
        ]) {
          final files = _Files('${WebDevConfigBuilder.marker}\nold');
          final logs = await _build(files, resources);
          expect(
            _severe(logs).single,
            allOf(
              contains('not allowed in a profile-specific document'),
              contains('is left as it is'),
            ),
            reason: '$resources',
          );
          expect(_warnings(logs), isEmpty, reason: '$resources');
          expect(files.content, '${WebDevConfigBuilder.marker}\nold');
        }
      }
    });

    // The document was dropped, so a key the app refuses in any document
    // escaped the checks.
    test('in a guard skips the document, which is still checked', () async {
      for (final (resources, error) in [
        (
          {
            'application.yaml': port,
            'application-web.yaml':
                'spring.flutter.web.host: w\n---\n'
                'spring.config.activate.on-profile: \${P}\n'
                'spring.profiles.active: dev\n',
          },
          'not allowed in a profile-specific document',
        ),
        (
          {
            'application.yaml':
                '$port---\n'
                'spring.config.activate.on-cloud-platform: \${CLOUD}\n'
                'spring.profiles: dev\n',
          },
          "should be replaced with 'spring.config.activate.on-profile'",
        ),
      ]) {
        final files = _Files();
        final logs = await _build(files, resources);
        expect(_severe(logs).single, contains(error), reason: '$resources');
        expect(files.content, isNull, reason: '$resources');
      }
      // Without such a key, the document is skipped with a warning.
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml': port,
        'application-web.yaml':
            'spring.flutter.web.host: w\n---\n'
            'spring.config.activate.on-profile: \${P}\n'
            'spring.flutter.web.host: p\n',
      });
      expect(_warnings(logs).single, contains('so the document is skipped'));
      expect(_body(files), 'server:\n  host: "w"\n  port: 5050\n');
    });

    // It was ignored without a word: no file, no warning.
    test('in spring.flutter.security.web.mode fails the build, as in a '
        'spring.flutter.web.* value', () async {
      for (final resources in [
        {'application.yaml': 'spring.flutter.security.web.mode: \${MODE}\n'},
        {
          'application.yaml':
              'spring.flutter.security.web.mode: \${MODE}\n$port',
        },
      ]) {
        final files = _Files();
        final logs = await _build(files, resources);
        expect(
          _severe(logs).single,
          allOf(
            contains(
              'spring.flutter.security.web.mode (in '
              r"lib/resources/application.yaml): '${MODE}' cannot be "
              'resolved at build time',
            ),
            contains('only config files count'),
          ),
          reason: '$resources',
        );
        expect(files.content, isNull);
      }
    });

    test('in a ; group of an import: the warning names the entry left '
        'out', () async {
      final files = _Files();
      final logs = await _build(files, {
        'application.yaml':
            '${port}spring.config.import: '
            r'optional:${DIR}/x.yaml;classpath:y.yaml'
            '\n',
        'y.yaml': 'spring.flutter.web.host: y\n',
      });
      expect(
        _warnings(logs).single,
        contains(
          r"so 'optional:${DIR}/x.yaml' is not read (the rest of the value "
          'is)',
        ),
      );
      expect(_body(files), 'server:\n  host: "y"\n  port: 5050\n');
    });
  });

  // A malformed on-profile expression escaped as a raw ArgumentError with
  // a stack trace, even in an app without a key (with a generated file and
  // a broken file the app does not read).
  group('a config the app cannot start with', () {
    test('fails the build cleanly when the app has a key', () async {
      for (final (resources, error) in [
        (
          {
            'application.yaml':
                'spring.flutter.web.port: 5050\n---\n'
                "spring.config.activate.on-profile: '(a'\ny: 1\n",
          },
          'Malformed profile expression',
        ),
        (
          {
            'application.yaml':
                'spring.flutter.web.port: 5050\n---\n'
                "spring.config.activate.on-profile: 'a & | b'\n",
          },
          'Malformed profile expression',
        ),
        (
          {
            'application.yaml':
                'spring.flutter.web.port: 5050\n'
                'spring.profiles.validate: false\n'
                "spring.profiles.active: '!x'\n",
          },
          'Invalid argument',
        ),
        (
          {
            'application.yaml':
                'spring.flutter.web.port: 5050\n'
                'a: ${'[' * 20000}${']' * 20000}\n',
          },
          'nested too deeply',
        ),
      ]) {
        final files = _Files('${WebDevConfigBuilder.marker}\nold');
        final logs = await _build(files, resources);
        expect(
          _severe(logs).single,
          allOf(
            contains('cannot be read'),
            contains(error),
            contains('is left as it is'),
            isNot(contains('#0 ')),
          ),
          reason: error,
        );
        expect(files.content, '${WebDevConfigBuilder.marker}\nold');
      }
    });

    test('is not the business of an app without one', () async {
      const generated = '${WebDevConfigBuilder.marker}\nold';
      final deep = {'application.yaml': 'a: ${'[' * 20000}${']' * 20000}\n'};
      for (final (resources, existing) in [
        // The broken file is one the app does not read: the generated file
        // is deleted.
        (
          {
            'application.yaml':
                "x: 1\n---\nspring.config.activate.on-profile: 'a & | b'\n",
            'application-ios.yaml': 'a: [\n',
          },
          generated,
        ),
        (deep, null),
      ]) {
        final files = _Files(existing);
        final logs = await _build(files, resources);
        expect(_problems(logs), isEmpty, reason: '$resources');
        expect(files.content, isNull, reason: '$resources');
      }
      // With a generated file, one the app reads that does not parse may
      // hold the keys: the build fails and keeps the file, naming it.
      final files = _Files(generated);
      final logs = await _build(files, deep);
      expect(
        _severe(logs).single,
        allOf(contains('application.yaml'), contains('nested too deeply')),
      );
      expect(files.content, generated);
    });
  });

  // The early check skipped a hinted import with a placeholder, and one
  // with an upper-case hint, so the keys of that file were not seen.
  test('an import with an extension hint is followed with its placeholders '
      'resolved and its hint in any case', () async {
    for (final resources in [
      {
        'application.yaml':
            r'spring.config.import: classpath:${X:web}.conf[.yaml]'
            '\n',
        'web.conf': 'spring.flutter.web.port: 5050\n',
      },
      {
        'application.yaml':
            'env: web\n'
            r'spring.config.import: classpath:${env}.conf[.yaml]'
            '\n',
        'web.conf': 'spring.flutter.web.port: 5050\n',
      },
      {
        'application.yaml':
            'spring.config.import: optional:classpath:web.conf[.YAML]\n',
        'web.conf': 'spring.flutter.web.port: 5050\n',
      },
    ]) {
      final files = _Files();
      final logs = await _build(files, resources);
      expect(_problems(logs), isEmpty, reason: '$resources');
      expect(_body(files), 'server:\n  port: 5050\n', reason: '$resources');
    }
    // Only the running app knows ENV: the file cannot be scanned.
    final files = _Files();
    final logs = await _build(files, {
      'application.yaml':
          r'spring.config.import: optional:classpath:${ENV}.conf[.yaml]'
          '\n',
      'web.conf': 'spring.flutter.web.port: 5050\n',
    });
    expect(_problems(logs), isEmpty);
    expect(files.content, isNull);
  });

  // A hinted import of a file in a bracketed directory (read through a
  // directory import, whose brackets belong to its path) was looked for
  // with the brackets kept; the app takes them out of the joined path, as
  // Spring Boot's FileHint does, and reads sub/y.conf.
  test('a hinted import is read where the app reads it: hints of the '
      'joined path', () async {
    final files = _Files();
    final logs = await _build(files, {
      'application.properties': 'spring.config.import=sub[x]/\n',
      'sub[x]/application.properties':
          'spring.config.import=y.conf[.properties]\n',
      'sub/y.conf': 'spring.flutter.web.port=7400\n',
    });
    expect(_problems(logs), isEmpty);
    expect(_body(files), 'server:\n  port: 7400\n');
  });

  // The main builder's "larger than 1048576 bytes" warning was repeated
  // by this builder, in every app.
  test('a resource too large to embed is not warned about again', () async {
    for (final application in [
      'a: 1\n',
      'spring.flutter.web.port: 5050\n',
    ]) {
      final logs = await _build(_Files(), {
        'application.yaml': application,
        'big.yaml': 'b: ${'x' * (1024 * 1024 + 1)}\n',
      });
      expect(_problems(logs), isEmpty, reason: application);
    }
  });
}
