# spring_boot_starter_flutter

An app on `spring_boot_starter_flutter` needs no package stack around Flutter.
Dependency injection, HTTP, JSON, configuration, state, navigation,
storage, background work and logging come from the Spring family, so the
app's `pubspec.yaml` lists Flutter, `spring_boot_starter_flutter` and the starters it
uses. Like the rest of the family, `spring_boot_starter_flutter` depends only on this
repository, the Flutter SDK and plugins of the Flutter and Dart teams
(`path_provider`, `shared_preferences`). The exceptions are packages that
nothing here should replace, each in its own optional starter and allowed
only there by the dependency check: Flutter Scene (3D, bound to the UI),
signals (reactive state) and a Rust bridge.

| Usually | With `spring_boot_starter_flutter` |
|---|---|
| `get_it`, `provider`, `riverpod` (dependency injection) | beans, constructor injection, `context.basket` / `SpringStatelessWidget<(...)>` in widgets, a bean scope per route |
| `dio`, `http`, `retrofit`, `web_socket_channel` | `spring_web_dart` transports, `@FeignClient`, `EventStream<T>`, `@WebSocketClient` (done) |
| `json_serializable`, `freezed` (JSON) | `ObjectMapper` on generated metadata (done) |
| `bloc`, `getx`, `mobx` (state) | beans with `@Signal` fields (`flutter_spring_signals`), application events, `@EventListener` |
| `go_router`, `auto_route` (navigation) | `@Route` widgets and a generated router on the Flutter SDK's `Router` |
| a hand-written `MaterialApp` (theme, locales, debug banner) | the app widget from `spring.flutter.app.*`, one `SpringThemeData` bean from `spring.flutter.theme.*` (Material and Cupertino themes made from it once), customizer beans |
| `flutter_dotenv`, `envied`, flavors (configuration) | `application-{profile}.properties`, `--dart-define` as a property source, platform profiles |
| `hive`, `shared_preferences` wrappers (settings, storage) | `@ConfigurationProperties` saved in `shared_preferences`; SQLite through the Data starter |
| `easy_localization` (texts) | `MessageSource` with `messages_{locale}.properties`, following the app's `Locale` |
| `workmanager`, hand-made timers (background work) | `@Scheduled` and the `TaskExecutor` (worker isolates), following the app lifecycle |
| `flutter_secure_storage` (tokens) | a `TokenStore` bean on the Keychain / Keystore through own platform channels |
| `logger` | `SpringLog` (on by default), log files in the app's directory, the logs in the Actuator (planned) |
| `mocktail` setups (tests) | `springBootTest` and `BeanOverride` under `flutter_test` (done) |

## Status

Done: `SpringApplicationWidget` (start, splash and failure screens, hot reload, close),
beans in widgets (`context.bean<T>()`, `@BuildContextAccess` getters,
`SpringStatelessWidget<(...)>` / `SpringStatefulWidget<(...)>` checked at startup), the app lifecycle as events with
pause / restart of the context, platform profiles, `--dart-define` as a
property source, the OS environment switch, `context.message`, tests with
`SpringScope` and `springBootTest`; the example `example/flutter_counter`.

Next: the app widget from configuration (`MaterialApp` / `CupertinoApp` /
`WidgetsApp` built from properties and beans), `@ConditionalOnPlatform(include: [AppPlatform.android, AppPlatform.ios],
exclude: [AppPlatform.web])` on top of the platform profiles (an
annotation with enums that the generator turns into a profile expression;
not `@Platform`, which `dart:io` already has), navigation (`@Route`, the
`route` scope, `AppNavigator`), settings
in `shared_preferences`, the `TokenStore`, beans kept in fields that
survive a hot reload; later an Actuator screen (logs, beans, environment,
conditions) on the endpoints of [spring_boot_actuator](spring_boot_actuator.md).

Optional starters: [signals](flutter_spring_signals.md), [Flutter Scene](flutter_spring_scene.md), [Rust](flutter_spring_rust.md).

## `SpringApplicationWidget`

The root widget. Starts the application (`runApplicationAsync`), shows a
splash screen until the runners are done (or the failure report), and gives
the context to the tree (see *Beans in widgets*).

## The app widget from configuration

Today the app writes its `MaterialApp` by hand under
`SpringApplicationWidget`: theme, locales, debug banner, title, all in
code. Like Boot configures Jackson or the web server from `spring.*`
properties and customizer beans, the starter builds the app widget itself,
so the look of the app is configuration — per profile, per platform,
changed without code, in `.properties` or `.yml` alike:

