# spring_boot_starter_flutter_signals (first version built)

On `signals_core`: an allowed exception to the dependency policy, only in
this starter. Part of the [Flutter plan](spring_boot_starter_flutter.md).

The first version is in the repository
(`spring_boot_starter_flutter_signals`; its README is the reference, its
`example/example.dart` the app the tests run). It goes to pub.dev with the
family's next version.

## Built (November 2026)

| Part | What is there |
|---|---|
| Annotations | `@Signal()` on a field, `@Computed()` on a getter or a method without parameters, `@Effect()` on a method; on the members of a component only |
| Plain fields | No wrapper type and no `.value`: the bean's proxy follows the reads and the assignments |
| Collections | A `List`, `Set`, `Map` or `Queue` field is handed out as one that tells of a change in place (`FollowedList` and the others), typed by the element types the generator writes |
| Asynchronous | A `@Computed` getter returning a `Future` or a `Stream`: one request until what it read changes; `books.state` (`AsyncValue`), `refresh()`, `reload()`; a late answer of an older request is dropped |
| One change for a method | Every method of such a bean is a batch; `batch` and `untracked` are exported |
| Widgets | `SpringStatelessWidget` and `SpringState` built again for the fields their `build` read (the Flutter starter's new `WidgetBuildTracker`); `Watch`; `AsyncView` |
| Lifetime | The state ends with the bean; its own `@PreDestroy` still reads its fields |
| Build checks | A misplaced annotation, a private or final field, a class that cannot be extended fail the build |
| Debugging | The State tab of the debug panel; `@Signal(hidden: true)`; the logger `spring.flutter.signals` |

How it is made, which is not what the plan below expected: the state is
**advice** (an interceptor on the bean's proxy), not code the generator
writes for each field. That took three things in the framework, each
useful apart from signals:

- `@ProxyTargetClass()` on an annotation class (`spring_core_dart`): a
  bean with such a member gets a proxy that extends its class, with every
  member kept and the calls the bean makes on itself seen by the advice
  that asks for them (`SelfCallInterceptor`, `adviseSelfCalls`). Other
  advice and other beans are as before.
- `TypeCapture` and `MethodSignature.returnTypeArguments`: the element
  type of `List<Book>` written by the generator, so advice can make a
  typed collection.
- `WidgetBuildTracker` (`spring_boot_starter_flutter`): how a state
  library joins the Spring widgets.

Found while building it:

- **The package's own collection signals do not tell of a change made
  inside a batch** (`ListSignal.add` inside `batch()`, signals_core
  7.0.0; seen in an isolated test). Every method of a bean is a batch
  here, so the starter has collections of its own over a counter. To
  report upstream.
- **An asynchronous getter's type arrives without its arguments** in the
  signature (`Future`), so its state is kept untyped and given its type
  where it is read (`books.state` on a `Future<List<Book>>`).
- **The bean's own calls** were first given to every advice on it
  (`@Cacheable` applied to a call from inside the bean, unlike
  everywhere else). Changed after the owner's question about a guarded
  value (below): only the advice that follows state sees them.

Checked after the owner asked what happens with the annotations where
they do not belong (a repository, and the rest):

- **Where no proxy follows them the build fails** instead of doing
  nothing: a class that is no bean (a widget, a `State`), the class a
  `@Bean` method returns, a `@Configuration` or `@ConfigurationProperties`
  class, an `@Aspect` or a post-processor, a repository or an HTTP client
  (their methods are generated), an enum, an extension, the top level,
  an abstract member, an override without the annotation, a member the
  proxy cannot override. An abstract class and a mixin may declare them.
- **Found on the way and fixed**: an error from a computed value or an
  effect came wrapped in the signals package's own exception; a `late`
  field read before its first assignment left a computed value that
  never computed again; a setter that is no field was not one change; a
  field declared as a collection class of its own (`HashSet`) would have
  been handed out as the follower, which is not one; the State tab
  failed on a computed value that throws; the states of prototypes were
  kept for ever.
- **Beside other advice** (asked by the owner: a signal with a
  transaction). Tried with an aspect standing for the transaction, not
  with the data starter itself: both run in one chain; a rollback does
  not undo the fields (said in the
  README); the advice of the default order ran for every read of a kept
  computed value (a transaction per read), so the signals' advice got an
  order of its own, one step before the default. Method security has
  an earlier order (`methodSecurityAdvisorOrder`), so `@PreAuthorize` on
  a `@Computed` member is checked for every read of the kept value; an
  ordered aspect stands for it in the starter's test.
- **A guarded value over a plain field, and a guarded effect** (asked by
  the owner). Found: the guard ran on the bean's own read too, so a
  value made from the guarded one failed for whoever happened to
  compute it; a run that was refused before it read anything followed
  nothing from then on (an effect dead without a word, a value that kept
  the refusal for every later caller); an effect's failure was thrown at
  whoever assigned the field, an anonymous caller too. Now: other advice
  skips the bean's own calls, as in Spring; a run that fails goes on
  following what the last good run followed (`FollowKeeper`); a computed
  value's failure is not kept; an effect's later failure is reported,
  not thrown (the owner has not decided this last one: it follows
  `ChangeNotifier` and MobX, and is one place to change back).
- **What it costs** (the owner, November 2026: frames must not suffer
  when everything is used together; more generated code is accepted for
  speed and for less to declare). Measured in a debug build
  (`spring_boot_starter_flutter_signals/benchmark`, Apple M5): a read of
  a `@Signal` field 45 ns against 3 for a plain one, a kept `@Computed`
  53, an assignment nobody reads 68, the build of a Spring widget 230 ns
  more than without the starter. Nearly all of a read was the proxy's
  call path, not the signals: it was 124 ns before the path was made
  shorter (in the core, for every advised member). 200 widgets built in
  one frame with five reads each are about 0.1 ms of 16. **Owed: the
  frames of an application with every starter at once, in a release
  build, on a phone and in a browser**; none of this was measured there.
- **Not verified**: a bean with such members in a library package used
  by an application (its proxy is generated in the library, as for any
  subclass proxy; no test of the two together); an application whose
  build leaves the starter's auto-configuration out has such beans made
  and nothing followed, without a word.

Not built, though talked through (below): a build check for a field read
after an `await` in an asynchronous `@Computed` getter; which fields a
computed value or an effect depends on, and which widget was built for
which field, in the State tab; changes on the debug timeline; state kept
between runs; a history with undo; the state of a running action.

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
