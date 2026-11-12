// The splash of the theme: parsing and its errors, and the flow in
// SpringApplicationWidget (progress, min-duration, exit, the builder that
// wins, the hand-off to the web page loader).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/loader_hand_off.dart';

import 'support/designs.dart' show MaterialSpringThemeData, testDesigns;

ThemeSplashData? _parse(Map<String, String> props) =>
    SpringThemes(props).data('light').splash;

Matcher _fails(Pattern text) => throwsA(
  isA<ThemePropertyException>().having(
    (e) => e.toString(),
    'message',
    contains(text),
  ),
);

class _Gate implements ApplicationRunner {
  _Gate(this.release);
  final Completer<void> release;

  @override
  Future<void> run(ApplicationArguments args) => release.future;
}

SpringApplication _app(Completer<void> release, Map<String, String> theme) =>
    SpringApplication(
      [
        BeanModule(
          'test',
          [
            BeanDefinition<_Gate>(
              name: 'gate',
              types: const [_Gate, ApplicationRunner],
              create: (_) => _Gate(release),
            ),
          ],
          resources: {
            'application.properties': [
              for (final MapEntry(:key, :value) in theme.entries)
                'spring.flutter.theme.$key=$value',
            ].join('\n'),
          }.map((k, v) => MapEntry(k, EmbeddedResource.text(v))),
        ),
      ],
      bannerMode: BannerMode.off,
    );

const _splash = {
  'splash.title': 'NEON',
  'splash.loader': 'dots',
  'splash.min-duration': '2s',
  'splash.exit.transition': '400ms linear',
  'loaders.dots.kind': 'dots',
};

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  for (var left = total; left > Duration.zero;) {
    const step = Duration(milliseconds: 50);
    await tester.pump(step);
    left -= step;
  }
}