```yaml
# lib/resources/application.yml
spring:
  flutter:
    app:
      type: material              # widgets (default) | material | cupertino
      title: ${counter.title}
      debug-banner: false         # default true, as in Flutter
      locales: [en, ja]           # default: the languages of messages_*.properties
    theme:                        # SpringThemeData, bound once
      mode: system                # system | light | dark
      seed-color: deepPurple      # a `Colors` name or '#673AB7'
      colors:
        error: '#B3261E'          # any color the seed would compute
      typography:
        font-family: Inter
        font-family-fallback: [Noto Sans JP]
        display: { font-family: Playfair Display, weight: 700 }
        code: { font-family: JetBrains Mono }
      shape:
        corner-radius: 12
      dark:
        seed-color: deepPurple
```
```properties
# lib/resources/application-ios.properties: the iOS look on iPhones
spring.flutter.app.type=cupertino
```
```dart
@SpringBootApplication()
void main() => runApp(SpringApplicationWidget(
  application: () => springApplication,
  home: const CounterPage(),       // passed into the generated app widget
));
```
`child:` stays for an app that builds its own `MaterialApp`; with `home:`
the starter builds it. Planned pieces:

- **Properties** as `@ConfigurationProperties` beans
  (`FlutterAppProperties`, `FlutterThemeProperties`): validated at start,
  completed and checked by the editor like any key.
- **One theme of the family, `SpringThemeData`**: the theme is not Material
  or Cupertino first, but the app's own: colors (a seed and any color set
  explicitly), typography, shapes, a dark variant. It is bound from
  `spring.flutter.theme.*` **once**, at the start, into a singleton bean
  that lives as long as the context (a hot reload with changed
  configuration restarts the context, so a new one is bound then). Every
  conversion runs once too: the starter registers the `ThemeData` beans
  `theme` and `darkTheme` (`springTheme.toMaterial(Brightness.light)`) and
  a `CupertinoThemeData` bean (`springTheme.toCupertino()`) at the start,
  never in `build`.
- **Several fonts, by text role** (a first design, not final): the
  typography has a default `font-family` and `font-family-fallback`, and
  roles that override them — `display`, `headline`, `title`, `body`,
  `label` (Material's `TextTheme` groups; Cupertino gets `display` as the
  large navigation title, `title` as the navigation title, `body` as the
  text style, `label` for actions and tabs) and `code` (no Material role,
  read through `SpringTheme`). A role sets `font-family`, `weight`,
  `letter-spacing`, optionally `size`; the rest stays Material's.
  ```yaml
  typography:
    font-family: Inter
    display:  { font-family: Playfair Display, weight: 700 }
    title:    { weight: 600 }
    code:     { font-family: JetBrains Mono }
  ```
- **Font files by convention, listed nowhere**: one directory under
  `flutter: assets:` (`assets/fonts/`, `spring.flutter.fonts.location`,
  empty to switch it off). At the start, behind the splash screen, the
  starter loads every `.ttf` / `.otf` / `.ttc` the asset manifest lists
  there with `FontLoader`, the family read from the font's own `name`
  table (`PlayfairDisplay-Bold.ttf` → "Playfair Display"; the Inter files
  join one family, their weights read from the files). Adding a font is
  dropping the file in; nothing repeats the pubspec. Families declared
  under `flutter: fonts:` keep working by name. A `font-family` that is
  neither loaded nor declared fails the start with the families found
  (Flutter would silently fall back). Tests load them too, so
  `example/flutter_counter` drops the hand-loaded Japanese font of its
  `flutter_test_config.dart`.
- **`SpringTheme`**, an inherited widget like `Theme`, gives the
  `SpringThemeData` to the tree (`SpringTheme.of(context)`), so the app's
  own widgets use one theme whatever the app type is.
- **The app type** picks the widget, **`widgets` by default** → `WidgetsApp`
  straight from `SpringThemeData` (`color`, `textStyle`, a page route of
  the starter for `home:`, which `WidgetsApp` needs), with no Material or
  Cupertino theme in between; an app of its own design system needs
  nothing more. `material` → `MaterialApp` (the
  `ThemeData` beans and the theme mode), `cupertino` → `CupertinoApp` (the
  `CupertinoThemeData` bean); Material widgets (`Scaffold`, `AppBar`) need
  `material`, so an app using them says so (`example/flutter_counter`
  does). With the platform profiles one app can be Material on
  Android and Cupertino on iOS by configuration only; beans for one type
  use `@ConditionalOnProperty('spring.flutter.app.type', havingValue: 'cupertino')`.
- **Replacing or adjusting it**: every bean above is
  `@ConditionalOnMissingBean`, so an app replaces the `SpringThemeData`
  (built from properties too) or only one conversion
  (`@Bean ThemeData theme(SpringThemeData springTheme) => ...`), or adjusts
  a result with `ThemeCustomizer` / `CupertinoThemeCustomizer` beans (in
  `@Order`), like Boot's `Jackson2ObjectMapperBuilderCustomizer`.
