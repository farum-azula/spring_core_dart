---
title: "Cupertino theme — Spring for Dart"
description: "Set CupertinoThemeData from YAML: primary color, backgrounds, selection handles and the eight text styles for iOS-style Flutter apps."
slug: /docs/flutter/theme/cupertino
section: Flutter / Theme
order: 11
keywords: [flutter, theme, yaml, cupertino, ios, CupertinoThemeData, text theme, primary color, CupertinoApp]
---

# Cupertino theme

With `spring_boot_starter_flutter_cupertino` the app is a `CupertinoApp`
(`spring.flutter.app.type: cupertino`, deduced when it is the one design
starter and needed when the Material starter is in the application too), and it
uses a `CupertinoThemeData` made from the same theme as the Material one. The
`cupertino` section adjusts it. Without it, iOS's own look is kept, with the
theme's primary color where iOS uses its blue.

```yaml
spring:
  flutter:
    app:
      type: cupertino
    theme:
      seed-color: '#0057B8'
      typography:
        font-family: Inter
      cupertino:
        primary-color: $colors.secondary
        primary-contrasting-color: white
        scaffold-background-color: '#F2F2F7'
        bar-background-color: $colors.surface-container
        selection-handle-color: $colors.primary
        apply-theme-to-all: false
        text-theme:
          primary-color: $colors.primary
          nav-title-text-style:
            style: title-large
            weight: 600
          nav-large-title-text-style: display-small
          action-text-style:
            color: $colors.primary
```

## Properties

`cupertino` is a section of the theme itself, at `spring.flutter.theme.cupertino`
(or `themes.<name>.cupertino`). It is not under `components`. Colors are
the same as in components: `#RRGGBB`, a `Colors` name, a reference to a role
(`$colors.primary`) or an object `{ color, mix, alpha }`.
Any other key stops the start and lists the valid ones.

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `cupertino.primary-color` | color | a color, or `$colors.<role>` | `colors.primary` if you set it, else the seed palette's primary if there is a `seed-color`, else iOS blue | The accent: actions, links, active controls, the cursor |
| `cupertino.primary-contrasting-color` | color | a color, or `$colors.<role>` | iOS's | The color shown on `primary-color`, such as the label of a filled button |
| `cupertino.scaffold-background-color` | color | a color, or `$colors.<role>` | the theme's `colors.surface` if you set it; transparent if the theme has a [background](background.md); else iOS's | The page background |
| `cupertino.bar-background-color` | color | a color, or `$colors.<role>` | `components.app-bar.background-color`, else iOS's | The background of navigation bars and tab bars |
| `cupertino.selection-handle-color` | color | a color, or `$colors.<role>` | iOS's | The color of the text selection handles |
| `cupertino.apply-theme-to-all` | bool | `true`, `false` | Flutter's (`false`) | Whether Cupertino widgets that use iOS's fixed colors by default take the theme's instead. Today only `CupertinoSwitch` (and `Switch.adaptive`): on, it is the primary color instead of iOS green (Flutter's `CupertinoThemeData.applyThemeToAll`) |
| `cupertino.text-theme.primary-color` | color | a color, or `$colors.<role>` | `cupertino.primary-color` | The primary color used by the text styles that carry it (actions, nav actions) |
| `cupertino.text-theme.text-style` | text style | see below | iOS's body style | The default style of text |
| `cupertino.text-theme.action-text-style` | text style | see below | iOS's | Text of actions and buttons |
| `cupertino.text-theme.tab-label-text-style` | text style | see below | iOS's | Labels of tab bars |
| `cupertino.text-theme.nav-title-text-style` | text style | see below | iOS's | The title of a navigation bar |
| `cupertino.text-theme.nav-large-title-text-style` | text style | see below | iOS's | The large title of a navigation bar |
| `cupertino.text-theme.nav-action-text-style` | text style | see below | iOS's | Buttons in a navigation bar |
| `cupertino.text-theme.picker-text-style` | text style | see below | iOS's | The items of a picker |
| `cupertino.text-theme.date-time-picker-text-style` | text style | see below | iOS's | The items of a date and time picker |

