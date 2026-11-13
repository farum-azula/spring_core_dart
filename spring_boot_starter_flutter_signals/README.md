# spring_boot_starter_flutter_signals

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-flutter-signals](https://farum-azula.org/components/spring-boot-starter-flutter-signals)

Reactive state in the beans of Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter):
three annotations on a component, and plain fields.

- **`@Signal()`** on a field: what read it is told when it is assigned.
- **`@Computed()`** on a getter: a value kept until what it read
  changes; from a `Future` or a `Stream` too, with its state.
- **`@Effect()`** on a method: run again when what it read changes.

No wrapper types and no `.value`: the bean's generated proxy follows the
reads and the assignments. A widget is built again only for the fields
its `build` read. It is on
[`signals_core`](https://pub.dev/packages/signals_core), and beside
`ChangeNotifier`, not instead of it: `@ChangeNotifierComponent` and
`@NotifyListeners` stay as they are.

## Contents

- [Install](#install)
- [State in a component](#state-in-a-component)
- [In a widget](#in-a-widget)
- [Collections](#collections)
- [Asynchronous state](#asynchronous-state)
- [Effects](#effects)
- [One change for a method](#one-change-for-a-method)
- [The lifetime of state](#the-lifetime-of-state)
- [What the build checks](#what-the-build-checks)
- [The debug tab and the log](#the-debug-tab-and-the-log)
- [Tests](#tests)
- [Things to know](#things-to-know)

## Install

```yaml
dependencies:
  spring_boot_starter_flutter_signals: ^0.8.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.8.0
```

The package re-exports the Flutter starter: an app lists it instead. The
generator writes the proxies; run `dart run build_runner build` after
adding or removing an annotation.

## State in a component

```dart
@Component()
class Basket {
  Basket(this.storage);              // ordinary injection

  final BasketStorage storage;

  @Signal()
  List<Book> items = [];

  @Signal()
  String? coupon;

  @Computed()                        // kept until items or coupon changes
  double get total =>
      items.fold(0.0, (sum, book) => sum + book.price) *
      (coupon == null ? 1 : 0.9);

  @Effect()                          // runs again whenever items changes
  void save() => storage.write(items);

  void add(Book book) => items.add(book);
  void apply(String code) => coupon = code;
}
```

A component is a singleton unless it says otherwise, so this is the app's
state, reached from anywhere by injection or from a widget's context.
The annotations are for the members of a component (`@Component`,
`@Service`, ...), not of a `@Configuration` class.

`@Computed` goes on a getter, or on a method without parameters:
`@Computed() bool isEmpty() => items.isEmpty;`.

## In a widget

A Spring widget follows its own `build`:

```dart
class BasketBadge extends SpringStatelessWidget<(Basket,)> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final (basket,) = beans;
    return Text('${basket.total}');   // built again when the total changes
  }
}
```

It is built again when `total` changes and not when anything else of the
basket does. Calling a method (`onPressed: basket.clear`) reads nothing
and costs no rebuild.

An ordinary widget uses `Watch`, which is also the way to keep a rebuild
small inside a large `build`:

```dart
Watch((context) => Text('${context.bean<Basket>().total}'))
```

## Collections

A `@Signal` field that holds a `List`, a `Set`, a `Map` or a `Queue` is
handed out as a collection that tells its readers of a change in place:

```dart
void add(Book book) => items.add(book);     // told, without an assignment
```

The field keeps the collection itself and its type stays what was
written (`List<Book>`). Assigning another collection is a change too.
What the getter handed out can be assigned back
(`items = items..sort()`): the field keeps the same list.

## Asynchronous state

A `@Computed` getter that returns a `Future` or a `Stream`:

```dart
@Component()
class Catalog {
  Catalog(this.client);

  final CatalogClient client;

  @Signal()
  String genre = 'fiction';

  @Computed()
  Future<List<Book>> get books => client.byGenre(genre);
}
```

- The request is made when `books` is first read. Every reader gets the
  same future until `genre` is assigned; then another request is made.
- In code it is an ordinary future: `final books = await catalog.books;`.
- Its state is `catalog.books.state`, an `AsyncValue<List<Book>>`:
  `isLoading`, `hasValue`, `value`, `error`, `isRefreshing`, and
  `when(data: ..., loading: ..., error: ...)`.
- `catalog.books.refresh()` asks again and keeps the last value on screen
  meanwhile; `reload()` asks again from nothing. Both complete when the
  new answer is there.
- An answer that comes after a newer request was made is dropped.
- A failure is a state, not an exception thrown into a widget.

`AsyncView` shows it:

```dart
AsyncView(
  () => context.bean<Catalog>().books,
  loading: (context) => const Spinner(),
  data: (context, books) => BookList(books),
)
```

The value is read inside the view (hence the function), so the view is
built again by itself when the load moves on and when the future changes.

A `Stream` is the same: `AsyncView.stream(() => catalog.prices, ...)`,
`catalog.prices.state` is its last event. The starter listens to the
stream itself, so a single-subscription stream must not be listened to a
second time.

**What it depends on must be read before the first `await`.** After an
`await` nothing is followed any more (this is how signals work, not a
limit of the starter):

```dart
@Computed()
Future<List<Book>> get books async {
  final genre = this.genre;                 // read first: followed
  final token = await auth.token();
  return client.byGenre(genre, token);      // `this.genre` here would not be
}
```

## Effects

An `@Effect` method runs once when the bean is made and again each time
something it read changes: a field or a computed value of its own bean or
of another.

```dart
@Effect()
void recalc() {
  final user = untracked(() => session.user);   // read, not followed
  price = pricing.of(basket.items, user);        // runs for basket.items only
}
```

It follows everything it reads except what it reads inside `untracked`.
It is a public method without parameters that returns nothing. The debug
tab says how often each ran.

## One change for a method

A method of a bean with such members is one change, whatever it assigns:

```dart
void clear() {
  items.clear();
  coupon = null;
}                    // readers are told once, when it returns
```

An effect that reads both runs once, and never sees the state between the
two. For several calls from outside, `batch(() { ... })` does the same.
A setter that is no followed field is one change too.

An asynchronous method is one change up to its first `await`; after it
each assignment is its own (wrap them in `batch` to tell them together).
A method that throws still tells what it assigned, once, and the error is
its caller's.

## The lifetime of state

The state lives as long as its bean, so a bean's scope is its state's
lifetime: the application's, a screen's
(`@Scope(NavigationScopes.route)`), a widget's.

When the bean is destroyed its effects stop and nothing is followed any
more. No `dispose` is written. The bean's own `@PreDestroy` methods run
after that and still read its fields.

A prototype (`@Scope('prototype')`) has its own state per instance. The
container never destroys a prototype, so its effects run while something
holds the instance, and its state goes with the last reference to it.

## What the build checks

The generator fails the build, naming the member and what to change, for:

- `@Signal` on a private, static or `final` field, or on a getter or a
  method;
- `@Computed` on a field, on a private or static member, or on a method
  with parameters or without a value;
- `@Effect` on a private or static method, with parameters, or with a
  value;
- any of them on a member of a `@Configuration` or
  `@ConfigurationProperties` class;
- any of them where no bean's proxy follows it: a class that is no bean
  (a widget, a `State`, a data class), the class returned by a `@Bean`
  method, a bean the container does not proxy (an `@Aspect`, a
  post-processor), an enum, an extension, a top-level variable or
  function;
- any of them on an abstract member: the method of a repository
  (`DataRepository`) or of an HTTP client (`@FeignClient`) is written by
  the generator and is not followed (read it in a `@Computed` getter of a
  component instead);
- a member that overrides a followed one without repeating its
  annotation;
- a followed member the proxy cannot override (an operator, a field of a
  private type);
- a class with such members that a generated class cannot extend
  (`final`, `sealed`, generic, a factory constructor).

Members must be public because the proxy is generated in another library.
A base class or a mixin may declare them for the components that extend
it (an abstract class, or a class that can be created and is a
component's base). Not checked by the build: a field read after an
`await` in an asynchronous `@Computed` getter.

## The debug tab and the log

"State" in the debug panel (`spring.flutter.signals.debug.enabled`; not
set: debug and profile builds) lists every bean with followed state that
lives now, by its class:

- a field: its value and how often it was assigned;
- a computed value: what it is now; an asynchronous one: where its load
  is and how often it ran;
- an effect: how often it ran.

A member shows once it was first used. `@Signal(hidden: true)` keeps a
value (a token) out of the tab and of the log.

The logger `spring.flutter.signals` writes every assignment and every run
of an effect at `debug`:

```yaml
logging:
  level:
    spring.flutter.signals: debug
```

## Tests

```dart
final app = springBootTest(
  springApplication,
  overrides: [BeanOverride<CatalogClient>(FakeCatalog())],
);

test('another genre loads other books', () async {
  final catalog = app.getBean<Catalog>()..genre = 'poetry';
  expect((await catalog.books).first.title, 'poetry one');
});
```

The beans are the container's (their proxies), so the state is followed
in a test as in the app. An instance made by hand (`Basket(storage)`) is
a plain object: its fields work, nothing follows them.

## Things to know

- **The bean's own calls are followed, and only followed.** A bean with
  such members is proxied by a subclass that sees the calls the bean
  makes on itself, so a field read or assigned inside a method is
  followed. Other advice on the bean (`@Transactional`, `@PreAuthorize`,
  `@Cacheable`) skips those calls, as in any bean and as in Spring: it
  runs for a call from outside.
- **With other advice on the same bean** (`@Transactional`, `@Cacheable`,
  an aspect) both run: one proxy, one chain. The advice that follows
  state is outside every advice of the default order (its order is
  `signalsAdvisorOrder`, one step before `Ordered.lowestPrecedence`), so:
  - a method is still one change, told after the other advice is done
    with it (an asynchronous one up to its first `await`);
  - **a rollback does not undo the fields.** The transaction rolls the
    database back; a field keeps what the method assigned, and its
    readers were told. Assign after the work that may fail, or assign
    the old value back in a `catch`;
  - on a `@Computed` member the other advice runs when the value is
    computed, not for each read of the kept one: a transaction is opened
    once per load;
  - an advice with an earlier order is outside and runs for every read.
    Method security is one (`methodSecurityAdvisorOrder`, before every
    other advice): `@PreAuthorize` on a `@Computed` member is checked for
    each read, and a kept value is never handed to someone who may not
    read it. An aspect of your own gets there with `@Order`.
- **A guard protects the member it is on, not what is under it.** With
  `@PreAuthorize` on a `@Computed` getter and a plain `@Signal` field
  under it, anybody reads and assigns the field: guard the field's
  writers (the methods that assign it) as well. A value another member
  of the same bean makes from the guarded one is not guarded (the bean's
  own call skips the check): put the guard on what callers read. A value
  or an effect of *another* bean that reads it is a call from outside:
  the guard runs as whoever made it run.
- **A check on an `@Effect` is on whoever changes the state.** Nobody
  calls an effect: it runs as the bean is made, and then for whoever
  assigns what it read. With `@PreAuthorize` on it, it does not run for
  a caller the check refuses (reported, see below), and with no user at
  the start the bean is not made. A check belongs on the methods that
  change the state.
- **A field nobody read is not followed yet**: it is mirrored when first
  read, from the field itself. A `late` field read before it is assigned
  fails as always, and whoever read it is told of the first assignment.
- **A collection is followed in place by the field's declared type**:
  `List`, `Set`, `Map`, `Queue`. A field declared as a collection class of
  its own (`HashSet<int>`, `UnmodifiableListView<int>`) keeps that class
  and is followed by assignment only.
- **Errors are the bean's own.** A `@Computed` getter that throws fails
  its reader with what it threw, and the failure is not kept: the next
  read computes again (what it failed for may be the caller, not the
  state).
- **An effect that throws does not fail the assignment that ran it.**
  The error is reported (`FlutterError.reportError`, as for a listener
  of a `ChangeNotifier`), the field keeps the new value, the code that
  assigned goes on, and the effect runs again at the next change of what
  it followed. An effect that throws on its first run, as the bean is
  made, stops the bean from being made.
- **Computed values that read each other in a circle** fail when read.
- **A field the container injects** (`@Autowired`, `@Value`) may be a
  `@Signal`; a method may be both `@PostConstruct` and `@Effect` (it is
  then called once and run as an effect).
- **Equal is unchanged.** Assigning a value equal to the one there tells
  nobody.
- **An effect runs at once when what it read is assigned** (at the end of
  the method that assigned it), not in a later frame.
- **Not built by the starter**: state kept between runs, a history with
  undo, the state of a running action ("saving..."), server data as a
  cache with invalidation.