- **Customizers for the rest**: `FlutterAppCustomizer` beans get the
  app's settings before the widget is built (`builder`, `scrollBehavior`,
  `shortcuts`, anything without a property), like Boot's
  `WebServerFactoryCustomizer`.
- **Collected beans**: every `LocalizationsDelegate` bean joins the app's
  delegates (Material, Cupertino and Widgets ones added by the starter
  when a locale other than English is supported: it depends on the SDK's
  `flutter_localizations`), every `NavigatorObserver` bean its observers.
- **Locales from the messages files**: `messages_ja.properties` makes `ja`
  supported, so the texts of `context.message` and the app's locales
  cannot drift apart; `spring.flutter.app.locales` overrides it.
- **Values that are not strings**: the starter's converters bind `Color`
  (`deepPurple`, `deepPurple.shade200`, `#RGB`, `#RRGGBB`, `#AARRGGBB`),
  `ThemeMode`, `Brightness` and `Locale` (`en`, `pt_BR`) from properties.
  The names come from a `const` table of Flutter's `Colors` in the
  starter's source, generated once by a tool script (no reflection, no
  work at run time).
- **Changes at run time**: a changed `application.yml` restarts the context
  on hot reload (the generated code changes), so the new theme shows at
  once; a theme mode the user picks is a setting kept in
  `shared_preferences` (see *Settings*) above the files.
- **Routes**: with `@Route` widgets (see *Navigation*) the starter builds
  `MaterialApp.router` / `CupertinoApp.router` on the generated router
  instead of `home:`.
- **Defaults**: a `WidgetsApp` with Flutter's defaults (debug banner on,
  Flutter's default seed color), so the app pulls in neither Material nor
  Cupertino until a property asks for it; the properties only state what
  differs. The localization delegates follow the type: Widgets ones always
  (when a locale other than English is supported), Material or Cupertino
  ones only for that type.
- **Tests**: `springBootTest(springApplication, properties:
  {'spring.flutter.theme.mode': 'dark'})` and a golden screenshot of the
  dark theme, without code for it in the app.

In `example/flutter_counter` the `CounterApp` widget then goes away: its
theme, locales and banner move to `application.yml`.

## Beans in widgets

State beans are used from many widgets anywhere in the tree, so passing them
through constructors does not scale. Two ways, both explicit; a widget's
constructor always stays the developer's own — nothing is injected into
constructor parameters by type, so a widget may still take a `Basket` passed
by hand.

- **Generated `BuildContext` getters** for the beans marked for it
  (`@BuildContextAccess()`, working name): only those, so the list stays
  short even with hundreds of beans. Typed, completed by the editor,
  named after the beans (unique in Spring); a `@Scope('route')` bean
  comes from the route the widget is in.
  ```dart
  @Component()
  @BuildContextAccess()
  class Basket { ... }

  // generated
  extension Beans on BuildContext {
    Basket get basket => SpringScope.beanOf<Basket>(this);
    BookSearch get bookSearch => SpringScope.beanOf<BookSearch>(this);
  }

  // in any widget
  Watch((context) => Badge(label: Text('${context.basket.count}')));
  IconButton(onPressed: () => context.basket.add(book.isbn), ...);
  ```
- **`SpringStatelessWidget<(...)>`**: the beans a widget needs in its type,
  read as `beans`, a record. Good for a few widgets with a few beans; it
  gets heavy when many widgets need many beans.
  ```dart
  class BasketBadge extends SpringStatelessWidget<(Basket, AppNavigator)> {
    const BasketBadge({this.compact = false, super.key}); // your constructor
    final bool compact;

    @override
    Widget build(BuildContext context) {
      final (basket, navigator) = beans;
      return Watch((_) => Badge(
            label: Text('${basket.count}'),
            child: IconButton(
              icon: const Icon(Icons.shopping_cart),
              onPressed: () => navigator.go(const BasketRoute()),
            ),
          ));
    }
  }
  ```
Both are resolved by generated code, without reflection; the generator
sees every use, so the start fails on a missing bean (or a route bean
used outside its route), and the editor navigates from a use to the
bean. Tests replace beans in a test `SpringApplicationWidget`
(`overrides: [BeanOverride<Basket>(fake)]`), or build a widget with fakes
directly: `buildWith(context, (FakeBasket(), FakeNavigator()))`. Services
keep constructor injection and never see a `BuildContext`.

## The app lifecycle as the Spring lifecycle

`AppLifecycleState` changes are application events
(`ApplicationPausedEvent`, `ApplicationResumedEvent`), and `SmartLifecycle`
beans are stopped in the background and started again in the foreground:
`@Scheduled` tasks pause, WebSocket connections close and reopen, caches
flush.

