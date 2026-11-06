// The deep links (spring.flutter.navigation.deep-links.*) written into the
// app's platform files between markers: the scheme and the domains per
// platform (its profile files count), a block changed by hand or a key of
// the app's own fails, a block without properties goes; the files the
// domains serve.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/deep_links_builder.dart';
import 'package:test/test.dart';

const _plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>books</string>
</dict>
</plist>
''';

const _entitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
</dict>
</plist>
''';

const _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="books">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <activity android:name=".Other" android:exported="true">
        </activity>
    </application>
</manifest>
''';

const _pbxproj = '''
  DEVELOPMENT_TEAM = ABCDE12345;
  PRODUCT_BUNDLE_IDENTIFIER = com.example.books;
  PRODUCT_BUNDLE_IDENTIFIER = com.example.books.RunnerTests;
''';

final class _Memory implements NativeFiles {
  _Memory(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files[path];

  @override
  Future<bool> exists(BuildStep buildStep, String package, String path) async =>
      files.containsKey(path);

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async => files[path] = content;
}

Future<List<String>> _build(
  _Memory files,
  Map<String, String> resources,
) async {
  final logs = <String>[];
  await testBuilder(
    DeepLinksBuilder(files: files),
    {
      'app|pubspec.yaml': 'name: app\n',
      for (final MapEntry(:key, :value) in resources.entries)
        'app|lib/resources/$key': value,
    },
    rootPackage: 'app',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return logs;
}

_Memory _app() => _Memory({
  'ios/Runner/Info.plist': _plist,
  'ios/Runner/Runner.entitlements': _entitlements,
  'ios/Runner.xcodeproj/project.pbxproj': _pbxproj,
  'macos/Runner/Info.plist': _plist,
  'android/app/src/main/AndroidManifest.xml': _manifest,
  'android/app/build.gradle.kts':
      'android { defaultConfig { applicationId = "com.example.books" } }',
  'web/index.html': '<html></html>',
});

const _config = '''
spring:
  flutter:
    navigation:
      deep-links:
        scheme: neonbooks
        domains: [books.example.com]
        exclude: ['/checkout', '/admin/**']
