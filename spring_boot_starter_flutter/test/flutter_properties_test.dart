// The properties classes: what they read, and that the editor metadata
// (lib/spring_gen/spring_metadata.json) names the same keys.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories.dart'
    show SqliteLocation;

Environment env(Map<String, String> properties) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', {...properties}));

T bind<T extends Object>(String name, Environment environment) =>
    boundProperties<T>(environment, name);

FlutterAppProperties app(Environment p) => bind('app', p);
FlutterLifecycleProperties lifecycle(Environment p) => bind('lifecycle', p);
FlutterRestartProperties restart(Environment p) => bind('restart', p);
FlutterFontsProperties fonts(Environment p) => bind('fonts', p);
DesktopWindowProperties window(Environment p) => bind('window', p);
FlutterDataSourceProperties dataSource(Environment p) => bind('dataSource', p);

void main() {
  test('app: defaults, then every key', () {
    final defaults = app(env({}));
    expect(defaults.type, AppType.widgets);
    expect(defaults.title, isNull);
    expect(defaults.debugBanner, isTrue);
    expect(defaults.locales, isNull);

    final set = app(
      env({
        'spring.flutter.app.type': ' Material ',
        'spring.flutter.app.title': 'Shop',
        'spring.flutter.app.debug-banner': 'FALSE',
        'spring.flutter.app.locales': 'en, ja,,pt_BR',
      }),
    );
    expect(set.type, AppType.material);
    expect(set.title, 'Shop');
    expect(set.debugBanner, isFalse);
    // The blank tag between the commas is dropped where the locales are
    // made (FlutterAppSettings).
    expect(set.locales, ['en', 'ja', '', 'pt_BR']);
  });

  test('app: a bad type or banner names the property', () {
    expect(
      () => app(env({'spring.flutter.app.type': 'x'})),
      throwsA(
        isA<ConfigurationPropertiesBindException>().having(
          (e) => '$e',
          'message',
          allOf(
            contains('spring.flutter.app.type'),
            contains('one of widgets, material, cupertino'),
          ),
        ),
      ),
    );
    expect(
      () => app(
        env({'spring.flutter.app.debug-banner': 'maybe'}),
      ),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
  });

  test('switches that only "false" turns off', () {
    expect(lifecycle(env({})).pauseInBackground, isTrue);
    expect(
      lifecycle(
        env({'spring.flutter.lifecycle.pause-in-background': 'False'}),
      ).pauseInBackground,
      isFalse,
    );
    expect(restart(env({})).enabled, isTrue);
    expect(
      restart(
        env({'spring.devtools.restart.enabled': 'false'}),
      ).enabled,
      isFalse,
    );
    final loaded = fonts(
      env({
        'spring.flutter.fonts.auto-load': 'false',
        'spring.flutter.fonts.exclude': 'a/*,b/*',
      }),
    );
    expect(loaded.autoLoad, isFalse);
    expect(loaded.exclude, ['a/*', 'b/*']);
  });

  test('scan-os-environment comes from the dart defines', () {
    expect(scanOsEnvironmentIn({}), isFalse);
    expect(
      scanOsEnvironmentIn({
        'spring.flutter.scan-os-environment': 'true',
      }),
      isTrue,
    );
    expect(
      scanOsEnvironmentIn({
        'SPRING_FLUTTER_SCANOSENVIRONMENT': ' TRUE ',
      }),
      isTrue,
    );
  });

  test('desktop window and sqlite location', () {
    final settings = window(
      env({
        'spring.flutter.desktop.window.title': ' Neon ',
        'spring.flutter.desktop.window.title-bar': 'hidden',
        'spring.flutter.desktop.window.initial-size': '1280x800',
        'spring.flutter.desktop.window.min-size': '640x480',
        'spring.flutter.desktop.window.max-size': '1920x1080',
      }),
    );
    // The settings trim the text and drop the blank.
    expect(
      DesktopWindowSettings.fromEnvironment(
        env({
          'spring.flutter.desktop.window.title': ' Neon ',
          'spring.flutter.desktop.window.min-size': ' ',
        }),
      ).title,
      'Neon',
    );
    expect(settings.title, ' Neon ');
    expect(settings.titleBar, 'hidden');
    expect(settings.initialSize, '1280x800');
    expect(settings.minSize, '640x480');
    expect(settings.maxSize, '1920x1080');
    expect(
      dataSource(env({'spring.datasource.sqlite.location': 'cache'}))
          .sqlite
          .location,
      SqliteLocation.cache,
    );
    expect(dataSource(env({})).sqlite.location, SqliteLocation.support);
    expect(dataSource(env({})).url, isNull);
  });

  test('the metadata names every key a class reads', () {
    final json = jsonDecode(
      File('lib/spring_gen/spring_metadata.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final names = {
      for (final p in json['properties']! as List)
        (p as Map<String, Object?>)['name']! as String,
    };
    expect(
      names,
      containsAll(const [
        'spring.flutter.app.type',
        'spring.flutter.app.title',
        'spring.flutter.app.debug-banner',
        'spring.flutter.app.locales',
        'spring.flutter.lifecycle.pause-in-background',
        'spring.flutter.scan-os-environment',
        'spring.flutter.fonts.auto-load',
        'spring.flutter.fonts.exclude',
        'spring.flutter.desktop.window.title',
        'spring.flutter.desktop.window.title-bar',
        'spring.flutter.desktop.window.initial-size',
        'spring.flutter.desktop.window.min-size',
        'spring.flutter.desktop.window.max-size',
        'spring.devtools.restart.enabled',
        'spring.datasource.url',
        'spring.datasource.sqlite.location',
        'spring.flutter.web.port',
        'spring.flutter.web.proxy[*].target',
      ]),
    );
    final hints = {
      for (final h in json['hints']! as List) (h as Map)['name']! as String: h,
    };
    final port = hints['spring.flutter.web.port']!;
    expect(port['range'], [0, 65535]);
    expect(
      ((port['warn']! as List).single as Map)['values'],
      containsAll([5060, 6667, 10080]),
    );
  });
}
