---
title: "Bottom sheet theme in YAML — Spring for Dart"
description: "Style the bottom sheet in YAML: 13 properties such as background-color, surface-tint-color and elevation, set under bottom-sheet."
slug: /docs/flutter/theme/components/bottom-sheet
section: Flutter / Theme / Components
order: 6
keywords: [flutter, theme, yaml, bottom sheet, BottomSheetThemeData]
---

# Bottom sheet theme in YAML

A panel that slides up from the bottom of the screen. It configures Flutter's `BottomSheetThemeData`. Set it under `spring.flutter.theme.components.bottom-sheet`. You can also set it inside a named theme, under `spring.flutter.theme.themes.<name>.components.bottom-sheet`.

## Example

```yaml
spring:
  flutter:
    theme:
      components:
        bottom-sheet:
          background-color: $colors.primary
          elevation: level2
          shape: large
          show-drag-handle: true
          drag-handle-size: { width: 48, height: 48 }
          clip-behavior: none
```

## Properties

Every property is optional. One you leave out keeps Flutter's value.

| Property | Type | Values | States | What it does | Flutter field | Default |
|---|---|---|---|---|---|---|
| `background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The bottom sheet's background color. Defines the bottom sheet's color. | `BottomSheetThemeData.backgroundColor` | Flutter's Material 3 default |
| `surface-tint-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The surface tint color of the sheet. Material 3 does not need it. | `BottomSheetThemeData.surfaceTintColor` | Flutter's Material 3 default |
| `elevation` | elevation | `level0` to `level5`, or a number | no | The z-coordinate at which to place this material relative to its parent. This controls the size of the shadow below the material. | `BottomSheetThemeData.elevation` | Flutter's Material 3 default |
| `modal-background-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | Value for background color when the Bottom sheet is presented as a modal bottom sheet. | `BottomSheetThemeData.modalBackgroundColor` | Flutter's Material 3 default |
| `modal-barrier-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the dimmed layer behind a modal bottom sheet. | `BottomSheetThemeData.modalBarrierColor` | Flutter's Material 3 default |
| `shadow-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The color of the shadow below the sheet. | `BottomSheetThemeData.shadowColor` | Flutter's Material 3 default |
| `modal-elevation` | elevation | `level0` to `level5`, or a number | no | Value for elevation when the Bottom sheet is presented as a modal bottom sheet. | `BottomSheetThemeData.modalElevation` | Flutter's Material 3 default |
| `shape` | shape | a token (`small`), a radius, or a map | no | The shape of the bottom sheet. Defines the bottom sheet's shape. | `BottomSheetThemeData.shape` | Flutter's Material 3 default |
| `show-drag-handle` | true / false | `true`, `false` | no | Specifies whether a drag handle is shown. The drag handle appears at the top of the bottom sheet. | `BottomSheetThemeData.showDragHandle` | Flutter default: false |
| `drag-handle-color` | color | `#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, mix, alpha }` | no | The bottom sheet drag handle's color. | `BottomSheetThemeData.dragHandleColor` | Flutter's Material 3 default |
| `drag-handle-size` | size | `width, height`, one number, or a map | no | The size of the drag handle shown at the top of the sheet. | `BottomSheetThemeData.dragHandleSize` | Flutter's Material 3 default |
| `clip-behavior` | choice | `none`, `hard-edge`, `anti-alias`, `anti-alias-with-save-layer` | no | The content will be clipped (or not) according to this option. Defines the bottom sheet's clip behavior. | `BottomSheetThemeData.clipBehavior` | Flutter's Material 3 default |
| `constraints` | constraints | a map of `min-width`, `max-width`, `min-height`, `max-height` | no | Constrains the size of the bottom sheet. | `BottomSheetThemeData.constraints` | Flutter's Material 3 default |

## Read it in Dart

The starter sets `ThemeData.bottomSheetTheme` from these properties. In a widget, read the result with:

```dart
final theme = Theme.of(context).bottomSheetTheme;
```

## See also

- [All component themes](index.md)
- [Theme overview](../index.md)
- [Colors](../colors.md)
- [Shape, spacing and elevation](../shape-spacing-elevation.md)
- [Styles and states](../styles-and-states.md)
- [Tokens and references](../tokens-and-references.md)
- [Root theme properties](../properties.md)
- [Configuration reference](../../../configuration.md) (all properties of the framework)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
