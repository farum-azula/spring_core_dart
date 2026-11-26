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
  spring_boot_starter_flutter_signals: ^0.10.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.10.0
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

## The debug tools

Three tools, each with its own switch, none of them in a release build
unless asked for, and none collecting anything unless it shows:

- **The Signals tab** of the debug panel (`spring.flutter.signals.debug.enabled`;
  not set: debug builds; never without the panel, whose
  `spring.flutter.debug.enabled` is its parent switch): every bean with
  followed state by class and scope, its members in columns:

  ```
           value      changed  told  changes  writes  ticks  reads/5s  time
  coupon   TEN        0.4s     0.4s  3        4       3      12        —
  items    List(2) ▸  12s      12s   5        5       5      40        —
  total    9.0        0.4s     —     8        —       —      18        14µs
  save()   effect     12s      —     5        —       —      —         30µs
  ```

  `changed` is the time since the value really changed (an equal value
  is no change), `told` since its readers were told (a queued write
  changes at once and is told at the flush). Values are short (a type's
  name, `Map(1)`, `List(3)`, a long text cut; a tap on a collection shows
  its first items), in the theme's `number` colour, a failure red, a load
  amber; a field marked `@Signal(hidden: true)`, a member whose name looks
  secret and a value kept for its caller show a lock with the reason,
  never the value. A row that changed in the last two seconds is lit and
  fades. The times move once a second.

  The tab has three sub-tabs: **Fields** (the columns above, then the
  queues: what waits, the schedule, the drops; and the open buffers),
  **Graph** and **List**. **Graph** is the debug panel's application
  graph with the signals layer alone, left to right: `@Signal` fields
  (rounded), `@Computed` values (hexagons) and `@Effect` methods
  (slanted) in a lane per bean, then the widgets that read them in the
  `Widgets` lane (a Spring widget a pill, a `Watch` a tagged box): by
  name, `MatchHeader`, `ReviewTile [42]` by a key that is a number, an
  enum or a plain word, a `Watch` after the widget it is in (`Watch in
  PageBackdrop`, never "a widget"); the widgets of one type fold into
  one plate, `ReviewTile ×10`, until it is tapped open. "On screen" (the
  default) shows the widgets in the app's window (the panel over them
  does not hide them), what they read and the effects on the same
  sources; "All" everything. When a field ticks its node flashes (a
  brighter border, a glow, at most a quarter of the theme's
  `graph-flash` in its fill) and a pulse runs along its edges to the
  readers. A tap on a node highlights everything before and after it
  and shows its value, counts, queue, a widget's rebuilds over the read
  window and what it read; the pointer over it shows a tooltip. When the
  tab opens, the widgets on the screen are built once again, so their
  reads show even on an idle page under the panel. **List** shows the
  same as an indented list (`MatchHeader · 4 rebuilds/5s`). The graph is
  laid out again only when who reads what changes, never for a value,
  and painted at most once a frame while something is lit. The Graph
  sub-tab is there when the build has the signals layer (`signalsGraphLayer`,
  with the panel's Graph tab: `spring.flutter.debug.graph.enabled`,
  `spring.flutter.debug.graph.layers`); without it the tab has Fields and
  List, and none of the graph's code.

  The widget names are kept by `signalWidgetNames`, a bean of the tab's,
  the graph's and the console's panes' modules, there only while one of
  those views is in the running app: a build or a run with none keeps
  nothing of any widget. Widgets are named only while a tool collects;
  when one starts, those on the screen are built once again. A
  third-party `WidgetBuildTracker` that wants the widget implements
  `WidgetAwareBuildTracker`.
- **The debug console's `signals` segment**, a module of its own: in the
  build only with the console (`spring.flutter.debug.console.enabled:
  true`) and when `spring.flutter.debug.console.segments` names `signals`
  or holds `*`; it shows the ticks, flushes and effect runs of the last
  frame (`signals 3 ticks · 1 flush · 2 effects`), collected only while
  the console shows.
- **The debug console's `signals` pane** (`signalsPane`, order 20), a
  module of its own: in the build only with the console and when
  `spring.flutter.debug.console.panes` names `signals` or holds `*`. The
  console's application graph preset to the signals layer, compact, on
  the console's own background: a node flashes and a pulse runs to its
  readers when it ticks; the scope, `Live only` and the bean lanes as in the Graph tab,
  a tapped node told in one line (value, times, counts, queue). It
  collects only while it shows; hidden it is not built. The console's
  `graph` pane (`panes: [graph]`) shows the same layer among the others
  the build has.
- **The signals layer of the application graph** (`signalsGraphLayer`):
  the debug panel's **Graph** tab (under `App`) and the console's `graph`
  pane draw it beside the other layers. In the build when
  `spring.flutter.debug.graph.layers` names `signals`, holds `*` or is
  not set, inside `spring.flutter.debug.graph.enabled`, this tab's and
  the panel's switches (the `graph` pane: inside the console's); it
  brings the Graph tab and the graph's engine with it.
- **The activity log** at DEBUG under `spring.flutter.signals.activity`
  (in the build with the tab, off until `debug.log.enabled: true`): writes,
  publications, flushes, drops, computations and effect runs with their
  time and failures; names only, never a value.

```yaml
spring:
  flutter:
    debug:
      console:
        enabled: true          # the console (not set: no code)
        segments: [fps, signals, frames-lost, filter]  # signals: built in
        panes: [commands, signals, graph]  # the graphs in the console: built in
        shown-panes: [signals]       # shown at the start
      graph:
        enabled: true          # the panel's Graph tab (not set: debug builds)
        layers: [signals]      # the layers built in (not set: all)
    signals:
      debug:
        enabled: true          # the Signals tab (false: no code)
        read-window: 5s        # the read counts
        reads: true            # count reads while a tool shows
        log:
          enabled: true        # the activity log
          reads: false         # every read too (very many lines)
logging:
  level:
    spring.flutter.signals.activity: debug
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

- **The bean's own calls are followed.** The bean is made as a generated
  subclass whose followed members go straight to their signals, so a
  field read or assigned inside a method is followed. Other advice on the
  bean (`@Transactional`, `@PreAuthorize`, `@Cacheable`) is an ordinary
  proxy around it and skips those calls, as in Spring; it needs
  `spring.flutter.signals.allow-advice: true`.
- **Writes are told by a queue** (`@Signal(queue: ...)`, the default one
  tells them in a microtask), and **a transaction holds them** in a
  `SignalBuffer` until its commit; a rollback drops them.
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
