# spring_boot_starter_flutter_navigation: example

A Flutter app with tabs, a book screen, a payment over the tabs and a
not-found screen. [`example.dart`](example.dart) is the whole app; the
generator writes `spring_gen/example.spring.dart`
(`dart run build_runner build`).

- `MainTabs` is a shell (`@RouteShell`): the catalog and the profile
  tabs, each with its own stack.
- `BookPage` is at `/catalog/books/{isbn}`, under the catalog branch, so
  it opens in the tabs with the catalog below it. It reads the ISBN, the
  `page` parameter (an `int`) and the `BookSummary` passed along through
  the generated `BookPageRoute` constants, and turns pages with
  `replaceParams`.
- `CheckoutPage` opens over the tabs with `push` and returns whether it
  was paid with `pop(true)`.
- `lib/resources/application.properties` starts the app at `/catalog`
  (`spring.flutter.navigation.initial`).

The app is a `MaterialApp` (`spring.flutter.app.type=material`) and its
screens use Material's widgets, so next to this package it depends on the
Material starter and on `material_ui`:

```yaml
dependencies:
  spring_boot_starter_flutter_navigation: ^0.7.4
  spring_boot_starter_flutter_material: ^0.7.4
  material_ui: ^1.11.0
```

The navigation itself needs no design library: an app of type `widgets`
or `cupertino` uses it the same way.
