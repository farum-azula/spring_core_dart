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
    home: const CounterPage(),   // the app widget is built from spring.flutter.app.*
  ),
);

@ChangeNotifierComponent()   // a bean whose proxy is a ChangeNotifier,
class Counter {              // notifying after every method
  int value = 0;
  void increment() => value++;
}

// reads counter.value in build: rebuilt after every increment
class CounterText extends SpringStatelessWidget<(Counter,)> {
  @override
  Widget build(BuildContext context) {
    final (counter,) = beans; // the beans by name
    return Text('${counter.value}');
  }
}

// only calls a method: an increment does not rebuild it
class AddButton extends SpringStatelessWidget<(Counter,)> {
  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return FloatingActionButton(onPressed: counter.increment, ...);
  }
}
```

A complete app: [`example/flutter_counter`](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_counter),
the `flutter create` counter split into beans, properties and messages.

## Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter: ^0.3.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.1
  flutter_test:
    sdk: flutter
  spring_boot_starter_test: ^0.3.1   # springBootTest, BeanOverride
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
  home: const CounterPage(),              // or child: your own MaterialApp
)
```

- **The app widget.** With `home:` it builds the app widget itself from the
  configuration (next section); with `child:` the app writes its own
  `MaterialApp` / `CupertinoApp` / `WidgetsApp`. Exactly one of them.
- **Hot reload.** Handled by the widget, see *Hot reload*.
- **Closing.** Removing `SpringApplicationWidget` closes the context (`@PreDestroy`,
  lifecycle stops).

## The app widget from configuration

`SpringApplicationWidget(home: ...)` puts a `SpringApp` at the root: a
`WidgetsApp`, `MaterialApp` or `CupertinoApp`, set up by properties
(`.properties` or `.yml`, per profile) instead of code:

```properties
# lib/resources/application.properties
spring.flutter.app.type=material        # widgets (default) | material | cupertino
spring.flutter.app.title=${counter.title}
spring.flutter.app.debug-banner=false   # default true, as in Flutter
spring.flutter.app.locales=en,ja        # default: the languages of the messages files
```

- **Type.** `widgets` by default: no Material or Cupertino design until a
  property asks for it. `Scaffold`, `AppBar` and other Material widgets
  need `material`. With the platform profiles, `type=cupertino` in
  `application-ios.properties` gives iPhones the iOS look.
- **Theme.** From `spring.flutter.theme.*`, see the next section.
- **Locales.** By default the languages of `lib/resources/messages*.properties`
  (`spring.messages.basename`): `messages.properties` counts as English,
  `messages_ja.properties` adds `ja`, so `context.message` and the app's
  locales agree. Flutter's own delegates for the type (texts of its
  widgets in every language) are added; `flutter_localizations` comes
  with the starter.
- **`NavigatorObserver` beans** become the app's observers.
- **`FlutterAppCustomizer` beans** change anything else before the widget
  is built (`builder`, `shortcuts`, `scrollBehavior`, the app's own
  localization delegates), in `@Order`:
  ```dart
  @Component()
  class AppLocalizations implements FlutterAppCustomizer {
    @override
    void customize(FlutterAppSettings app) =>
        app.localizationsDelegates.add(LegalTerms.delegate);
  }
  ```
- **Once per context.** The settings are made once when the application
  starts (`FlutterAppSettings.of(context)`), and an invalid value
  (`type=swing`) fails the start with the failure report.

## Themes from properties

The look of the app is configuration too: the shared part of the theme,
the standard `light` and `dark` themes and any number of custom ones, in
`.properties` or `.yml`, per profile, even loaded from a server at run
time. No `ThemeData` in the code; every value the properties leave out is
Flutter's Material 3 default.

