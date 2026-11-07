---
title: "Flutter themes in YAML — Spring for Dart"
description: "Describe the whole look of a Flutter app in YAML: colors, fonts, shapes, components, dark mode and themes of your own. Start here."
slug: /docs/flutter/theme
section: Flutter / Theme
order: 1
keywords: [flutter, theme, yaml, material 3, dark mode, spring.flutter.theme, configuration, design system]
---

# Flutter themes in YAML

With `spring_boot_starter_flutter` the look of an app lives in configuration,
not in `ThemeData` code. You write colors, fonts, shapes, component styles,
backgrounds and animations under `spring.flutter.theme` in `application.yml`.
The starter reads them when the app starts and builds Material's `ThemeData`
and Cupertino's `CupertinoThemeData` from them. Designers can change the look
in one file, per profile or per platform, without touching widgets.

## A first theme

```yaml
spring:
  flutter:
    theme:
      seed-color: deepPurple
      typography:
        font-family: Inter
      shape:
        medium: 16
      components:
        card:
          shape: large
        app-bar:
          center-title: true
```

That is a complete theme. Everything you do not write keeps Flutter's
Material 3 default. A theme without any property is Flutter's own Material 3
theme.

Every value is checked at start. A misspelled key, a color that does not
exist or a number where a word is expected stops the start with a message that
names the property, the value and what is allowed, often with a "did you mean".
Nothing is ignored silently.

## How a theme is chosen

There are three parts:

1. The **root** of `spring.flutter.theme` is shared by every theme.
2. **`light` and `dark`** always exist. Write `themes.light` or `themes.dark`
   to change only what differs in them.
3. Any number of **themes of your own** live under `themes.<name>`. Each one
   holds only what it changes.

```yaml
spring:
  flutter:
    theme:
      active: system          # system, or the name of a theme
      system-light: light     # what "system" shows in light mode
      system-dark: dark       # what "system" shows in dark mode

      seed-color: deepPurple  # shared by every theme

      themes:
        dark:
          seed-color: deepPurple.shade200
        ocean:
          seed-color: teal
          scheme-variant: vibrant
        ocean-night:
          extends: ocean      # start from ocean, not from the root
          brightness: dark
```

| Key | Where | What it does |
|---|---|---|
| `active` | root | The theme shown at start. `system` (the default) follows the device's light or dark mode |
| `system-light` | root | The theme `system` shows when the device is in light mode. Default `light` |
| `system-dark` | root | The theme `system` shows when the device is in dark mode. Default `dark` |
| `remember` | root | Keeps the theme the user chooses between runs and shows it again while the splash shows. Default `true` |
| `themes.<name>` | root | A theme of your own, or a change to `light` or `dark` |
| `extends` | in `themes.<name>` | Starts the theme from another theme instead of the root. Chains work; a cycle or an unknown name stops the start |

A theme is made in layers, each over the one before:

1. its brightness (`dark` for the `dark` theme, otherwise `light`),
2. the root, or the theme it `extends`,
3. its own keys.

A list in a later layer replaces the whole list of an earlier one. References
(`$colors.primary`) are resolved after the layers are put together, so a theme
that changes `colors.primary` also changes everything that refers to it. See
[tokens and references](tokens-and-references.md).

Theme names and property names are compared without case, `-` and `_`.
`seed-color`, `seedColor` and `seed_color` are the same key, and `Ocean-Night`
and `ocean_night` are the same theme.

## Choosing and switching at run time

The `ThemeSelection` bean holds the choice. A settings page calls `select`
and the whole app changes at once.

```dart
selection.select('ocean');    // a theme
selection.select('system');   // follow the device again
```

The choice is kept between runs (`remember`, `true` by default): the
`ThemeChoiceStore` bean writes it at each choice (`FileThemeChoiceStore`,
the app's files, IndexedDB in a browser; declare your own bean to keep it
elsewhere), and `ThemeChoiceRestore`, a splash task, shows it again while
the splash shows, so a reload does not flash `active` first. A kept theme
that no longer exists is ignored; `remember: false` keeps nothing.

