// Several in-memory builds per test; the machine may be busy with other
// test processes.
@Timeout(Duration(minutes: 2))
library;

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

/// Runs the builder over [resources] (paths below `lib/resources/`);
/// returns the log records as `LEVEL: message`.
Future<List<String>> _build(
  _Files files,
  Map<String, String> resources,
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
}
