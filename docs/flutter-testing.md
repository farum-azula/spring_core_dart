# Flutter testing

> **Status.** This page is mostly a **specification**. What works today:
> section 2 (`spring_boot_starter_test` under `flutter_test`, with
> `SpringScope`) and the first example of section 8
> (`SpringApplicationWidget` in a widget test). The starter
> `spring_boot_starter_flutter_test` and everything else on this page are
> **planned** ([roadmap](../roadmap/spring_boot_starter_flutter_test.md));
> the API described here may still change.

A widget test of a Spring app needs the app's beans: the widgets get
their state and services from the application context, not from their
constructors. So a test starts the application (or the part it needs),
replaces some beans with fakes, and shows the widget with that context.

Flutter apps get a test starter of their own for this,
`spring_boot_starter_flutter_test`. It is built on
[`spring_boot_starter_test`](testing.md) and re-exports it, so everything
on the [Testing](testing.md) page works the same in a Flutter app:
`@SpringBootTest` classes, `@Autowired` fields, `@TestBean` fakes,
properties and profiles, `@DirtiesContext`, logs. This page adds what
only Flutter has: widget tests, pumping widgets with the test's beans,
themes, platforms and golden files. `spring_boot_starter_test` itself
stays free of Flutter, so Dart packages and servers do not pull Flutter
in.

| Flutter | Here |
|---|---|
| `testWidgets(...)` | a `@WidgetTest()` method taking a `WidgetTester` |
| `tester.pumpWidget(MaterialApp(home: ...))` | `tester.pumpSpring(...)`: the widget with the test's context, inside the app widget of the properties |
| `debugDefaultTargetPlatformOverride` | `@TargetPlatformTest(TargetPlatform.iOS)` on the class: the platform and its profiles |
| `matchesGoldenFile` | the same, plus `@Golden()` for one screenshot per theme |

## Contents

