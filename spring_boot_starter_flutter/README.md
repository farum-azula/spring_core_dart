# spring_boot_starter_flutter

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring Boot for Flutter apps. It gives a Flutter app one place for its
state and services, and a way to hand them to widgets without passing
them through constructors.

You write your services and your app state as plain classes and mark
them `@Component()`. The framework creates one object of each, called a
**bean**, and connects them: a bean that needs another one simply asks
for it in its constructor. All beans live in the **application context**,
which starts when the app starts. This package puts that context into the
widget tree, so any widget can get the beans it needs, and widgets that
show a bean's state rebuild when it changes.

The rest comes with it:

- The app widget (`MaterialApp`, `CupertinoApp` or `WidgetsApp`), its
  themes, fonts and languages are set in configuration files
  (`application.properties` or `application.yml`), not in code.
- The platform is a *profile*: a file such as
  `application-ios.properties`, or a bean marked `@Profile(['android'])`,
  is used on that platform only.
- When the app goes to the background, `@Scheduled` tasks and WebSocket
  connections stop; they start again when it comes back.
- A hot reload that changed beans restarts the context with the new code.

It is for Flutter developers who want dependency injection,
configuration files and the rest of the Spring model in an app, or who
share code and habits with a Spring (or Dart Spring) server. You do not
need to know Spring to use it.

```dart
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'main.spring.dart'; // written by the generator

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    // The app widget is built from spring.flutter.app.* in the
    // configuration files.
    home: const CounterPage(),
  ),
);

// The count is a bean, not a State: any widget or service can read and
// change it. The generated proxy notifies the listeners after every method.
@ChangeNotifierComponent()
class Counter {
  int value = 0;
  void increment() => value++;
}

// Lists the bean it needs in its type and gets it as `beans`.
class CounterPage extends SpringStatelessWidget<(Counter,)> {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Scaffold(
      body: const Center(child: CounterText()),
      // Only calls a method, so a tap does not rebuild the page.
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Reads counter.value in build, so it rebuilds after every increment.
class CounterText extends SpringStatelessWidget<(Counter,)> {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Text('${counter.value}');
  }
}
```

```properties
# lib/resources/application.properties
# Scaffold needs a MaterialApp; the default is a plain WidgetsApp.
spring.flutter.app.type=material
spring.flutter.app.title=Counter
```

A complete app: the [Flutter guide](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide),
a bookstore's app that uses everything the family offers a Flutter app,
explained chapter by chapter.

