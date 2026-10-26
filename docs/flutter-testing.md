# Flutter testing

> **Status.** Section 2 describes what works today
> (`spring_boot_starter_test` with `flutter_test`, `SpringScope`). The
> starter `spring_boot_starter_flutter_test` and everything else on this
> page is **planned** ([roadmap](../roadmap/spring_boot_starter_flutter_test.md));
> this page is its specification and may still change.

Flutter apps get their own test starter, `spring_boot_starter_flutter_test`.
It is built on [`spring_boot_starter_test`](testing.md) and re-exports it,
so everything on the [Testing](testing.md) page works the same in a
Flutter app: `@SpringBootTest` classes, `@Autowired` fields, `@TestBean`
fakes, properties and profiles, `@DirtiesContext`, logs. This page adds what
only Flutter has: widget tests, pumping widgets with the test's beans,
themes, platforms and golden files.

| Spring / Flutter | Here |
|---|---|
| `testWidgets(...)` | a `@WidgetTest()` method taking a `WidgetTester` |
| `tester.pumpWidget(MaterialApp(home: ...))` | `tester.pumpSpring(...)`: the widget with the test's context and the app widget from the properties |
| `debugDefaultTargetPlatformOverride` | `@TargetPlatformTest(TargetPlatform.iOS)`: the platform and its profiles |
| `matchesGoldenFile` | the same, plus `@Golden()` for the theme × platform matrix |

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

```yaml
# pubspec.yaml
dev_dependencies:
  spring_boot_starter_flutter_test: ^0.4.0  # brings spring_boot_starter_test
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
```

One import gives everything: `springBootTest`, the annotations of
[Testing](testing.md), and this page's additions.

```dart
import 'package:spring_boot_starter_flutter_test/spring_boot_starter_flutter_test.dart';
```

Test configuration goes to `test/resources/`, as in a Dart package.

## 2. A widget test today

