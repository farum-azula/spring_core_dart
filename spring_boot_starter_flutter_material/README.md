# spring_boot_starter_flutter_material

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-flutter-material](https://farum-azula.org/components/spring-boot-starter-flutter-material)

Material Design for Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter),
on the Flutter team's [`material_ui`](https://pub.dev/packages/material_ui).

`spring_boot_starter_flutter` knows no design library: an app of
`spring.flutter.app.type: widgets` has its themes, its palette and its
text styles without Material in the build. This starter adds Material:

- **A `MaterialApp` from properties**: in the dependencies, it makes the
  app a `MaterialApp` (`spring.flutter.app.type: material`), with the
  title, locales and themes of the configuration.
- **Material's `ThemeData` from `spring.flutter.theme.*`**: colors,
  typography, shapes, and about fifty component themes under
  `components.*` (`card`, `app-bar`, `filled-button`, `input`, ...), each
  by Flutter's own property names.
- **Palettes from a seed color**: `seed-color`, `scheme-variant` and
  `contrast` make a Material 3 palette (`ColorScheme.fromSeed`).
- **Themes in code where properties end**: `ThemeCustomizer` beans change
  every `ThemeData`; a `ThemeData` bean named `theme` or `darkTheme`
  replaces the made one.
- **For the other starters**: Material's page route for the router of
  `spring_boot_starter_flutter_navigation`, Material's text field and
  button for the login form of `spring_boot_starter_flutter_security`.

## Contents

- [Setup](#setup)
- [The app widget](#the-app-widget)
- [Themes](#themes)
- [Components](#components)
- [Themes in code](#themes-in-code)
- [A MaterialApp of your own](#a-materialapp-of-your-own)
- [Tests](#tests)

## Setup

```yaml
dependencies:
  material_ui: ^1.11.0
  spring_boot_starter_flutter_material: ^0.8.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.0
```

The starter brings and re-exports `spring_boot_starter_flutter`; an app
lists this package, and `material_ui` for the Material widgets it uses:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';
```

Flutter 3.50 or later (Dart 3.14): the first whose `widgets` library the
Flutter starter needs nothing else of.

## The app widget

```yaml
# lib/resources/application.yml
spring.flutter:
  app:
    title: Counter
  theme:
    seed-color: deepPurple
```

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const HomePage(),
  ),
);
```

`SpringApplicationWidget` builds a `MaterialApp` (or, without a `home`,
`MaterialApp.router` on the application's router). With
`spring.flutter.theme.active: system` (the default) Material switches
between the light and the dark theme with the device; a theme picked with
the `ThemeSelection` bean, or loaded at run time, shows at once.

`spring.flutter.app.type` need not be set: as Spring Boot deduces
`spring.main.web-application-type` from the class path, the starters
decide, and with this one as the only design starter the app is of type
`material`. The property is for choosing: with
`spring_boot_starter_flutter_cupertino` in the dependencies too, the start
fails until it is set, for every platform or per platform in a profile
(`spring.flutter.app.type=cupertino` in `application-ios.properties`);
`widgets` keeps a `WidgetsApp` although this starter is in the build. Set,
it always wins.

Without this starter in the dependencies, `spring.flutter.app.type:
material` fails the start and says which package to add.

## Themes

Every theme of `spring.flutter.theme.*` is Material's `ThemeData` here.
Only what the properties set differs from Flutter's own Material 3 theme:

```yaml
spring.flutter.theme:
  seed-color: teal
  scheme-variant: vibrant        # tonalSpot, fidelity, monochrome, ...
  contrast: 0.5                  # -1 to 1
  colors:
    error: '#B3261E'
  typography:
    font-family: Inter
    title-large: { weight: 600 }
  visual-density: compact        # adaptive, standard, comfortable, compact
  tap-target-size: shrink-wrap   # padded, shrink-wrap
  splash: sparkle                # ripple, sparkle, none
  motion:
    page-transition: zoom
  themes:
    night:
      brightness: dark
      seed-color: indigo
```

Widgets read the theme as always:

```dart
final scheme = Theme.of(context).colorScheme;
```

and what Material's theme has no place for (spacing, the `code` style,
the app's own tokens) with `SpringTheme.of(context)`; the `ThemeData`
carries it too (`Theme.of(context).extension<SpringThemeExtension>()`).

## Components

`components.<name>.*` sets a component theme of `ThemeData`, by Flutter's
property names in kebab case; colors may be roles of the palette, shapes
tokens of the shape scale, and what Flutter models per state takes a map
of states:

```yaml
spring.flutter.theme.components:
  card: { elevation: level2, shape: large, color: $colors.surface-container }
  app-bar: { center-title: true, title-style: title-medium }
  button: { shape: full }                     # every kind of button
  filled-button: { padding: '24, 10' }
  input: { style: outline }
  checkbox:
    fill-color: { selected: $colors.primary, disabled: $colors.outline }
```

An unknown component or property, or a wrong value, fails the start and
names the property and the valid ones. The reference of every component
is in the documentation.

## Themes in code

A `ThemeCustomizer` bean changes every `ThemeData` made from the
properties, for what they do not cover:

```dart
@Component()
class RoundedChips implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
      );
}
```

A `ThemeData` bean named `theme` replaces the `light` theme, one named
`darkTheme` the `dark` one. The `MaterialThemes` bean has the result:

```dart
class ThemePreview extends SpringStatelessWidget<(MaterialThemes,)> {
  const ThemePreview({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final (themes,) = beans;
    return Theme(data: themes.theme(name), child: const PreviewCard());
  }
}
```

## A MaterialApp of your own

An app that builds its own `MaterialApp` takes the themes from the bean,
and gives the starter's widgets Material's look with a `DesignScope`:

```dart
MaterialApp(
  theme: themes.theme('light'),
  darkTheme: themes.theme('dark'),
  builder: (context, child) => DesignScope(
    textStyle: (context, style) =>
        Theme.of(context).textTheme.styleNamed(style),
    selectable: (context, child) => SelectionArea(child: child),
    controls: const MaterialDesignControls(),
    child: child!,
  ),
  home: const HomePage(),
);
```

## Tests

A test reads themes with Material's design by passing it:

```dart
final themes = SpringThemes(
  {'seed-color': 'teal', 'components.card.elevation': '2'},
  designs: const ThemeDesigns(
    all: [MaterialThemeDesign()],
    appType: 'material',
  ),
);
expect(themes.data('light').toMaterial().cardTheme.elevation, 2);
```

(`ThemeDesigns` is in `package:spring_boot_starter_flutter/theme_design.dart`.)
A widget test of the whole app (`SpringApplicationWidget(application: ()
=> springApplication)`) has the design from the generated application.

Spring (Java) has no themes for apps; the names follow Spring where there
is something to follow: a starter with its auto-configuration, customizer
beans, `spring.factories` for what must work before the beans exist.
