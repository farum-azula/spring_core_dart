# spring_boot_starter_flutter_cupertino: example

A `CupertinoApp` whose look is all configuration.
[`example.dart`](example.dart) is the whole app; its themes are in
[`lib/resources/application.yml`](lib/resources/application.yml); the
generator writes `spring_gen/example.spring.dart`
(`dart run build_runner build`).

- No `spring.flutter.app.type`: with this one design starter in the
  dependencies the app is a `CupertinoApp`; the starter builds it, with the title,
  the locales and the theme shown.
- `colors.*`: the roles of the palette, a light and a dark set; nothing
  is made from a seed, so the app needs no algorithm of Material's. A
  `seed-color` works too: the starter makes the same palette as Material
  3, without Material.
- `cupertino.*`: Cupertino's own theme, by Flutter's property names;
  `$colors.primary` names a role of the palette.
- `Contrast` is a `CupertinoThemeCustomizer` bean: what no property
  sets, in code, on every theme. Here the text color on the primary
  color, black or white by the primary color's luminance.
- The button in the navigation bar switches the theme with the
  `ThemeSelection` bean; the app shows the other theme at once.

The app's dependencies:

```yaml
dependencies:
  spring_boot_starter_flutter_cupertino: ^0.8.1
  # Cupertino's widgets, which the page itself uses.
  cupertino_ui: ^1.1.6

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.1
```

To run it, make an app around it:

```sh
flutter create themes && cd themes
flutter pub add spring_boot_starter_flutter_cupertino cupertino_ui
flutter pub add dev:build_runner dev:spring_core_dart_generator
# copy example.dart to lib/main.dart, change its import
# 'spring_gen/example.spring.dart' to 'spring_gen/main.spring.dart',
# and copy lib/resources/application.yml
dart run build_runner build
flutter run
```
