# flutter_spring_signals (planned)

On `signals` — an allowed exception to the dependency policy, only in this
starter. Part of the [Flutter plan](flutter_spring.md).

## Reactive state in beans

Reactive state in beans. Annotations on fields; the generator writes the
signals under the hood, so the code keeps plain fields — no `signal(...)`,
no `.value`. Reads are tracked like signals track them: a widget rebuilds
only when a field it read in `build` changes, a `@Computed` getter is cached
until one of the fields it read changes, an `@Effect` method runs again when
its fields change.

```dart
@Component()
class Basket {
  Basket(this.catalog, this.storage);   // ordinary injection
  final CatalogClient catalog;
  final BasketStorage storage;

  @Signal()
  List<Book> items = const [];

  @Signal()
  String? coupon;

  @Computed()                           // cached; recomputed when items or coupon change
  double get total =>
      items.fold(0.0, (sum, b) => sum + b.price) * (coupon == null ? 1 : 0.9);

  @Effect()                             // runs again whenever items changes
  void save() => storage.write(items);

  Future<void> add(String isbn) async =>
      items = [...items, await catalog.find(isbn)];
}

// Rebuilds when total changes, not when other fields of Basket do
Watch((context) => Text('${context.basket.total} ₽'));
```
Like `mobx_codegen`, the generator overrides the annotated fields with
signal-backed getters and setters, so reads inside the bean's own
methods are tracked too. Everything else stays Spring: injection, AOP on
the methods (`@Cacheable`, `@Retryable`), the bean's scope as the state's
lifetime (the app, a route, a widget), events for what spans several
beans, and tests with `BeanOverride`. A change is an assignment
(`items = [...items, book]`); collections changed in place are not seen,
as with signals.