''';

const _android = '''
spring.flutter.navigation.deep-links.sha256-cert-fingerprints=AB:CD:EF
''';

void main() {
  test('the scheme and the domains in every platform file', () async {
    final files = _app();
    final logs = await _build(files, {
      'application.yml': _config,
      'application-android.properties': _android,
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);

    final ios = files.files['ios/Runner/Info.plist']!;
    expect(ios, contains('<!-- spring:deep-links:start sha='));
    expect(ios, contains('\t<key>FlutterDeepLinkingEnabled</key>\n\t<true/>'));
    expect(ios, contains('\t\t\t\t<string>neonbooks</string>'));
    expect(
      ios,
      endsWith('<!-- spring:deep-links:end -->\n</dict>\n</plist>\n'),
    );

    expect(
      files.files['ios/Runner/Runner.entitlements'],
      contains('<string>applinks:books.example.com</string>'),
    );

    final macos = files.files['macos/Runner/Info.plist']!;
    expect(macos, contains('<string>neonbooks</string>'));
    expect(macos, isNot(contains('FlutterDeepLinkingEnabled')));

    final manifest = files.files['android/app/src/main/AndroidManifest.xml']!;
    // In the main activity, not in the other one.
    final main = manifest.substring(0, manifest.indexOf('.Other'));
    expect(main, contains('flutter_deeplinking_enabled'));
    expect(main, contains('<data android:scheme="neonbooks" />'));
    expect(main, contains('<intent-filter android:autoVerify="true">'));
    expect(main, contains('<data android:host="books.example.com" />'));

    final apple = jsonDecode(
      files.files['web/.well-known/apple-app-site-association']!,
    ) as Map<String, Object?>;
    expect(jsonEncode(apple), contains('"ABCDE12345.com.example.books"'));
    expect(
      jsonEncode(apple),
      contains(
        '{"/":"/checkout","exclude":true},{"/":"/admin/*","exclude":true},'
        '{"/":"*"}',
      ),
    );
    expect(
      files.files['web/.well-known/assetlinks.json'],
      allOf(contains('"com.example.books"'), contains('"AB:CD:EF"')),
    );
  });

  test('a second build changes nothing', () async {
    final files = _app();
    final resources = {
      'application.yml': _config,
      'application-android.properties': _android,
    };
    await _build(files, resources);
    final first = Map.of(files.files);
    await _build(files, resources);
    expect(files.files, first);
  });

  test('a block changed by hand fails the build and is kept', () async {
    final files = _app();
    await _build(files, {'application.yml': _config});
    final changed = files.files['ios/Runner/Info.plist']!.replaceFirst(
      '<string>neonbooks</string>',
      '<string>other</string>',
    );
    files.files['ios/Runner/Info.plist'] = changed;
    final logs = await _build(files, {'application.yml': _config});
    expect(
      logs,
      contains(allOf(startsWith('SEVERE'), contains('changed by hand'))),
    );
    expect(files.files['ios/Runner/Info.plist'], changed);
  });

  test('a scheme the app declares itself fails the build', () async {
    final files = _app();
    files.files['ios/Runner/Info.plist'] = _plist.replaceFirst(
      '</dict>\n</plist>',
      '\t<key>CFBundleURLTypes</key>\n\t<array/>\n</dict>\n</plist>',
    );
    final logs = await _build(files, {'application.yml': _config});
    expect(
      logs,
      contains(allOf(startsWith('SEVERE'), contains('CFBundleURLTypes'))),
    );
  });

  test('without the properties the blocks go', () async {
    final files = _app();
    await _build(files, {'application.yml': _config});
    await _build(files, {'application.yml': 'spring.application.name: books'});
    expect(files.files['ios/Runner/Info.plist'], _plist);
    expect(files.files['android/app/src/main/AndroidManifest.xml'], _manifest);
  });

  test('a platform profile turns them off for that platform', () async {
    final files = _app();
    await _build(files, {
      'application.yml': _config,
      'application-macos.yml':
          'spring.flutter.navigation.deep-links.enabled: false',
    });
    expect(files.files['macos/Runner/Info.plist'], _plist);
    expect(files.files['ios/Runner/Info.plist'], contains('neonbooks'));
  });

  test(
    'without the Android fingerprints: a warning, no assetlinks.json',
    () async {
      final files = _app();
      final logs = await _build(files, {'application.yml': _config});
      expect(logs, contains(contains('sha256-cert-fingerprints')));
      expect(files.files, isNot(contains('web/.well-known/assetlinks.json')));
    },
  );

  test('the scheme of a login redirect is named', () async {
    final logs = await _build(_app(), {
      'application.yml': _config,
      'application-sso.properties':
          'spring.security.oauth2.client.registration.kc.redirect-uri='
          'neonbooks:/oauth2/callback',
    });
    expect(logs, contains(contains('scheme of a login redirect')));
  });

  group('DeepLinkSettings', () {
    DeepLinkSettings? read(Map<String, Object> values) {
      final environment = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(MapPropertySource('test', values));
      ConfigurationPropertySources.attach(environment);
      return DeepLinkSettings.of(environment);
    }

    test('lists written either way', () {
      final settings = read({
        'spring.flutter.navigation.deep-links.domains':
            'a.example.com, b.example.com',
        'spring.flutter.navigation.deep-links.exclude[0]': '/x',
      })!;
      expect(settings.domains, ['a.example.com', 'b.example.com']);
      expect(settings.exclude, ['/x']);
    });

    test('a domain with a scheme or a path is refused', () {
      expect(
        () => read({
          'spring.flutter.navigation.deep-links.domains':
              'https://a.example.com',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('http is no scheme of the app', () {
      expect(
        () => read({'spring.flutter.navigation.deep-links.scheme': 'https'}),
        throwsA(isA<Exception>()),
      );
    });
  });

  test("Apple's components of Spring patterns", () {
    expect(DomainFiles.appleComponent('/admin/**'), '/admin/*');
    expect(DomainFiles.appleComponent('/books/{isbn}/notes'), '/books/*/notes');
    expect(DomainFiles.appleComponent('/docs/{*path}'), '/docs/*');
  });
}
