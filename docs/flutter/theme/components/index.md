---
title: "Component themes in YAML — Spring for Dart"
description: "Every Flutter Material component you can style from YAML: app bar, buttons, cards, dialogs, inputs and more, with all their properties."
slug: /docs/flutter/theme/components
section: Flutter / Theme / Components
order: 0
keywords: [flutter, theme, yaml, components, material, widgets]
---

# Component themes in YAML

Each Material component has a theme in Flutter: the look every widget of that kind starts from. Spring for Dart reads them from `spring.flutter.theme.components.<name>`, with the same names and values as Flutter, in kebab case (`background-color` for `backgroundColor`). Pick a component below to see all its properties, what they do and an example.

| Component | Flutter class | What it styles | Properties |
|---|---|---|---|
| [App bar](app-bar.md) | `AppBarTheme` | The bar at the top of a screen, with a title and actions. | 17 |
| [Badge](badge.md) | `BadgeThemeData` | A small dot or number shown on top of another widget, such as an unread count on an icon. | 8 |
| [Banner](banner.md) | `MaterialBannerThemeData` | A message bar at the top of a screen with actions to dismiss or follow it. | 8 |
| [Bottom app bar](bottom-app-bar.md) | `BottomAppBarThemeData` | The bar at the bottom of a screen that can hold actions and a floating action button. | 6 |
| [Bottom navigation bar](bottom-navigation-bar.md) | `BottomNavigationBarThemeData` | The bar at the bottom of a screen to switch between a few top-level pages. | 14 |
| [Bottom sheet](bottom-sheet.md) | `BottomSheetThemeData` | A panel that slides up from the bottom of the screen. | 13 |
| [Button](button.md) | `ButtonStyle` | The settings every button shares: elevated, filled, outlined and text buttons start from them. | 25 |
| [Elevated button](elevated-button.md) | `ElevatedButtonThemeData` | A raised button with a shadow. | 25 |
| [Filled button](filled-button.md) | `FilledButtonThemeData` | A button with a solid fill, for the main action. | 25 |
| [Outlined button](outlined-button.md) | `OutlinedButtonThemeData` | A button with a border and no fill. | 25 |
| [Text button](text-button.md) | `TextButtonThemeData` | A flat button with no border and no fill. | 25 |
| [Icon button](icon-button.md) | `IconButtonThemeData` | A button that shows only an icon. | 25 |
| [Segmented button](segmented-button.md) | `SegmentedButtonThemeData` | A row of connected buttons, one or more of them selected. | 25 |
| [Menu button](menu-button.md) | `MenuButtonThemeData` | The buttons inside a menu or a menu bar. | 25 |
| [Toggle buttons](toggle-buttons.md) | `ToggleButtonsThemeData` | A row of buttons that can each be switched on or off. | 15 |
| [Floating action button](floating-action-button.md) | `FloatingActionButtonThemeData` | The round button floating over the content for the main action of a screen. | 21 |
| [Card](card.md) | `CardThemeData` | A rounded panel with a shadow that groups related content. | 7 |
| [Carousel view](carousel-view.md) | `CarouselViewThemeData` | A scrolling row of large items that stretch and shrink as you swipe. | 6 |
| [Checkbox](checkbox.md) | `CheckboxThemeData` | A box that is ticked or cleared. | 9 |
| [Chip](chip.md) | `ChipThemeData` | A small pill for a tag, a filter, a choice or an input. | 22 |
| [Data table](data-table.md) | `DataTableThemeData` | A table of rows and columns of data. | 15 |
| [Date picker](date-picker.md) | `DatePickerThemeData` | The dialog to pick a day or a range of days. | 125 |
| [Dialog](dialog.md) | `DialogThemeData` | A window that appears over the content and asks for a decision. | 14 |
| [Divider](divider.md) | `DividerThemeData` | A thin line between two pieces of content. | 6 |
| [Drawer](drawer.md) | `DrawerThemeData` | A panel that slides in from the side of the screen. | 9 |
| [Dropdown menu](dropdown-menu.md) | `DropdownMenuThemeData` | A text field with a menu of choices. | 53 |
| [Expansion tile](expansion-tile.md) | `ExpansionTileThemeData` | A list row that opens to show more content. | 13 |
| [Icon](icon.md) | `IconThemeData` | The default look of every icon. | 7 |
| [Primary icon](primary-icon.md) | `IconThemeData` | The default look of icons drawn on the primary color. | 7 |
| [Input](input.md) | `InputDecorationThemeData` | Text fields: the border, fill, labels and hints. | 38 |
| [List tile](list-tile.md) | `ListTileThemeData` | A row in a list with a title, a subtitle and icons. | 22 |
| [Menu](menu.md) | `MenuThemeData` | The panel of a menu that opens from a button. | 13 |
| [Menu bar](menu-bar.md) | `MenuBarThemeData` | A horizontal bar of menus, as at the top of a desktop window. | 13 |
| [Navigation bar](navigation-bar.md) | `NavigationBarThemeData` | The Material 3 bar at the bottom of the screen to switch between pages. | 12 |
| [Navigation drawer](navigation-drawer.md) | `NavigationDrawerThemeData` | The Material 3 side panel with the destinations of the app. | 10 |
| [Navigation rail](navigation-rail.md) | `NavigationRailThemeData` | A narrow bar at the side of the screen to switch between pages. | 13 |
| [Popup menu](popup-menu.md) | `PopupMenuThemeData` | The small menu that pops up from a button or a tap. | 13 |
| [Progress indicator](progress-indicator.md) | `ProgressIndicatorThemeData` | The circular and linear bars that show progress or waiting. | 14 |
| [Radio](radio.md) | `RadioThemeData` | A round button to pick one option out of several. | 9 |
| [Scrollbar](scrollbar.md) | `ScrollbarThemeData` | The bar that shows where you are in a scrolling list. | 11 |
| [Search bar](search-bar.md) | `SearchBarThemeData` | A field to type a search, with a leading icon and actions. | 12 |
| [Search view](search-view.md) | `SearchViewThemeData` | The full-screen view with suggestions that opens from a search bar. | 13 |
| [Slider](slider.md) | `SliderThemeData` | A control to pick a value by dragging a thumb along a track. | 25 |
| [Snack bar](snack-bar.md) | `SnackBarThemeData` | A short message that appears at the bottom of the screen. | 15 |
| [Switch](switch.md) | `SwitchThemeData` | An on and off toggle. | 9 |
| [Tab bar](tab-bar.md) | `TabBarThemeData` | The row of tabs to switch between pages of content. | 16 |
| [Text selection](text-selection.md) | `TextSelectionThemeData` | The cursor, the highlight and the handles when you select text. | 3 |
| [Time picker](time-picker.md) | `TimePickerThemeData` | The dialog to pick a time of day. | 109 |
| [Tooltip](tooltip.md) | `TooltipThemeData` | The small label that appears when you hover or long-press something. | 16 |
| [Cupertino](../cupertino.md) | `CupertinoThemeData` | The iOS look of Cupertino widgets. It is read from its own root, not below components. | 15 |

## See also

- [Theme overview](../index.md)
- [Root theme properties](../properties.md)
- [Styles and states](../styles-and-states.md)
- [Colors](../colors.md)
- [Cupertino](../cupertino.md)

---

*Property descriptions are adapted from the documentation of the Flutter SDK (3.47.7), copyright The Flutter Authors, BSD 3-Clause license.*
