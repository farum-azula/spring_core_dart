---
title: "Text selection theme in YAML — Spring for Dart"
description: "Style the text selection in YAML: 3 properties such as cursor-color, selection-color and selection-handle-color, set under text-selection."
slug: /docs/flutter/theme/components/text-selection
section: Flutter / Theme / Components
order: 47
keywords: [flutter, theme, yaml, text selection, TextSelectionThemeData]
---

# Text selection theme in YAML

The cursor, the highlight and the handles when you select text. It configures Flutter's `TextSelectionThemeData`. Set it under `spring.flutter.theme.components.text-selection`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.text-selection`. The Material starter, `spring_boot_starter_flutter_material`, reads it: an app without that package in its dependencies shows nothing of it.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        text-selection:
          cursor-color: $colors.primary
          selection-color: $colors.on-primary
          selection-handle-color: $colors.surface
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field |
|---|---|---|---|---|---|
| `cursor-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the cursor in the text field. The cursor indicates the current location of text insertion point in the field. | `TextSelectionThemeData.cursorColor` |
| `selection-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The background color of selected text. | `TextSelectionThemeData.selectionColor` |
| `selection-handle-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the selection handles on the text field. Selection handles are used to indicate the bounds of the selected text, or as a handle to drag the cursor to a new location in the text. | `TextSelectionThemeData.selectionHandleColor` |

## Read it in Dart

The Material starter sets `ThemeData.textSelectionTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).textSelectionTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.50.0), copyright The Flutter Authors, BSD 3-Clause license.*