*In the guides:* [app, 1. The application](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#1-the-application), [2. State in beans](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#2-state-in-beans), [3. Themes](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#3-themes).

## Contents

- [Setup](#setup)
- [`SpringApplicationWidget`](#springapplicationwidget)
- [The app widget from configuration](#the-app-widget-from-configuration)
- [Beans in widgets](#beans-in-widgets)
- [State beans: `@ChangeNotifierComponent`, `@NotifyListeners`](#state-beans-changenotifiercomponent-notifylisteners)
- [Themes from properties](#themes-from-properties)
- [Messages and languages](#messages-and-languages)
- [The app lifecycle](#the-app-lifecycle)
- [Platform profiles](#platform-profiles)
- [Assets](#assets)
- [Configuration at build time](#configuration-at-build-time)
- [The web version's port](#the-web-versions-port)
- [Hot reload](#hot-reload)
- [Tests](#tests)
- [Known limits](#known-limits)
- [Platforms](#platforms)

## Setup

```yaml
dependencies:
  flutter:
    sdk: flutter
  spring_boot_starter_flutter: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
  flutter_test:
    sdk: flutter
  spring_boot_starter_test: ^0.4.3   # springBootTest, BeanOverride
```

Then:

1. Put `@SpringBootApplication()` on `main` in `lib/main.dart`.
2. Run `dart run build_runner watch` (or `build`). The generator writes
   `lib/main.spring.dart`, with `springApplication`: the application,
   with every bean found under `lib/`. Keep `watch` running while you
   work.
3. Put configuration files and message files into `lib/resources/`. The
   generator embeds them into the generated code, so they need no
   `flutter: assets:` entry.

**One import.** The starter depends on `spring_core_dart`,
`spring_boot_dart` and `spring_boot_starter_logging` and exports them.
`import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';`
also gives `@Component`, `@Value`, `@ConfigurationProperties`,
`@SpringBootApplication`, events, validation and JSON.

Two names are left out because Flutter has its own: Boot's startup
`Banner` (Flutter has a `Banner` widget) and the validation constraint
`Size` (`dart:ui` has `Size`). The constraint is exported as
`SizeConstraint`:

```dart
// A title from the configuration must be 1 to 60 characters long.
@ConfigurationProperties('shop')
@Validated()
class ShopProperties {
  @SizeConstraint(min: 1, max: 60)
  String title = 'Books';
}
```

**Logging is on from the start**, as in a Spring Boot app. `SpringLog`
lines go to the console (`flutter run`, the IDE) in Spring Boot's
format, and into an in-memory `LogBuffer` bean that a screen can show.
The levels and patterns come from `logging.*`:

```text
INFO 82749 --- [main] spring_boot_dart.SpringApplication : The following 2 profiles are active: "desktop", "macos"
INFO 82749 --- [main] counter.lifecycle                  : App inactive
```

```properties
logging.level.root=warn
logging.level.counter=debug
```

A class gets a logger with `@Log()`: the generator writes a `log` getter
for it. The logger is named `<package>.<Class>`, or `topic:` when given.
Java developers know this as Lombok's `@Slf4j`.

```dart
// Writes each change of the app's state to the log.
@Component()
@Log(topic: 'counter.lifecycle')
class LifecycleLog {
  @EventListener()
  void onState(AppLifecycleStateEvent event) =>
      log.info('App ${event.state.name}');
}
```

**The other starters stay separate**, as in Spring Boot: add
`spring_boot_starter_feign`, `spring_boot_starter_scheduling`,
`spring_boot_starter_cache`, ... when the app uses them. An app that
logs its user in or keeps secrets lists
[`spring_boot_starter_flutter_security`](https://pub.dev/packages/spring_boot_starter_flutter_security)
instead of this package: it brings this one, the OAuth2 client and the
security core.

## `SpringApplicationWidget`

The root widget, passed to `runApp`. It starts the application: it
reads the configuration files, creates the beans and runs the
application's runners. Meanwhile it shows `splash`. When the start
fails, it shows `failure` and logs the failure report. Once the context
is ready, it gives it to every widget below.

```dart
SpringApplicationWidget(
  // A function, not the value: after a hot reload the widget calls it
  // again to get the new generated code.
  application: () => springApplication,
  splash: (context) => const ColoredBox(color: Colors.white),
  failure: (context, error) => ErrorScreen(error),
  home: const CounterPage(),
)
```

| Parameter | Default | Meaning |
|---|---|---|
| `application` | required | Returns the application to run, `() => springApplication` |
| `home` | — | The first page. The widget builds the app widget around it from the configuration (next section) |
| `child` | — | Your own app widget (`MaterialApp`, ...) instead. Give `home` or `child`, not both |
| `splash` | an empty box | What is shown while the application starts |
| `failure` | a plain screen with the error (a short note in release builds) | What is shown when the start fails |
| `args` | none | Command-line arguments (`--name=value`), read as properties; for desktop apps started with some |
| `rerunRunnersOnReload` | `false` | Whether `ApplicationRunner` and `CommandLineRunner` beans run again after a hot reload restarts the context |

Besides starting the application, it:

- adds the platform's profiles ([Platform profiles](#platform-profiles));
- does not read the OS environment variables
  ([Configuration at build time](#configuration-at-build-time));
- loads the font files among the app's assets
  ([Fonts](#fonts));
- checks that every bean a Spring widget needs exists, so a missing one
  fails the start instead of a later build;
- publishes the app's lifecycle and pauses the context in the background
  ([The app lifecycle](#the-app-lifecycle));
- restarts the context after a hot reload that changed beans
  ([Hot reload](#hot-reload));
- closes the context when it is removed from the tree (`@PreDestroy`
  methods run, lifecycle beans stop).

Spring (Java) has no widget. The nearest thing is the `main` method of a
Spring Boot app, `SpringApplication.run(App.class, args)`.

## The app widget from configuration

With `home:`, `SpringApplicationWidget` puts a `SpringApp` at the root:
a `WidgetsApp`, `MaterialApp` or `CupertinoApp` set up by properties
instead of code. The properties can differ per profile, so iPhones can
get a `CupertinoApp` while the other platforms get a `MaterialApp`.

```properties
# lib/resources/application.properties
spring.flutter.app.type=material
spring.flutter.app.title=NEON Books
spring.flutter.app.debug-banner=false
spring.flutter.app.locales=en,ja
```

```properties
# lib/resources/application-ios.properties: the iOS look on iPhones
spring.flutter.app.type=cupertino
```

| Key | Default | Meaning |
|---|---|---|
| `spring.flutter.app.type` | `widgets` | `widgets` (a `WidgetsApp`, no Material or Cupertino design), `material` (needed by `Scaffold`, `AppBar` and the other Material widgets) or `cupertino` |
| `spring.flutter.app.title` | empty | The app's name for the OS: the task switcher, the browser tab |
| `spring.flutter.app.debug-banner` | `true` | Flutter's DEBUG banner in debug builds |
| `spring.flutter.app.locales` | the languages of the messages files | The locales the app supports, comma-separated (`en,ja,pt_BR`) |

- **Locales.** By default the app supports the languages it has texts
  for: `messages.properties` counts as English, and each
  `messages_<locale>.properties` adds its locale (`messages_ja` adds
  `ja`). So the app's locales and `context.message` agree. Flutter's own
  translations for the app type (the texts of its widgets, in every
  language) are added; `flutter_localizations` comes with the starter.
  Write `locales` as one comma-separated value, also in YAML
  (`locales: en, ja`): a YAML list is not read
  ([Known limits](#known-limits)).
- **Theme.** From `spring.flutter.theme.*`, see
  [Themes from properties](#themes-from-properties).
- **`NavigatorObserver` beans** become the app's navigator observers, in
  `@Order`.
- **`FlutterAppCustomizer` beans** change whatever no property covers: a
  `builder`, keyboard `shortcuts`, the `scrollBehavior`, the app's own
  localization delegates. Each one gets the `FlutterAppSettings` once,
  before the app widget is first built, in `@Order`:

  ```dart
  // The app's own translations, and text that never grows past 130 %.
  @Component()
  class AppLocalizations implements FlutterAppCustomizer {
    @override
    void customize(FlutterAppSettings app) {
      app.localizationsDelegates.add(LegalTerms.delegate);
      app.builder = (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child!,
      );
    }
  }
  ```

  Spring Boot (Java) customizes its web server the same way, with a
  `WebServerFactoryCustomizer` bean.
- **Checked at the start.** The settings are made once per context, when
  the application starts. An invalid value (`type=swing`,
  `debug-banner=maybe`) fails the start with the failure report, naming
  the property.
- **With `child:`** you write your own app widget, and these keys are not
  used.

There are no route properties yet (`routes`, `onGenerateRoute`,
`routerConfig`): `home` is the first page, and the app navigates with
`Navigator`.

## Beans in widgets

Services get their beans through their constructors. Widgets cannot:
Flutter and your own code create them, so nothing is injected into them.
A widget gets beans in one of four ways.

**`context.bean<T>()`** returns any bean by type, or by name with
`qualifier:`. It works in every widget and callback, so it suits one-off
uses, such as a button that calls a service. It does not rebuild the
widget when the bean changes.

```dart
// Sends the order when tapped.
FilledButton(
  onPressed: () => context.bean<OrderService>().placeOrder(),
  child: const Text('Order'),
);
```

**Generated getters.** Mark a bean `@BuildContextAccess()` and the
generator writes a typed getter on `BuildContext`, named after the bean:
`context.basket`. Use it for the few beans many widgets need, deep in the
tree: a basket, a session, the current user. Only marked beans get one,
so the list stays short. `@BuildContextAccess(name: 'cart')` picks
another name. The getters are generated into `main.spring.dart`; import
it where you use them. Like `context.bean`, a getter does not rebuild the
widget when the bean changes.

```dart
@ChangeNotifierComponent()
@BuildContextAccess()
class Basket { ... }

// In a book's tile: put the book into the basket on a tap.
IconButton(
  onPressed: () => context.basket.add(book),
  icon: const Icon(Icons.add_shopping_cart),
);
```

**`SpringStatelessWidget<(...)>`** is the usual way for a widget that
shows or uses beans. The widget lists its beans in its type, as a record,
and reads them from `beans` in `build`. Compared with `context.bean`:

- the beans are typed and listed in one place;
- the generator sees every such widget, so a missing bean fails the
  start, not some later build;
- the widget rebuilds when a state bean it shows changes (see
  [State beans](#state-beans-changenotifiercomponent-notifylisteners)).

One bean stays in place (`<(Basket,)>`). For several, name the record
with a typedef named after the widget, one bean per line with a trailing
comma ([code style](https://github.com/farum-azula/spring_core_dart/blob/main/docs/style.md#beans-of-a-widget)):

```dart
/// The beans of [BasketBadge].
typedef BasketBadgeBeans = (
  Basket,
  Clock,
);

// The basket's icon with the number of books.
class BasketBadge extends SpringStatelessWidget<BasketBadgeBeans> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final (
      basket,
      clock,
    ) = beans;
    return Badge(
      label: Text('${basket.count}'),
      isLabelVisible: clock.now().hour < 22, // no badge at night
      child: const Icon(Icons.shopping_basket_outlined),
    );
  }
}
```

Read `beans` in `build` and in the callbacks made there (`onPressed`).
A widget is immutable, and one `const` instance may be built in several
places, so after `build` it holds the beans of its latest build. A widget
built under two application contexts at once (rare: two
`SpringScope`s) takes them into locals in `build`, as above.

A record with named fields (`({Clock utc})`, read as `beans.utc`) works
too. When several beans have a field's type, the field's name picks one,
like a constructor parameter's name in Spring. A nullable field
(`Clock?`) is optional.

**`SpringStatefulWidget<(...)>`** with a **`SpringState<W, (...)>`** is
the same for a widget that also needs a `State`: a text controller, an
animation, or work started in `initState`. The `State` has the beans as
`beans`, available from `initState` on. Dart cannot take the record from
the widget, so it is written on both; the compiler checks that they
match, and a typedef keeps it in one place.

```dart
/// The beans of [BasketPage].
typedef BasketPageBeans = (
  Basket,
  Clock,
);

class BasketPage extends SpringStatefulWidget<BasketPageBeans> {
  const BasketPage({super.key});

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends SpringState<BasketPage, BasketPageBeans> {
  @override
  void initState() {
    super.initState();
    // Fetch the basket from the server once, when the page opens.
    final (
      basket,
      _,
    ) = beans;
    basket.load();
  }

  @override
  Widget build(BuildContext context) {
    final (
      basket,
      clock,
    ) = beans;
    return Text('${basket.count} books at ${clock.now()}');
  }
}
```

A `SpringState` that overrides `dispose` or `didChangeDependencies` must
call `super`.

**When Spring widgets rebuild.** A `SpringStatelessWidget` or
`SpringState` rebuilds when one of its beans that is a `Listenable`
notifies. For a `@ChangeNotifierComponent` or `@NotifyListeners` bean,
only when the widget's `build` read its state (see
[Reading is free](#reading-is-free)). Every widget that gets beans is
also built afresh when the context is replaced after a hot reload. With
`context.bean` and the getters, listen yourself, as usual in Flutter:
`ListenableBuilder` for a `Listenable`, `StreamBuilder` for a stream.

Spring has no counterpart: a Java bean is injected into a controller or a
view, never looked up from a UI tree.

## State beans: `@ChangeNotifierComponent`, `@NotifyListeners`

In Flutter, shared state is usually a `ChangeNotifier` whose methods end
with `notifyListeners()`; a forgotten call leaves the screen stale. Here
the bean's generated proxy (an object that wraps the bean and runs code
around its methods) makes that call.

**`@ChangeNotifierComponent()`** declares a state bean from a plain
class: no `extends ChangeNotifier`, no `notifyListeners()`. It is a
`@Component`, so the class becomes a bean. Its proxy is a
`ChangeNotifier` and notifies after every public method and setter,
except the ones named in `exclude`. Getters never notify.

```dart
// The basket, shared by the book screen, the badge and the Basket screen.
@ChangeNotifierComponent(exclude: ['peek'])
class Basket {
  Basket(this._api);

  final ShopApi _api;
  final _items = <String>[];

  int get count => _items.length;      // a getter: never notifies

  void add(String isbn) => _items.add(isbn);
  void clear() => _items.clear();
  String? peek() => _items.lastOrNull; // excluded: only reads

  Future<void> load() async {          // notifies when the Future completes
    _items.addAll(await _api.basket());
  }
}
```

The class itself is no `Listenable`, since generated code cannot give it
a superclass; the bean the container hands out is. So:

- `SpringStatelessWidget` and `SpringState` subscribe to it by
  themselves;
- elsewhere, `listenableOf(bean)` gives the `Listenable`:
  `ListenableBuilder(listenable: listenableOf(context.basket), builder: ...)`.
  It throws an `ArgumentError` for an object that is no `Listenable`,
  such as an instance created by hand.

The build fails when a name in `exclude` is not a method, setter or
field of the class, or when the class declares one of
`ChangeNotifier`'s own members (`addListener`, `dispose`, ...).

**`@NotifyListeners()`** does the same for a class that already extends
`ChangeNotifier`, for example because it also notifies from a stream
callback. On the class it notifies after every public method and setter
(except `exclude`); on a method or setter, after that one only.

```dart
// Notifies after `select`, `clear` and every write to `selected`.
@Component()
@NotifyListeners()
class Search extends ChangeNotifier {
  Book? selected;

  void select(Book book) => selected = book;
  void clear() => selected = null;
}

// Only `restock` notifies.
@Component()
class Stock extends ChangeNotifier {
  final _available = <String, int>{};

  @NotifyListeners()
  void restock(String isbn, int count) => _available[isbn] = count;
}
```

Either way the listeners are notified after the method returns, also
when it throws (the state may have changed before the error), and after
a returned `Future` completes. It works on the bean the container hands
out, not on an instance created by hand. Calls the bean makes on itself
(`this.add(...)`) notify only when its proxy is a subclass proxy (a class
with private members); otherwise only calls from outside notify.

Spring has no counterpart. It is advice around the bean's methods, like
`@Transactional`.

### Reading is free

A Spring widget listens to a `@ChangeNotifierComponent` bean, or to a
class marked `@NotifyListeners`, only when its `build` read the bean's
state: a getter or a field. Calling a method (`onPressed:
counter.increment`) costs no rebuilds. So a page can hold the counter for
its button while only the `Text` that shows the count rebuilds:

```dart
class CounterPage extends SpringStatelessWidget<(Counter,)> {
  const CounterPage({super.key});

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

The proxy sees the reads, so the rule follows what the widget actually
shows: a build that stops reading the bean stops listening, and the next
one that reads it listens again. The bean's reads of itself, inside its
own methods, do not count.

One case to know: a read outside the widget's own `build` (in a
`ListView.builder` item builder, a `Builder` below it, a callback,
`initState`, another bean) cannot be told apart from a read for the
screen. After one, every widget holding the bean keeps listening, so the
screen is never stale but may rebuild more than needed. Call methods
rather than reading state outside `build` when that matters.

Any other `Listenable` bean (a plain `ChangeNotifier`, or one with
`@NotifyListeners` on methods only) is listened to always.

## Themes from properties

The look of the app is configuration too: the part shared by every
theme, the standard `light` and `dark` themes, and any number of themes
of your own, in `.properties` or `.yml`, per profile, even loaded from a
server at run time. There is no `ThemeData` in the code, and every value
the properties leave out is Flutter's Material 3 default. Designers can
change the look in one file without touching widget code.

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
      components:                             # values refer to the tokens above
        app-bar: { center-title: true, scrolled-under-elevation: level2, title-style: title-large }
        button: { shape: full, padding: '24, 10' }
        filled-button: { shape: medium }
        card: { shape: large, color: surface-container-low, elevation: level1 }
        input: { style: outline, shape: small }
        navigation-bar: { label-behavior: onlyShowSelected }
        snack-bar: { behavior: floating }
      tokens:                                 # the app's own values, read through SpringTheme
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

- **Standard and custom themes.** `light` and `dark` always exist, made
  from the shared part with Material's light and dark palettes. A custom
  theme is light unless it says `brightness: dark` or extends a dark one.
  `extends` builds a theme on another one; a cycle or an unknown name
  fails the start. Custom themes can live in files of their own:
  `spring.config.import: classpath:themes/ocean.yml`.
- **Components** are Material's, built from the tokens as Material 3
  specifies; `components.*` only changes what differs. A changed shape
  value reaches the components that use it (`shape.medium` → cards). The
  components: `app-bar`, `button` (all four buttons) and
  `filled-button` / `elevated-button` / `outlined-button` / `text-button`,
  `card`, `input`, `chip`, `dialog`, `bottom-sheet`, `navigation-bar`,
  `snack-bar`, `tooltip`, `list-tile`, `divider`,
  `floating-action-button`, `tab-bar`, `popup-menu`.
- **Checked at the start.** Every theme is read when the application
  starts. An invalid value (`seed-color: purpel`, `shape: hugee`) or a
  misspelled key (`seed-colour`, `typography.body.colour`, an unknown
  component or component property) fails the start, naming the property
  and what it may be.
- **Made once.** Each theme becomes a `SpringThemeData`, a Material
  `ThemeData` and a `CupertinoThemeData` once; switching only picks
  another one.
- **Switching at run time.** The `ThemeSelection` bean holds the choice:
  `select('ocean')`, or `select('system')` to follow the device's light
  or dark mode. The app follows at once, with Flutter's animation. The
  choice is not stored; an app that wants to remember it saves
  `selection.active` itself.

  ```dart
  /// The beans of [ThemeMenu].
  typedef ThemeMenuBeans = (
    ThemeSelection,
    SpringThemes,
  );

  // A menu of every theme; picking one changes the whole app at once.
  class ThemeMenu extends SpringStatelessWidget<ThemeMenuBeans> {
    const ThemeMenu({super.key});

    @override
    Widget build(BuildContext context) {
      final (
        selection,
        themes,
      ) = beans;
      return PopupMenuButton<String>(
        onSelected: selection.select,
        itemBuilder: (_) => [
          for (final name in ['system', ...themes.names])
            CheckedPopupMenuItem(
              value: name,
              checked: selection.active == name,
              child: Text(name),
            ),
        ],
      );
    }
  }
  ```
- **Themes from a server.** `SpringThemes.loadYaml(yaml)` (or
  `load(map)`) adds or changes themes at run time, over the files'
  properties. They are checked first, so an invalid one throws a
  `ThemePropertyException` and changes nothing. `unload()` drops them
  again; a selection showing a theme that is gone falls back to `system`.

  ```dart
  // A seasonal theme published on the shop's server, shown right away.
  themes.loadYaml(await http.read(Uri.parse('https://cdn.example.com/themes.yml')));
  selection.select('winter');
  ```
- **The app's own widgets** read the theme shown, whatever the app type,
  with `SpringTheme.of(context)`. It has what Material's `Theme` has no
  place for: `colorScheme`, `textStyle('code')`, `shape('large')`,
  `space('m')`, `duration('medium')`, `curve('standard')`,
  `tokenColor('brand.accent')`, `tokenNumber('brand.hero-height')`.

  ```dart
  // A banner sized and colored by the brand's tokens.
  final theme = SpringTheme.of(context);
  Container(
    height: theme.tokenNumber('brand.hero-height'),
    color: theme.tokenColor('brand.accent'),
    padding: EdgeInsets.all(theme.space('m')),
    child: Text('NEON Books', style: theme.textStyle('headlineMedium')),
  );
  ```
- **Cupertino and Widgets apps.** `type: cupertino` gets a
  `CupertinoThemeData` from the same theme (primary color, text styles,
  backgrounds where set; iOS's defaults otherwise). `type: widgets` gets
  the theme's text style and color.
- **Replacing a part in code.** A `ThemeData` bean named `theme` or
  `darkTheme` replaces the made `light` or `dark` Material theme, and a
  `CupertinoThemeData` bean the Cupertino ones. `ThemeCustomizer` and
  `CupertinoThemeCustomizer` beans adjust every made theme, in `@Order`,
  for what the properties do not cover:

  ```dart
  // Stadium-shaped chips in every theme.
  @Component()
  class RoundedChips implements ThemeCustomizer {
    @override
    ThemeData customize(ThemeData theme, SpringThemeData spring) =>
        theme.copyWith(
          chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
        );
  }
  ```

Every theme property, step by step and as a reference:
[Configuration, 17. Reference: Flutter](https://github.com/farum-azula/spring_core_dart/blob/main/docs/configuration.md#17-reference-flutter).
A complete app with every theme feature and golden screenshots of each
theme: [the Flutter guide, 3. Themes](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#3-themes).

### Fonts

Font files go into any directory under `flutter: assets:` and are listed
nowhere else. When the application starts (behind the splash screen),
the starter loads every `.ttf` and `.otf` file among the app's assets,
into the family the file itself names: `Inter-SemiBold.ttf` becomes a
weight of `Inter`. The theme then names families only. Families declared
under `flutter: fonts:` keep working. A family the theme names but
neither the assets nor `flutter: fonts:` have is logged as a warning (it
may still be one of the platform's own fonts, such as `.SF UI Text`). A
file whose family cannot be read, such as a `.ttc` collection, is
skipped with a warning.

```properties
# false: load no font file this way
spring.flutter.fonts.auto-load=true
# font files for other uses, such as PDFs
spring.flutter.fonts.exclude=assets/pdf/**
```

## Messages and languages

`context.message` returns a text from the application's message files
(`lib/resources/messages.properties`, `messages_ja.properties`, ...) in
the app's current language: the locale of `Localizations`, else the
device's. `args` fill the `{0}`, `{1}`, ... placeholders.

```properties
# lib/resources/messages.properties
basket.total=Total: {0}
# lib/resources/messages_ja.properties
basket.total=合計：{0}
```

```dart
Text(context.message('basket.total', args: [total]));
```

A missing code throws a `NoSuchMessageException`, unless you pass
`defaultMessage:` or set `spring.messages.use-code-as-default-message=true`
(then the code itself is shown).

The app's locales are the languages of these files unless
`spring.flutter.app.locales` lists them
([The app widget from configuration](#the-app-widget-from-configuration)).
With other files than `messages*.properties`, set
`spring.messages.basename` as one comma-separated value with `/` as the
separator (`i18n/messages,i18n/errors`): the starter looks for the
locales of these files that way ([Known limits](#known-limits)).

## The app lifecycle

Each change of Flutter's `AppLifecycleState` is published as an
`AppLifecycleStateEvent`, so any bean can react without a widget in
between:

```dart
// An unsent draft is saved when the user leaves the app.
@EventListener()
void onLifecycle(AppLifecycleStateEvent event) {
  if (event.state == AppLifecycleState.paused) drafts.save();
}
```

When the app goes to the background (`hidden` or `paused`), the context
is paused: `@Scheduled` tasks, WebSocket connections and the other
pauseable `SmartLifecycle` beans stop, then a `ContextPausedEvent` is
published. Back in the foreground (`resumed`), they start again and a
`ContextRestartedEvent` follows. This saves battery and data; it is
the context's `pause()` and `restart()` of Spring Framework 7. To keep
them running in the background:

```properties
spring.flutter.lifecycle.pause-in-background=false
```

`@Scheduled` tasks are scheduled afresh when the app comes back, so the
runs missed in the background are not made up. Tasks a bean starts
itself with the `TaskScheduler` (`scheduleAtFixedRate`,
`scheduleWithFixedDelay`, ...) are not paused: they keep running while
the system lets the app run, and when it suspended the app, they catch
up on its return as Spring's scheduler does. A fixed-rate task then
starts every run missed meanwhile at once (a 1-second rate after a
minute away: about 60 runs back to back); a fixed-delay one runs once
and goes on. So give polls and UI ticks a fixed delay, or cancel them
when their screen goes away (or on `ContextPausedEvent`). The same holds
for `@Scheduled(fixedRate: ...)` with `pause-in-background=false`, and
for a browser tab whose timers are throttled while hidden.

## Platform profiles

A profile is a name that switches configuration files and beans on. The
platform the app runs on is an active profile:

| Platform | Profiles |
|---|---|
| Android | `mobile`, `android` |
| iOS | `mobile`, `ios` |
| macOS | `desktop`, `macos` |
| Windows | `desktop`, `windows` |
| Linux | `desktop`, `linux` |
| a browser | `web` |

So an app can configure and assemble itself per platform without code.
Profile files load by themselves, and the specific one wins over the
group (`application-ios.properties` over `application-mobile.properties`):

```text
lib/resources/application.properties          api.url=https://api.neon.books
lib/resources/application-mobile.properties   images.size=small
lib/resources/application-ios.properties      push.provider=apns
```

```dart
// Each platform gets its own push service.
@Component()
@Profile(['android'])
class FcmPushService implements PushService { ... }

@Component()
@Profile(['ios'])
class ApnsPushService implements PushService { ... }
```

The profiles follow Flutter's `defaultTargetPlatform`. In a widget test
the platform is Android unless the test changes it
(`debugDefaultTargetPlatformOverride`).

## Assets

A Flutter app has two places for files, as a Spring app has
`src/main/resources` and its static content:

| | `lib/resources/` | Flutter assets (`flutter: assets:` in `pubspec.yaml`) |
|---|---|---|
| for | config files, messages, small texts and templates | images, video, sound, large data |
| how | embedded into the generated code (up to 1 MB per file) | in the app's asset bundle, loaded when read |
| location | `classpath:mail/welcome.txt` | `asset:assets/intro.mp4` |
| reading | synchronous or asynchronous | asynchronous |

Both are injected the same way, with `@Value` and a `Resource`. A bean
that reads a file then does not care where it comes from:

```dart
// The About screen's logo and text.
@Component()
class AboutContent {
  AboutContent(
    @Value('asset:assets/images/logo.png') this.logo,
    @Value('asset:assets/texts/about.md') this.text,
  );

  final Resource logo;
  final Resource text;

  Future<String> read() => text.readAsString();

  // Flutter's image, video and audio APIs take the asset key.
  ImageProvider get logoImage => AssetImage((logo as AssetResource).key);
}
```

`asset:` gives an `AssetResource` of `rootBundle`; an `AssetBundle` bean
replaces `rootBundle` (in tests, for example). `asset:/assets/x.png`
works too, and so does `context.getResource('asset:...')`. `exists()`
looks the key up in the app's asset manifest, which
`SpringApplicationWidget` loads before the start. (`@Resource` is not for
this: in Spring, and here, it injects a bean by name.)

Spring (Java): a `ClassPathResource` from `@Value("classpath:...")`.

The generator checks every `@Value('asset:...')`. A missing file, or one
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
directory, but not those of its subdirectories (as in Flutter). Keys
with placeholders (`asset:${sound.file}`) and other packages' assets
(`asset:packages/...`) are only known at run time and are not checked.

## Configuration at build time

A Flutter app has no command line, and on a phone the OS environment
variables are of no use. So `SpringApplicationWidget` does not read them.
On desktop, a build can turn them on with
`--dart-define=spring.flutter.scan-os-environment=true`.

Values for a build come from `--dart-define` instead. They go into a
property source that wins over the config files:

```sh
flutter run --dart-define=SPRING_PROFILES_ACTIVE=dev --dart-define=API_URL=http://localhost:8080
flutter build apk --dart-define-from-file=config/prod.json
```

A define is read like an environment variable in Spring Boot:
`API_URL` answers both `@Value(r'${API_URL}')` and `api.url`.

A compiled app can only read the defines whose names the generator wrote
into `main.spring.dart` (`String.fromEnvironment` needs a constant
name). It writes every name the app can read: the `${...}` placeholders
of annotations, the fields of `@ConfigurationProperties` classes, the
keys of the config files, and a few such as `spring.profiles.active`.
Each name is offered as it is (`api.url`) and in the environment form
(`API_URL`). A define for any other name is not seen.

Everything defined at build time ends up in the app and can be read from
it: no secrets there.

## The web version's port

`flutter run -d chrome` (or `-d web-server`) serves the web version on a
random port, such as `localhost:54385`. That breaks whatever needs a
fixed origin: the server's CORS list, the page an SSO login sends the
browser back to. Set the port in the app's config, and every
`flutter run` on the web uses it, from an editor or the command line:

```yaml
# lib/resources/application-web.yaml: only the web reads it
spring:
  flutter:
    web:
      port: 5050
```

Since Flutter 3.38, `flutter run` on the web reads its dev server's
settings from `web_dev_config.yaml` in the project directory.
`spring_core_dart_generator` writes that file from the
`spring.flutter.web.*` properties when `build_runner` runs. It reads them
as the app reads its config in a browser: `application.*`, then
`application-web.*` (the `web` platform profile), and the files of the
profiles `spring.profiles.active` names there. Environment variables and
`--dart-define` values do not count, because the file is written at
build time: a placeholder only they resolve (`${APP_PROFILE}` without a
default) leaves out the profile name it is in (`dev,${ENV}-eu` is read as
`dev`), the import location it is in, or the document whose
`spring.config.activate.*` guard has it, with a warning (in a
`spring.flutter.*` value it fails the build). A `--web-port` or
`--web-hostname` flag still wins over the file.

| Property | Default | Description |
|---|---|---|
| `spring.flutter.web.host` | any address | The address to listen on (`localhost`, `0.0.0.0` for other devices on the LAN) |
| `spring.flutter.web.port` | a free port | The port, from 0 to 65535 |
| `spring.flutter.web.base-href` | `/` | The path the app is served under, starting and ending with `/` (`/shop/`) |
| `spring.flutter.web.https.cert-path` | none (HTTP) | The TLS certificate (PEM); serves HTTPS together with `cert-key-path` |
| `spring.flutter.web.https.cert-key-path` | none | Its private key (PEM) |
| `spring.flutter.web.headers.<Name>` | none | A header added to every response (`spring.flutter.web.headers.Cross-Origin-Opener-Policy=same-origin`) |
| `spring.flutter.web.proxy[n].target` | none | The server that the requests matching the rule are forwarded to (`http://localhost:8080`) |
| `spring.flutter.web.proxy[n].prefix` | none | The rule matches paths starting with it (`/api/`) |
| `spring.flutter.web.proxy[n].regex` | none | Or the paths matching this pattern; set exactly one of `prefix` and `regex` |
| `spring.flutter.web.proxy[n].replace` | the path unchanged | The forwarded path: the matched part replaced, `$1` for a group |

The proxy is the simplest way to talk to your own server during
development. With `/api/` forwarded to the server, the page and the API
have one origin: no CORS settings on the server, and a session cookie is
an ordinary first-party cookie, so a login with a session works in every
browser, including those that block third-party cookies.

```properties
# lib/resources/application-web.properties
spring.flutter.web.port=5050
spring.flutter.web.proxy[0].prefix=/api/
spring.flutter.web.proxy[0].target=http://localhost:8080
# the app calls the API at its own origin: http://localhost:5050/api/...
```

The build fails, naming the property, for a port outside 0..65535 or not
a number, an empty host, a `base-href` without the slashes, only one of
the two HTTPS paths, or a proxy rule without `target` or without exactly
one of `prefix` and `regex`. A misspelt `spring.flutter.web.*` name is a
warning.

The generated file starts with a `# GENERATED FILE - DO NOT MODIFY BY HAND.`
comment saying where its values come from; edit the properties, not the
file. Commit it with the other
generated files, so that `flutter run` works right after a checkout.
Without these properties nothing is written. A `web_dev_config.yaml` you
wrote yourself is never changed or deleted: with the properties set as
well, the build fails and asks you to remove one of the two. After
deleting the file, run `dart run build_runner clean` or change a file of
`lib/resources/`: `build_runner` does not watch `web_dev_config.yaml`.

These settings are for `flutter run` only: `flutter build web` makes
files for your own web server, which has its own settings.

## Hot reload

A hot reload (`r` in `flutter run`, saving in the IDE) puts the new code
into the running app without starting it again: `main` does not run, and
the objects in memory stay. For beans that is a problem. The application
context was built from the old generated code, so a new `@Component`
would be missing and a changed one would keep its old dependencies.

`SpringApplicationWidget` takes care of it, as Spring Boot DevTools'
*restart* does; it is on by default and needs no setup. Flutter calls the
root widget's `reassemble()` on every hot reload. There the widget
compares the fingerprint of the generated code (`lib/main.spring.dart`)
with the one the running context was built from.

**Only method bodies changed: the context stays.** The fingerprint is the
same, so nothing restarts. Dart already runs the new method bodies, and
the beans keep their state.

```dart
@Component()
@BuildContextAccess()
class Counter extends ChangeNotifier {
  int value = 0;
  void increment() {
    value += 2;          // was `value++`: after `r` the next tap adds 2,
    notifyListeners();   // and the count reached so far is kept
  }
}
```

**Beans, annotations or `lib/resources/` changed: the context restarts.**
With `dart run build_runner watch` running, the generator rewrites
`main.spring.dart` a moment after you save. The next hot reload sees a
new fingerprint, and the widget:

1. closes the running context (`@PreDestroy` methods run, lifecycle
   beans stop, `ContextClosedEvent`);
2. starts the application again with the new beans and config files. The
   `ApplicationRunner`s do not run again, unless
   `rerunRunnersOnReload: true`: the app did not really start again;
3. builds the widgets below it afresh, their `State`s included, so no
   widget keeps a bean of the closed context. Navigation and scroll
   positions start over, as after a hot restart, but the app process
   (and anything outside the context) stays.

```dart
// Added while the app runs; `build_runner watch` regenerates, then `r`:
@Component()
class Clock {
  DateTime now() => DateTime.now();
}

// and in a widget:
Text('${context.bean<Clock>().now()}');   // found: the context restarted
```

```properties
# application.properties: no code changed, still a restart
counter.step=2
```

**What a hot reload cannot do.** Without `build_runner watch` the
generated code stays old: a new bean is not found until you run the
generator and reload again. A change Flutter itself cannot hot reload (a
changed `main`, an enum turned into a class, ...) needs a hot restart
(`R`), which starts everything from `main`. When the restart of the
context fails (a bean that throws, a bad property), the failure screen
shows the error; fix the code and reload again, and the widget starts
the application anew.

**Turning it off.** A context restart drops the state of every bean. To
keep the context as it is after every hot reload (and restart by hand
with `R` when beans changed), set Spring Boot DevTools' switch:

```properties
spring.devtools.restart.enabled=false
```

Release and profile builds have no hot reload, so none of this happens
there.

## Tests

`springBootTest` from `spring_boot_starter_test` works under
`flutter_test`. It starts the application once for the file's tests,
with test properties and fakes. Put the widget under a `SpringScope` with
the test's context, and under a `SpringApp` for the app widget, themes
and texts of the properties. Replace beans with `BeanOverride`:

```dart
void main() {
  final app = springBootTest(
    springApplication,
    properties: {'counter.step': 2},
    overrides: [BeanOverride<Clock>(FixedClock())],
  );

  setUp(app.markDirty); // a fresh Counter for every test

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

`springBootTest` adds no platform profile. To test the start itself
(splash, a failed start, the platform profiles), pump
`SpringApplicationWidget` as `runApp` does.

A `SpringStatelessWidget` can also be built with fakes and no
application, through `buildWith`:
`const BasketBadge().buildWith(context, (FakeBasket(), FakeClock()))`.

More, and the planned Flutter test starter:
[Flutter testing](https://github.com/farum-azula/spring_core_dart/blob/main/docs/flutter-testing.md).

## Known limits

- **`spring.flutter.app.locales` and `spring.messages.basename` are read
  as single values.** Write them comma-separated, also in YAML
  (`locales: en, ja`). A YAML list (`[en, ja]`) is not seen: the locales
  then come from the message files, and the starter looks for the
  locales of `messages*.properties` even when the application's
  `MessageSource` reads other files. Write the basename with `/`
  (`i18n/messages`): the `MessageSource` also accepts dots
  (`i18n.messages`), but the starter then finds no locale files.
- **`ThemeConfig` is not exported.** `SpringThemes.config` returns one
  and `SpringThemeData.of` takes one, but an app cannot name the type.
  Its values are readable (`themes.config.active`); to show a theme, use
  `SpringThemes.data(name)` and `ThemeSelection`.
- **Widgets with the same beans record share one binding.** The
  generator writes one binding per record type, and widgets find it by
  that type. When a bean is missing, the start fails naming one of the
  widgets that use the record, not each of them.
- **No route properties**: the app navigates with `Navigator`
  ([The app widget from configuration](#the-app-widget-from-configuration)).
- **`SpringApplicationWidget` takes no bean overrides** for tests: a
  test that replaces beans and starts the whole app adds the overrides
  to a copy of `springApplication` itself (see the Flutter guide's
  `test/support/fake_server.dart`).

## Platforms

Android, iOS, macOS, Windows, Linux and the web. On Fuchsia the only
platform profile is `fuchsia`.

The starter is pure Dart and Flutter: no platform code of its own, no
plugin. Logins and secrets (the Keychain, the Android Keystore, the
system's login window, widgets that follow the logged-in user) are
[`spring_boot_starter_flutter_security`](https://pub.dev/packages/spring_boot_starter_flutter_security),
which brings this package; an app without a login carries none of it.
