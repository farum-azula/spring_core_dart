# spring_boot_starter_flutter_test

A test starter for Flutter apps, built on `spring_boot_starter_test` and
re-exporting it: everything of the Dart test starter (`springBootTest`,
test classes with `@SpringBootTest`, `@Autowired`, `@TestBean`, ...) plus
what only Flutter has. `spring_boot_starter_test` itself stays free of
Flutter, so Dart packages and servers do not pull it in.

The specification is the documentation page
[docs/flutter-testing.md](../docs/flutter-testing.md).

## Today

Flutter tests use `spring_boot_starter_test` with `flutter_test` and wrap
the widget in `SpringScope(applicationContext: app.context, child:
SpringApp(home: ...))` (see the Flutter guide's tests, `example/flutter_guide/test/`).

## Planned

Depends on the test classes of
[spring_boot_starter_test.md](spring_boot_starter_test.md) (the test builder
must be open to annotations of other starters).

1. **The package**: `spring_boot_starter_flutter_test`, depending on
   `spring_boot_starter_test`, `spring_boot_starter_flutter` and
   `flutter_test`; one import for everything.
2. **`WidgetTester.pumpSpring(widget, {theme, app, context, settle})`**: the
   widget inside `SpringScope` and the app widget of the properties; works
   in function tests too.
3. **`@WidgetTest([name], variant:)`**: a method taking a `WidgetTester`,
   generated as `testWidgets`.
4. **`@TargetPlatformTest(platform)`** on a class: sets
   `debugDefaultTargetPlatformOverride` and adds the platform's profiles
   (`mobile` + `android`, `desktop` + `macos`, ...) to the context.
5. **`tester.pumpSpringApplication(home:, properties:)`**: the whole start
   through `SpringApplicationWidget`, with test properties and
   `test/resources/`, closed at the end of the test.
6. **`@Golden(themes:, size:)`**: one widget test per theme, compared with
   `goldens/<method>.<theme>.png`.
7. **Build errors** of docs/flutter-testing.md section 12.
8. **Examples**: the Flutter guide's
   tests as classes; the docs examples run in CI (on the macOS runner for
   goldens).

## Open questions

- Platforms as a matrix (`@TargetPlatformTest([iOS, android])` making one
  context per platform) or one class per platform, as specified now.
- Integration tests (`integration_test`, a real device): the same classes
  with `IntegrationTestWidgetsFlutterBinding`, later.
