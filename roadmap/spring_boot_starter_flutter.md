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

**Done in 0.6.2** (the owner, November 2026; the theme and the messages),
with the theme from a URL and the components' states below still to come.

As built (differs from the sketch below): one builder, `spring_flutter_keys`,
writes `lib/spring_gen/theme.spring.keys.dart` and `lib/spring_gen/messages.spring.keys.dart` (the extensions
`SpringThemeKeys` and `SpringMessageKeys` on `BuildContext`, with `theme` and
`messages`). The classes are `AppTheme` (`colors`, `spacing`,
`typography`, `tokens`), `AppThemes` (static constants for
`ThemeSelection.select`) and `AppMessages`; they are cheap views that read
the active theme through the starter's `ThemeKeyReader` when a getter is
called (no per-theme fields). Tokens are two levels (`tokens.<group>.<key>`),
typed by value (`#RRGGBB` / `0x...` colour, number, else text); the message
parameters are `Object?` (no types from the formats yet); `spring.messages.basename`
is read from the config files; the generator reads every config file of
`lib/resources/` (any profile, any theme). Still open: the same `Messages` for
a server, asset and route constants.

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

### The theme from a URL (0.6.2; the owner, November 2026)

**Done in 0.6.2** (docs: the starter's README, "Themes from a URL", and
`docs/configuration.md`, "A theme from a URL"): `ThemeSourceLoader` (an
`ApplicationRunner`, so the first frame has the theme) as specified below.
Details settled while building it: the cache is
`spring/themes/<sha256 of source + "\n" + pin>/theme.yml` and `meta.json`
(`source`, `sha256` of the content, `fetchedAt`, `etag`, `lastModified`);
the file is written like the theme part of `application.yml` (under
`spring.flutter.theme`, or its keys at the top, or one `themes.<any name>`
block); the first download waits at most 10 s and 1 MiB (no cache), redirects
only to `https`; the HTTP client is the app's `HttpTransport` bean, else
`spring_web_dart`'s (the Flutter starter depends on it now);
`SpringThemes.applySource` keeps the downloaded themes between the files'
and `load`'s. Not done: a retry when the network returns while the app runs
without `refresh` (the next start retries); the web (IndexedDB) store is not
exercised by a test in a browser.

A theme loaded from `https` (a raw GitHub link, or a `github:owner/repo/path@ref`
shorthand) under a name the app chooses, whatever the file calls it:

```yaml
spring:
  flutter:
    theme:
      active: brand
      themes:
        brand:
          source: https://raw.githubusercontent.com/neon/themes/main/ocean.yml
          source-sha256: 3f9a…     # optional: refuse other content
          refresh: 1h              # optional: re-read in the background; without it, cached forever
        brand-dark:
          extends: brand
          brightness: dark
```

- Only the theme's own keys are read from the file (`spring.flutter.theme.*`
  under that theme); anything else in it is ignored with a warning: a remote
  file never changes the application's other settings. Not a general
  `spring.config.import` from URLs (Spring Boot has none either).
- The theme is always cached in the app's directory and the cache survives
  restarts. Without `refresh` it is downloaded once (the first start that
  has the network) and then read from the cache forever: no request on
  later starts. With `refresh` the cache is used at once and re-read in the
  background when it is older than that interval. The cache belongs to the
  source: another `source` or `source-sha256` downloads again (that is how
  a new version of the theme is picked up without `refresh`).
- `https` only; offline,
  a timeout or an error falls back to the cache, else to the theme in the
  app's resources: the start never fails or hangs on the network.
- Typed keys (above) come from the build: a remote file changes values, it
  does not add keys.

### More of the theme: states and every component (0.6.2; the owner, November 2026)

**Done in 0.6.2** (docs: the starter's README, "Themes from properties", and
`docs/configuration.md`, "Themes: every property"): a `ThemeReader` maps each
component's constructor by property type, 48 components and `cupertino.*`,
states per property, errors with the valid keys and a "did you mean". Only
the named variants below are left to decide.

The theme configures Flutter's own components (`ThemeData` and its component
themes); the app keeps using Flutter's widgets. **No generated widgets**: the
generator does not write components of its own.

- States: a property may give a value per state (Flutter's
  `WidgetStateProperty`): `background: { default: $colors.primary, hovered: …,
  pressed: …, focused: …, disabled: … }`.
- Every component theme of Flutter (about 50, today 16) with all their
  properties (borders per state, shadows, icons, overlay), mapped by property
  type (color, shape, border, text style, value per state) so coverage grows
  without writing each property by hand; the Cupertino components too.
