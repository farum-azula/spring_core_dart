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
| `flutter_secure_storage`, `flutter_web_auth` (tokens, login) | a `SecretStore` bean on the Keychain / Keystore / DPAPI / libsecret and the system's login window, own platform code, in `spring_boot_starter_flutter_security` (done) |
| `logger` | `SpringLog` (on by default), log files in the app's directory, the logs in the Actuator (planned) |
| `mocktail` setups (tests) | `springBootTest` and `BeanOverride` under `flutter_test` (done) |

## Status

Done: `SpringApplicationWidget` (start, splash and failure screens, hot reload, close),
beans in widgets (`context.bean<T>()`, `@BuildContextAccess` getters,
`SpringStatelessWidget<(...)>` / `SpringStatefulWidget<(...)>` checked at startup), the app lifecycle as events with
pause / restart of the context, platform profiles, `--dart-define` as a
property source, the OS environment switch, `context.message`, tests with
`SpringScope` and `springBootTest`; the [Flutter guide](../example/flutter_guide/README.md).

The app widget from configuration is done: `SpringApp` from
`spring.flutter.app.*` (type, title, debug banner, locales from the
messages files), observers and customizers, and themes from
`spring.flutter.theme.*` (shared part, `light` / `dark` / custom themes
with `extends`, the full Material 3 token set and 19 components, the
app's own tokens, switching at run time, themes loaded from a server,
fonts from any asset directory); the Flutter guide's chapter 3.
Next for themes: the remaining Material components, typed tokens
(`@ThemeTokens` classes generated into `ThemeExtension`s), the user's
choice kept in `shared_preferences` (see *Settings*).

Next: `@ConditionalOnPlatform(include: [AppPlatform.android, AppPlatform.ios],
exclude: [AppPlatform.web])` on top of the platform profiles (an
annotation with enums that the generator turns into a profile expression;
not `@Platform`, which `dart:io` already has), navigation (`@Route`, the
`route` scope, `AppNavigator`), settings
in `shared_preferences`, beans kept in fields that
survive a hot reload; later an Actuator screen (logs, beans, environment,
conditions) on the endpoints of [spring_boot_actuator](spring_boot_actuator.md).

Optional starters: [signals](flutter_spring_signals.md), [Flutter Scene](flutter_spring_scene.md), [Rust](flutter_spring_rust.md).

## `SpringApplicationWidget`

The root widget. Starts the application (`runApplicationAsync`), shows a
splash screen until the runners are done (or the failure report), and gives
the context to the tree (see *Beans in widgets*).

## The app widget from configuration