1. [Setup](#1-setup)
2. [A widget test today](#2-a-widget-test-today)
3. [A widget test class](#3-a-widget-test-class)
4. [`pumpSpring`](#4-pumpspring)
5. [Beans in widget tests](#5-beans-in-widget-tests)
6. [Themes](#6-themes)
7. [Platforms and their profiles](#7-platforms-and-their-profiles)
8. [The whole app: `SpringApplicationWidget`](#8-the-whole-app-springapplicationwidget)
9. [Golden files](#9-golden-files)
10. [Plain tests next to widget tests](#10-plain-tests-next-to-widget-tests)
11. [What the generator writes](#11-what-the-generator-writes)
12. [Build errors](#12-build-errors)

## 1. Setup

*Planned.*

```yaml
# pubspec.yaml
dev_dependencies:
  spring_boot_starter_flutter_test: ^0.4.0  # brings spring_boot_starter_test
  flutter_test:
    sdk: flutter
  build_runner: ^2.17.0
```

One import gives everything: `springBootTest`, the annotations of
[Testing](testing.md), and this page's additions.

```dart
import 'package:spring_boot_starter_flutter_test/spring_boot_starter_flutter_test.dart';
```

Test configuration goes to `test/resources/`, as in a Dart package:
`springBootTest` reads it today already.

## 2. A widget test today

*Works today*, with `spring_boot_starter_test` as a dev dependency. The
app is a counter whose `counter.step` property says how much a tap adds.
The [Flutter guide](../example/flutter_guide/README.md#11-testing) tests
every screen this way.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';
import 'package:my_app/main.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

void main() {
  // Starts the application once for this file, with a test property.
  final app = springBootTest(
    springApplication,
    properties: {'counter.step': 2},
  );

  setUp(app.markDirty); // a fresh Counter for every test

  testWidgets('a tap adds counter.step', (tester) async {
    await tester.pumpWidget(
      SpringScope(
        applicationContext: app.context,
        child: const SpringApp(home: CounterPage()),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(app.context.getBean<Counter>().value, 2);
  });
}
```

- `SpringScope` gives the widgets below it the test's context, so
  `context.bean<T>()`, the generated getters and the Spring widgets find
  the test's beans and fakes (`springBootTest(overrides: [...])`).
- `SpringApp` builds the app widget from the properties, with its
  themes, texts and locales, as `SpringApplicationWidget(home: ...)`
  does in the app. A widget that needs no app widget can go directly
  under `SpringScope`.

## 3. A widget test class

*Planned.* The same test as a class, the way Spring writes tests:

```dart
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_test/spring_boot_starter_flutter_test.dart';

import 'spring/counter_page.test.spring.dart';

@SpringBootTest(properties: {'counter.step': 2})
@DirtiesContext() // a fresh Counter for every test
class CounterPageTest {
  @Autowired()
  late Counter counter;

  @WidgetTest('a tap adds counter.step')
  Future<void> tapAdds(WidgetTester tester) async {
    await tester.pumpSpring(const CounterPage());

    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(counter.value, 2);
  }

  @Test() // a plain test in the same class, with the same context
  void startsAtZero() => expect(counter.value, 0);
}

void main() => runSpringTests();
```

- **`@WidgetTest([name])`** marks a widget test. The method takes a
  `WidgetTester` and returns `Future<void>`. It runs as `testWidgets`,
  in Flutter's fake async zone.
- **`@Test()`** methods still work in the same class and run as `test`.
- `@Disabled`, `@Tag` and `@TestOptions` apply as they do to `@Test`.
  `@WidgetTest(variant: TargetPlatformVariant.mobile())` runs the test
  once per variant, like `testWidgets(variant:)`.

## 4. `pumpSpring`

*Planned.* An extension on `WidgetTester` that shows a widget with the
test's beans in one call. It works in function tests too.

```dart
await tester.pumpSpring(const CounterPage());
await tester.pumpSpring(const CounterPage(), theme: 'dark');
await tester.pumpSpring(const BasketBadge(), app: false); // no app widget
await tester.pumpSpring(page, context: otherContext);      // another context
```

| Parameter | Default | Meaning |
|---|---|---|
| `widget` | | What to show |
| `theme` | `spring.flutter.theme.active` | A theme to select (`ThemeSelection.select`) before pumping |
| `app` | `true` | `true`: inside `SpringApp(home: widget)`, the app widget of the properties (`MaterialApp`, `CupertinoApp` or `WidgetsApp`, with themes, locales, title). `false`: only `SpringScope` and a `Directionality`, for a widget that needs no app widget |
| `context` | the test class's context | The `ApplicationContext` to give the widget |
| `settle` | `true` | Calls `pumpAndSettle()` afterwards |

It is short for:

```dart
await tester.pumpWidget(
  SpringScope(
    applicationContext: app.context,
    child: SpringApp(home: widget),
  ),
);
await tester.pumpAndSettle();
```

## 5. Beans in widget tests

*Planned* in class form; with functions, `springBootTest(overrides:)`
and `app.getBean` do the same today.

Everything of [Testing, sections 5–7](testing.md#5-injecting-beans)
works. Inject the beans the widget shows, and replace those it calls:

```dart
@SpringBootTest()
class CheckoutPageTest {
  @TestBean()
  final Payments payments = FakePayments();     // the page calls it

  @Autowired()
  late Basket basket;                           // the page shows it

  @BeforeEach()
  void fill() => basket..clear()..add('Dune', 10);

  @WidgetTest('pay pays the basket total')
  Future<void> pays(WidgetTester tester) async {
    await tester.pumpSpring(const CheckoutPage());

    expect(find.text('10.00'), findsOneWidget);
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect((payments as FakePayments).paid, [10]);
    expect(find.text('Thank you'), findsOneWidget);
  }
}
```

- A `@ChangeNotifierComponent` bean changed by the test itself
  (`basket.add`) rebuilds the widgets that read it, as in the app;
  `await tester.pump()` shows the change.
- Beans with `@PreDestroy` methods or running timers are closed with the
  context after the class (or after a `@DirtiesContext` test), not after
  each `@WidgetTest`. So Flutter's "a Timer is still pending" check does
  not see them. Cancel a timer the test itself started.

## 6. Themes

*Planned:* the `theme:` parameter and the class form. A property in
`springBootTest(properties:)` selects a theme today.

Themes come from the properties
([Configuration, 17. Reference: Flutter](configuration.md#17-reference-flutter)),
so a test chooses one with a property, a profile or
`pumpSpring(theme:)`:

```dart
@SpringBootTest(properties: {'spring.flutter.theme.active': 'dark'})
class DarkThemeTest {
  @WidgetTest()
  Future<void> titleUsesThePrimaryColor(WidgetTester tester) async {
    await tester.pumpSpring(const HomePage());

    final title = tester.widget<Text>(find.text('Shop'));
    final theme = SpringTheme.of(tester.element(find.text('Shop')));
    expect(title.style?.color, theme.colorScheme.primary);
    expect(theme.name, 'dark');
  }

  @WidgetTest()
  Future<void> sepiaToo(WidgetTester tester) async {
    await tester.pumpSpring(const HomePage(), theme: 'sepia');
    expect(SpringTheme.of(tester.element(find.byType(HomePage))).name, 'sepia');
  }
}
```

- With `active: system`, the theme follows
  `tester.platformDispatcher.platformBrightnessTestValue`: set it to
  `Brightness.dark` to test the device's dark mode.
- The theme's fonts are loaded from the assets in tests as in the app,
  so golden tests show them instead of the test font.

## 7. Platforms and their profiles

In the app, the platform's profiles are active: `android` and `mobile`,
`ios` and `mobile`, `macos` and `desktop`, and so on. In a widget test
the platform is Android unless the test changes it.

*Works today:* a test that pumps `SpringApplicationWidget` gets the
profiles of the test's platform (`mobile` and `android` by default; set
`debugDefaultTargetPlatformOverride` before pumping for another one).
`springBootTest` adds no platform profile; pass `profiles:` to it.

*Planned:* `@TargetPlatformTest` on a class sets
`debugDefaultTargetPlatformOverride` for its tests and adds that
platform's profiles to the context:

```dart
@SpringBootTest()
@TargetPlatformTest(TargetPlatform.macOS)       // the desktop and macos profiles
class DesktopMenuTest {
  @Autowired()
  late MenuLayout layout;                       // a @Profile(['desktop']) bean

  @WidgetTest()
  Future<void> showsTheMenuBar(WidgetTester tester) async {
    await tester.pumpSpring(const HomePage());
    expect(find.byType(PlatformMenuBar), findsOneWidget);
  }
}
```

- The profiles belong to the context, so the platform is set per class.
  To test several platforms, write a class per platform. For differences
  in the widgets only, use `@WidgetTest(variant: ...)`; the context and
  its profiles stay the class's.
- `@TargetPlatformTest(null)` adds no platform profile at all.

## 8. The whole app: `SpringApplicationWidget`

To test the start itself (the splash screen, a failed start, the
platform profiles), let `SpringApplicationWidget` start the application
as `flutter run` does. No `springBootTest` context is involved.

*Works today:*

```dart
testWidgets('SpringApplicationWidget starts the application', (tester) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      home: const CounterPage(),
    ),
  );
  await tester.pumpAndSettle();

  // The test runs as Android: the phone's profiles are active.
  final context = SpringScope.of(tester.element(find.byType(CounterPage)));
  expect(context.environment.activeProfiles, ['mobile', 'android']);
  expect(find.text('0'), findsOneWidget);

  await tester.pumpWidget(const SizedBox()); // removing the widget closes the context
});
```

`SpringApplicationWidget` takes no test properties or bean overrides. A
test that needs them passes its own `SpringApplication` built from
`springApplication`; the Flutter guide does so in
`test/support/fake_server.dart`.

*Planned:* `tester.pumpSpringApplication(home: ..., properties: {...})`
does the same with test properties and `test/resources/`, and closes the
context at the end of the test.

## 9. Golden files

Golden tests are widget tests that compare the screen with a stored
image (`matchesGoldenFile`). `pumpSpring` gives them the real theme and
fonts.

*Planned:* `@Golden()` runs one widget test per theme given and names
the image files after them. The platform comes from the class
(`@TargetPlatformTest`).

```dart
@SpringBootTest()
class HomeGoldens {
  @WidgetTest()
  @Golden(themes: ['light', 'dark', 'sepia'], size: Size(400, 800))
  Future<void> home(WidgetTester tester) async {
    await tester.pumpSpring(const HomePage());
    // compared with goldens/home.light.png, goldens/home.dark.png, ...
  }
}
```

- Golden images depend on how the operating system draws text. This
  repository makes and compares them on macOS, in CI too. Keep one OS for
  your goldens as well, and tag them (`@Tag('golden')`) to run them only
  there.
- `flutter test --update-goldens` writes the files.

## 10. Plain tests next to widget tests

A Flutter package can test its pure Dart beans with `@Test` methods or
plain `test(...)` functions. They run in `flutter test` like the rest,
without a widget tree. Code without Flutter that is shared with a server
is better kept in its own Dart package, tested with
`spring_boot_starter_test` and `dart test`.

## 11. What the generator writes

*Planned.* The test classes become the same generated file as in
[Testing](testing.md#15-what-the-generator-writes):
`test/spring/counter_page.test.spring.dart`, with `runSpringTests()`.
The Flutter starter adds:

- each `@WidgetTest` method as `testWidgets(name, (tester) =>
  instance.tapAdds(tester), variant: ..., skip: ...)`;
- `@TargetPlatformTest` as a `setUp` and `tearDown` that set
  `debugDefaultTargetPlatformOverride`, and the platform's profiles added
  to `springBootTest(profiles: ...)`;
- `@Golden` as one `testWidgets` per theme, with the
  `matchesGoldenFile` check after the method.

The generator learns these annotations from the Flutter test starter;
the core test starter knows nothing about Flutter.

## 12. Build errors

*Planned*, on top of [Testing's](testing.md#16-build-errors):

| Message | Fix |
|---|---|
| `@WidgetTest method 'pays' must take one WidgetTester` | `Future<void> pays(WidgetTester tester) async` |
| `@Test method 'pays' takes a WidgetTester: use @WidgetTest` | change the annotation |
| `@WidgetTest needs spring_boot_starter_flutter_test` | add the dev dependency (the core starter has no Flutter) |
| `@TargetPlatformTest on a method: the platform belongs to the class` | move it to the class, or use `@WidgetTest(variant:)` |
| `@Golden without @WidgetTest` | add `@WidgetTest()` |