- Named variants of a component (a "danger" button) only if they can stay
  data (a style the theme holds, read by a typed key), never a generated
  widget — to decide when the rest is done.

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

## Themes without Dart (0.6.3; the owner, November 2026)

**Done in 0.6.3 (unreleased)** (branch `theme`; docs: the starter's README,
"Themes without Dart", and `docs/configuration.md`). The measure is the NEON design
system (`neon_ui`, a theme package written in Dart): before 0.6.3 it needed
`neonColor` / `neonNumber` / `neonJson` helpers, JSON inside a YAML
string (`modal: >- {"width": 460, ...}`), constants for derived colors
(`badgeAlpha = 0.12`, `hoverLighten = 0.14`), a hand-written
`NeonPressable` for hover, a hand-written `AnimationController` for the
glowing border and a `NeonBackground` wrapped around every screen. After
0.6.3 such a theme is YAML, and its widgets read typed values.

As built (differs from the text below, where the code says otherwise the
code is right):

- Style and animation names are canonical inside (`neon-chip`, `neonChip`
  and `neon_chip` are one), and any spelling reads.
- A style property with states must have `default`.
- `@SpringBootApplication` also counts as the parent of the generated parts
  (besides `@ComponentScan`). The parts use unprefixed imports.
- `$path` is a reference only when it is the whole value or an operand of a
  color object; inside a longer text it stays text.
- An image token is a token map with `source` and only image keys.
- `headers` is a map.
- A redirect to another origin (host, port or scheme) drops the custom
  headers. Headers and the image keys `source`, `fallback`, `source-sha256`
  are not searched for `$` references.
- A Material role or shape the theme does not declare is referenceable
  (`$colors.outline`, `$shape.extra-small`): computed from the theme's seed,
  brightness, variant and contrast.
- Durations: `ms`, `s`, `m`, `h`, a space allowed. The classification of a
  value is fixed by `test/fixtures/theme_value_kinds.yaml`.
- Reduce motion: `repeat: none` goes to its end; loops stand still at 0.
- A radial gradient's `begin` is its center.
- The example: `example/themes/neon` (app type `widgets`) on
  `example/themes/neon_ui`, the NEON design system as a library (theme and
  components), moved onto 0.6.3.

### Generated files: `lib/spring_gen/theme.spring.keys.dart`, `lib/spring_gen/messages.spring.keys.dart`

Generated code is always `*.spring.dart` and lies in `lib/spring_gen/`, which mirrors the source path:

```
lib/
  main.dart                         # the app's, with @ComponentScan
  spring_gen/
    main.spring.dart                # generated: beans, the context
    theme.spring.keys.dart               # generated: part of main.spring.dart, context.theme
    messages.spring.keys.dart            # generated: part of main.spring.dart, context.messages
```

- `spring_flutter_keys` writes `lib/spring_gen/theme.spring.keys.dart` and
  `lib/spring_gen/messages.spring.keys.dart` as `part of '<parent>.spring.dart'`; the
  parent is the `.spring.dart` of the package's `@ComponentScan` library
  (`spring_gen/main.spring.dart` in an app, `spring_gen/spring_auto_configuration.spring.dart`
  in a library such as `neon_ui`). The main builder writes the `part`
  directives (only for parts that exist) and the imports the parts need;
  a part has no imports of its own. More parts follow the same way later
  (web, data, HTTP clients), one generated file per concern.
- Widgets get `context.theme` by importing the parent
  (`import 'package:app/spring_gen/main.spring.dart';`). Two `@ComponentScan`
  libraries in one package: the build stops and names both. None: no key
  files, a log line says why.
- A library's keys live in its own `.spring.dart`, an app's in its own: an
  app never sees the library's `context.theme`, no conflict.
- The extensions: `SpringThemeKeys` (`theme`), `SpringMessageKeys`
  (`messages`).

### References and color objects

Any value of a theme can name another value of the same theme with
`$<path>`:

```yaml
seed-color: $colors.primary
tokens:
  neon:
    yellow: $colors.primary
    badge-fill: { color: $colors.primary, alpha: 12% }
    hover-fill: { color: $colors.primary, mix: { with: white, amount: 14% } }
  logs:
    error: $colors.error
```

- A path starts at the theme's root (`$colors.primary`, `$spacing.m`,
  `$shape.extra-small`, `$motion.durations.fast`,
  `$tokens.neon.yellow`); a token path may drop `tokens.` when its group
  is not a root section (`$neon.yellow`).
