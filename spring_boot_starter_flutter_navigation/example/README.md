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
