import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class Greeter {
  Greeter(this.greeting);
  final String greeting;
}

class Clock {
  final DateTime now = DateTime(2026);
}

class Events {
  final List<Object> received = [];
}

/// An application of [definitions] with embedded `lib/resources/` files,
/// built by hand like the generator would.
SpringApplication app({
  List<BeanDefinition<Object>> definitions = const [],
  Map<String, String> resources = const {},
  Map<String, String> dartDefines = const {},
  String? fingerprint,
}) => SpringApplication(
  [
    BeanModule(
      'test',
      [
        BeanDefinition<Greeter>(
          name: 'greeter',
          types: const [Greeter],
          create: (r) => Greeter(r.value<String>(r'${greeting:Hello}')),
        ),
        BeanDefinition<Events>(
          name: 'events',
          types: const [Events],
          create: (_) => Events(),
        ),
        ...definitions,
      ],
      resources: {
        for (final MapEntry(:key, :value) in resources.entries)
          key: EmbeddedResource.text(value),
      },
    ),
  ],
  dartDefines: dartDefines,
  fingerprint: fingerprint,
  bannerMode: BannerMode.off,
);

/// Shows the greeting of the Greeter bean.
class Greeting extends StatelessWidget {
  const Greeting({super.key});

  @override
  Widget build(BuildContext context) =>
      Text(context.bean<Greeter>().greeting, textDirection: TextDirection.ltr);
}

Future<ApplicationContext> pumpApp(
  WidgetTester tester,
  SpringApplication Function() application, {
  Widget child = const Greeting(),
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(application: application, child: child),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byWidget(child)));
}