- Not `${...}`: that is Spring's placeholder, resolved by the
  `Environment` against all properties (and it still works, e.g.
  `${cdn.token}` in a header). `$` followed by anything but a letter is
  text (`$5`); `$$` is a literal `$`.
- Resolved per theme after `extends`, so an extending theme that changes
  `colors.primary` changes everything that refers to it. A cycle or an
  unknown path stops the start with the chain and "did you mean".
- Colors: `<color> alpha <n>%` (or `0..1`), `<color> mix <color> <n>%`;
  `<color>` is a reference, `#RRGGBB`, `#AARRGGBB`, `0x...` or a named
  color (`white`, `black`, `transparent`).

### Nested tokens

Tokens of any depth, lists, durations; no more JSON in a string:

```yaml
tokens:
  neon:
    modal:
      width: 460
      barrier: transparent
      border:
        width: 1
        glow: 8
        glow-alpha: 0.6
        colors: [$neon.yellow, $neon.cyan, $neon.pink, $neon.lavender]
```

Typed by value as in 0.6.2 (color, number, text) plus durations
(`250ms`), lists of one type (`List<Color>`, `List<double>`,
`List<String>`) and groups (a generated class per group:
`context.theme.tokens.neon.modal.border.colors`). Two-level tokens of
0.6.2 read as before.

### Styles of the app's own widgets: `styles.*`

Values per state for widgets that are not Material's, with the states
and precedence of the components (disabled > error > pressed > dragged >
hovered > focused > selected > scrolled-under > default):

```yaml
styles:
  neon-chip:
    padding: [12, 6]
    border: { default: $colors.outline, hovered: $colors.primary, selected: $colors.primary }
    fill:   { default: transparent, selected: { color: $colors.primary, alpha: 12% } }
    text:   { default: $colors.on-surface-variant, hovered: $colors.primary, selected: $colors.primary }
    transition: 120ms ease-out
```

A property is one value (every state) or a map of states. Types by
value: color, number, insets (`[all]`, `[h, v]`, `[l, t, r, b]`), text,
duration. `transition: <duration> [<curve>]` animates between states.

```dart
ThemeStates(
  style: context.theme.styles.neonChip,
  selected: selected,
  onPressed: onPressed,
  builder: (context, s) => Container(
    padding: s.padding,                               // EdgeInsets
    decoration: BoxDecoration(color: s.fill, border: Border.all(color: s.border)),
    child: Text(label, style: TextStyle(color: s.text)),
  ),
)
```

`ThemeStates` (a starter widget, nothing generated) tracks hover, focus,
press and disabled (`onPressed == null`), takes `selected` and `error`
from its arguments, handles keyboard activation and the mouse cursor, and
lerps the values over `transition`. The style is a `ThemeStyle<V>`: the
generated `NeonChipStyle` gives typed values (`s.fill` is a `Color`);
the runtime `StateStyle` reads untyped (`values.color('fill')`).

### Motion and animations

```yaml
motion:
  durations: { fast: 120ms, medium: 250ms }
  curves: { emphasized: [0.2, 0, 0, 1], out: ease-out }
  page-transition: fade-upwards
animations:
  border-spin: { duration: 4s, curve: linear, repeat: loop }
  glow-pulse: { duration: 1.6s, curve: ease-in-out, repeat: reverse }
```

- `context.theme.motion.fast` is a `Duration`, `Duration.zero` when the
  system asks for less motion (`MediaQuery.disableAnimations`);
  `context.theme.motion.curves.emphasized` is a `Curve` (named curves:
  `linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`,
  `fast-out-slow-in`, `emphasized`, ... or four numbers).
- `animations.<name>`: `duration`, `curve`, `repeat: none | loop |
  reverse`, an `AnimationSpec`. `ThemeAnimation(spec, builder: (context,
  t) => ...)` owns the controller, repeats, stands still with less motion
  and takes a new duration when the theme changes.

### The background: `background`

```yaml
background:
  color: $colors.surface-container-lowest
  image:
    source: https://cdn.example.com/neon/background.jpg
    fit: cover
    alignment: center
    opacity: 0.9
    blur: 0
  overlay:
    gradient: { type: linear, begin: top, end: bottom, colors: [transparent, '#CC0A0C12'] }
  animation: background-drift      # an animations.* name
  effect: drift                    # drift | zoom | pulse
  transition: 400ms ease-out
  screens:
    login: { image: { source: packages/neon_ui/assets/images/login.jpg } }
```

