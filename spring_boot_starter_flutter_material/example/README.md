# spring_boot_starter_flutter_material: example

A `MaterialApp` whose look is all configuration. [`example.dart`](example.dart)
is the whole app; its themes are in
[`lib/resources/application.yml`](lib/resources/application.yml); the
generator writes `spring_gen/example.spring.dart`
(`dart run build_runner build`).

- No `spring.flutter.app.type`: with this one design starter in the
  dependencies the app is a `MaterialApp`; the starter builds it, with the title,
  the locales and both themes.
- `seed-color`: Material 3's algorithm makes every role of the palette from
  one color, in the light and in the dark theme.
- `components.app-bar` and `components.card`: Material's own component
  themes, by Flutter's property names; `$colors.primary-container` is a
  role of the palette made from the seed.
- `BrandTheme` is a `ThemeCustomizer` bean: what no property sets, in
  code, on every theme. Here a `ThemeExtension` of the app's own, made
  from the palette, which the page reads with
  `Theme.of(context).extension<Brand>()`.
- The button in the app bar switches the theme with the `ThemeSelection`
  bean; the app shows the other theme at once.

The app's dependencies:

```yaml
dependencies:
  spring_boot_starter_flutter_material: ^0.8.1
  # Material's widgets, which the page itself uses.
  material_ui: ^1.11.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.1
```

To run it, make an app around it:

```sh
flutter create themes && cd themes
flutter pub add spring_boot_starter_flutter_material material_ui
flutter pub add dev:build_runner dev:spring_core_dart_generator
# copy example.dart to lib/main.dart, change its import
# 'spring_gen/example.spring.dart' to 'spring_gen/main.spring.dart',
# and copy lib/resources/application.yml
dart run build_runner build
flutter run
```