## Navigation

Routes found by the generator, typed parameters with the same
`@PathVariable` / `@RequestParam` as the web, deep links and the web URL bar
through the SDK's `Router`, guards as AOP advice (`@PreAuthorize` once
security exists), and a `route` bean scope: created when the route is
pushed, destroyed when it is popped. Routes are also generated as typed
classes (`BookRoute(isbn)`) for an `AppNavigator` bean, so a service can
navigate (e.g. after a login) without a `BuildContext`.

```dart
@Route('/books/:isbn')
class BookPage extends StatelessWidget {
  const BookPage(@PathVariable() this.isbn, {super.key});
  final String isbn;
  ...
}

context.go('/books/978-0');
```

## Texts

The existing `MessageSource` with
`lib/resources/messages_{locale}.properties`, following the app's `Locale`
(`context.message('cart.total', args: [total])`), checked by the editor like
property keys.

## Settings

`shared_preferences` as a property source, and `@ConfigurationProperties`
beans written back to it, so user settings are ordinary configuration.

## Environment of the app

Flutter's `main()` gets no arguments, so two sources stand in for Boot's
command line and OS environment:

- the Dart compile-time environment (`--dart-define=key=value`,
  `String.fromEnvironment`), always on: its keys bind like `--key=value`
  arguments (relaxed binding, above the config files);
- the OS environment variables (`Platform.environment`), only when the
  property `spring.flutter.scan-os-environment=true` (name to settle) turns
  them on; **off by default**: on a phone the OS environment is noise, a
  desktop or dev setup opts in. With the flag off only the Dart defines
  are read.

## Tokens and secrets of the user

A `TokenStore` bean on the iOS / macOS Keychain and the Android Keystore
through own platform channels (no community plugin), used by Feign and
WebSocket interceptors and by
[the OAuth2 client](spring_boot_starter_oauth2_client.md) to keep the login
across restarts.

## Hot reload without code

A root `SpringApplicationWidget` widget calls `reloadApplication` from its `reassemble()`
itself, gives the context to the widget tree, and rebuilds widgets that use
beans after a restart, so cached beans never point to a closed context. When
a reload cannot apply a change (e.g. `build_runner watch` has not finished),
it shows "beans changed, hot restart required" instead of a
`NoSuchBeanDefinitionException`. Today the same works with two lines in
`reassemble()` (see `spring_boot_dart`'s README, *Hot reload*).

## Beans that survive hot reload even when kept in a field

Widgets get a generated wrapper instead of the bean, built like the `@Lazy`
proxies — every call looks the bean up in the *current* context. A reference
saved once in `initState` stays valid after the context is rebuilt:

```dart
class _ShopState extends State<Shop> {
  late final Checkout checkout;

  @override
  void initState() {
    super.initState();
    checkout = context.bean<Checkout>(); // a wrapper, not the object itself
  }

  // after a hot reload checkout.pay() already calls the new Checkout bean
}
```
The type must be an interface or a class without private members (the
same rule as for `@Lazy`); for other types the plain bean is returned
and the widget is rebuilt instead.

## Platform profiles

The running platform is an active profile — `android`, `ios`, `web`,
`macos`, `windows`, `linux` — plus the groups `mobile` (android, ios) and
`desktop` (macos, windows, linux). Beans are created only on their platform
with the usual `@Profile(['ios'])` / `@Profile(['mobile & !web'])`, and
`application-android.properties` / `application-mobile.properties` are
loaded automatically:

```dart
@Component()
@Profile(['android'])
class AndroidPushService implements PushService { ... }

@Component()
@Profile(['ios'])
class ApnsPushService implements PushService { ... }
```

## `--dart-define` as a property source

A Flutter app has no environment variables at runtime (almost empty on
Android/iOS, none on the web), so `${API_URL}` placeholders cannot come from
the OS there. Values passed at build time become properties instead, above
the properties files:

```sh
flutter build apk --dart-define=SPRING_PROFILES_ACTIVE=prod \
  --dart-define=API_URL=https://api.neon.books
# or --dart-define-from-file=config/prod.json
```
`SPRING_PROFILES_ACTIVE` picks `application-prod.properties` (Spring
profiles instead of flavors) and `@Value(r'${API_URL}')` gets the build's
value. `String.fromEnvironment` works only as `const` with a literal key
in AOT and web builds, so the generator writes a
`const String.fromEnvironment('API_URL')` / `bool.hasEnvironment(...)`
pair for every key it finds in placeholders and properties files.
Documented with it: a client app holds no secrets. `--dart-define`
values, properties and assets all end up in the APK / IPA /
`main.dart.js` and can be read; passwords and private keys stay on a
server, the app gets tokens from it.