- With `background` set, the starter puts it under every screen (around
  the navigator) and makes the Material scaffold and Cupertino page
  backgrounds transparent unless the theme sets them; the image is
  precached at start; a theme switch or a new image cross-fades over
  `transition`.
- `ThemeBackground.screen('login', child: ...)` takes `screens.login`
  over the theme's background; `ThemeBackground.none(child: ...)` an
  opaque surface.
- `context.theme.background` reads it.

### Images from the network: `ThemeImage`

One image source for the background, the screens' backgrounds and image
tokens (a token map with `source`):

```yaml
image:
  source: https://cdn.example.com/neon/background.jpg   # or an asset path
  refresh: 1d
  source-sha256: 9f2c…
  headers: { Authorization: Bearer ${cdn.token} }
  timeout: 10s
  fallback: packages/neon_ui/assets/images/neon-background.jpg
```

- Like the theme from a URL: the same `HttpTransport`, a persistent cache
  through `FileTemplate` (`spring/images/<sha256>/`), without `refresh`
  downloaded once and read from the cache forever, with `refresh` re-read
  in the background with conditional requests and swapped live; the start
  never waits for the network: the cache, else `fallback`, else
  `background.color`. A file not matching `source-sha256` is dropped with
  a warning. The web caches in IndexedDB and logs a CORS hint on failure.
- `https` by default; `http://` only with `allow-http: true` (else the
  start stops with the hint), as Android and iOS refuse clear text
  anyway.

### Names

The widgets read the theme and are named for it: `ThemeStates`,
`ThemeAnimation`, `ThemeBackground`, `ThemeImage`; the data `StateStyle`,
`ThemeStyle<V>`, `AnimationSpec`. Not `ImageSource` (`image_picker`'s
name). `SpringTheme` / `SpringThemeData` stay.

## Loaders and the splash (0.6.3; the owner, November 2026)

**In 0.6.3.** Three kinds of loader, all from the theme, one look from the
first byte of the page to the first screen:

1. **Component loaders** — `loaders.<name>` in a theme, shown by
   `ThemeLoader` (indeterminate or with `progress: 0..1`) and
   `ThemeSkeleton` (the content, or a placeholder while `loading`).
2. **The splash** — `splash` in a theme, shown by `SpringApplicationWidget`
   while the context starts (its `splash:` builder still wins).
3. **The web page loader** — what the browser shows while it downloads
   Flutter (today a thin blue bar): generated at build time from the
   theme's `splash` into the app's web page, and handed over to the
   Flutter splash without a jump.

### `loaders.<name>`

```yaml
loaders:
  dots:     { kind: dots, color: $colors.primary, size: 10, count: 3,
              animation: { duration: 900ms, curve: ease-in-out, repeat: loop } }
  upload:   { kind: bar, color: $colors.primary,
              track: { color: $colors.primary, alpha: 20% }, height: 3 }
  card:     { kind: skeleton, base: $colors.surface-container-high,
              highlight: $colors.surface-container-highest, radius: $shape.medium,
              shimmer: { duration: 1.2s, angle: 20 } }
  neon-doors:
    kind: doors                    # a kind of the app's own, see below
    phases:
      close: { duration: 500ms, curve: ease-in }
      fill:  { progress: true }    # follows the real progress
      open:  { duration: 450ms, curve: emphasized }
    door: { color: '#0B0D14', edge: { color: $neon.cyan, width: 2, glow: 12 } }
    seam: { width: 6, fill: $neon.pink,
            glow: { color: { color: $neon.pink, alpha: 60% }, blur: 24 },
            flicker: { duration: 120ms, repeat: reverse } }
    web: web/loaders/neon-doors.html   # how the kind looks before Flutter runs
```

- Built-in kinds: `spinner`, `dots`, `pulse`, `bar`, `skeleton` (each with
  its documented keys; colours in the theme's one colour form, durations
  in the one syntax, `$` references).
- `phases`: named steps; a phase is an animation spec (`duration`,
  `curve`, `repeat`) or `{progress: true}` (driven by the progress the
  loader is given). Built-in kinds have one implicit phase.
- A kind of the app's own: a class with `@ThemeLoaderKind('doors')`
  extending `ThemeLoaderPainter<P>` (`paint(canvas, size, frame)`, where
  `frame.phase('close')` is 0..1 and `frame.props` is `P`) — or
  `ThemeLoaderWidget<P>` building widgets. The generator writes `P`
  (`DoorsLoaderProps`) from the keys the theme gives that loader (typed
  like tokens), and the typed key `context.theme.loaders.neonDoors`.
  An unknown `kind` or a key the kind does not take stops the build and
  the start.