Done (see the starter's README, *The app widget from configuration* and
*Themes from properties*, and the Flutter guide): the app widget
from `spring.flutter.app.*`, themes from `spring.flutter.theme.*` as
named themes (`active: system | light | dark | <name>`, `themes.<name>`,
`extends`), switched by `ThemeSelection`, loaded from a server by
`SpringThemes.loadYaml`, and fonts from any asset directory. The design
notes below are what it started from; where they differ, the README is
current (e.g. `mode` became `active`, a `dark:` section became the theme
`themes.dark`, fonts are found among all assets). Like Boot configures Jackson or the web server from `spring.*`
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
  the Flutter guide drops the hand-loaded Japanese font of its
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
  `material`, so an app using them says so (the Flutter guide
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

In an app the hand-written `MaterialApp` widget then goes away: its
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
  typedef BasketBadgeBeans = (
    Basket,
    AppNavigator,
  );

  class BasketBadge extends SpringStatelessWidget<BasketBadgeBeans> {
    const BasketBadge({this.compact = false, super.key}); // your constructor
    final bool compact;

    @override
    Widget build(BuildContext context) {
      final (
        basket,
        navigator,
      ) = beans;
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

## Typed keys from the configuration (generated)

Today the theme's own values are read by string keys:
`SpringTheme.of(context).colors['surface']`, `theme.space('m')`,
`theme.textStyle('code')`, the `tokens.*` (`brand.accent`), theme names
(`active: ocean`). Renaming a key in `application.yml` breaks nothing at
build time: the app compiles, and the widget fails (or silently falls
back) at run time. The generator reads the same properties at build time
(as it does for `spring.flutter.web.*`), so it can write typed names
instead, and a renamed or removed key becomes a compile error.

Only the Spring side is generated: what the app declares under
`spring.flutter.theme.*` (its own colors, spacing, text styles, tokens,
theme names). What Flutter computes from it (the Material 3 roles from
the seed, the 15 `TextTheme` styles) stays where every Flutter developer
knows it, `Theme.of(context).colorScheme` / `.textTheme`, already typed.

```yaml
spring:
  flutter:
    theme:
      seed-color: deepPurple
      colors:
        error: '#B3261E'
        surface-container-low: grey.shade100
      spacing: { s: 8, m: 16 }
      typography:
        code: { font-family: JetBrains Mono, size: 13 }
      tokens:
        brand: { accent: '#FF6B00', hero-height: 240 }
      themes:
        ocean:
          colors:
            highlight: '#00BFA5'   # only in ocean
```

```dart
// generated into main.spring.dart: a class per group, a final field per
// declared key, filled once when a theme is built
class ThemeColors {
  final Color error;
  final Color surfaceContainerLow;
  /// Set in: ocean. Other themes: the Material default.
  final Color highlight;
}
class ThemeSpacing { final double s, m; }
class ThemeTextStyles { final TextStyle code; }
class ThemeTokensBrand { final Color accent; final double heroHeight; }
class AppThemes { final String light, dark, ocean; }
```

Short from any widget of the app (a `SpringApplicationWidget` below), one
entry on the context as for the messages (`context.messages`): the
groups of `spring.flutter.theme.*` under `context.theme`:

```dart
// generated: the active Spring theme's declared values
class AppTheme {
  final ThemeColors colors;
  final ThemeSpacing spacing;
  final ThemeTextStyles textStyles;
  final ThemeTokens tokens;
  final ThemeNames names;          // light, dark, ocean, ...
}

Widget build(BuildContext context) => Card(
  color: context.theme.colors.surfaceContainerLow,
  child: Padding(
    padding: EdgeInsets.all(context.theme.spacing.m),
    child: Text('isbn', style: context.theme.textStyles.code),
  ),
);

context.theme.tokens.brand.accent;
context.themes.activate(context.theme.names.ocean);
Theme.of(context).colorScheme.primary;   // Flutter's, from the seed
```

- `context.theme` is a generated `BuildContext` extension getter that
  reads the active theme and rebuilds the widget when it changes (dark
  mode, a theme switched at run time), like `Theme.of(context)`;
  `SpringTheme.of(context)` stays for code that has the theme already.
  Flutter has no `context.theme` of its own; a clash with another
  package's extension of that name is solved by hiding one import.
- A key declared in the properties that is also a Material role
  (`error`, `surface-container-low`) is in both places with the same
  value.
- Renaming a key in `application.yml` makes
  `context.theme.colors.oldName` a compile error; a changed value needs no code change; a value whose
  type changes (`hero-height: tall`) or differs between themes fails the
  build with the property named; a name that is no Dart name, or two
  keys that become the same name, too.
- Values can still change at run time (a theme loaded from a server, a
  profile): the generated getters fix the keys, not the values; a key a
  run-time theme lacks falls back to the Material 3 default, as today.
- The string API stays as it is (`colorOf('promo')`, `space('m')`,
  `colors['...']`): for keys added at run time (a theme from a server,
  values the app writes itself) and for code that picks a key
  dynamically; the generated fields are the typed way for declared keys.
- Material and Cupertino are untouched: the generated classes only read
  the values `SpringThemeData` already holds; `ThemeData`,
  `CupertinoThemeData` and the `widgets` app type are built from the
  properties as before, and the `context.*` getters work with every app
  type (`context.theme` reads the Spring theme, not `Theme.of`).
- The same principle for the other maps keyed by strings in the
  configuration, each checked at build time:
  - message keys of `messages*.properties`: the same way as the theme,
    see "Typed messages" below;
  - asset paths of `@Value('asset:...')` (already checked against
    `pubspec.yaml`) -> generated constants;
  - routes, once the starter has navigation;
  - `@ConfigurationProperties` maps whose keys the app fixes.
  Spring has nothing like it (Java reads these by string too; Boot's
  `spring-boot-configuration-processor` only writes metadata for editor
  completion), so it is an addition, listed as such in the docs.

### Typed messages

The same for the message files: today `context.message('basket.total',
args: [total])`; a renamed key or a forgotten argument shows up at run
time (`NoSuchMessageException`, or `{0}` on screen).

```properties
# lib/resources/messages.properties
basket.total=Total: {0}
basket.empty=Your basket is empty
order.shipped=Order {0} shipped on {1,date,short}
# lib/resources/messages_ja.properties
basket.total=合計：{0}
basket.empty=カートは空です
order.shipped=注文 {0} は {1,date,short} に発送されました
```

```dart
// generated into main.spring.dart: a class per key prefix, a member per
// key; keys without placeholders are getters, keys with placeholders are
// methods with one parameter per placeholder, typed from its format
class Messages {
  final MessagesBasket basket;
  final MessagesOrder order;
}
class MessagesBasket {
  String total(Object p0);         // {0}
  String get empty;
}
class MessagesOrder {
  String shipped(Object p0, DateTime p1);   // {1,date,short} -> DateTime
}

// used as, in the current language, rebuilt when it changes
Text(context.messages.basket.total(total));
Text(context.messages.basket.empty);
Text(context.messages.order.shipped(order.id, order.shippedAt));
```

- From the default file (`messages.properties`) and every locale file:
  a key missing in one language, or with other placeholders there, is a
  build warning naming the file; a key only in a locale file is one too.
- Placeholders: the count and the types from the `MessageFormat`
  formats (`{0}` -> `Object`, `{1,number}` -> `num`, `{1,date,...}` /
  `{1,time,...}` -> `DateTime`, `{1,choice,...}` -> `num`); a key with a
  wrong placeholder fails the build.
- Names: the dots make the nesting (`basket.total` ->
  `messages.basket.total`), dashes become camel case; a key that is no
  Dart name, or a key that is both a leaf and a prefix (`basket` and
  `basket.total`), fails the build with the key named.
- `spring.messages.basename` (several bases, other folders) is read as
  the runtime reads it; each base's keys go into the same `Messages`.
- The string API stays as it is (`context.message('...', args: ...)`,
  `MessageSource.getMessage`): for keys built at run time and messages
  from elsewhere (a server, a database `MessageSource`).
- A server (`spring_boot_dart` without Flutter) gets the same `Messages`
  class over its `MessageSource`, for the messages it renders (errors,
  mails), with the locale passed in (`messages.of(locale)`).

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

Moved (October 2026) to
[`spring_boot_starter_flutter_security`](spring_boot_starter_flutter_security.md),
with the renames there (`SecretStore`, `PlatformSecretStore`,
`AuthorizationWindow`, `PlatformAuthorizationWindow`): the Flutter starter
has no platform code again, and an app without a login carries none of
it. What it was:

Done (October 2026): the starter is a Flutter plugin with its own platform
code (no community plugin). `PlatformSecretStore` is the `SecretStore` bean of
the app login ([spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md),
section 3), which keeps the login across restarts: the Keychain on iOS and macOS (generic passwords,
`AfterFirstUnlockThisDeviceOnly`, not synced; on macOS the data protection
keychain for builds signed with a team, the login keychain for builds
signed to run locally, which get `errSecMissingEntitlement`), an
AES-256-GCM key of the Android Keystore with the values in a private
preferences file (undecryptable values deleted), DPAPI files on Windows
and the Secret Service through libsecret on Linux (both `dart:ffi`, no
native build; never a plain-file fallback). None on the web: the server
logs in. `PlatformAuthorizationWindow` is the `AuthorizationWindow`
bean on Android (Custom Tabs; the redirect caught by the starter's
`RedirectReceiverActivity`, which an app that logs in declares with its
scheme in its manifest, so apps without a login configure nothing), iOS
and macOS (`ASWebAuthenticationSession`). Both are registered unless the
app has its own, before the OAuth2 client's module. Run on the macOS
desktop, the iOS simulator and an Android emulator
(`example/flutter_guide/integration_test`); the Windows and Linux stores
are untested on a device.

Next: the token on Feign and WebSocket interceptors (the OAuth2 client's
`OAuth2AccessTokenInterceptor`), the Windows and Linux stores run on CI.

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
