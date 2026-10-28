# The Flutter guide: NEON Books, the app

NEON Books is the bookstore of the guides. This is its Flutter app
(package `neon_books_app`), a client of the bookstore's server,
[`example/server_guide`](../server_guide/README.md). It runs on phones,
desktops and, as far as a browser allows, the web.

The app shows how a Flutter app is built on the spring_core_dart family,
and it uses everything the family offers a Flutter app:

- the app's state and services in beans (objects the framework creates
  once and hands to whoever needs them), given to the widgets;
- themes and texts from configuration files instead of code;
- the server's REST API and a WebSocket as Dart interfaces;
- the logged-in user and role checks with Spring Security, and single
  sign-on with Keycloak (the system browser on devices, the server on
  the web);
- caching, scheduled work, validation and logging;
- tests that need no server, and screenshots compared in CI.

Read it chapter by chapter. Each chapter says what it shows, which files
to open, what to try and which test proves it. The packages' READMEs
have the details:
[`spring_boot_starter_flutter`](../../spring_boot_starter_flutter/README.md),
[`spring_boot_starter_feign`](../../spring_boot_starter_feign/README.md),
[`spring_boot_starter_websocket`](../../spring_boot_starter_websocket/README.md),
[`spring_security_core`](../../spring_security_core/README.md),
[`spring_boot_starter_cache`](../../spring_boot_starter_cache/README.md),
[`spring_boot_starter_scheduling`](../../spring_boot_starter_scheduling/README.md),
[`spring_boot_starter_logging`](../../spring_boot_starter_logging/README.md),
[`spring_boot_starter_test`](../../spring_boot_starter_test/README.md),
[`spring_web_dart`](../../spring_web_dart/README.md) and
[Flutter testing](../../docs/flutter-testing.md). The code follows the
[code style](../../docs/style.md) of the family.

## Run

Start the server, then the app:

```sh
cd example/server_guide && dart run bin/main.dart     # http://localhost:8080
cd example/flutter_guide && flutter pub get && flutter run
```

```sh
flutter run -d macos                                  # a desktop window (desktop profile)
flutter run -d emulator-5554                          # Android: the server at 10.0.2.2:8080
flutter run --dart-define=API_HOST=192.168.1.20:8080  # a phone on the LAN
flutter run -d chrome                                 # the web, on http://localhost:5050/
```

`flutter run` serves the web version on port 5050, the origin the server's
CORS and SSO settings expect: `spring.flutter.web.port=5050` in
`lib/resources/application-web.properties`, which the generator writes
into `web_dev_config.yaml` for the Flutter tool. No `--web-port` flag is
needed, from the command line or an editor.

Single sign-on with Keycloak (chapter 7): Keycloak, then the server
and the app with the `sso` profile:

```sh
cd example/keycloak && docker compose up              # see its README
cd example/server_guide && dart run bin/main.dart --spring.profiles.active=dev,sso
cd example/flutter_guide && flutter run -d macos --dart-define=SPRING_PROFILES_ACTIVE=sso
flutter run -d chrome --dart-define=SPRING_PROFILES_ACTIVE=sso
flutter run -d web-server --dart-define=SPRING_PROFILES_ACTIVE=sso  # any browser
adb reverse tcp:8180 tcp:8180                         # Android emulator: Keycloak at localhost
```

Users: `ada` / `ada-secret` (role USER), `root` / `root-secret` (USER and
ADMIN). The catalog needs no login; ordering, the orders, the support
chat and the Admin screen do.

The app is not part of the repository's pub workspace, because
`flutter_test` pins its own `test_api`. Its `pubspec_overrides.yaml`
takes the family's packages from their folders instead.

After changing beans, annotations or `lib/resources/`, regenerate
`lib/main.spring.dart` (and `web_dev_config.yaml`):

```sh
dart run build_runner build      # or `watch` while developing
```

```sh
flutter test --exclude-tags 'golden || e2e'  # every chapter's tests, no server needed
flutter test --tags golden                   # the screenshots (macOS only, see chapter 11)
```

## The screens

| Screen | File | Reached from |
|---|---|---|
| Catalog | `lib/src/catalog/catalog_page.dart` | the first section |
| Book (cover, stock) | `lib/src/catalog/book_page.dart` | a book of the catalog |
| Basket | `lib/src/basket/basket_page.dart` | the second section (its icon counts the books) |
| Orders | `lib/src/orders/orders_page.dart` | the third section |
| Live stock | `lib/src/stock/live_stock_page.dart` | the fourth section |
| Support chat | `lib/src/support/support_page.dart` | More → Support |
| Admin (add book, cover upload, server log) | `lib/src/admin/admin_page.dart` | More → Admin, for admins only |
| Settings (theme, language) | `lib/src/settings/settings_page.dart` | More → Settings |
| Logs | `lib/src/logs/logs_page.dart` | More → Logs |
| About | `lib/src/about/about_page.dart` | More → About |
| Login | `lib/src/account/login_page.dart` | the app bar's "Log in" |