- Reduce motion: no animation, the end state of each phase, no flicker
  or shimmer.

### `splash`

```yaml
splash:
  background: { color: $colors.surface-container-lowest }   # the keys of `background`
  logo: { source: assets/images/logo.png, size: 96 }        # a ThemeImage
  title: NEON                                               # text
  loader: neon-doors                                        # a loaders.* name
  animation: splash-in                                      # an animations.* name for the logo
  min-duration: 1.2s
  exit: { transition: 400ms ease-out }
```

- The splash gets the start's progress (`SpringApplication` reports the
  share of bean definitions and runners done) for a `{progress: true}`
  phase; when the context is ready the loader's last phase (`open`)
  plays, then the splash fades out over `exit`, not before `min-duration`.

### The web page loader

- The generator (with the web dev config) writes the page loader of the
  active theme's `splash` into the app's web output: a self-contained
  block in `web/index.html` between markers (`<!-- spring:loader -->`),
  rewritten on every build, plain HTML + CSS + a few lines of JS, no
  external files; built-in kinds have a CSS form; a kind of the app's own
  gives its `web:` HTML file (CSS variables filled from the theme:
  `--door-color`, `--seam-fill` ...).
- It shows at once, follows Flutter's loading (`_flutter.loader` stages:
  downloading the engine, the app, the first frame) as its progress, and
  is removed when the Flutter splash paints its first frame, which starts
  from the same state, so there is no jump. `prefers-reduced-motion`
  stops its animations. Nothing is written for an app without a
  `splash`.

### The runtime API (as built)

- `ThemeLoaderSpec` (`name`, `kind`, `phases`, `values`, `look`, `web`),
  read by `ThemeKeyReader.loader(name)` and `SpringThemeData.loaders`
  (canonical names: `neondoors`). `ThemeSplashData` by
  `ThemeKeyReader.splash()` / `SpringThemeData.splash` (`background`,
  `logo`, `logoSize`, `title`, `loader`, `animation`, `minDuration`, `exit`).
  Note: `splash: ripple` (a scalar) stays the ink splash of taps; the
  splash of this section is the map form.
- Widgets: `ThemeLoader(spec, {progress, ready, size, onFinished})`,
  `ThemeSkeleton(spec, {loading, child, placeholder})`, `ThemeSplash`.
- Custom kinds: `@ThemeLoaderKind('name')` (annotation, `annotations.dart`);
  `ThemeLoaderPainter<P>.paint(Canvas, Size, LoaderFrame<P>)`,
  `ThemeLoaderWidget<P>.build(BuildContext, LoaderFrame<P>)`;
  `LoaderFrame<P>` has `phase(name)`, `progress`, `props`, `values`
  (`LoaderValues`: `color`, `number`, `duration`, `text`, `boolean`, `curve`,
  `animation`, each with an `...OrNull` form, `at(key)`, `has(key)`,
  `keys([key])`; a dot goes one level down) and `reduceMotion`.
- The registry the generated code fills, before the context starts (the
  themes check every `kind` when they are read):
  `ThemeLoaderKinds.register<P>(name, {painter | widget, props: P Function(LoaderValues), keys})`.
  `keys` are the keys the kind takes besides `kind`, `phases` and `web`
  (`null`: any); `props` runs once at the start, so a missing or wrong key
  fails it with a `ThemePropertyException`.
- Start progress: `SpringApplication.progressListener(StartupProgress)`
  (`done`, `total`, `fraction`; beans created + runners called, never goes
  back, 1 when ready). `SpringApplicationWidget` reads the properties as
  soon as the environment is prepared (`ApplicationEnvironmentPreparedEvent`)
  and shows the active theme's splash from then on.
- Web hand-off: `window.springLoaderHandOff(progress)` is called once (if
  defined) after the first frame that paints the Flutter splash (or the
  `splash:` builder, or when the theme has no splash, or on a failed start).

### Generator, page loader and editor (as built)

- Markers in `web/index.html`: `<!-- spring:loader:start -->` and
  `<!-- spring:loader:end -->` (builder `spring_flutter_page_loader`). The
  script exposes `window.springLoader` (`progress`, `stage`, `handOff`), sets
  `--spring-progress` and `data-stage` (`load`, `app`, `engine`, `run`,
  `done`) on `#spring-loader`, and `window.springLoaderHandOff(progress)`
  removes it (timeout 60 s, 3 s after `flutter-first-frame`). The `web:` file
  is found below the app's directory, else in `lib/resources/` of a
  dependency. The CSS variables of a loader are the key path in kebab case.