Themes can also arrive at run time:
`themes.loadYaml(yaml)` adds YAML from a server, and a theme can be
downloaded from a URL by itself (see [properties](properties.md#a-theme-from-a-url)).

## Read the theme in Dart

Material widgets read Flutter's own `Theme.of(context)`. For everything
Material has no place for (spacing, your tokens, the `code` text style,
backgrounds, styles for your own widgets), and for apps of any type, use
`SpringTheme.of(context)`:

```dart
final theme = SpringTheme.of(context);
Container(
  padding: EdgeInsets.all(theme.space('m')),
  color: theme.colorScheme.surfaceContainer,
  child: Text(isbn, style: theme.textStyle('code')),
);
```

### Typed keys: `context.theme`

The build generator reads your properties and writes
`lib/spring_gen/theme.spring.dart`. From it, `context.theme` has a getter for
every key you declare, so a renamed property is a compile error and not a
surprise at run time:

```dart
context.theme.colors.surfaceContainerLow;   // Color
context.theme.spacing.m;                    // double
context.theme.typography.titleLarge;        // TextStyle
context.theme.tokens.brand.accent;          // Color
context.theme.styles.neonChip;              // AppStyleNeonChip, for ThemeStates
context.theme.motion.fast;                  // Duration
context.theme.motion.curves.out;            // Curve
context.theme.animations.borderSpin;        // AnimationSpec
context.theme.background;                   // ThemeBackgroundData?
AppThemes.ocean;                            // 'ocean', for ThemeSelection.select
```

Run `dart run build_runner build` after you add a key. The getters read the
theme that is shown when they are called, so a theme switch gives the new
values and the widget rebuilds. Only keys you declare are generated; the
Material roles computed from the seed stay in `Theme.of(context).colorScheme`.
Import `spring_gen/main.spring.dart` to use them.

Names become Dart names: `-` and `_` start a new word (`surface-container-low`
is `surfaceContainerLow`), a leading digit gets a `$` in front (`2xl` is
`$2xl`) and a Dart keyword gets a `$` behind (`default` is `default$`). Two
keys that give the same Dart name fail the build.

## Pages of this reference

| Page | What it covers |
|---|---|
| [Properties](properties.md) | Every property of `spring.flutter.theme` and of a theme: `active`, `extends`, `brightness`, `seed-color`, `scheme-variant`, `contrast`, `visual-density`, `tap-target-size`, `splash`, and a theme downloaded from a URL |
| [Colors](colors.md) | The 46 Material 3 color roles, the seed and its variants, contrast, named colors, hex forms, `alpha` and `mix` |
| [Typography](typography.md) | The 15 text roles and `code`, every style key, fonts from assets |
| [Shape, spacing and elevation](shape-spacing-elevation.md) | The corner scale, spacing names, elevation levels and how components use them |
| [Tokens and references](tokens-and-references.md) | Your own values, how a value is typed, `$` references and `$$` |
| [Styles and states](styles-and-states.md) | A look per state for your own widgets, state precedence, `ThemeStates`, per-state values of components, and `MarkdownView`'s look (`styles.code`, `heading`, `table`, `callout`, `link`) and code languages (`syntax`) |
| [Motion and animations](motion-and-animations.md) | Durations, curves, page transitions, `animations.*`, reduced motion |
| [Background](background.md) | A color, an image, an overlay and a slow animation behind every screen |
| [Loaders and the splash](loaders.md) | Spinners, dots, bars, skeletons, loaders of your own and the splash shown while the app starts |
| [Images](images.md) | Images from assets or the network, with a cache, a refresh, a checksum and a fallback |
| [Cupertino](cupertino.md) | `CupertinoThemeData` for iOS-style apps |
| [Components](components/index.md) | One page per Material component, with every property it accepts |

## See also

- [Configuration reference](../../configuration.md): config files, profiles,
  imports and placeholders, which all work inside a theme.
- [Flutter testing](../../flutter-testing.md): choosing a theme in a widget
  test and golden files.
