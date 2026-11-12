# spring_boot_starter_flutter_cupertino

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-flutter-cupertino](https://farum-azula.org/components/spring-boot-starter-flutter-cupertino)

Cupertino for Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter),
on the Flutter team's
[`cupertino_ui`](https://pub.dev/packages/cupertino_ui). The Flutter
starter knows no design library; this package adds the iOS one:

- **A `CupertinoApp` from properties**: in the dependencies, it makes the
  app a `CupertinoApp` (`spring.flutter.app.type: cupertino`), with the
  title, locales and theme of the configuration.
- **Themes as `CupertinoThemeData`**: every theme of
  `spring.flutter.theme.*` made Cupertino, with its own `cupertino.*`
  properties, checked when the application starts.
- **Palettes from a seed color**: `seed-color`, `scheme-variant` and
  `contrast` make the Material 3 palette a Material app has from the same
  properties, without Material in the build.
- **The iOS page route** for `spring_boot_starter_flutter_navigation`: the
  slide with its swipe back, in an app of type `cupertino` or for
  `motion.page-transition: cupertino` anywhere.
- **Cupertino's controls** for the starters' own widgets: iOS's text
  selection handles in `MarkdownView`, Cupertino's fields and buttons in
  the login form of `spring_boot_starter_flutter_security`.

## Contents

- [Setup](#setup)
- [The theme](#the-theme)
- [Themes in code](#themes-in-code)
- [Page transitions](#page-transitions)
- [Tests](#tests)

## Setup

```yaml
dependencies:
  spring_boot_starter_flutter_cupertino: ^0.8.0
  # The widgets themselves.
  cupertino_ui: ^1.1.6

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.0
```

The starter brings and re-exports `spring_boot_starter_flutter`; an app
lists only this package, next to `cupertino_ui` for the widgets it uses:

```dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';
```

```properties
# lib/resources/application.properties
spring.flutter.app.title=Counter
```

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const CounterPage(),
  ),
);
```

Then `dart run build_runner build`: the generator finds the starter and
adds its beans and its design to `lib/spring_gen/main.spring.dart`.

`spring.flutter.app.type` need not be set: as Spring Boot deduces
`spring.main.web-application-type` from the class path, the starters
decide, and with this one as the only design starter the app is of type
`cupertino`. Set, the property always wins (`widgets` keeps a
`WidgetsApp` although this starter is in the build).

An app that is Material on Android and Cupertino on iOS depends on both
design starters and must set the type: with app widgets of two types the
start fails, naming the property and the types, until one is chosen, for
every platform or per platform in a profile:

```properties
# lib/resources/application.properties
spring.flutter.app.type=material
```

```properties
# lib/resources/application-ios.properties
spring.flutter.app.type=cupertino
```

## The theme

The theme shown is the one `ThemeSelection` picks, as a
`CupertinoThemeData`. Without properties it is iOS's own. What the
properties set goes over that:

```yaml
spring.flutter.theme:
  seed-color: teal
  typography:
    font-family: Inter
  cupertino:
    primary-color: '#00897B'
    primary-contrasting-color: '#FFFFFF'
    scaffold-background-color: '#F2F2F7'
    bar-background-color: '#E5E5EA'
    selection-handle-color: '#00897B'
    apply-theme-to-all: true
    text-theme:
      nav-title-text-style: { weight: 600 }
      nav-large-title-text-style: display-small
```

- The primary color is `cupertino.primary-color`, else `colors.primary`,
  else the primary color of the seed's palette, else iOS blue. The action
  text styles carry it.
- The text styles are iOS's, with the theme's font family and what
  `typography.*` sets for the matching style (`title-large` for the
  navigation title, `display-small` for the large title, `body-large` for
  text, `label-large` for actions, `label-small` for tab labels), then
  what `cupertino.text-theme.*` sets.
- The scaffold's background is `cupertino.scaffold-background-color`, else
  `colors.surface`; clear when the theme has a `background`, which then
  shows through.
- The bars' background is `cupertino.bar-background-color`, else, in an
  app that also has the Material starter, `components.app-bar.background-color`.

A wrong value or an unknown key under `cupertino` stops the start with
the property's name. A theme with `cupertino.*` in an application without
this starter is accepted (a theme library has it for the apps that use
Cupertino), not shown and not checked; one line of the log names the
package that reads it.

`SpringTheme.of(context)` is the same theme for the app's own widgets: its
palette (`colorScheme.surfaceContainer`), text styles, spacing and tokens.

## Themes in code

A `CupertinoThemeCustomizer` bean changes every theme after it is made:

```dart
// Bar backgrounds follow the theme's surface color.
@Component()
class SurfaceBars implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) => theme.copyWith(barBackgroundColor: spring.colorScheme.surface);
}
```

A `CupertinoThemeData` bean of the application replaces the themes made
from the properties (the customizers still run). The `CupertinoThemes`
bean has every theme by name (`cupertinoThemes.theme('ocean')`), and
`SpringTheme.of(context).toCupertino()` the one of the theme shown.

## Page transitions

With `spring_boot_starter_flutter_navigation`, the screens of an app of
type `cupertino` come in with the iOS slide, and go back with a swipe,
as in Flutter's `CupertinoApp`: `platform`, the theme's default, is the
slide there (`motion.page-transition: none` switches pages at once);
`cupertino` asks for it in an app of any type:

```yaml
spring.flutter.theme.motion.page-transition:
  type: cupertino
  duration: 350ms
```

## Tests

A test that reads themes by hand names the design:

```dart
final themes = SpringThemes(
  const {'cupertino.primary-color': '#00897B'},
  designs: const ThemeDesigns(
    all: [CupertinoThemeDesign()],
    appType: 'cupertino',
  ),
);
expect(
  themes.data('light').toCupertino().primaryColor,
  const Color(0xFF00897B),
);
```

A widget test of the generated application needs nothing more: its
`springApplication` has the starter's beans and its design.