void main() {
  testWidgets('shows the splash, then the child with the beans', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: app,
        splash: (_) => const Text('starting', textDirection: TextDirection.ltr),
        child: const Greeting(),
      ),
    );
    expect(find.text('starting'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('a failed start shows the failure screen', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => app(
          definitions: [
            BeanDefinition<Clock>(
              name: 'clock',
              types: const [Clock],
              create: (_) => throw StateError('no clock'),
            ),
          ],
        ),
        failure: (_, error) =>
            Text('failed: $error', textDirection: TextDirection.ltr),
        child: const Greeting(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('failed:'), findsOneWidget);
    expect(find.textContaining('no clock'), findsOneWidget);
  });

  testWidgets('a check failing after the start closes the context', (
    tester,
  ) async {
    final contexts = <ApplicationContext>[];
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => app(
          definitions: [_tracker(contexts)],
          resources: {'application.properties': 'spring.flutter.app.type=nope'},
        ),
        failure: (_, error) =>
            Text('failed: $error', textDirection: TextDirection.ltr),
        home: const Greeting(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('spring.flutter.app.type'), findsOneWidget);
    expect(contexts, hasLength(1));
    // Its runners and scheduled tasks do not go on behind the screen.
    expect(
      (contexts.single as ConfigurableApplicationContext).isActive,
      isFalse,
    );

    // Each hot reload's retry fails the same way: none is left running.
    for (var i = 0; i < 2; i++) {
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
    }
    expect(contexts, hasLength(3));
    expect(
      contexts.whereType<ConfigurableApplicationContext>().where(
        (c) => c.isActive,
      ),
      isEmpty,
    );
  });

  testWidgets('the default failure screen shows the error', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => app(
          definitions: [
            BeanDefinition<Clock>(
              name: 'clock',
              types: const [Clock],
              create: (_) => throw StateError('no clock'),
            ),
          ],
        ),
        child: const Greeting(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The application failed to start'),
      findsOneWidget,
    );
  });

  group('platform profiles', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('are active, the specific one last', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final context = await pumpApp(
        tester,
        () => app(
          resources: {
            'application.properties': 'greeting=Hello',
            'application-mobile.properties': 'greeting=Hello mobile',
            'application-ios.properties': 'greeting=Hello iOS',
          },
        ),
      );
      expect(
        context.environment.activeProfiles,
        containsAll(['mobile', 'ios']),
      );
      expect(find.text('Hello iOS'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    test('per platform', () {
      final expected = {
        TargetPlatform.android: ['mobile', 'android'],
        TargetPlatform.iOS: ['mobile', 'ios'],
        TargetPlatform.macOS: ['desktop', 'macos'],
        TargetPlatform.windows: ['desktop', 'windows'],
        TargetPlatform.linux: ['desktop', 'linux'],
        TargetPlatform.fuchsia: ['fuchsia'],
      };
      for (final MapEntry(key: platform, value: profiles) in expected.entries) {
        debugDefaultTargetPlatformOverride = platform;
        expect(platformProfiles(), profiles, reason: '$platform');
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('OS environment', () {
    testWidgets('is not read by default', (tester) async {
      final context = await pumpApp(tester, app);
      expect(context.environment.getProperty('PATH'), isNull);
    });

    testWidgets('is read with spring.flutter.scan-os-environment', (
      tester,
    ) async {
      final context = await pumpApp(
        tester,
        () => app(dartDefines: {'SPRING_FLUTTER_SCANOSENVIRONMENT': 'true'}),
      );
      expect(context.environment.getProperty('PATH'), isNotNull);
    });
  });

  group('app lifecycle', () {
    late List<Object> events;

    SpringApplication listening({Map<String, String> resources = const {}}) =>
        app(resources: resources)..addListeners([
          ApplicationListenerAdapter.of<ApplicationEvent>((event) {
            if (event is AppLifecycleStateEvent ||
                event is ContextPausedEvent ||
                event is ContextRestartedEvent) {
              events.add(event);
            }
          }),
        ]);

    setUp(() => events = []);

    testWidgets('states are events; the background pauses the context', (
      tester,
    ) async {
      await pumpApp(tester, listening);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(events.whereType<AppLifecycleStateEvent>().map((e) => e.state), [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(events.whereType<ContextPausedEvent>(), hasLength(1));
      expect(events.whereType<ContextRestartedEvent>(), hasLength(1));
      expect(
        events.indexOf(events.whereType<ContextRestartedEvent>().single),
        greaterThan(
          events.indexOf(events.whereType<ContextPausedEvent>().single),
        ),
      );
    });

    testWidgets('pause-in-background=false keeps the context running', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () => listening(
          resources: {
            'application.properties':
                'spring.flutter.lifecycle.pause-in-background=false',
          },
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(events.whereType<AppLifecycleStateEvent>(), hasLength(4));
      expect(events.whereType<ContextPausedEvent>(), isEmpty);
      expect(events.whereType<ContextRestartedEvent>(), isEmpty);
    });
  });

  group('hot reload', () {
    testWidgets('keeps the context when the beans did not change', (
      tester,
    ) async {
      final before = await pumpApp(tester, () => app(fingerprint: 'same'));
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      final after = SpringScope.of(tester.element(find.byType(Greeting)));
      expect(after, same(before));
    });

    testWidgets('restarts the context and the widgets when they did', (
      tester,
    ) async {
      var fingerprint = 'one';
      var greeting = 'Hello';
      final before = await pumpApp(
        tester,
        () => app(
          fingerprint: fingerprint,
          resources: {'application.properties': 'greeting=$greeting'},
        ),
        child: const _Stateful(),
      );
      expect(find.text('Hello 1'), findsOneWidget);
      await tester.tap(find.byType(_Stateful));
      await tester.pump();
      expect(find.text('Hello 2'), findsOneWidget);

      fingerprint = 'two';
      greeting = 'Hi';
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();

      final after = SpringScope.of(tester.element(find.byType(_Stateful)));
      expect(after, isNot(same(before)));
      expect((before as ConfigurableApplicationContext).isActive, isFalse);
      // A fresh State with the new bean.
      expect(find.text('Hi 1'), findsOneWidget);
    });

    testWidgets('spring.devtools.restart.enabled=false keeps the context', (
      tester,
    ) async {
      var fingerprint = 'one';
      final before = await pumpApp(
        tester,
        () => app(
          fingerprint: fingerprint,
          resources: {
            'application.properties': 'spring.devtools.restart.enabled=false',
          },
        ),
      );
      fingerprint = 'two';
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      final after = SpringScope.of(tester.element(find.byType(Greeting)));
      expect(after, same(before));
      expect((before as ConfigurableApplicationContext).isActive, isTrue);
    });

    testWidgets('a restart failing its check leaves no context running', (
      tester,
    ) async {
      final contexts = <ApplicationContext>[];
      var fingerprint = 'one';
      var type = 'widgets';
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => app(
            fingerprint: fingerprint,
            definitions: [_tracker(contexts)],
            resources: {
              'application.properties': 'spring.flutter.app.type=$type',
            },
          ),
          failure: (_, error) =>
              Text('failed: $error', textDirection: TextDirection.ltr),
          home: const Greeting(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);

      fingerprint = 'two';
      type = 'nope';
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      expect(find.textContaining('failed:'), findsOneWidget);
      expect(contexts, hasLength(2));
      expect(
        contexts.whereType<ConfigurableApplicationContext>().where(
          (c) => c.isActive,
        ),
        isEmpty,
      );

      // Fixed: the retry starts the only context.
      type = 'widgets';
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(
        contexts.whereType<ConfigurableApplicationContext>().where(
          (c) => c.isActive,
        ),
        hasLength(1),
      );
    });

    testWidgets('after a failed start, tries again', (tester) async {
      var fail = true;
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => app(
            definitions: [
              BeanDefinition<Clock>(
                name: 'clock',
                types: const [Clock],
                create: (_) => fail ? throw StateError('no clock') : Clock(),
              ),
            ],
          ),
          child: const Greeting(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsNothing);
      fail = false;
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  testWidgets('removing SpringApplicationWidget closes the context', (
    tester,
  ) async {
    final context = await pumpApp(tester, app);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect((context as ConfigurableApplicationContext).isActive, isFalse);
  });

  testWidgets('context.message follows the app locale', (tester) async {
    final messages = StaticMessageSource()
      ..addMessage('hello', 'en', 'Hello {0}')
      ..addMessage('hello', 'ja', 'こんにちは {0}');
    final application = app(
      definitions: [
        BeanDefinition<MessageSource>(
          name: 'messageSource',
          types: const [MessageSource],
          create: (_) => messages,
        ),
      ],
    );
    final message = Builder(
      builder: (context) => Text(
        context.message('hello', args: ['Neo']),
        textDirection: TextDirection.ltr,
      ),
    );
    for (final (locale, text) in [
      (const Locale('ja'), 'こんにちは Neo'),
      (const Locale('en', 'US'), 'Hello Neo'),
    ]) {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => application,
          child: Localizations(
            locale: locale,
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: message,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('SpringScope.of without a scope explains what is missing', (
    tester,
  ) async {
    await tester.pumpWidget(const Greeting());
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect('$error', contains('No SpringScope above Greeting'));
  });
}

class _Stateful extends StatefulWidget {
  const _Stateful();

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _StatefulState extends State<_Stateful> {
  int taps = 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => taps++),
    child: Text(
      '${context.bean<Greeter>().greeting} $taps',
      textDirection: TextDirection.ltr,
    ),
  );
}

/// Records every context the application starts.
class _ContextTracker implements ApplicationContextAware {
  _ContextTracker(this.contexts);
  final List<ApplicationContext> contexts;

  @override
  void setApplicationContext(ApplicationContext applicationContext) =>
      contexts.add(applicationContext);
}

/// An eager bean that adds each started context to [contexts].
BeanDefinition<_ContextTracker> _tracker(List<ApplicationContext> contexts) =>
    BeanDefinition<_ContextTracker>(
      name: 'contextTracker',
      types: const [_ContextTracker],
      create: (_) => _ContextTracker(contexts),
    );
