// spring.flutter.desktop.window.*: reading and checking the properties.
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Environment env(Map<String, String> properties) {
  final environment = StandardEnvironment();
  environment.propertySources.addFirst(
    MapPropertySource('test', {...properties}),
  );
  return environment;
}

void main() {
  group('title bar', () {
    test('three styles, case does not matter', () {
      expect(TitleBarStyle.parse('default'), TitleBarStyle.defaultStyle);
      expect(TitleBarStyle.parse(' Transparent '), TitleBarStyle.transparent);
      expect(TitleBarStyle.parse('HIDDEN'), TitleBarStyle.hidden);
    });

    test('another value names the key and the allowed ones', () {
      expect(
        () => TitleBarStyle.parse('glass'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('spring.flutter.desktop.window.title-bar'),
              contains('default, transparent, hidden'),
            ),
          ),
        ),
      );
    });
  });

  group('sizes', () {
    WindowSize parse(String text) =>
        WindowSize.parse(text, property: 'spring.flutter.desktop.window.x');

    test('width x height in logical pixels', () {
      expect(parse('1280x800'), const WindowSize(1280, 800));
      expect(parse(' 800 X 600 '), const WindowSize(800, 600));
      expect(parse('1024.5x768'), const WindowSize(1024.5, 768));
      expect(parse('1280x800').toString(), '1280x800');
    });

    for (final bad in [
      '1280x',
      'x800',
      '1280',
      '-1x5',
      '5x-1',
      '0x600',
      'axb',
    ]) {
      test('"$bad" stops with the expected format', () {
        expect(
          () => parse(bad),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('spring.flutter.desktop.window.x'),
                contains('<width>x<height>'),
                contains('1280x800'),
              ),
            ),
          ),
        );
      });
    }
  });

  group('settings', () {
    test('nothing set: the defaults, nothing to apply', () {
      final settings = DesktopWindowSettings.fromEnvironment(env({}));
      expect(settings.titleBar, TitleBarStyle.defaultStyle);
      expect(settings.initialSize, isNull);
      expect(settings.minSize, isNull);
      expect(settings.isEmpty, isTrue);
    });

    test('empty values are not set', () {
      final settings = DesktopWindowSettings.fromEnvironment(
        env({
          'spring.flutter.desktop.window.title-bar': ' ',
          'spring.flutter.desktop.window.initial-size': '',
        }),
      );
      expect(settings.isEmpty, isTrue);
    });

    test('the three properties', () {
      final settings = DesktopWindowSettings.fromEnvironment(
        env({
          'spring.flutter.desktop.window.title-bar': 'transparent',
          'spring.flutter.desktop.window.initial-size': '1280x800',
          'spring.flutter.desktop.window.min-size': '800x600',
        }),
      );
      expect(settings.titleBar, TitleBarStyle.transparent);
      expect(settings.initialSize, const WindowSize(1280, 800));
      expect(settings.minSize, const WindowSize(800, 600));
      expect(settings.isEmpty, isFalse);
    });

    test('an initial size below the minimum names both values', () {
      expect(
        () => DesktopWindowSettings.fromEnvironment(
          env({
            'spring.flutter.desktop.window.initial-size': '700x900',
            'spring.flutter.desktop.window.min-size': '800x600',
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('initial-size=700x900'),
              contains('min-size=800x600'),
            ),
          ),
        ),
      );
    });

    test('equal sizes are fine', () {
      expect(
        DesktopWindowSettings.fromEnvironment(
          env({
            'spring.flutter.desktop.window.initial-size': '800x600',
            'spring.flutter.desktop.window.min-size': '800x600',
          }),
        ).isEmpty,
        isFalse,
      );
    });

    test('title and max size', () {
      final settings = DesktopWindowSettings.fromEnvironment(
        env({
          'spring.flutter.desktop.window.title': '  NEON Books  ',
          'spring.flutter.desktop.window.max-size': '1920x1080',
        }),
      );
      expect(settings.title, 'NEON Books');
      expect(settings.maxSize, const WindowSize(1920, 1080));
      expect(settings.isEmpty, isFalse);
    });

    test('a blank title is no title', () {
      final settings = DesktopWindowSettings.fromEnvironment(
        env({'spring.flutter.desktop.window.title': '   '}),
      );
      expect(settings.title, isNull);
      expect(settings.isEmpty, isTrue);
    });

    test('a maximum below the minimum names both values', () {
      expect(
        () => DesktopWindowSettings.fromEnvironment(
          env({
            'spring.flutter.desktop.window.min-size': '800x600',
            'spring.flutter.desktop.window.max-size': '700x900',
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('max-size=700x900'), contains('min-size=800x600')),
          ),
        ),
      );
    });

    test('an initial size above the maximum names both values', () {
      expect(
        () => DesktopWindowSettings.fromEnvironment(
          env({
            'spring.flutter.desktop.window.initial-size': '1280x800',
            'spring.flutter.desktop.window.max-size': '1000x900',
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('initial-size=1280x800'),
              contains('max-size=1000x900'),
            ),
          ),
        ),
      );
    });

    test('min <= initial <= max, equal allowed', () {
      expect(
        DesktopWindowSettings.fromEnvironment(
          env({
            'spring.flutter.desktop.window.initial-size': '800x600',
            'spring.flutter.desktop.window.min-size': '800x600',
            'spring.flutter.desktop.window.max-size': '800x600',
          }),
        ).maxSize,
        const WindowSize(800, 600),
      );
    });

    test('a malformed max size names its key', () {
      expect(
        () => DesktopWindowSettings.fromEnvironment(
          env({'spring.flutter.desktop.window.max-size': 'big'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            contains('spring.flutter.desktop.window.max-size'),
          ),
        ),
      );
    });

    test('a malformed value names its key', () {
      expect(
        () => DesktopWindowSettings.fromEnvironment(
          env({'spring.flutter.desktop.window.min-size': '800x'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            contains('spring.flutter.desktop.window.min-size'),
          ),
        ),
      );
    });
  });

  group('insets', () {
    test('from the native answer', () {
      final insets = DesktopWindowInsets.fromMap({
        'left': 70.0,
        'top': 28,
        'right': 0.0,
      });
      expect(insets.left, 70);
      expect(insets.top, 28);
      expect(insets.right, 0);
      expect(insets.bottom, 0);
      expect(insets.edgeInsets, const EdgeInsets.fromLTRB(70, 28, 0, 0));
    });

    test('no map: zero', () {
      expect(DesktopWindowInsets.fromMap(null), DesktopWindowInsets.zero);
    });
  });
}