```text
lib/
  main.dart                    @SpringBootApplication, SpringApplicationWidget
  main.spring.dart             generated: the beans, proxies, Feign clients, context getters, `log`
  resources/                   the classpath: application*.properties, application.yml,
                               themes/*.yml, messages*.properties
  src/app/                     the home (sections), app properties, language, lifecycle and route logs
  src/api/                     the server's API: models, Feign clients, the WebSocket client,
                               the session transports, the cookie jar, the browser page,
                               ProblemDetail helpers
  src/account/                 Session, the AuthenticationProvider, Login screen, account button,
                               Keycloak (roles, tokens on calls)
  src/catalog/ basket/ orders/ stock/ support/ admin/ settings/ logs/ about/
assets/                        images, texts, a theme "from the server"
res/fonts/                     Roboto, Roboto Condensed (loaded by family, listed nowhere)
test/                          a test file per chapter, test/support/ (the fake server), goldens
```

## 1. The application

`lib/main.dart` is the whole of `main`:

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const HomePage(),
  ),
);
```

`SpringApplicationWidget` starts the application (configuration files,
beans) and gives it to the widgets. There is no hand-written
`MaterialApp`. The app widget is built from `spring.flutter.app.*` in
`lib/resources/application.properties` (`type=material`, the title, no
debug banner), its locales from the message files, and its themes from
`application.yml` (chapter 3).

- **Platform profiles.** The platform the app runs on is an active
  profile: `mobile` with `android` or `ios`, `desktop` with `macos`,
  `windows` or `linux`, and `web`. Each profile may have its own file,
  read on that platform only:
  `application-mobile.properties` puts the sections in a bottom bar,
  `application-desktop.properties` and `application-web.properties` in a
  side rail. The setting is `app.navigation`, bound to `AppProperties`
  (`lib/src/app/app_properties.dart`), which `HomePage` reads.
  `application-android.properties` points the app at `10.0.2.2:8080`,
  the Android emulator's way to the computer. `@Profile(['!web'])` keeps
  two beans out of the browser (chapter 6).
- **Navigation.** `HomePage` (`lib/src/app/home_page.dart`) shows the
  sections; other screens are pushed with `Navigator`. The starter has no
  route properties yet, so its part is the `NavigatorObserver` beans:
  `RouteLog` (`lib/src/app/route_log.dart`) logs every screen opened and
  closed.
- **The app lifecycle** arrives as application events. `LifecycleLog`
  (`lib/src/app/lifecycle_log.dart`) logs each `AppLifecycleStateEvent`,
  and the `ContextPausedEvent` and `ContextRestartedEvent` that follow
  when the app goes to the background and comes back (the context is
  paused: chapter 8).
- **`@Log`** gives a class a `log` getter, generated into
  `main.spring.dart` (Lombok's `@Slf4j` in Java). The logger is named
  `topic:` (`neon.lifecycle`), else `neon_books_app.LifecycleLog`.
- **Checked at startup.** `ApiProperties` (`lib/src/api/api_properties.dart`)
  is `@ConfigurationProperties('api')` with constraints (`@NotBlank`,
  `@Matches`), and `AppProperties` limits the title's length. A bad
  value, such as an `api.base-url` that is no `http` URL, stops the start
  and the failure report shows on screen, instead of the first request
  failing later.

Try: `flutter run -d macos` and `flutter run` on a phone; send the app
to the background and watch the console (`neon.lifecycle`).

Test: `test/app_test.dart` (the profiles on a phone and on a desktop, the
lifecycle events, the `NavigatorObserver`, a failed start).

## 2. State in beans

The app's state is in beans, not in `State` objects, so every screen and
every service reads and changes the same object, and switching sections
loses nothing.

- **`@ChangeNotifierComponent`**: `Basket` (`lib/src/basket/basket.dart`),
  `Catalog` (`lib/src/catalog/catalog.dart`), `Session`
  (`lib/src/account/session.dart`), `LanguageSelection`
  (`lib/src/app/language.dart`). They are plain classes. The generated
  proxy of each bean is a `ChangeNotifier` and notifies after every
  method (for a method returning a `Future`, once it completes).

  ```dart
  @ChangeNotifierComponent()
  @BuildContextAccess()
  @Log(topic: 'neon.basket')
  class Basket {
    ...
    /// How many books (the badge).
    int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

    /// One more copy of [book].
    Future<void> add(Book book) => setQuantity(...);
  }
  ```
- **`@NotifyListeners`** on classes that extend `ChangeNotifier`
  themselves: `LiveStock` (`lib/src/stock/live_stock.dart`) and
  `SupportChat` (`lib/src/support/support_chat.dart`). Their news arrives
  in stream callbacks, not in method calls, so they call
  `notifyListeners()` there themselves. The annotation adds the call
  after their public methods; `exclude:` leaves out `LiveStock.stop`
  (called while the screen closes) and `SupportChat.join`.
- **`SpringStatelessWidget<(...)>`** gets the beans of its record as
  `beans`: `BasketBadge`, `BasketPage`, `CatalogList`, `MorePage`,
  `SettingsPage`, ... One bean stays in place (`<(Basket,)>`). Several
  get a typedef named after the widget, one bean per line:

  ```dart
  /// The beans of [BasketPage].
  typedef BasketPageBeans = (
    Basket,
    Session,
    OrderService,
  );

  class BasketPage extends SpringStatelessWidget<BasketPageBeans> {
  ```

  **`SpringStatefulWidget<(...)>`** with a `SpringState` is for screens
  with their own state: `CatalogPage` (the search field), `BookPage`,
  `LoginPage`, `AdminPage`, `OrdersPage`, `ChatInput`, ...
- **`@BuildContextAccess`** generates `context.basket`, `context.catalog`,
  `context.session` and `context.languageSelection` (imported from
  `main.spring.dart`). `BookTile` calls `context.basket.add(book)`;
  `AccountButton` listens to `context.session` with a
  `ListenableBuilder`.
- **Only the widgets that read a bean rebuild.** `BasketBadge` reads
  `basket.count`, so a book added anywhere rebuilds it; the book tile
  only calls `basket.add` and is not rebuilt. `CatalogPage` only calls
  `catalog.search`, so a new answer rebuilds `CatalogList`, not the page
  with the text field. One rule to keep in mind: a read outside every
  build (in `initState`, in another bean) makes every widget holding the
  bean listen from then on. So `CatalogPage.initState` calls
  `catalog.search('')`, and `CatalogRefresh` calls `catalog.reload()`,
  instead of reading `catalog.books`.

Try: add books from the catalog and watch the badge; search, then switch
sections and come back.

Test: `test/state_test.dart` (which widgets rebuild, recorded with
Flutter's `debugOnRebuildDirtyWidget`; `context.basket`; a bean changed
by a service).

## 3. Themes

There is no `ThemeData` in the code. `lib/resources/application.yml`
holds the part shared by every theme (seed color, fonts per text role,
shapes, components, spacing, the app's own `brand` tokens) and what the
standard `dark` theme changes. It imports one file per custom theme
(`spring.config.import`):

| File | Theme |
|---|---|
| `lib/resources/themes/neon.yml` | the bookstore's pink and cyan, full-round buttons |
| `lib/resources/themes/neon-night.yml` | `extends: neon`, `brightness: dark` |
| `lib/resources/themes/sepia.yml` | its own colors, nearly square shapes, no splash |
| `lib/resources/themes/high-contrast.yml` | `extends: light`, `contrast: 1.0` |
| `assets/remote/winter.yml` | a theme as the server could send it, loaded at run time |

```yaml
# lib/resources/themes/neon-night.yml: everything of `neon`, dark
spring.flutter.theme.themes.neon-night:
  extends: neon
  brightness: dark
```

- **Fonts from an asset folder.** `res/fonts/roboto/` and
  `res/fonts/condensed/` are listed under `flutter: assets:` only, not
  under `flutter: fonts:`. The starter loads every font file into the
  family the file names, and the theme names the families (`Roboto`,
  `Roboto Condensed`).
- **The app's own values.** Widgets read the theme shown with
  `SpringTheme.of(context)`. `ThemeBanner`
  (`lib/src/settings/settings_page.dart`) reads the brand tokens,
  `tokenColor('brand.accent')` and `tokenNumber('brand.banner-height')`,
  and `space('m')` and `shape('large')`. `ThemePreview`
  (`lib/src/settings/theme_preview.dart`) uses `space`, `shape('small')`
  and `textStyle('code')`. The other screens use `space` and `shape`
  too.
- **Switching.** Settings (`lib/src/settings/settings_page.dart`) is a
  `SpringStatelessWidget<SettingsPageBeans>` (`ThemeSelection`,
  `SpringThemes`, `LanguageSelection`, `AppAssets`). A tap on a theme
  calls `selection.select(name)`, and the whole app changes at once.
  "Load a theme from the server" passes `assets/remote/winter.yml` to
  `SpringThemes.loadYaml` and selects `winter`.
- **Checked at the start.** A misspelled key or value fails the start,
  naming the property.

Try: More → Settings and pick each theme. `flutter run
--dart-define=SPRING_FLUTTER_THEME_ACTIVE=neon` starts in one.

Test: `test/themes_test.dart` (the themes and their order, `extends`,
the fonts, switching, `loadYaml`, a broken property), and the
screenshots of Settings in every theme (chapter 11).

## 4. Texts

Every text is in `lib/resources/messages.properties` (English) and
`messages_ja.properties` (Japanese), read with
`context.message('basket.added', args: [book.title])`. The app supports
the languages of these files.

Settings → Language picks a language or follows the device. The starter
has a property for the supported locales but none for the one shown, so
a `FlutterAppCustomizer` bean (`LanguageCustomizer`,
`lib/src/app/language.dart`) sets the app widget's `builder`. It wraps
the navigator in `Localizations.override`, driven by the
`LanguageSelection` bean; `context.message` and Flutter's own widgets
follow at once.

The validation messages of the Admin form use Spring's error codes
(`Pattern.newBook.isbn`, `NotBlank`, `typeMismatch.newBook.price`), so
they are translated in the same files (chapter 9).

Try: Settings → 日本語, or a device in Japanese.

Test: `test/texts_test.dart`; the screenshots `japanese.png` and
`about_japanese.png`.

## 5. Assets

`AppAssets` (`lib/src/about/app_assets.dart`) gets the app's assets
injected as `Resource`s:

```dart
@Component()
class AppAssets {
  AppAssets(
    @Value('asset:assets/images/leaf.png') this.logo,
    @Value('asset:assets/texts/about.txt') this.about,
    @Value('asset:assets/images/sample_cover.png') this.sampleCover,
    @Value('asset:assets/remote/winter.yml') this.winterTheme,
  );
  ...
}
```

The logo is shown with `AssetImage(key)`. The About text is read with
`readAsString()`, and its Japanese file `about_ja.txt` is found next to
it with `createRelative`. The sample cover is what the Admin screen
uploads, and `winter.yml` is the "server's" theme. The generator checks
each `asset:` against `flutter: assets:` in `pubspec.yaml`, so a missing
file fails the build. Config files and messages stay in
`lib/resources/` (the classpath, embedded into the generated code).

Try: More → About, in English and in Japanese.

Test: `test/assets_test.dart`; the screenshots `about.png` and
`about_japanese.png`.

## 6. Server access

The server's API (see [API](#api)) is written as Dart interfaces; the
generator writes the HTTP and WebSocket code:

```dart
@FeignClient('catalog', url: r'${api.base-url}', path: '/api/books')
abstract interface class CatalogClient {
  /// `GET /api/books?q=dune&page=0`; a `null` query is left out.
  @GetMapping()
  Future<PageOfBooks> page({
    @RequestParam('q') String? query,
    @RequestParam('page') int? page,
  });
  ...
}
```

| Client | File | Shows |
|---|---|---|
| `CatalogClient` | `lib/src/api/catalog_client.dart` | `@FeignClient(url: r'${api.base-url}', path:)`, `@RequestParam`s left out when `null`, `@PathVariable`, bytes (`Future<Uint8List>`) |
| `AccountClient` | `lib/src/api/account_client.dart` | a form body (`consumes: applicationFormUrlencoded`), `Future<ResponseEntity<void>>` |
| `ShopClient` | `lib/src/api/shop_client.dart` | `PUT` with a JSON body, `Future<ResponseEntity<ShopOrder>>` (status, `Location`) |
| `AdminClient` | `lib/src/api/admin_client.dart` | a multipart upload (`@RequestPart('file') MultipartFile`), `DELETE`, raw JSON |
| `StockClient` | `lib/src/api/stock_client.dart` | `EventStream<StockChanged>`: server-sent events, reconnecting with `Last-Event-ID` |
| `SupportSocket` | `lib/src/api/support_socket.dart` | `@WebSocketClient`: an `@OnMessage` stream, `@SendMessage`, `close()` |

- **The session.** The server keeps the user in an HTTP session and
  protects `POST`, `PUT` and `DELETE` with a CSRF token in the
  `XSRF-TOKEN` cookie. A browser would handle both; the app does it
  itself. `SessionTransport` (`lib/src/api/session_transport.dart`)
  wraps the network: it sends and stores the cookies of the `CookieJar`
  (`lib/src/api/cookie_jar.dart`) and copies the token into the
  `X-XSRF-TOKEN` header. `ApiConfig` (`lib/src/api/api_config.dart`)
  declares the platform's transport as the bean `networkTransport`, and
  the session transport as the `@Primary` `HttpTransport` that every
  Feign client uses. Only requests to the server (`api.base-url`) get
  the session: the Keycloak login of chapter 7 goes through the same
  bean, and the server's cookies are none of Keycloak's business.
- **The session in a browser.** The browser keeps the cookies itself and
  hides the session cookie (`HttpOnly`) from the app. The page
  (localhost:5050) and the server (localhost:8080) are two origins of one
  site, so `fetch` must be told to send cookies to the server:
  `platformHttpTransport(credentials: FetchCredentials.include)` (the
  server allows it, CORS with credentials). The CSRF cookie is no
  `HttpOnly` and cookies ignore ports, so the page reads the server's
  `XSRF-TOKEN` (`document.cookie`, through `BrowserPage`,
  `lib/src/api/browser_page.dart`, a `web` profile bean on
  `dart:js_interop`), and `BrowserSessionTransport` sends it as
  `X-XSRF-TOKEN`. The form login works in a browser this way too.
- **The chat's handshake** carries the session cookie:
  `SupportHandshake` (`lib/src/api/support_handshake.dart`) is a
  `WebSocketHandshakeInterceptor` bean.
- **Retries.** A `Retryer` bean (`DefaultRetryer(maxAttempts: 3)`) tries
  again what failed without an answer (no connection, a timeout); a
  `POST` that got an answer is never sent twice. The Logs screen shows
  the `---> RETRYING` lines when the server is down.
- **Errors.** `CatalogService.find` turns a 404 (`FeignNotFound`) into
  `null`, and the screen says "There is no book ...". The Admin form
  shows the field errors of a 400 ProblemDetail under its fields
  (`fieldErrorsOf`, `lib/src/api/problems.dart`). `errorMessage`
  (`lib/src/app/messages.dart`) says "The server cannot be reached" for
  a `RetryableException`.
- **Properties.** The read timeout, the logger level, the event stream's
  reconnect delay and attempts, and the socket's reconnect back-off are
  `spring.cloud.openfeign.client.config.*` and
  `spring.websocket.client.config.*` in `application.properties`.

Try: with the server running, open Live stock while the server's restock
job runs; open a book; stop the server and watch the catalog's error and
the retries in Logs.

Test: `test/server_access_test.dart` (query parameters and JSON, the
`Retryer`, `FeignNotFound`, cookies and the CSRF header, logout,
`ResponseEntity` with `Location`, the multipart upload, the event stream
on screen, the chat with the session cookie, the server's field errors in
the Admin form).

## 7. Login & roles

- **Logging in.** The Login screen (`lib/src/account/login_page.dart`)
  calls `Session.login`. `Session` asks Spring Security's
  `AuthenticationManager`, which `spring_security_core` builds around the
  app's `AuthenticationProvider` bean, `ServerAuthenticationProvider`
  (`lib/src/account/server_authentication_provider.dart`). The provider
  posts the form login to `/api/login` (after a `GET /api/me` for the
  CSRF cookie, when there is none yet), reads `/api/me` and returns a
  `UsernamePasswordAuthenticationToken` with the roles as authorities. A
  401 becomes a `BadCredentialsException`: "Wrong user name or
  password".
- **The user.** `Session` puts the result into the
  `SecurityContextHolder` (outside any zone there is one security context
  for the whole app) and publishes a `LoggedIn` event, a plain object.
  `Basket` and `SupportChat` listen to it with `@EventListener`.
- **Role checks.** `@PreAuthorize("hasRole('ADMIN')")` on `AdminService`
  (`lib/src/admin/admin_service.dart`) and
  `@PreAuthorize('isAuthenticated()')` on `OrderService`
  (`lib/src/orders/order_service.dart`) check the user before any request
  is sent. A USER calling an admin method gets an
  `AccessDeniedException`; ordering without a login, an
  `AuthenticationCredentialsNotFoundException`.
- The Admin entry of More appears for admins only (`session.isAdmin`).
- **Logging out** (the account menu) posts `/api/logout`, clears the
  `SecurityContextHolder` and the cookies, and publishes `LoggedOut`: the
  chat closes its socket and the basket empties.

All of this is a convenience for the user: the app hides what a user may
not do and does not send what would fail. The protection is the
server's, which checks the session and the role of every request again.

Try: log in as `ada`, then as `root`; More shows Admin only for `root`.

Test: `test/security_test.dart` (a wrong password, a USER, an ADMIN,
`@PreAuthorize` with `withMockUser`, logout).

### Single sign-on with Keycloak

With the `sso` profile (`--dart-define=SPRING_PROFILES_ACTIVE=sso`, and
the server with `--spring.profiles.active=dev,sso`), the Login screen
has one button, "Sign in with Keycloak", and the password is typed into
Keycloak's page, never into the app. Afterwards the app is the same: a
user in the `SecurityContextHolder` with `ROLE_*` authorities, the same
`Session`, `@PreAuthorize`, Admin entry and `LoggedIn` event. How the
login happens depends on the platform, for the security of the tokens:

| Platform | Who logs in | The tokens | The server knows the user by |
|---|---|---|---|
| iOS, Android, macOS | the app: `OAuth2LoginService`, a public client with PKCE, Keycloak's page in the system browser (`ASWebAuthenticationSession`, a Custom Tab), back to `books.neon.app:/oauth2/callback` | the platform's secure storage (Keychain, Keystore) | `Authorization: Bearer` |
| Windows, Linux | the same, back to `http://127.0.0.1:<free port>/oauth2/callback` (a loopback server of the app) | DPAPI, libsecret | `Authorization: Bearer` |
| Web | the server (`oauth2Login()`): the page goes to `<server>/oauth2/authorization/keycloak` and comes back | on the server only; the page holds the `HttpOnly` session cookie | the session |

An app cannot keep a secret (anyone can read it out of the binary), so
it logs in without one; PKCE makes a code caught by another app useless.
The system browser, never a WebView, shows Keycloak's page: the app
cannot read the password, and a login of the browser is reused. A web
page has no safe place at all for tokens (any injected script reads
them), so the server logs the web app in and keeps them. The reasons in
full: [the roadmap](../../roadmap/spring_boot_starter_oauth2_client.md#which-flow-where-the-security-decision).

- **Configuration, no code.** `application-sso.properties` sets
  `neon.sso.enabled` (`SsoProperties`, `lib/src/account/sso_properties.dart`),
  which the Login screen reads. The native apps' registration is
  `spring.security.oauth2.client.registration.keycloak.*` in a document
  of `application.properties` guarded by `on-profile=sso & !web` (the
  web has none, so it gets no login service and no tokens); another
  document, `sso & (windows | linux)`, changes the redirect to the
  loopback. The issuer is `http://localhost:8180/realms/neon` everywhere:
  the server accepts only tokens of that issuer, so the Android emulator
  reaches Keycloak through `adb reverse tcp:8180 tcp:8180` rather than
  `10.0.2.2`.
- **The login.** `Session.signInWithKeycloak`: on a native platform
  `OAuth2LoginService.login('keycloak')` (from
  `spring_boot_starter_oauth2_client`; the Flutter starter supplies the
  secure storage and the system browser); on the web it navigates the
  page (`BrowserPage.open`). The user is named by `preferred_username`
  (`user-name-attribute`), and `KeycloakRolesMapper`
  (`lib/src/account/keycloak.dart`), a `GrantedAuthoritiesMapper` bean,
  turns the realm roles of the `roles` claim into `ROLE_USER` and
  `ROLE_ADMIN`.
- **Tokens on the calls.** `KeycloakTokenInterceptor`, a
  `RequestInterceptor` bean, puts `Authorization: Bearer` with a fresh
  token (refreshed a minute before it expires) on every Feign call of a
  Keycloak user. Not `spring.cloud.openfeign.oauth2.enabled`: its
  interceptor, as Spring Cloud OpenFeign's, fails every call made while
  nobody is logged in, and the catalog is public. The support chat's
  handshake carries the token too (`SupportHandshake`). A 401 to a token
  that looked valid marks it expired (`OAuth2AccessTokenErrorDecoder`).
- **Restarts.** `Session.restore` runs at `ApplicationReadyEvent`: a
  native app brings the user back from the stored tokens
  (`OAuth2LoginService.restore`, offline too); the web app asks the
  server `/api/me` with its cookie, which is how it finds the user after
  Keycloak sent the page back.
- **Logout.** A native app revokes its tokens at Keycloak, forgets them
  and ends Keycloak's session in the system browser
  (`logout(endSession: true)`, back to `books.neon.app:/oauth2/logout`).
  The web app posts `/api/logout`; the server answers with Keycloak's
  logout URL, and the page goes there and comes back logged out.
- **Android** catches the redirect with the Flutter starter's
  `RedirectReceiverActivity`, declared with the scheme `books.neon.app`
  in `android/app/src/main/AndroidManifest.xml`. iOS and macOS need
  nothing: the login session waits for the redirect URI's scheme.

Try: on macOS, "Log in", "Sign in with Keycloak", `root` / `root-secret`
in the sheet; Admin appears. Quit and start the app again: still `root`.
In a browser at `http://localhost:5050/`, the same button leaves for
Keycloak and comes back logged in.

Test: `test/sso_test.dart` (Keycloak played by the fake server, the
system browser by a fake that logs in at once: the button, root's roles,
the Bearer token on calls and none on anonymous ones, no server cookie
sent to Keycloak, a closed login page, a restart that restores the user,
the logout's revocation and end of session; and the web: the navigation
to the server, the user after the return, the CSRF header from the
page's cookie, the logout URL).

## 8. Cache & scheduling

- **Caching.** `CatalogService` (`lib/src/catalog/catalog_service.dart`)
  is the catalog the screens read. Its answers are kept in memory, so
  going back to a page or a book shows it at once without a request:

  | Method | Annotation |
  |---|---|
  | `page(query, page)` | `@Cacheable('catalog')`: one entry per query and page |
  | `find(isbn)` | `@Cacheable('books', unless: '#result == null')`: a missing book is not remembered |
  | `cover(isbn)` | `@Cacheable('covers', unless: '#result == null')` |
  | `refresh()` | `@CacheEvict.of(cacheNames: ['catalog', 'books'], allEntries: true)`: covers rarely change |
  | `coverChanged(isbn)` | `@CacheEvict('covers', key: '#isbn')`, after an upload |

  The caches are configured with `spring.cache.*`; `covers` holds at
  most 50 entries.
- **A scheduled refresh.** `CatalogRefresh`
  (`lib/src/catalog/catalog_refresh.dart`) runs every
  `catalog.refresh-interval` (5 minutes):

  ```dart
  @Scheduled(
    fixedDelayString: r'${catalog.refresh-interval:5m}',
    initialDelayString: r'${catalog.refresh-interval:5m}',
  )
  Future<void> refresh() async { ... }
  ```

  It empties the caches and reloads the page on screen, so new books and
  prices show up. Only in the foreground: when the app goes to the
  background, `SpringApplicationWidget` pauses the context, which stops
  `@Scheduled` tasks (and the chat's socket), and starts them again when
  the app comes back. `spring.flutter.lifecycle.pause-in-background=false`
  would keep them running.

Try: `flutter run --dart-define=CATALOG_REFRESHINTERVAL=30s`, change a
price on the server and wait; send the app to the background and watch
Logs.

Test: `test/cache_scheduling_test.dart` (one request per page, misses
not cached, eviction, the schedule paused in the background).

## 9. Validation

The Admin form is checked in the app before anything is sent. `NewBook`
(`lib/src/api/models.dart`) carries the constraints:

```dart
@Introspected()
class NewBook {
  @NotBlank()
  @Matches(r'^97[89]\d{10}$')
  String isbn = '';
  ...
  @Positive()
  @Max(1000)
  double price = 0;
}
```

`BookForm` (`lib/src/admin/book_form.dart`) binds the form's texts onto a
`NewBook` with a `DataBinder` ("twelve" as a price is a `typeMismatch`
error) and checks it with the auto-configured `BeanValidator`. The field
errors carry Spring's codes. The Admin screen asks the `MessageSource`
for their texts (`getMessageFromResolvable`), in English or Japanese.
What the server still refuses comes back as a ProblemDetail (chapter 6).

Try: Admin, "Add the book" with an empty form, then with the ISBN
`978-0`.

Test: `test/validation_test.dart` (the codes, the messages in both
languages, the form showing them without a request); the screenshot
`admin_errors.png`.

## 10. Logging

The app logs through `SpringLog`: the `@Log` getters, with structured
fields (`log.info('order placed', fields: {...})`). `logging.*` in
`application.properties` sets the levels (`neon` and `feign` at debug).
The logging starter writes Spring Boot's console lines, which
`flutter run` shows, and keeps the last 500 records in the `LogBuffer`
bean. The Logs screen (`lib/src/logs/logs_page.dart`) is a
`SpringStatefulWidget<(LogBuffer,)>` that shows
`buffer.watch(LogQuery(minLevel: ...))`, filtered by level. The Admin
screen shows the server's own log (`GET /api/admin/logs`).

Try: More → Logs, Debug: the Feign calls (`---> GET ...`), the screens
opened, the cookies stored.

Test: `test/logging_test.dart` (the levels, fields, the screen and its
filter).

## 11. Testing

The tests need no server, except the end-to-end ones.
`test/support/fake_server.dart` plays the server with a
`MockHttpTransport` and a `MockWebSocketTransport`. They replace the
app's network through `BeanOverride`s, below the app's own session
transport (`BeanOverride<HttpTransport>(http, name: 'networkTransport')`),
so the cookies and the CSRF header are tested too.

- **Screens and services: `springBootTest`.** Most tests start the
  application once per file with `springBootTest` and the fake server's
  overrides; `setUp(app.markDirty)` gives every test a fresh context.
  Screens are shown under `SpringScope` and `SpringApp` (`showPage`,
  `test/support/app.dart`); services are tested with plain `test`s.
- **The whole app: `SpringApplicationWidget`.** Some tests start the app
  as `flutter run` does (`startApp`): the profiles, the lifecycle, the
  fonts, a failed start. `SpringApplicationWidget` takes no overrides
  yet, so the fake server's `application()` makes a copy of
  `springApplication` with the same overrides (a `BeanOverrideProcessor`
  in an `ApplicationContextInitializer`).
- **Golden screenshots.** `test/golden_test.dart` compares screens with
  `test/goldens/*.png`: the catalog, a book, the basket, live stock, the
  chat, the Admin errors, Login, Japanese, About (English and Japanese),
  desktop, and Settings in every theme of the files (a gallery of the
  themes). They use real fonts: the app's Roboto files, the SDK's
  Material icons and a Japanese subset (`test/fonts/`,
  `test/flutter_test_config.dart`). Tagged `golden`: made on macOS and
  compared only there.
- **End to end.** `test/e2e_test.dart` runs the app's services against
  the real server guide over real sockets: the catalog and a cover, a
  wrong password, a user's basket and order (and no admin rights), an
  admin adding a book with a cover, live stock events, the support chat.
  It keeps the two guides honest: CI starts the server guide and runs it
  with the other tests. Tagged `e2e`.

| Chapter | Test |
|---|---|
| 1 | `test/app_test.dart` |
| 2 | `test/state_test.dart` |
| 3 | `test/themes_test.dart` |
| 4 | `test/texts_test.dart` |
| 5 | `test/assets_test.dart` |
| 6 | `test/server_access_test.dart` |
| 7 | `test/security_test.dart`, `test/sso_test.dart` |
| 8 | `test/cache_scheduling_test.dart` |
| 9 | `test/validation_test.dart` |
| 10 | `test/logging_test.dart` |
| 11 | `test/golden_test.dart` |

```sh
(cd ../server_guide && dart run bin/main.dart) &  # for the e2e tests
flutter test --exclude-tags golden                # on any OS, with the server
flutter test --exclude-tags 'golden || e2e'       # without the server
flutter test --tags golden                        # macOS
flutter test --tags golden --update-goldens       # accept a new look
```

Tests see no system fonts, so the Japanese glyphs come from
`test/fonts/NotoSansJP-Subset.ttf`. It holds only the characters of
`messages_ja.properties` and `assets/texts/about_ja.txt`, cut from Noto
Sans JP (SIL Open Font License, `test/fonts/NotoSansJP-OFL.txt`). After
changing the Japanese texts, cut it again with
[fonttools](https://github.com/fonttools/fonttools):

```sh
fonttools varLib.instancer 'NotoSansJP[wght].ttf' wght=400 -o NotoSansJP-Regular.ttf
pyftsubset NotoSansJP-Regular.ttf --layout-features='*' \
  --text="$(sed -n 's/^[^=]*=//p' lib/resources/messages_ja.properties)$(cat assets/texts/about_ja.txt)" \
  --output-file=test/fonts/NotoSansJP-Subset.ttf
```

The images match on macOS only: Linux and Windows draw the letters
differently. Small differences between macOS versions, up to 0.5 % of
the pixels, are tolerated (`test/flutter_test_config.dart`).

## Limits

- **The web.** `flutter build web --release` builds. The page and the
  server must be on one site (`localhost` with two ports here,
  `app.example.com` and `api.example.com` in production): browsers drop
  the cookies of another site. The server allows the page's origin with
  credentials (CORS, `neon.cors.*`), and with SSO sends the browser back
  to `neon.app.web-url` (`http://localhost:5050/`), the port
  `spring.flutter.web.port` gives `flutter run` on the web.
- **Routes.** The starter has no route or router properties yet;
  navigation is `Navigator.push`, with `NavigatorObserver` beans.
- **The language** is picked with a `FlutterAppCustomizer`, as no
  property sets the locale shown.

## API

The contract between this app and the server guide (the same section is
in [the server guide's README](../server_guide/README.md#api)):

Base URL `http://localhost:8080` (property `server.port`). JSON everywhere, errors as
`application/problem+json`.

Users (in memory, passwords stored as `{argon2}` hashes, generated once and written into
application.properties, never plain text): `ada` / `ada-secret` role USER, `root` / `root-secret`
roles USER and ADMIN.

Security (spring_boot_starter_security): one chain for the API, sessions, CSRF with
`CookieCsrfTokenRepository.withHttpOnlyFalse()` (the app reads cookie `XSRF-TOKEN` and sends
header `X-XSRF-TOKEN` on POST/PUT/DELETE, as Spring's SPA recipe), CORS from properties (for the
Flutter web build), form login at `POST /api/login` (fields `username`, `password`) answering
`204` on success and `401` on failure (custom success/failure handlers: no redirects, an API
client logs in), logout at `POST /api/logout` → `204`. Anonymous GETs of the catalog are allowed.

Single sign-on (both with the profile `sso`, Keycloak of `example/keycloak`): no form login; browsers
log in at `GET /oauth2/authorization/keycloak` and come back to `neon.app.web-url` with the session
cookie, native apps send Keycloak's access token (`Authorization: Bearer`, audience `neon-api`);
`POST /api/logout` → `200 {"logoutUrl"}` after a browser's Keycloak login (the page goes there),
else `204`.

| Method | Path | Who | What |
|---|---|---|---|
| GET | `/api/books?q=&page=` | anyone | catalog page (`Page`-like JSON: items, page, total), `@RequestParam`s, cached |
| GET | `/api/books/{isbn}` | anyone | one book, 404 ProblemDetail if unknown |
| GET | `/api/books/{isbn}/cover` | anyone | the cover image (`Resource`, `Range`, `Cache-Control`) |
| POST | `/api/books` | ADMIN | add a book, `@Valid` body (400 with field errors), 201 + `Location` |
| PUT | `/api/books/{isbn}/cover` | ADMIN | upload a cover (multipart `@RequestPart MultipartFile`) |
| DELETE | `/api/books/{isbn}` | ADMIN | remove (method security `@PreAuthorize` on the service) |
| GET | `/api/stock/events` | anyone | server-sent events `StockChanged {isbn, available}` (`EventStream` or `SseEmitter`), `Last-Event-ID` resume |
| GET | `/api/me` | logged in | `{name, roles}` (any kind of login) |
| GET | `/api/basket` | logged in | the user's basket (kept in the `HttpSession`) |
| PUT | `/api/basket/items/{isbn}` | logged in | set a quantity `{quantity}` |
| POST | `/api/orders` | logged in | order the basket: 201 `Order`; publishes `OrderPlaced` |
| GET | `/api/orders` | logged in | the user's orders (`@PostFilter` on the service: own orders; ADMIN sees all) |
| WS | `/ws/support` | logged in | support chat: JSON `ChatMessage {from, text, at}`; the handshake passes the security chain (session cookie); the server answers with a bot and broadcasts to admins |
| GET | `/actuator`-like `/api/admin/logs` | ADMIN | the last log lines from `LogBuffer` |

### The JSON the app reads and writes

The contract names the endpoints; the app's model classes
(`lib/src/api/models.dart`, all `@Introspected`) expect these bodies.
Unknown properties are ignored, and every property but the first of each
line has a default, so a server that sends more (or a little less) still
works:

| Body | JSON |
|---|---|
| a book | `{"isbn", "title", "author", "price", "available"}` |
| a catalog page | `{"items": [book...], "page", "size", "total"}` (`page` from 0; without `size`, the length of the page) |
| a new book (`POST /api/books`) | `{"isbn", "title", "author", "price"}` |
| a stock change (SSE data) | `{"isbn", "available"}` |
| `/api/me` | `{"name", "roles": ["USER", "ADMIN"]}` (`ROLE_USER` works too) |
| `POST /api/logout` after a Keycloak login of the web app | `{"logoutUrl"}` |
| the basket | `{"items": [{"isbn", "title", "quantity"}]}` |
| a quantity (`PUT /api/basket/items/{isbn}`) | `{"quantity"}`, 0 removes the line |
| an order | `{"id", "user", "lines": [{"isbn", "title", "quantity"}], "total", "placedAt"}` (`id` a number or a text) |
| a chat message | `{"from", "text", "at"}` |
| `/api/admin/logs` | a JSON array of lines (strings, or objects with a `message`) |
| a 400 of `@Valid` | a ProblemDetail with `"errors": [{"field", "message"}]` (the web starter's format) |