```yaml
# lib/resources/application.yml
spring:
  flutter:
    theme:
      active: system              # system | light | dark | a custom theme
      system-light: light         # what `system` shows in the device's light mode
      system-dark: dark           # ... and in its dark mode

      # Shared by every theme
      seed-color: deepPurple      # a Colors name or '#RRGGBB'
      scheme-variant: tonalSpot   # tonalSpot | fidelity | content | vibrant | expressive | ...
      contrast: 0                 # -1 … 1
      colors:                     # any ColorScheme role over the seed's palette
        error: '#B3261E'
        surface-container-low: grey.shade100
      typography:
        font-family: Inter
        font-family-fallback: [Noto Sans JP]
        defaults: { letter-spacing: 0.1 }
        display: { font-family: Playfair Display, weight: bold }   # display large/medium/small
        title-large: { weight: 600, size: 22, height: 1.3 }       # one of the 15 TextTheme styles
        code: { font-family: JetBrains Mono, size: 13 }           # SpringTheme.of(context).textStyle('code')
      shape: { medium: 16, large: 20 }        # the Material 3 scale: none … extra-large, full
      elevation: { level1: 2 }
      visual-density: compact                 # adaptive | standard | comfortable | compact
      tap-target-size: padded
      splash: sparkle                         # ripple | sparkle | none
      motion:
        page-transition: zoom                 # platform | fadeUpwards | zoom | cupertino | none
        duration-medium: 250ms
        easing-standard: '0.2, 0, 0, 1'
      spacing: { s: 8, m: 16 }                # SpringTheme.of(context).space('m')
      components:                             # values reference the tokens above
        app-bar: { center-title: true, scrolled-under-elevation: level2, title-style: title-large }
        button: { shape: full, padding: '24, 10' }
        filled-button: { shape: medium }
        card: { shape: large, color: surface-container-low, elevation: level1 }
        input: { style: outline, shape: small }
        navigation-bar: { label-behavior: onlyShowSelected }
        snack-bar: { behavior: floating }
      tokens:                                 # the app's own, read through SpringTheme
        brand: { accent: '#FF6B00', hero-height: 240 }

      # Themes: only what differs from the shared part
      themes:
        dark:
          seed-color: deepPurple.shade200
        ocean:
          seed-color: teal
          shape: { large: 28 }
        ocean-night:
          extends: ocean                      # ocean's properties, then these
          brightness: dark
```

