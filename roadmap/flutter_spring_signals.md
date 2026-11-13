# flutter_spring_signals (planned)

On `signals` — an allowed exception to the dependency policy, only in this
starter. Part of the [Flutter plan](spring_boot_starter_flutter.md).

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

## Disposal (the owner, November 2026)

The generator writes the disposal too: when the bean is destroyed, every
signal it has is disposed, with no code in the bean. The generated
subclass adds it to the bean's destroy (as a `@PreDestroy` of its own, run
with the bean's): the `@Effect` methods are stopped first, then the
`@Computed` values, then the `@Signal` fields, so nothing runs against a
value already disposed. A `@PreDestroy` method of the bean itself runs
before, while its fields still work.

To check when it is built: a bean whose scope does not call destroy (a
prototype made by hand) leaves its signals to whoever made it, so the
generated class should also offer the disposal as a method.

## Only in components (the owner, November 2026)

`@Signal`, `@Computed` and `@Effect` are for fields and methods of a
component (`@Component`, `@Service` and the like). That is enough: a
component is a singleton unless it says otherwise, so its state is the
app's and is reached from anywhere, by injection or `context.<bean>`.
Nothing is planned for a bean made in a `@Configuration` class (a `@Bean`
method returning a class with signals, a signal as a bean of its own):
the generator refuses the annotations there with a message that says to
make the class a component.

## Beside ChangeNotifier, not instead of it (the owner, November 2026)

`ChangeNotifier` stays for good: it is Flutter's own tool, what
controllers, animations and other packages' widgets are built on, and
`@ChangeNotifierComponent` / `@NotifyListeners` stay as they are. Signals
are a second way, for a bean whose fields change apart from each other.

## A sketch of the rest (talked through with the owner, not decided)

- **The field's type picks the signal.** `@Signal()` on a plain field is
  a `signal`; on a `List`, `Set`, `Map` or `Queue` it is the package's
  collection signal, so a change in place (`items.add(book)`) is seen
  too, which lifts the "an assignment only" rule above.
- **`@Computed` and `@Effect` on methods.** `@Effect` on a method without
  arguments or a result, first run after the bean is made. `@Computed` on
  a getter or a method without arguments. With arguments it is a family
  by argument (`computedContainer`) and close to `@Cacheable`: refused by
  the build in the first version. Both must be synchronous: tracking ends
  at the first `await`.
- **What Spring already has instead of the package's functions**: a
  public method of a bean as one batch (advice around it), the bean's
  scope instead of a family by argument, `@Scheduled` instead of a timer
  signal, `@EventListener` or a subscription instead of `connect`.
- **Spring widgets track by field.** `SpringStatelessWidget` and
  `SpringState` already subscribe by what `build` read; `Watch` is for
  ordinary widgets.
- **Asynchronous state** is the common need left open: a field of
  `AsyncState<T>` filled by a method (a fourth annotation, with its own
  rules for when to run and retry). The second step, not the first.
- **Later**: a field kept between runs (the package's persisted signals
  over the Flutter starter's store), history with undo, server data as a
  cache with invalidation, forms.
- **Debugging**: the generator names every signal by its bean and field;
  a tab of the debug panel with the values by bean, how often each
  changes, what a computed value depends on, which widget rebuilt for
  which field; changes on the debug timeline; a logger
  `spring.flutter.signals`. A module of its own, out of release builds.
  To check: the package has one observer for the process, and values
  need a length limit and a way to hide a field (a token).