*Works today*, with `spring_boot_starter_test` and `SpringScope` (from
`example/flutter_counter/test/widget_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_counter/main.spring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

void main() {
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

`SpringScope` gives the widgets below it the test's context, so
`context.bean<T>()` and the Spring widgets find the test's beans and
fakes. `SpringApp` builds the app widget (and themes) from the
properties.

## 3. A widget test class

*Planned.* The same test as a class:

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

  @Test() // a plain test in the same class, same context
  void startsAtZero() => expect(counter.value, 0);
}

void main() => runSpringTests();
```

- **`@WidgetTest([name])`** marks a widget test; the method takes a
  `WidgetTester` and returns `Future<void>`. It runs as `testWidgets`, in
  Flutter's fake async zone.
- **`@Test()`** methods still work in the same class, run as `test`.
- `@Disabled`, `@Tag` and `@TestOptions` apply as for `@Test`;
  `@WidgetTest(variant: TargetPlatformVariant.mobile())` runs it once per
  variant, like `testWidgets(variant:)`.

## 4. `pumpSpring`

*Planned*, an extension on `WidgetTester` (works in function tests too).

```dart
await tester.pumpSpring(const CounterPage());
await tester.pumpSpring(const CounterPage(), theme: 'dark');
await tester.pumpSpring(const BasketBadge(), app: false); // no app widget
await tester.pumpSpring(page, context: otherContext);      // another context
```

| Parameter | Default | Meaning |
|---|---|---|
| `widget` | | what to show |
| `theme` | `spring.flutter.theme.active` | selects a theme (`ThemeSelection.select`) before pumping |
| `app` | `true` | `true`: inside `SpringApp(home: widget)`, the app widget of the properties (`MaterialApp`, `CupertinoApp` or `WidgetsApp`, with themes, locale, title). `false`: only `SpringScope` and a `Directionality`, for a widget that needs no app |
| `context` | the test class's context | the `ApplicationContext` to give the widget |
| `settle` | `true` | `pumpAndSettle()` afterwards |

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

Everything of [Testing, sections 5–7](testing.md#5-injecting-beans) works:
inject the beans the widget changes, replace those it calls.

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

- A `@ChangeNotifierComponent` bean changed in the test (`basket.add`)
  rebuilds the widgets that read it, as in the app; `await tester.pump()`
  shows the change.
- Beans with `@PreDestroy` or running timers are closed with the context
  after the class (or after a `@DirtiesContext` test), not after each
  `@WidgetTest`, so Flutter's "a Timer is still pending" check does not
  see them. Cancel a timer the test itself started.

## 6. Themes

Themes come from the properties ([Configuration, Themes](configuration.md#17-reference-flutter)),
so a test chooses one with a property, a profile or `pumpSpring(theme:)`:

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

- `active: system` follows `tester.platformDispatcher.platformBrightnessTestValue`:
  set it to `Brightness.dark` to test the system's dark mode.
- Fonts from the theme are loaded in tests like in the app (from the
  assets); golden tests show them, not the test font.

## 7. Platforms and their profiles

In the app, the platform's profiles are active (`android` + `mobile`,
`ios` + `mobile`, `macos` + `desktop`, ...). In a test the platform is
Android unless changed, so the `mobile` and `android` profiles are active
(today this is the case for `SpringApplicationWidget` tests; `springBootTest`
adds no platform profile).

*Planned:* `@TargetPlatformTest` on the class sets
`debugDefaultTargetPlatformOverride` for its tests and adds that platform's
profiles to the context:

```dart
@SpringBootTest()
@TargetPlatformTest(TargetPlatform.macOS)       // desktop + macos profiles
class DesktopMenuTest {
  @Autowired()
  late MenuLayout layout;                       // the @Profile('desktop') bean

  @WidgetTest()
  Future<void> showsTheMenuBar(WidgetTester tester) async {
    await tester.pumpSpring(const HomePage());
    expect(find.byType(PlatformMenuBar), findsOneWidget);
  }
}
```

- The profiles belong to the context, so the platform is per class; to
  test several platforms, write a class per platform, or use
  `@WidgetTest(variant: ...)` for widget-only differences (the context
  and its profiles stay the class's).
- `@TargetPlatformTest(null)`: no platform profile at all.

## 8. The whole app: `SpringApplicationWidget`

To test the start itself (splash, a failed start, the platform profiles),
let `SpringApplicationWidget` start the application as `flutter run` does;
no `@SpringBootTest` context is involved. *Works today:*

```dart
testWidgets('SpringApplicationWidget starts the application', (tester) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      home: const CounterPage(),
    ),
  );
  await tester.pumpAndSettle();

  // The test runs as Android: the mobile profile's title.
  expect(find.text('Flutter Demo Home Page (mobile)'), findsOneWidget);

  await tester.pumpWidget(const SizedBox()); // closes the context
});
```

*Planned:* `tester.pumpSpringApplication(home: ..., properties: {...})`
does the same with test properties and `test/resources/`, and closes the
context at the end of the test.

## 9. Golden files

Golden tests are widget tests with `matchesGoldenFile`; `pumpSpring` gives
them the real theme and fonts. *Planned:* `@Golden()` runs one widget test
for each theme × platform given and names the files after them:

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

- Golden images depend on the operating system's text rendering; this
  repository renders them on macOS in CI. Keep one OS for your goldens
  too and tag them (`@Tag('golden')`) to run them only there.
- `flutter test --update-goldens` writes the files.

## 10. Plain tests next to widget tests

A Flutter package can test its pure Dart beans with `@Test` methods (or
plain `test(...)`): they run in `flutter test` like the rest, without a
widget tree. Code without Flutter that is shared with a server is better
in its own Dart package, tested with `spring_boot_starter_test` and
`dart test`.

## 11. What the generator writes

The same generated file as in [Testing](testing.md#15-what-the-generator-writes):
`test/spring/counter_page.test.spring.dart` with `runSpringTests()`. The Flutter
starter adds:

- `@WidgetTest` methods as `testWidgets(name, (tester) =>
  instance.tapAdds(tester), variant: ..., skip: ...)`;
- `@TargetPlatformTest` as `setUp`/`tearDown` setting
  `debugDefaultTargetPlatformOverride`, and the platform profiles added to
  `springBootTest(profiles: ...)`;
- `@Golden` as one `testWidgets` per theme and the `matchesGoldenFile`
  check after the method.

The generator learns these annotations from the Flutter starter; the core
test starter knows nothing about Flutter.

## 12. Build errors

*Planned*, on top of [Testing's](testing.md#16-build-errors):

| Message | Fix |
|---|---|
| `@WidgetTest method 'pays' must take one WidgetTester` | `Future<void> pays(WidgetTester tester) async` |
| `@Test method 'pays' takes a WidgetTester: use @WidgetTest` | change the annotation |
| `@WidgetTest needs spring_boot_starter_flutter_test` | add the dev dependency (the core starter has no Flutter) |
| `@TargetPlatformTest on a method: the platform belongs to the class` | move it to the class, or use `@WidgetTest(variant:)` |
| `@Golden without @WidgetTest` | add `@WidgetTest()` |