- **Standard and custom themes.** `light` and `dark` always exist (made
  from the shared part, Material's light and dark palettes); a custom
  theme is light unless it says `brightness: dark` or extends a dark one.
  `extends` chains themes; a cycle or an unknown name fails the start.
  Custom themes can live in their own files:
  `spring.config.import: classpath:themes/ocean.yml`.
- **Components** are Material's, built from the tokens as Material 3
  specifies; `components.*` only changes what differs. A changed shape
  value reaches the components using it (`shape.medium` → cards). The
  components: `app-bar`, `button` (all four buttons) and
  `filled-button` / `elevated-button` / `outlined-button` / `text-button`,
  `card`, `input`, `chip`, `dialog`, `bottom-sheet`, `navigation-bar`,
  `snack-bar`, `tooltip`, `list-tile`, `divider`,
  `floating-action-button`, `tab-bar`, `popup-menu`.
- **Checked at the start.** Every theme is read when the application
  starts; an invalid value (`seed-color: purpel`, `shape: hugee`) or a
  misspelled key (`seed-colour`, `typography.body.colour`, an unknown
  component or component property) fails the start with the property's
  name and what it may be.
- **Made once.** Each theme becomes a `SpringThemeData`, a Material
  `ThemeData` and a `CupertinoThemeData` once; switching only picks
  another one.
- **Switching at run time.** The `ThemeSelection` bean picks the theme
  (`select('ocean')`, `select('system')`); the app follows at once, with
  Flutter's animation:
  ```dart
  class ThemeMenu extends SpringStatelessWidget<(ThemeSelection, SpringThemes)> {
    @override
    Widget build(BuildContext context) {
      final (selection, themes) = beans;
      return PopupMenuButton<String>(
        onSelected: selection.select,
        itemBuilder: (_) => [
          for (final name in ['system', ...themes.names])
            CheckedPopupMenuItem(value: name, checked: selection.active == name, child: Text(name)),
        ],
      );
    }
  }
  ```
- **Themes from a server.** `SpringThemes.loadYaml(yaml)` (or `load(map)`)
  adds or changes themes at run time, over the files' properties; they are
  checked first, so an invalid one throws and changes nothing.
  `unload()` drops them again.
  ```dart
  themes.loadYaml(await http.read(Uri.parse('https://cdn.example.com/themes.yml')));
  selection.select('winter');
  ```
- **The app's own widgets** read the theme shown, whatever the app type,
  with `SpringTheme.of(context)`: `colorScheme`, `textStyle('code')`,
  `shape('large')`, `space('m')`, `duration('medium')`,
  `tokenColor('brand.accent')`, `tokenNumber('brand.hero-height')`.
- **Cupertino and Widgets apps.** `type: cupertino` gets a
  `CupertinoThemeData` from the same theme (primary color, text styles,
  backgrounds where set; iOS's defaults otherwise), `type: widgets` its
  text style and color.
- **Replacing a part.** A `ThemeData` bean named `theme` / `darkTheme`
  replaces the made `light` / `dark` Material theme, a
  `CupertinoThemeData` bean the Cupertino ones; `ThemeCustomizer` /
  `CupertinoThemeCustomizer` beans adjust every made theme (in `@Order`).

### Fonts

Font files go into any directory under `flutter: assets:` and are listed
nowhere else: when the application starts (behind the splash screen) the
starter loads every `.ttf` / `.otf` among the app's assets, in the family
the file itself names (`Inter-SemiBold.ttf` → `Inter`, a weight of the
family). The theme then names families only. Families declared under
`flutter: fonts:` keep working. A family the theme names but neither the
assets nor `flutter: fonts:` have is logged as a warning (it may still be
the platform's own, like `.SF UI Text`).

```properties
spring.flutter.fonts.auto-load=true         # false: load nothing
spring.flutter.fonts.exclude=assets/pdf/**  # files for other uses
```

A complete app with every theme feature and golden screenshots of each
theme: [`example/flutter_themes`](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_themes).

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

**`SpringStatelessWidget<(...)>`**: the beans a widget needs, in its type;
the widget reads them as `beans`, a record, like a `SpringState`. The
generator sees every `SpringStatelessWidget`, so the start fails when one of
its beans is missing.

```dart
class BasketBadge extends SpringStatelessWidget<(Basket, Clock)> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final (basket, clock) = beans;
    return Badge(label: Text('${basket.count}'));
  }
}
```

`beans` is meant for `build` and the callbacks made there (`onPressed`).
A widget is immutable and one `const` instance may be built in several
places, so after `build` it holds the beans of the latest build; a widget
built under two application contexts at once takes them into locals in
`build`.

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
*State beans*) — a `@ChangeNotifierComponent` or `@NotifyListeners` bean
only when the widget read its state: see *Reading is free*. Widgets that read beans are also rebuilt when the context
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
  beans of their record they read and rebuild when one notifies; no
  `ListenableBuilder` needed;
- elsewhere, `listenableOf(bean)` gives the `Listenable`:
  `ListenableBuilder(listenable: listenableOf(context.basket), builder: ...)`.

The build checks that every name in `exclude` is a method, setter or field
of the class, and that the class declares none of `ChangeNotifier`'s own
members (`addListener`, `dispose`, ...).

**Reading is free.** A Spring widget listens to a `@ChangeNotifierComponent`
or `@NotifyListeners` bean of its record only when its `build` read the
bean's state (a getter, a field). Calling a method (`onPressed:
counter.increment`) costs no rebuilds, so a page can hold the counter for
its button while only the `Text` showing the count rebuilds:

```dart
class CounterPage extends SpringStatelessWidget<(Counter,)> {
  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Scaffold(
      body: const CounterText(),                  // rebuilt after a tap
      floatingActionButton: FloatingActionButton( // the page is not
        onPressed: counter.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

The reads go through the bean's AOP proxy, so the rule follows the state
the widget actually shows: a build that stops reading the bean stops
listening, the next one that reads it listens again. A read outside the
widget's own build — in a `ListView.builder` item builder or a `Builder`
below it, in a callback — cannot be told apart from the UI's, so after one
the widget keeps listening (never a stale screen). The bean's reads of
itself in its methods do not count. A `ChangeNotifier` bean without either
annotation (no proxy) is listened to always.

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

The generator checks every `@Value('asset:...')`: a missing file, or one
not declared under `flutter: assets:`, fails the build with the lines to
add, instead of the app failing when it reads the asset:

```
@Value('asset:assets/sounds/tap.mp3') in ...#Sounds: assets/sounds/tap.mp3 is
not declared in pubspec.yaml, so the app would not contain it. Add it under
`flutter: assets:`:

flutter:
  assets:
    - assets/sounds/
```

A directory entry (`- assets/sounds/`) takes in the new files of that
directory by itself, but not those of its subdirectories (as in Flutter).
Keys with placeholders (`asset:${sound.file}`) and other packages' assets
(`asset:packages/...`) are only known at run time and not checked.

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
      SpringScope(
        applicationContext: app.context,
        child: const SpringApp(home: CounterPage()),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });
}
```

A `SpringStatelessWidget` can also be built with fakes directly:
`const BasketBadge().buildWith(context, (FakeBasket(), FakeClock()))`.

## Platforms

Android, iOS, macOS, Windows, Linux and the web.