The theme's `brightness` becomes the Cupertino theme's brightness.

### Text styles

Each `text-theme` style is written in one of two ways:

```yaml
spring:
  flutter:
    theme:
      cupertino:
        text-theme:
          nav-title-text-style: title-large          # one of the theme's styles
          action-text-style:                         # or a map
            style: label-large                       # the base (optional)
            color: $colors.primary
            font-family: Inter
            size: 17
            weight: semibold
            height: 1.3
            letter-spacing: -0.4
            italic: false
            decoration: none
```

| Key | Type | Values | What it does |
|---|---|---|---|
| a name | text | `display-large` ... `label-small`, or `code` | Uses that style of the theme's [typography](typography.md) |
| `style` | text | the same names | The base the other keys change. Without it the base is iOS's own style for that slot |
| `color` | color | a color, or `$colors.<role>` | Text color |
| `font-family` | text | a family | Font |
| `size` | number | logical pixels | Font size |
| `weight` | number or name | `100`..`900`, `bold`, `semibold` ... | Font weight |
| `height` | number | multiple of the size | Line height |
| `letter-spacing` | number | logical pixels | Space between letters |
| `italic` | bool | `true`, `false` | Italic or upright |
| `decoration` | enum | `none`, `underline`, `line-through`, `overline` | Text decoration |

## How the theme is built

1. **Colors.** `primary-color` is your `cupertino.primary-color`, else
   `colors.primary`, else the primary of the palette made from your
   `seed-color`, else iOS blue. `scaffold-background-color` and
   `bar-background-color` follow the table above.
2. **Text styles.** The eight styles start from iOS's own, with the primary
   color in the ones that carry it. If the theme sets a `typography`
   (`font-family`, `font-family-fallback` or any style), each iOS style also
   takes the font, and the size, weight, height and letter spacing of a
   matching theme style:

   | Cupertino style | Takes from the theme |
   |---|---|
   | `text-style` | `body-large` |
   | `action-text-style` | `label-large` |
   | `tab-label-text-style` | `label-small` |
   | `nav-title-text-style` | `title-large` |
   | `nav-large-title-text-style` | `display-small` |
   | `nav-action-text-style` | `label-large` |
   | `picker-text-style` | `body-large` |
   | `date-time-picker-text-style` | `body-large` |

   A style you write under `cupertino.text-theme` wins over this. Without a
   `typography` and without `text-theme`, the text theme is iOS's untouched.
   A style named after a theme style (`nav-large-title-text-style:
   display-small`) is that style as the theme sets it: its font and what
   `typography.display-small` says, not the size of the Material 3 type
   scale; give it a `size` under `typography` when the large title should
   be large. A style written as a map without `style` starts from iOS's
   own style, so it keeps iOS's font unless the map names one.
3. **Customizing in code.** A bean that implements `CupertinoThemeCustomizer`
   changes every Cupertino theme after it is made; a `CupertinoThemeData`
   bean replaces it.

```dart
@Component()
class SurfaceBars implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(CupertinoThemeData theme, SpringThemeData spring) =>
      theme.copyWith(barBackgroundColor: spring.colorScheme.surface);
}
```

## Differences from Material

- **Page transitions.** A `CupertinoApp` routed by the navigation starter
  follows `motion.page-transition` like any app: `platform` by default,
  the iOS slide with the swipe-back gesture, as a `CupertinoApp` of
  Flutter's has it; `none` switches pages at once. Without the router, `Navigator.push` with a `CupertinoPageRoute`
  keeps Cupertino's own slide.
- **Components.** `components.*` configure Material's `ThemeData`. A
  `CupertinoApp` shows Cupertino widgets, which read only `cupertino.*`
  (and `components.app-bar.background-color`, used as the default bar color).
- **Light and dark.** Cupertino follows the theme shown: with `active:
  system`, a device switching to dark mode shows the `system-dark` theme's
  Cupertino theme.
- **Background.** A theme with a [background](background.md) makes the
  Cupertino page transparent so the background shows.

## See also

- [Typography](typography.md): the text styles Cupertino takes from
- [Colors](colors.md)
- [Background](background.md)
- [Properties](properties.md)
