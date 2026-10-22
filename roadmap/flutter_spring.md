# flutter_spring (planned)

An app on `flutter_spring` needs no package stack around Flutter.
Dependency injection, HTTP, JSON, configuration, state, navigation,
storage, background work and logging come from the Spring family, so the
app's `pubspec.yaml` lists Flutter, `flutter_spring` and the starters it
uses. Like the rest of the family, `flutter_spring` depends only on this
repository, the Flutter SDK and plugins of the Flutter and Dart teams
(`path_provider`, `shared_preferences`). The exceptions are packages that
nothing here should replace, each in its own optional starter and allowed
only there by the dependency check: Flutter Scene (3D, bound to the UI),
signals (reactive state) and a Rust bridge.

| Usually | With `flutter_spring` |
|---|---|
| `get_it`, `provider`, `riverpod` (dependency injection) | beans, constructor injection, `context.basket` / `SpringWidget<(...)>` in widgets, a bean scope per route |
| `dio`, `http`, `retrofit`, `web_socket_channel` | `spring_web_dart` transports, `@FeignClient`, `EventStream<T>`, `@WebSocketClient` (done) |
| `json_serializable`, `freezed` (JSON) | `ObjectMapper` on generated metadata (done) |
| `bloc`, `getx`, `mobx` (state) | beans with `@Signal` fields (`flutter_spring_signals`), application events, `@EventListener` |
| `go_router`, `auto_route` (navigation) | `@Route` widgets and a generated router on the Flutter SDK's `Router` |
| `flutter_dotenv`, `envied`, flavors (configuration) | `application-{profile}.properties`, `--dart-define` as a property source, platform profiles |
| `hive`, `shared_preferences` wrappers (settings, storage) | `@ConfigurationProperties` saved in `shared_preferences`; SQLite through the Data starter |
| `easy_localization` (texts) | `MessageSource` with `messages_{locale}.properties`, following the app's `Locale` |
| `workmanager`, hand-made timers (background work) | `@Scheduled` and the `TaskExecutor` (worker isolates), following the app lifecycle |
| `flutter_secure_storage` (tokens) | a `TokenStore` bean on the Keychain / Keystore through own platform channels |
| `logger` | `SpringLog`, log files in the app's directory, a log viewer screen over `LogBuffer` |
| `mocktail` setups (tests) | `springBootTest` and `BeanOverride` under `flutter_test` (done) |

Optional starters: [signals](flutter_spring_signals.md), [Flutter Scene](flutter_spring_scene.md), [Rust](flutter_spring_rust.md).

## `SpringApp`

The root widget. Starts the application (`runApplicationAsync`), shows a
splash screen until the runners are done (or the failure report), and gives
the context to the tree (see *Beans in widgets*).

## Beans in widgets

State beans are used from many widgets anywhere in the tree, so passing them
through constructors does not scale. Two ways, both explicit; a widget's
constructor always stays the developer's own — nothing is injected into
constructor parameters by type, so a widget may still take a `Basket` passed
by hand.

- **Generated `BuildContext` getters** for the beans marked for it
  (`@ContextAccess()`, working name): only those, so the list stays
  short even with hundreds of beans. Typed, completed by the editor,
  named after the beans (unique in Spring); a `@Scope('route')` bean
  comes from the route the widget is in.
  ```dart
  @Component()
  @ContextAccess()
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
- **`SpringWidget<(...)>`**: the beans a widget needs in its type, handed
  to `build` as a record. Good for a few widgets with a few beans; it
  gets heavy when many widgets need many beans.
  ```dart
  class BasketBadge extends SpringWidget<(Basket, AppNavigator)> {
    const BasketBadge({this.compact = false, super.key}); // your constructor
    final bool compact;

    @override
    Widget build(BuildContext context, (Basket, AppNavigator) beans) {
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
bean. Tests replace beans in a test `SpringApp`
(`overrides: [BeanOverride<Basket>(fake)]`), or call
`build(context, (FakeBasket(), FakeNavigator()))` directly. Services
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

## Tokens and secrets of the user

A `TokenStore` bean on the iOS / macOS Keychain and the Android Keystore
through own platform channels (no community plugin), used by Feign and
WebSocket interceptors and by
[the OAuth2 client](spring_boot_starter_oauth2_client.md) to keep the login
across restarts.

## Hot reload without code

A root `SpringApp` widget calls `reloadApplication` from its `reassemble()`
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
