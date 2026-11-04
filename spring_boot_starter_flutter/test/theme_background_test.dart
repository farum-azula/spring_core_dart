// The theme's background: parsing and its errors, the screens' overrides,
// and the ThemeBackground widget (transparent scaffold, .none, .screen,
// cross-fade, reduced motion).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

// A 1x1 PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

// A server that is never asked: the images are in the cache.
class _Silent implements HttpTransport {
  @override
  Future<HttpResponse> send(HttpRequest request) =>
      throw StateError('no network in this test');

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw StateError('no network in this test');

  @override
  void close() {}
}

ThemeBackgroundData? _parse(Map<String, String> props) =>
    SpringThemes(props).data('light').background;

Matcher _fails(Pattern text) => throwsA(
  isA<ThemePropertyException>().having(
    (e) => e.toString(),
    'message',
    contains(text),
  ),
);

void main() {
  group('parsing', () {
    test('no background key, no background', () {
      expect(_parse({'seed-color': 'red'}), isNull);
    });

    test('every key', () {
      final b = _parse({
        'animations.background-drift.duration': '20s',
        'animations.background-drift.repeat': 'reverse',
        'background.color': '#101010',
        'background.image.source': 'assets/bg.jpg',
        'background.image.fit': 'contain',
        'background.image.alignment': 'top-left',
        'background.image.opacity': '0.9',
        'background.image.blur': '4',
        'background.overlay.color': '#80000000',
        'background.overlay.gradient.type': 'radial',
        'background.overlay.gradient.begin': 'center',
        'background.overlay.gradient.colors': 'transparent, #CC0A0C12',
        'background.overlay.gradient.stops': '0, 1',
        'background.animation': 'background-drift',
        'background.transition': '400ms ease-out',
      })!;
      expect(b.color, const Color(0xFF101010));
      expect(b.image!.image!.source, 'assets/bg.jpg');
      expect(b.image!.fit, BoxFit.contain);
      expect(b.image!.alignment, Alignment.topLeft);
      expect(b.image!.opacity, 0.9);
      expect(b.image!.blur, 4);
      expect(b.overlay!.color, const Color(0x80000000));
      final gradient = b.overlay!.gradient!;
      expect(gradient.type, BackgroundGradientType.radial);
      expect(gradient.colors, [
        const Color(0x00000000),
        const Color(0xCC0A0C12),
      ]);
      expect(gradient.stops, [0, 1]);
      expect(gradient.toGradient(), isA<RadialGradient>());
      expect(b.animation, 'background-drift');
      expect(b.effect, isNull);
      expect(b.effectiveEffect, BackgroundEffect.drift);
      expect(b.transition!.duration, const Duration(milliseconds: 400));
      expect(b.transition!.curve, Curves.easeOut);
    });

    test('color objects: the color, the overlay and a gradient item', () {
      final b = _parse({
        'background.color.color': '#101010',
        'background.color.alpha': '50%',
        'background.overlay.gradient.colors.0.color': '#FF0000',
        'background.overlay.gradient.colors.0.alpha': '0%',
        'background.overlay.gradient.colors.1': '#0A0C12',
      })!;
      expect(b.color!.a, closeTo(0.5, 0.01));
      expect(b.overlay!.gradient!.colors, [
        const Color(0x00FF0000),
        const Color(0xFF0A0C12),
      ]);
    });

    test('an effect needs an animation', () {
      expect(
        () => _parse({'background.effect': 'zoom'}),
        _fails("effect needs 'animation'"),
      );
    });

    test('a radial gradient has no end', () {
      expect(
        () => _parse({
          'background.overlay.gradient.type': 'radial',
          'background.overlay.gradient.end': 'bottom',
          'background.overlay.gradient.colors': 'red, blue',
        }),
        _fails('radial uses begin as its center'),
      );
    });

    test('no animation, no effect; the transition has a default', () {
      final b = _parse({'background.color': 'black'})!;
      expect(b.effectiveEffect, isNull);
      expect(b.transitionOrDefault, ThemeBackgroundData.defaultTransition);
      expect(b.image, isNull);
    });

    test('a theme overrides the shared background key by key', () {
      final themes = SpringThemes({
        'background.color': '#111111',
        'themes.ocean.background.color': '#222222',
      });
      expect(themes.data('light').background!.color, const Color(0xFF111111));
      expect(themes.data('ocean').background!.color, const Color(0xFF222222));
    });

    test('errors name the property and what is valid', () {
      expect(
        () => _parse({'background.colour': 'red'}),
        _fails("did you mean 'color'"),
      );
      expect(
        () => _parse({'background.color': 'purpel'}),
        _fails('background.color'),
      );
      expect(
        () => _parse({'background.image.fit': 'stretchy'}),
        _fails('cover'),
      );
      expect(
        () => _parse({'background.image.opacity': '2'}),
        _fails('0 to 1'),
      );
      expect(
        () => _parse({'background.image.fit': 'cover'}),
        _fails('background.image.source'),
      );
      expect(
        () => _parse({
          'animations.drift.duration': '4s',
          'background.animation': 'drift',
          'background.effect': 'spin',
        }),
        _fails('drift, zoom or pulse'),
      );
      expect(
        () => _parse({'background.transition': 'soon'}),
        _fails('<duration> [<curve>]'),
      );
      expect(
        () => _parse({'background.transition': '1s wobble'}),
        _fails('ease-out'),
      );
      expect(
        () => _parse({'background.overlay.gradient.colors': 'red'}),
        _fails('at least two'),
      );
      expect(
        () => _parse({
          'background.overlay.gradient.colors': 'red, blue',
          'background.overlay.gradient.stops': '0.5',
        }),
        _fails('as many numbers'),
      );
      expect(
        () => _parse({
          'background.overlay.gradient.type': 'conic',
          'background.overlay.gradient.colors': 'red, blue',
        }),
        _fails('linear or radial'),
      );
      expect(
        () => _parse({'background.overlay.colour': 'red'}),
        _fails('an overlay'),
      );
      expect(
        () => _parse({'background.screens.login.screens.x.color': 'red'}),
        _fails('a screen of the background'),
      );
    });

    test('an animation must be one of animations.*', () {
      expect(
        () => _parse({'background.animation': 'nope'}),
        _fails('this theme has none'),
      );
      expect(
        () => _parse({
          'animations.background-drift.duration': '5s',
          'background.animation': 'background-drfit',
        }),
        _fails("did you mean 'backgrounddrift'"),
      );
    });
  });

  group('screens', () {
    final data = _parse({
      'background.color': '#111111',
      'background.image.source': 'assets/bg.jpg',
      'background.image.blur': '3',
      'background.overlay.color': '#80000000',
      'background.screens.login.image.source': 'assets/login.jpg',
      'background.screens.login.image.opacity': '0.5',
      'background.screens.login.color': '#333333',
      'background.screens.plain.overlay.color': '#00000000',
      'background.screens.fit-only.image.fit': 'fill',
    })!;

    test('a screen overrides key by key, the rest is the theme\'s', () {
      final login = data.screen('login');
      expect(login.color, const Color(0xFF333333));
      expect(login.image!.image!.source, 'assets/login.jpg');
      expect(login.image!.opacity, 0.5);
      expect(login.image!.blur, 3);
      expect(login.overlay!.color, const Color(0x80000000));
    });

    test('a screen may keep the image and change a setting of it', () {
      final screen = data.screen('Fit_Only');
      expect(screen.image!.image!.source, 'assets/bg.jpg');
      expect(screen.image!.fit, BoxFit.fill);
      expect(data.screen('plain').overlay!.color, const Color(0x00000000));
    });

    test('an unknown screen is the theme\'s background', () {
      expect(data.screen('settings'), same(data));
    });

    test('the images of all screens are known to the loader', () {
      expect(
        data.images.map((i) => i.source),
        ['assets/bg.jpg', 'assets/login.jpg'],
      );
    });

    test('a screen cannot start an image without a source', () {
      expect(
        () => _parse({
          'background.color': 'black',
          'background.screens.login.image.fit': 'cover',
        }),
        _fails('background.screens.login.image.source'),
      );
    });
  });

  group('ThemeKeyReader', () {
    test('background() and tokenImage()', () {
      final themes = SpringThemes({
        'background.color': '#111111',
        'themes.ocean.seed-color': 'teal',
      });
      expect(
        ThemeKeyReader(themes.data('light')).background().color,
        const Color(0xFF111111),
      );
      expect(
        () => ThemeKeyReader(themes.data('dark')).background(),
        returnsNormally,
      );
    });
  });

  group('the app themes', () {
    test('a background makes the scaffold transparent', () {
      final themes = SpringThemes({
        'background.color': '#111111',
        'themes.plain.background.color': '#222222',
        'themes.plain.cupertino.scaffold-background-color': '#FF0000',
      });
      expect(
        themes.material('light').scaffoldBackgroundColor,
        Colors.transparent,
      );
      expect(
        themes.cupertino('light').scaffoldBackgroundColor,
        Colors.transparent,
      );
      expect(
        themes.cupertino('plain').scaffoldBackgroundColor,
        const Color(0xFFFF0000),
      );
    });

    test('no background, the surface as before', () {
      final themes = SpringThemes({'seed-color': 'teal'});
      expect(
        themes.material('light').scaffoldBackgroundColor,
        themes.data('light').colorScheme.surface,
      );
    });
  });

  group('the widget', () {
    Widget app(
      SpringThemeData data,
      Widget child, {
      bool disableAnimations = false,
    }) => SpringTheme(
      data: data,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );

    // A theme whose image is a network one, already in the cache.
    Future<SpringThemeData> themed(
      Map<String, String> props, {
      String name = 'light',
    }) async {
      final themes = SpringThemes(props);
      final files = FileTemplate(InMemoryFileStore());
      for (final image in themes.data(name).images) {
        await files.write('${image.cacheFolder}/image', _png);
        await files.write(
          '${image.cacheFolder}/meta.json',
          jsonEncode({
            'source': image.source,
            'sha256': sha256Hex(_png),
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
      await ThemeImageLoader(
        themes: themes,
        files: files,
        transport: _Silent(),
      ).run(ApplicationArguments(const []));
      return themes.data(name);
    }

    testWidgets('the color, the image and the overlay are under the child', (
      tester,
    ) async {
      final data = (await tester.runAsync(
        () => themed({
          'background.color': '#101010',
          'background.image.source': 'https://x.test/bg.png',
          'background.overlay.color': '#80000000',
        }),
      ))!;
      await tester.pumpWidget(
        app(data, const ThemeBackground(child: Text('hello'))),
      );
      expect(find.text('hello'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF101010),
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0x80000000),
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a background it is just the child', (tester) async {
      final data = SpringThemes({}).data('light');
      await tester.pumpWidget(
        app(data, const ThemeBackground(child: Text('hello'))),
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('a theme switch keeps the state of the child', (tester) async {
      final plain = SpringThemes({}).data('light');
      final colored = SpringThemes({'background.color': '#101010'})
          .data('light');
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final field = Localizations(
        locale: const Locale('en'),
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Material(child: TextField(controller: controller)),
      );
      await tester.pumpWidget(app(plain, ThemeBackground(child: field)));
      controller.text = 'typed';
      await tester.pump();
      final state = tester.state(find.byType(EditableText));

      await tester.pumpWidget(app(colored, ThemeBackground(child: field)));
      expect(tester.state(find.byType(EditableText)), same(state));
      await tester.pumpWidget(app(plain, ThemeBackground(child: field)));
      expect(tester.state(find.byType(EditableText)), same(state));
      expect(find.text('typed'), findsOneWidget);
    });

    testWidgets('an unbounded parent does not break the layout', (
      tester,
    ) async {
      final data = SpringThemes({'background.color': '#101010'}).data('light');
      await tester.pumpWidget(
        app(
          data,
          const SingleChildScrollView(
            child: ThemeBackground(child: SizedBox(height: 40, width: 40)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ThemeBackground)).height, 40);
    });

    testWidgets('.none is an opaque surface, no image', (tester) async {
      final data = SpringThemes({
        'background.color': '#101010',
        'background.image.source': 'assets/bg.jpg',
      }).data('light');
      await tester.pumpWidget(
        app(data, const ThemeBackground.none(child: Text('plain'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == data.colorScheme.surface,
        ),
        findsOneWidget,
      );
      expect(find.text('plain'), findsOneWidget);
    });

    testWidgets('.screen takes the screen over the theme\'s', (tester) async {
      final data = SpringThemes({
        'background.color': '#101010',
        'background.screens.login.color': '#AA0000',
      }).data('light');
      await tester.pumpWidget(
        app(
          data,
          const Column(
            children: [
              Expanded(
                child: ThemeBackground.screen(
                  'login',
                  child: Text('login'),
                ),
              ),
            ],
          ),
        ),
      );
      Finder color(int argb) => find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Color(argb),
      );
      expect(color(0xFFAA0000), findsOneWidget);
      expect(color(0xFF101010), findsNothing);
      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('.screen with an unknown screen is an error in debug', (
      tester,
    ) async {
      final data = SpringThemes({
        'background.color': '#101010',
        'background.screens.login.color': '#AA0000',
      }).data('light');
      await tester.pumpWidget(
        app(data, const ThemeBackground.screen('logn', child: Text('x'))),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains("background.screens.logn"));
      expect(error.toString(), contains('its screens are login'));
      expect(error.toString(), contains("did you mean 'login'"));
    });

    testWidgets('a theme switch cross-fades over the transition', (
      tester,
    ) async {
      final themes = SpringThemes({
        'background.color': '#101010',
        'background.transition': '400ms',
        'themes.ocean.background.color': '#0000AA',
      });
      Widget build(String name) => app(
        themes.data(name),
        const ThemeBackground(child: Text('x')),
      );
      await tester.pumpWidget(build('light'));
      await tester.pumpWidget(build('ocean'));
      await tester.pump(const Duration(milliseconds: 100));
      Finder color(int argb) => find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Color(argb),
      );
      // Both are there while it fades.
      expect(color(0xFF101010), findsOneWidget);
      expect(color(0xFF0000AA), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(color(0xFF101010), findsNothing);
      expect(color(0xFF0000AA), findsOneWidget);
    });

    testWidgets('the animation moves the image, and stops with less motion', (
      tester,
    ) async {
      final data = (await tester.runAsync(
        () => themed({
          'animations.drift.duration': '2s',
          'animations.drift.repeat': 'loop',
          'background.image.source': 'https://x.test/bg.png',
          'background.animation': 'drift',
        }),
      ))!;
      await tester.pumpWidget(
        app(data, const ThemeBackground(child: Text('x'))),
      );
      expect(find.byType(ThemeAnimation), findsOneWidget);

      await tester.pumpWidget(
        app(
          data,
          const ThemeBackground(child: Text('x')),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.byType(ThemeAnimation), findsNothing);
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, Duration.zero);
    });

    testWidgets('a Cupertino app shows it through the transparent page', (
      tester,
    ) async {
      final themes = SpringThemes({'background.color': '#101010'});
      final data = themes.data('light');
      await tester.pumpWidget(
        SpringTheme(
          data: data,
          child: CupertinoApp(
            theme: themes.cupertino('light'),
            builder: (context, child) => ThemeBackground(child: child!),
            home: const CupertinoPageScaffold(child: Text('page')),
          ),
        ),
      );
      expect(find.text('page'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF101010),
        ),
        findsOneWidget,
      );
    });
  });
}
