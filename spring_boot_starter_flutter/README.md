# spring_boot_starter_flutter

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring Boot for Flutter apps. [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
already runs inside Flutter; this package connects it to the widget tree:
`SpringApplicationWidget` starts the application, widgets reach the beans, the app's
lifecycle drives the context's, and the platform is a profile.

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    child: const CounterApp(),
  ),
);

@ChangeNotifierComponent()   // a bean whose proxy is a ChangeNotifier,
@BuildContextAccess()        // notifying after every method
class Counter {
  int value = 0;
  void increment() => value++;
}

// in any widget below SpringApplicationWidget
FloatingActionButton(onPressed: context.counter.increment, ...);

// rebuilt after every increment, no ListenableBuilder
class CounterText extends SpringStatelessWidget<(Counter,)> {
  @override
  Widget build(BuildContext context, (Counter,) beans) =>
      Text('${beans.$1.value}');
}
```

A complete app: [`example/flutter_counter`](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_counter),
the `flutter create` counter split into beans, properties and messages.

## Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter: ^0.2.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.2.0
  flutter_test:
    sdk: flutter
  spring_boot_starter_test: ^0.2.0   # springBootTest, BeanOverride
```

`spring_boot_starter_flutter` brings `spring_core_dart`, `spring_boot_dart`
and `spring_boot_starter_logging` and exports them: `import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';` gives
`@Component`, `@Value`, `@ConfigurationProperties`, `@SpringBootApplication`,
events, validation and JSON too. Two of their names would clash with
Flutter's and are left out: Boot's startup `Banner` (Flutter's `Banner`
widget) and the validation constraint `Size` (`dart:ui`'s `Size`), which is
exported as `SizeConstraint`:

```dart
@SizeConstraint(min: 1, max: 60)
String title = 'Books';
```

Logging is on from the start, like in a Spring Boot app: `SpringLog`
lines go to the console (`flutter run`, the IDE) in Boot's format, with
levels and patterns from `logging.*`, and to an in-memory `LogBuffer`:

```text
INFO 82749 --- [main] spring_boot_dart.SpringApplication : The following 2 profiles are active: "desktop", "macos"
INFO 82749 --- [main] counter.lifecycle                  : App inactive
```

```properties
logging.level.root=warn
logging.level.counter=debug
```

A class gets its logger with `@Log()` (from the core, like Lombok's
`@Slf4j`): a generated `log` getter, the logger named after the class or
`topic:`.

```dart
@Component()
@Log(topic: 'counter.lifecycle')
class LifecycleLog {
  @EventListener()
  void onState(AppLifecycleStateEvent event) =>
      log.info('App ${event.state.name}');
}
```

The other starters stay separate, as in Spring Boot: add
`spring_boot_starter_feign`, `spring_boot_starter_scheduling`, ... when the
app uses them.

Put `@SpringBootApplication()` on `main` in `lib/main.dart` and run
`dart run build_runner watch`: it writes `lib/main.spring.dart` with the
`springApplication` of the beans under `lib/`. Config files and messages go
to `lib/resources/` (embedded into the generated code: no asset
declarations).

## `SpringApplicationWidget`

The root widget. It runs the application (`runAsync`: config files,
auto-configuration, runners), shows `splash` until it is ready and
`failure` if the start fails (the failure report is logged either way),
then gives the context to the widgets below.

```dart
SpringApplicationWidget(
  application: () => springApplication,  // a function: hot reload gets the new beans
  splash: (context) => const ColoredBox(color: Colors.white),
  failure: (context, error) => ErrorScreen(error),
  child: const CounterApp(),
)
```

- **Hot reload.** Handled by the widget, see the next section.
- **Closing.** Removing `SpringApplicationWidget` closes the context (`@PreDestroy`,
  lifecycle stops).

## Hot reload

A hot reload (`r` in `flutter run`, saving in the IDE) puts the new code
into the running app without starting it again: `main` does not run, the
objects in memory stay. For beans that is a problem: the application
context was built from the old generated code, so a new `@Component` would
be missing and a changed one would keep its old dependencies.
`SpringApplicationWidget` takes care of it, like Spring Boot DevTools'
*restart* — on by default, nothing to set up. Flutter calls the root widget's `reassemble()` on every hot
reload; there the widget compares the fingerprint of the generated code
(`lib/main.spring.dart`) with the one the running context was built from.

**Only method bodies changed: the context stays.** The fingerprint is the
same, so nothing is restarted; Dart already runs the new method bodies, and
the beans keep their state.

```dart
@Component()
@BuildContextAccess()
class Counter extends ChangeNotifier {
  int value = 0;
  void increment() {
    value += 2;          // was `value++`: after `r`, the next tap adds 2,
    notifyListeners();   // and the count reached so far is kept
  }
}
```

**Beans, annotations or `lib/resources/` changed: the context restarts.**
With `dart run build_runner watch` running, the generator rewrites
`main.spring.dart` a moment after you save; the next hot reload sees a new
fingerprint and:

1. closes the running context (`@PreDestroy` methods, lifecycle beans
   stopped, `ContextClosedEvent`);
2. starts the application again with the new beans and config files
   (not the `ApplicationRunner`s, unless `rerunRunnersOnReload: true`:
   the app did not really start again);
3. builds the widgets below it afresh, their `State`s included, so no
   widget keeps a bean of the closed context. Navigation and scroll
   positions start over, like after a hot restart, but the app process
   (and anything outside the context) stays.

```dart
// added while the app runs, `build_runner watch` regenerates, then `r`:
@Component()
class Clock {
  DateTime now() => DateTime.now();
}

// and in a widget:
Text('${context.bean<Clock>().now()}');   // found: the context was restarted
```

```properties
# application.properties — no change to the counter, a restart:
counter.step=2
```

**What a hot reload cannot do.** Without `build_runner watch` the generated
code stays old: a new bean is not found until you run the generator (and
reload again). A change Flutter itself cannot hot reload (a changed
`main`, an enum turned into a class, ...) needs a hot restart (`R`), which
starts everything from `main`. When the restart of the context fails (a
bean that throws, a bad property), the failure screen shows the error;
fix the code and reload again, the widget then starts the application
anew.

**Turning it off.** The restarts are on by default. A context restart
drops the state of every bean; to
keep the context as it is after every hot reload (and restart by hand with
`R` when beans changed), set Spring Boot DevTools' switch:

```properties
spring.devtools.restart.enabled=false
```

Release and profile builds have no hot reload, so none of this happens
there.

## Beans in widgets

Services keep constructor injection. Widgets have their own constructors
(nothing is injected into them), so they get beans in one of these ways.

**`context.bean<T>()`**: any bean by type (or `qualifier:`), like
`getBean`.

```dart
final properties = context.bean<CounterProperties>();
```

**Generated getters** for the beans marked `@BuildContextAccess()`: typed,
named after the bean (or `@BuildContextAccess(name: 'cart')`), generated into
`main.spring.dart`; import it where they are used. Only marked beans get
one, so the list stays short.

```dart
@Component()
@BuildContextAccess()
class Basket { ... }

Text('${context.basket.count}');
```

**`SpringStatelessWidget<(...)>`**: the beans a widget needs, in its type, handed to
`build` as a record. The generator sees every `SpringStatelessWidget`, so the start
fails when one of its beans is missing.

```dart
class BasketBadge extends SpringStatelessWidget<(Basket, Clock)> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context, (Basket, Clock) beans) {
    final (basket, clock) = beans;
    return Badge(label: Text('${basket.count}'));
  }
}
```

A record with named fields (`({Clock utc})`) works too: when several beans
have a field's type, its name picks one, like a constructor parameter's
name in Spring. A nullable field (`Clock?`) is optional.

**`SpringStatefulWidget<(...)>`** with a **`SpringState<W, (...)>`**: the
same for a stateful widget; its `State` has the beans as `beans`, available
from `initState` on. The record is written on both (Dart cannot take it from
the widget); the compiler checks that they match, and a typedef keeps it in
one place.

```dart
class BasketPage extends SpringStatefulWidget<(Basket, Clock)> {
  const BasketPage({super.key});

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends SpringState<BasketPage, (Basket, Clock)> {
  @override
  void initState() {
    super.initState();
    final (basket, _) = beans;
    basket.load();
  }

  @override
  Widget build(BuildContext context) {
    final (basket, clock) = beans;
    return Text('${basket.count} at ${clock.now}');
  }
}
```

Spring widgets rebuild when one of their beans that is a `Listenable`
notifies (a `ChangeNotifier`, a `@ChangeNotifierComponent` bean; see
*State beans*). Widgets that read beans are also rebuilt when the context
is replaced. A bean
that notifies (a `ChangeNotifier`, a `Stream`) is listened to as usual
(`ListenableBuilder`, `StreamBuilder`).

Spring has no counterpart: a Java bean is injected into a controller or a
view, never looked up from a UI tree.

## State beans: `@ChangeNotifierComponent`, `@NotifyListeners`

A state bean usually is a `ChangeNotifier` that ends every method with
`notifyListeners()`. Here the bean's AOP proxy does that.

**`@ChangeNotifierComponent`**: a stereotype (a `@Component`) for a plain
class. The generated proxy mixes `ChangeNotifier` in and notifies after
every public method and setter, except the ones in `exclude`:

```dart
@ChangeNotifierComponent(exclude: ['peek'])
class Basket {
  final _items = <String>[];
  int get count => _items.length;     // getters never notify

  void add(String isbn) => _items.add(isbn);
  void clear() => _items.clear();
  String? peek() => _items.lastOrNull; // excluded: does not notify

  Future<void> load() async {         // notifies when the Future completes
    _items.addAll(await api.basket());
  }
}
```

The class itself is no `Listenable` (Dart cannot give it a superclass from
generated code); the bean the container hands out is. So:

- `SpringStatelessWidget` and `SpringState` subscribe to the `Listenable`
  beans of their record and rebuild when one notifies; no
  `ListenableBuilder` needed;
- elsewhere, `listenableOf(bean)` gives the `Listenable`:
  `ListenableBuilder(listenable: listenableOf(context.basket), builder: ...)`.

The build checks that every name in `exclude` is a method, setter or field
of the class, and that the class declares none of `ChangeNotifier`'s own
members (`addListener`, `dispose`, ...).

**`@NotifyListeners`**: the same advice for a class that extends
`ChangeNotifier` itself, on the class (with `exclude`) or on single
methods:

```dart
@Component()
@NotifyListeners(exclude: ['peek'])
class Basket extends ChangeNotifier { ... }

class Search extends ChangeNotifier {
  @NotifyListeners()
  void select(Book book) => selected = book;
}
```

Either way the listeners are notified after the method returns, also when
it throws (the state may have changed before the error), and after a
returned `Future` completes. Spring has no counterpart; it is advice
around the bean's methods, like `@Transactional`.

## The app lifecycle

Each `AppLifecycleState` change is published as an
`AppLifecycleStateEvent`:

```dart
@EventListener()
void onLifecycle(AppLifecycleStateEvent event) {
  if (event.state == AppLifecycleState.paused) drafts.save();
}
```

When the app goes to the background (`hidden` / `paused`) the context is
paused, like Spring 7's `pause()`: `@Scheduled` tasks, WebSocket
connections and other pauseable `SmartLifecycle` beans stop, then
`ContextPausedEvent`. Back in the foreground (`resumed`) it is restarted
(`ContextRestartedEvent`). To keep them running:

```properties
spring.flutter.lifecycle.pause-in-background=false
```

## Platform profiles

The platform is an active profile: `android` / `ios` with `mobile`,
`macos` / `windows` / `linux` with `desktop`, `web` in a browser. Profile
files load by themselves, the specific one winning over the group:

```text
lib/resources/application.properties          api.url=https://api.neon.books
lib/resources/application-mobile.properties   images.size=small
lib/resources/application-ios.properties      push.provider=apns
```

```dart
@Component()
@Profile(['android'])
class FcmPushService implements PushService { ... }

@Component()
@Profile(['ios'])
class ApnsPushService implements PushService { ... }
```

## Assets

Two places for files, like `src/main/resources` and static content in a
Spring app:

| | `lib/resources/` | Flutter assets (`flutter: assets:` in `pubspec.yaml`) |
|---|---|---|
| for | config files, messages, small texts and templates | images, video, sound, large data |
| how | embedded into the generated code (up to 1 MB per file) | in the app's asset bundle, loaded when read |
| location | `classpath:mail/welcome.txt` | `asset:assets/intro.mp4` |
| reading | synchronous or asynchronous | asynchronous |

Both are injected the Spring way, with `@Value` and a `Resource`:

```dart
@Component()
class Onboarding {
  Onboarding(
    @Value('asset:assets/terms.md') this.terms,
    @Value('asset:assets/intro.mp4') this.video,
  );
  final Resource terms;
  final Resource video;

  Future<String> termsText() => terms.readAsString();

  // Flutter's APIs take the asset key:
  VideoPlayerController player() =>
      VideoPlayerController.asset((video as AssetResource).key);
}
```

`asset:` resolves to an `AssetResource` of `rootBundle` (an `AssetBundle`
bean replaces it, e.g. in tests); `asset:/assets/x.png` works too, and
`context.getResource('asset:...')` as well. `exists()` checks the app's
asset manifest. (`@Resource` is not used for this: in Spring, and here, it
injects a bean by name.)

## Configuration at build time

A Flutter app has no command line and, on a phone, no useful environment
variables, so `SpringApplicationWidget` does not read the OS environment (on desktop,
turn it on with `--dart-define=spring.flutter.scan-os-environment=true`).
Build-time values come from `--dart-define`, which the generator turns
into a property source above the config files:

```sh
flutter run --dart-define=SPRING_PROFILES_ACTIVE=dev --dart-define=API_URL=http://localhost:8080
flutter build apk --dart-define-from-file=config/prod.json
```

`@Value(r'${API_URL}')` and `api.url` both see `API_URL`, like environment
variables in Spring Boot. Everything defined at build time ends up in the
app and can be read from it: no secrets there.

## Messages

`context.message` reads the application's `MessageSource`
(`lib/resources/messages.properties`, `messages_ja.properties`, ...) in the
app's current locale (`Localizations`, else the device's):

```dart
// messages.properties: basket.total=Total: {0}
Text(context.message('basket.total', args: [total]));
```

## Tests

`springBootTest` from `spring_boot_starter_test` works under
`flutter_test`; put the widget under a `SpringScope` with its context, and
replace beans with `BeanOverride`:

```dart
void main() {
  final app = springBootTest(
    springApplication,
    properties: {'counter.step': 2},
    overrides: [BeanOverride<Clock>(FixedClock())],
  );

  testWidgets('a tap adds the step', (tester) async {
    await tester.pumpWidget(
      SpringScope(applicationContext: app.context, child: const CounterApp()),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });
}
```

A `SpringStatelessWidget`'s `build` can also be called with fakes directly:
`const BasketBadge().build(context, (FakeBasket(), FakeClock()))`.

## Platforms

Android, iOS, macOS, Windows, Linux and the web.
