# spring_boot_starter_flutter_signals: example

A Flutter app with reactive state in its beans.
[`example.dart`](example.dart) is the whole app; the generator writes
`spring_gen/example.spring.dart` (`dart run build_runner build`).

- `Basket` has two `@Signal` fields (a list and a coupon), a `@Computed`
  total and an `@Effect` that saves it. `add` changes the list in place;
  `clear` changes two things and tells its readers once.
- `Catalog` has asynchronous state: `books` (a `Future`) is loaded once
  and again when `genre` is assigned, and `price` (a `Stream`) gives its
  last event.
- `Shop` shows the catalog with an `AsyncView` and the total with a
  `Watch`; `CouponLabel` is a Spring widget that follows its own `build`.

```yaml
dependencies:
  spring_boot_starter_flutter_signals: ^0.8.0
```

The package's tests run this app as generated
(`test/signals_test.dart`, `test/signal_widgets_test.dart`).