void main() {
  tearDown(() => LoaderHandOff.override = null);

  group('parsing', () {
    test('reads every key', () {
      final splash = _parse({
        'splash.background.color': '#101010',
        'splash.logo.source': 'assets/logo.png',
        'splash.logo.size': '96',
        'splash.title': 'NEON',
        'splash.loader': 'dots',
        'splash.animation': 'in',
        'splash.min-duration': '1.2s',
        'splash.exit.transition': '400ms ease-out',
        'loaders.dots.kind': 'dots',
        'animations.in.duration': '300ms',
      })!;
      expect(splash.background!.color, const Color(0xFF101010));
      expect(splash.logo!.source, 'assets/logo.png');
      expect(splash.logoSize, 96);
      expect(splash.title, 'NEON');
      expect(splash.loader, 'dots');
      expect(splash.animation, 'in');
      expect(splash.minDuration, const Duration(milliseconds: 1200));
      expect(splash.exit.duration, const Duration(milliseconds: 400));
      expect(splash.exit.curve, Curves.easeOut);
    });

    test('none without a map; a single value is the ink splash of the '
        'Material starter', () {
      expect(_parse({}), isNull);
      // Without the starter the value is accepted, and no splash of it.
      expect(_parse({'splash': 'none'}), isNull);
      expect(_parse({'splash': 'ripple'}), isNull);
      final data = SpringThemes({
        'splash': 'none',
      }, designs: testDesigns).data('light');
      expect(data.splash, isNull);
      expect(data.splashFactory, isNotNull);
    });

    test('defaults', () {
      final splash = _parse({'splash.title': 'x'})!;
      expect(splash.minDuration, Duration.zero);
      expect(splash.exit, ThemeSplashData.defaultExit);
    });

    test('errors name the property', () {
      expect(() => _parse({'splash.titel': 'x'}), _fails('title'));
      expect(
        () => _parse({'splash.loader': 'nope', 'loaders.a.kind': 'dots'}),
        _fails('loaders'),
      );
      expect(() => _parse({'splash.animation': 'nope'}), _fails('animations'));
      expect(
        () => _parse({'splash.min-duration': 'soon'}),
        _fails('splash.minduration'),
      );
      expect(
        () => _parse({'splash.exit.transition': 'x'}),
        _fails('400ms ease-out'),
      );
      expect(() => _parse({'splash.exit.fade': '1s'}), _fails('transition'));
    });

    test('ThemeKeyReader.splash', () {
      final reader = ThemeKeyReader(
        SpringThemes({'splash.title': 'x'}).data('light'),
      );
      expect(reader.splash().title, 'x');
      expect(
        () => ThemeKeyReader(SpringThemes({}).data('light')).splash(),
        throwsStateError,
      );
    });
  });

  group('flow', () {
    testWidgets('shows while starting, waits min-duration, then fades', (
      tester,
    ) async {
      final release = Completer<void>();
      final handOffs = <double>[];
      LoaderHandOff.override = handOffs.add;
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, _splash),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('NEON'), findsOneWidget);
      expect(find.byType(ThemeLoader), findsOneWidget);
      expect(find.text('home'), findsNothing);
      // The start's progress reaches the splash (beans are created).
      final splash = tester.widget<ThemeSplash>(find.byType(ThemeSplash));
      expect(splash.progress.value, greaterThan(0));
      expect(splash.progress.value, lessThan(1));
      expect(splash.ready, isFalse);
      // The web page loader stays over the splash until the app is built.
      expect(handOffs, isEmpty);

      release.complete();
      await _pumpFor(tester, const Duration(milliseconds: 300));
      // Ready, but 2 s have not passed.
      expect(find.text('home'), findsOneWidget);
      expect(handOffs, hasLength(1));
      expect(
        tester.widget<ThemeSplash>(find.byType(ThemeSplash)).ready,
        isTrue,
      );
      expect(
        tester.widget<ThemeSplash>(find.byType(ThemeSplash)).progress.value,
        1,
      );
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(find.byType(ThemeSplash), findsOneWidget);
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(ThemeSplash),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        1,
      );
      // After min-duration the fade runs for 400 ms.
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byType(ThemeSplash), findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.byType(ThemeSplash), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(handOffs, hasLength(1));
    });

    testWidgets('reduced motion: no fade once min-duration is over', (
      tester,
    ) async {
      final release = Completer<void>()..complete();
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, {
            ..._splash,
            'splash.min-duration': '300ms',
          }),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _pumpFor(tester, const Duration(milliseconds: 700));
      expect(find.byType(ThemeSplash), findsNothing);
    });

    testWidgets('the splash: builder wins over the theme splash', (
      tester,
    ) async {
      final release = Completer<void>();
      final handOffs = <double>[];
      LoaderHandOff.override = handOffs.add;
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, _splash),
          splash: (_) => const Text('mine', textDirection: TextDirection.ltr),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('mine'), findsOneWidget);
      expect(find.byType(ThemeSplash), findsNothing);
      expect(find.text('NEON'), findsNothing);
      expect(handOffs, hasLength(1));
      release.complete();
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('mine'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(find.byType(ThemeSplash), findsNothing);
    });

    testWidgets('a theme without a splash: nothing shown, still handed off', (
      tester,
    ) async {
      final release = Completer<void>();
      final handOffs = <double>[];
      LoaderHandOff.override = handOffs.add;
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, {}),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(ThemeSplash), findsNothing);
      expect(handOffs, hasLength(1));
      release.complete();
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('home'), findsOneWidget);
      expect(handOffs, hasLength(1));
    });

    testWidgets('a loader kind with phases: the splash waits for its end', (
      tester,
    ) async {
      ThemeLoaderKinds.register<LoaderValues>('shutters', painter: _Paint());
      addTearDown(ThemeLoaderKinds.clear);
      final release = Completer<void>()..complete();
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, {
            'splash.loader': 'sh',
            'loaders.sh.kind': 'shutters',
            'loaders.sh.phases.close.duration': '200ms',
            'loaders.sh.phases.open.duration': '1s',
          }),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 500));
      // `open` takes 1 s: the splash is still there, not yet fading.
      expect(find.byType(ThemeSplash), findsOneWidget);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      expect(find.byType(ThemeSplash), findsNothing);
    });

    testWidgets('exit.reveal: the last phase plays over the app', (
      tester,
    ) async {
      ThemeLoaderKinds.register<LoaderValues>('shutters', painter: _Paint());
      addTearDown(ThemeLoaderKinds.clear);
      final release = Completer<void>()..complete();
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(release, {
            'splash.loader': 'sh',
            'splash.title': 'NEON',
            'splash.exit.reveal': 'true',
            'loaders.sh.kind': 'shutters',
            'loaders.sh.phases.close.duration': '200ms',
            'loaders.sh.phases.open.duration': '1s',
          }),
          home: const Text('home', textDirection: TextDirection.ltr),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 500));
      // `open` plays: the splash is there, but its background and title are
      // gone, so the app shows wherever the loader does not paint.
      expect(find.byType(ThemeSplash), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('NEON'), findsNothing);
      final shown = tester.widgetList<Visibility>(
        find.descendant(
          of: find.byType(ThemeSplash),
          matching: find.byType(Visibility),
        ),
      );
      expect(shown.every((v) => !v.visible), isTrue);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      expect(find.byType(ThemeSplash), findsNothing);
    });

    test('exit.reveal is read, and false by default', () {
      expect(_parse({'splash.exit.reveal': 'true'})!.reveal, isTrue);
      expect(_parse({'splash.title': 'x'})!.reveal, isFalse);
      expect(
        () => _parse({'splash.exit.reveal': 'maybe'}),
        _fails('true or false'),
      );
    });

    test('the web hook is a no-op off the web', () {
      expect(() => LoaderHandOff.call(0.5), returnsNormally);
      expect(LoaderHandOff.pageProgress(), isNull);
      expect(LoaderHandOff.pageElapsed(), isNull);
    });

    test('the page loader\'s time can be replaced for tests', () {
      LoaderHandOff.pageElapsedOverride = () => const Duration(seconds: 2);
      addTearDown(() => LoaderHandOff.pageElapsedOverride = null);
      expect(LoaderHandOff.pageElapsed(), const Duration(seconds: 2));
    });
  });

  group('the hand-over to the web page loader', () {
    // The splash with a logo whose asset is not in the test bundle: its
    // image never paints, as a logo still on its way.
    SpringThemeData theme() => SpringThemes({
      'splash.logo.source': 'assets/missing_logo.png',
      'splash.logo.size': '96',
      'splash.title': 'NEON',
      'splash.loader': 'bar',
      'loaders.bar.kind': 'bar',
    }).data('light');

    Widget splash(SpringThemeData theme, {VoidCallback? onShown}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeSplash(
            theme: theme,
            progress: ValueNotifier(0.5),
            ready: false,
            onShown: onShown,
          ),
        );

    testWidgets('the logo has its box from the first frame: nothing moves', (
      tester,
    ) async {
      await tester.pumpWidget(splash(theme()));
      final box = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 96 && w.height == 96,
      );
      expect(box, findsOneWidget);
      final title = tester.getTopLeft(find.text('NEON'));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getTopLeft(find.text('NEON')), title);
      // The page loader's gap: 20 between the logo, the title and the
      // loader.
      expect(
        tester.getTopLeft(find.text('NEON')).dy - tester.getBottomLeft(box).dy,
        20,
      );
    });

    testWidgets('onShown waits for the logo, never past logoWait', (
      tester,
    ) async {
      var shown = 0;
      await tester.pumpWidget(splash(theme(), onShown: () => shown++));
      await tester.pump();
      // The asset's load fails or times out: the hand-over still comes,
      // once, after a frame and within logoWait.
      await tester.pump(ThemeSplash.logoWait);
      await tester.pump();
      expect(shown, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(shown, 1);
    });

    testWidgets('without a logo: onShown after the first frame', (
      tester,
    ) async {
      var shown = 0;
      await tester.pumpWidget(
        splash(
          SpringThemes({'splash.title': 'NEON'}).data('light'),
          onShown: () => shown++,
        ),
      );
      await tester.pump();
      expect(shown, 1);
    });
  });
}

class _Paint extends ThemeLoaderPainter<LoaderValues> {
  @override
  void paint(Canvas canvas, Size size, LoaderFrame<LoaderValues> frame) {}
}