- The props class of a kind is `<Kind>LoaderProps`, written in the package
  that declares the `@ThemeLoaderKind` class; kinds of dependencies are known
  from `loaderKinds` of their `spring_metadata.json`. The registration is in
  the module getter, before the `BeanModule` is built.
- The editor knows `loaders.*` (kind values incl. `loaderKinds`, the keys of
  each kind), `splash.loader` / `splash.animation` (completion, errors,
  go to definition) and `web:` (existence, completion, go to the file).

### Examples

Every example app shows all three: the Flutter guide, `example/themes/`
material, cupertino and neon (neon: the title-screen loader, its kind in
`neon_ui`, so a library can ship loader kinds with its theme).

## Navigation

A starter of its own, the next release:
[spring_boot_starter_flutter_navigation.md](spring_boot_starter_flutter_navigation.md).
This starter only uses a `RouterConfig` bean when there is one.

## Search engines, previews and models: `spring.flutter.web.seo.*`

Done on the release branch after 0.7.0 (November 2026), with the
navigation starter; the documentation site is its first user. Built as
below: the generator's `spring_flutter_seo` builder (from the routes of
`spring_metadata.json`, the `content[n]` folders and `pages[n]`; the keys
are lists, `pages[n].path`, not a map keyed by path), `MarkdownView` and
`CodeTokens` in this starter, `RouteContentView` in the navigation
starter, the head and manifest of the app from `spring.flutter.app.title`
/ `.description` and the theme, the dev server's keys moved to
`spring.flutter.web.dev-server.*`. Not built: `_headers` and `404.html`
(Cloudflare Pages serves `index.html` for unknown paths when a site has
no `404.html`; `_headers` waits for the deep links' domain files there). A Flutter web page draws on a
canvas: the HTML the server sends holds a script and no text, so search
engines, link previews (messengers, Slack, X) and the bots of models (which
run no JavaScript) see an empty page under the template's title. Pages
written by hand next to the app would repeat the interface; instead the
build writes, for every page, the text it already has (Markdown, titles)
into the HTML the page loader already lives in.

### Keys

Read by the generator at build time, as `spring.flutter.web.*` is
(`application.*`, `application-web.*`, the active profiles, imports); nothing
reads them at run time.

```yaml
# lib/resources/application-web.yml
spring:
  flutter:
    web:
      seo:
        enabled: true                         # default false: nothing written
        site-url: https://spring-dart.dev     # required when enabled
        from-routes: true                     # pages from the navigation starter's routes
        title: '{title} · Spring Dart'        # <title>; {title} from the page
        description: Spring for Dart and Flutter.   # when a page has none
        image: resources:images/og.png        # the preview picture by default
        content:                              # Markdown, a page per file
          - location: resources:content/docs/
            path: /docs                       # core/configuration.md → /docs/core/configuration
            exclude: ['**/_*.md']             # drafts
          - location: resources:content/blog/
            path: /blog
        pages:                                # pages by hand: no Markdown, no route
          '/':
            title: Spring Dart
            description: Spring Boot for Dart servers and Flutter apps.
          '/pricing':
            index: false                      # noindex, not in the sitemap
        sitemap: true                         # sitemap.xml, robots.txt
        llms: true                            # llms.txt, llms-full.txt
        markdown: true                        # <path>.md next to every Markdown page
```

| Key | What | Unset |
|---|---|---|
| `enabled` | turns the rest on | `false` |
| `site-url` | absolute URLs: `canonical`, `og:url`, the sitemap | the build fails when `enabled` |
| `from-routes` | every route of the navigation starter is a page (below) | `false`; `true` without the navigation starter fails the build |
| `title`, `description`, `image` | defaults of `<head>`; a page's own values win | `title`: `spring.flutter.app.title` |
| `content[n].location`, `.path`, `.exclude` | a folder of Markdown files and the URL it is served under | no Markdown pages |
| `pages` | `title`, `description`, `image`, `index` per path, for pages of no route or to override one | none |
| `sitemap`, `llms`, `markdown` | one output off | all on |

### Pages from three sources

The page list is the union of:

1. **Routes** (`from-routes: true`): `@Route(title:)`, `@Seo(...)` and
   `@Route(content:)` of the navigation starter
   ([spring_boot_starter_flutter_navigation.md](spring_boot_starter_flutter_navigation.md#search-engines-seo-and-title)).
   A route with path variables and no `content:` has no list of values at
   build time (the app does not run in the build): it is left out of the
   sitemap with a warning, unless `@Seo(paths: [...])` lists them; in the
   app its `<title>` and description are set when it opens.
2. **`content`**: every Markdown file of each location, at `path` + its
   path without `.md` (`index.md` is the folder's URL). The front matter
   gives `title` and `description` (else the first `#` heading, with a
   warning, and the default).
3. **`pages`**: by hand, for an app without the navigation starter or for a
   page whose route says nothing.

Merging, field by field: `pages` over the route's annotations over the
defaults, so a description changes without touching code. The build
fails when one Markdown file gets two URLs (a `content` folder and a
route's `content:` disagree), when two files get one URL
(`configuration.md` and `configuration/index.md`), when a location does
not exist, or when a Markdown link points to a file that does not exist
(links between files become the site's URLs: `configuration.md#profiles`
→ `/docs/core/configuration#profiles`). With `from-routes`, a `content` or
`pages` URL no route opens is a warning.

### What the build writes

For every page, `<path>/index.html`: a copy of `web/index.html` with

- `<head>`: `<title>`, `description`, `canonical`, `og:title`,
  `og:description`, `og:image`, `og:url`, `robots` (`noindex` when
  `index: false`), `<link rel="alternate" type="text/markdown">` for a
  Markdown page, `hreflang` per language;
- `<body>`: the page loader as today, then `<main>` with the page's text in
  plain HTML (headings, paragraphs, lists, tables, links, `<pre><code
  class="language-yaml">`) from the same Markdown the app renders, then the
  Flutter bootstrap.

The text is not shown to people: it lies under the loader and then under
Flutter's view. It is never removed (Google indexes the page after running
its JavaScript, so a removed text is lost), not `display:none` (weighed
less), and it is exactly what the screen shows, since both come from one
file; that keeps it clear of Google's hidden-text and cloaking rules. It
is also what a screen reader can read on the web, where Flutter's own
semantics are weak.

Next to the pages: `sitemap.xml` (every page with `index: true`),
`robots.txt` (with the sitemap's URL), `<path>.md` (the Markdown as written,
for models), `llms.txt` (a map of the `.md` pages with their descriptions),
`llms-full.txt` (all of them in one file).

Code in the HTML has no colors (only robots read it). The colors of code in
the app come from the theme (`styles.markdown.*`, `styles.code.tokens.*`:
`keyword`, `string`, `comment`, `key`, `number`, ...), with a small
tokenizer of our own for the languages of the docs (Dart, YAML,
properties, shell); no package of the Dart team does it.

### Decided (the owner, November 2026)

- The dev server's keys (`host`, `port`, `https`, `headers`, `proxy`, the
  CSP) move to `spring.flutter.web.dev-server.*` (breaking, allowed before
  1.0), so `spring.flutter.web.*` holds `dev-server` and `seo`.
- The pages go to `web/` (`flutter build web` copies them, nothing else is
  run); the app ignores them in git, one line.
- Languages from the start: `content/ja/...` and the `messages_ja` titles at
  `/ja/...` with `hreflang`.
- The `<head>` and `manifest.json` of the app itself (title, description,
  `theme_color`, `background_color`, names) from `spring.flutter.app.*` and
  the theme, so `web/index.html` and the manifest repeat nothing by hand;
  useful without `seo`.

## Texts

The existing `MessageSource` with
`lib/resources/messages_{locale}.properties`, following the app's `Locale`
(`context.message('cart.total', args: [total])`), checked by the editor like
property keys.

## Settings

`shared_preferences` as a property source, and `@ConfigurationProperties`
beans written back to it, so user settings are ordinary configuration.

## The window on desktop (0.6.1, a patch right after 0.6.0; the owner, November 2026)

**Done** (November 2026; docs in the starter's README, "Desktop window", and
[docs/configuration.md](../docs/configuration.md)). `title` and `max-size`
are done too (blank title = unset; max-size: macOS `contentMaxSize`, Windows
`ptMaxTrackSize`, GTK `GDK_HINT_MAX_SIZE`; min <= initial <= max or the start
stops). Left: the position, restoring the size and position the user left. Not yet
run on real Windows and Linux machines (CI builds them: the `Desktop window`
job); macOS is checked by `integration_test/desktop_window_test.dart` in the
Flutter guide. On Linux `transparent` is a flat header bar of its own, since
GTK draws no content under one.

The native window of a desktop app set up by properties, like the app
widget: the title bar, as in Zed or VS Code (content drawn under a
transparent title bar, the window buttons over it), and the window's size:

```properties
spring.flutter.desktop.window.title=NEON Books        # blank: the runner's
spring.flutter.desktop.window.title-bar=transparent   # default | transparent | hidden
spring.flutter.desktop.window.initial-size=1280x800   # the size of a first start
spring.flutter.desktop.window.min-size=800x600        # the user cannot make it smaller
spring.flutter.desktop.window.max-size=1920x1080      # ... or larger
```

- `initial-size`: width x height in logical pixels, the size the window
  opens with (centered on the screen); without it the runner's default.
- `min-size`: the smallest size the user can drag the window's edges to
  (macOS `contentMinSize`, Windows `WM_GETMINMAXINFO`, GTK
  `gtk_window_set_geometry_hints`); without it no limit. An `initial-size`
  smaller than `min-size` stops the start with both values named.
- `title`: the window's title (macOS `NSWindow.title`, Windows
  `SetWindowTextW`, GTK `gtk_window_set_title`); a blank value is unset.
- `max-size`: the largest size the user can drag to (macOS `contentMaxSize`,
  Windows `ptMaxTrackSize` scaled by DPI, GTK `GDK_HINT_MAX_SIZE` with the
  minimum hint); `max-size` below `min-size` or `initial-size` outside
  min..max stops the start. Maximize follows the OS: macOS zoom respects
  it, Windows maximizes to `ptMaxSize` (the same size), GTK is up to the
  window manager.

The key carries the platform in its name, as the other platform-only keys
(`spring.flutter.web.*`, `spring.flutter.security.web.mode`): only desktop
apps read it; another value for one OS goes into its platform profile file
(`application-macos.properties`, `application-windows.properties`).

- macOS: `titlebarAppearsTransparent`, `titleVisibility = .hidden`,
  `.fullSizeContentView` on the `NSWindow` (three lines in the runner today,
  see `MainFlutterWindow.swift`);
- Windows: the frame extended into the client area (DWM) and a drag area
  the app marks;
- Linux (GTK): a header bar of our own (`gtk_window_set_titlebar`);
- the space the window buttons take reaches Flutter (a padding in
  `MediaQuery`, or a widget) so layouts leave room for them; a widget marks
  the area that drags the window.

This needs native code in the Flutter starter (as
`spring_boot_starter_flutter_security` has); no third-party package
(`window_manager` and the like are not allowed by the dependency rules).
Later in the same place: the position, and the size and position the user left restored on the next start (then
`initial-size` applies to the first start only).

## Files of the app: `FileTemplate` (0.6.2; the owner, November 2026)

**Done in 0.6.2** (docs: the starter's README, "Files of the app", and
`docs/configuration.md`): `FileTemplate`, `FileArea` (`files.cache`),
`FileStore`, `LocalFileStore` (dart:io; stale runs found by an exclusive lock
on the run folder's `.lock`, which the OS drops when the process dies),
`IndexedDbFileStore` (the web, `dart:js_interop` only, in memory where
IndexedDB is missing) and `InMemoryFileStore`. `list(prefix)` is a folder when
the prefix ends in `/`, else the start of a path. On the web `tempDir` and
`TempFile.path` are unsupported. Windows' `support` is `path_provider`'s
(roaming) support directory, not the local one the SQLite databases use.

A bean of the Flutter starter for the app's own files, shaped like
`SecretTemplate` (a template over a replaceable store):

```dart
await files.write('catalog.json', books);              // support: kept
final books = await files.read<List<Book>>('catalog.json');
await files.cache.write('thumb.png', bytes);           // the OS may clear it
await files.documents.write('export.csv', csv);        // the user sees it

final small = await files.temp((file) async {          // a new temporary file,
  await file.writeAsBytes(photo);                      // deleted after the block
  return compress(file);
});
await files.tempDir((dir) => unzip(archive, into: dir));
final keep = await files.createTemp();                 // when a block is not enough
```

- Places: `support` (default, kept), `cache`, `documents`, temporary — the
  directories the starter already finds through `path_provider`; the web
  uses IndexedDB.
- Writes are atomic (a temporary file, then a rename); paths stay inside
  their place (`..` and absolute paths are refused); objects go through the
  `ObjectMapper`.
- Temporary files have unique names under the app's own folder of the run;
  removed after their block (an error too), when the context closes, and at
  the next start for runs that died.
- Replaceable: `FileStore` (write, read, delete, list, modified at, per
  place) under `FileTemplate`; both beans `@ConditionalOnMissingBean`, so an
  app swaps the store (encrypted, remote) and everything on top — the theme
  cache too — follows.
- The theme from a URL keeps its cache through it (in `support`).

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
