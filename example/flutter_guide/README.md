# The Flutter guide: NEON Books, the app

NEON Books is the bookstore of the guides. This is its Flutter app
(package `neon_books_app`): a client of the bookstore's server,
[`example/server_guide`](../server_guide/README.md), on phones, desktops
and (as far as a browser allows) the web. It uses everything the family
offers a Flutter app: beans for state, themes and texts from properties,
Feign clients and a WebSocket for the server, Spring Security for the
user, caching, scheduling, validation, logging and tests that need no
server.

Read it chapter by chapter: each says what it shows, which files to open,
what to try, and which test proves it. The packages' READMEs have the
details:
[`spring_boot_starter_flutter`](../../spring_boot_starter_flutter/README.md),
[`spring_boot_starter_feign`](../../spring_boot_starter_feign/README.md),
[`spring_boot_starter_websocket`](../../spring_boot_starter_websocket/README.md),
[`spring_security_core`](../../spring_security_core/README.md),
[`spring_boot_starter_cache`](../../spring_boot_starter_cache/README.md),
[`spring_boot_starter_scheduling`](../../spring_boot_starter_scheduling/README.md),
[`spring_boot_starter_logging`](../../spring_boot_starter_logging/README.md),
[`spring_boot_starter_test`](../../spring_boot_starter_test/README.md),
[`spring_web_dart`](../../spring_web_dart/README.md) and
[Flutter testing](../../docs/flutter-testing.md).

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
flutter run -d chrome                                 # the web: see "Limits" below
```

Users: `ada` / `ada-secret` (role USER), `root` / `root-secret` (USER and
ADMIN). The catalog needs no login; ordering, the orders, the support
chat and the Admin screen do.

The app resolves outside the pub workspace (`flutter_test` pins its own
`test_api`): `pubspec_overrides.yaml` takes the family's packages from
their folders. After changing beans, annotations or `lib/resources/`,
regenerate `lib/main.spring.dart`:

```sh
dart run build_runner build      # or `watch` while developing
```

```sh
flutter test --exclude-tags golden   # every chapter's tests (no server needed)
flutter test --tags golden           # the screenshots (macOS only, see chapter 11)
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
                               the session transport, the cookie jar, ProblemDetail helpers
  src/account/                 Session, the AuthenticationProvider, Login screen, account button
  src/catalog/ basket/ orders/ stock/ support/ admin/ settings/ logs/ about/
assets/                        images, texts, a theme "from the server"
res/fonts/                     Roboto, Roboto Condensed (loaded by family, listed nowhere)
test/                          a test file per chapter, test/support/ (the fake server), goldens
```

## 1. The application

`lib/main.dart` is all of `main`: `@SpringBootApplication()` on it and
`SpringApplicationWidget(application: () => springApplication, home:
HomePage())`. There is no hand-written `MaterialApp`: the app widget is
built from `spring.flutter.app.*` (`type=material`, the title, no debug
banner) in `lib/resources/application.properties`, its locales from the
messages files, its themes from `application.yml` (chapter 3).

- **Platform profiles.** The platform is an active profile: `mobile` +
  `android` / `ios`, `desktop` + `macos` / `windows` / `linux`, `web`.
  `application-mobile.properties` puts the sections in a bottom bar,
  `application-desktop.properties` and `application-web.properties` in a
  rail (`app.navigation`, bound by `AppProperties`,
  `lib/src/app/app_properties.dart`); `application-android.properties`
  points the app at `10.0.2.2:8080`, the emulator's way to the computer.
  `@Profile(['!web'])` keeps two beans out of the browser (chapter 6).
- **Navigation.** `HomePage` (`lib/src/app/home_page.dart`) shows the
  sections; screens are pushed with `Navigator`. `spring.flutter.app.*`
  has no routes yet (no `routes`, `onGenerateRoute` or `routerConfig`),
  so the starter's part is the `NavigatorObserver` beans: `RouteLog`
  (`lib/src/app/route_log.dart`) logs every screen opened and closed.
- **The app lifecycle** arrives as application events: `LifecycleLog`
  (`lib/src/app/lifecycle_log.dart`) logs `AppLifecycleStateEvent`s, and
  `ContextPausedEvent` / `ContextRestartedEvent` when the app goes to the
  background and comes back (the context is paused: chapter 8).
- **`@Log`** generates the `log` getter of a class into
  `main.spring.dart` (Lombok's `@Slf4j`), the logger named by `topic:`.
- **Checked at startup.** `ApiProperties` (`lib/src/api/api_properties.dart`)
  is `@ConfigurationProperties('api')` with constraints: a bad
  `api.base-url` stops the start with the failure report on screen.

Try: `flutter run -d macos` and `flutter run` on a phone; background the
app and watch the console (`neon.lifecycle`).

Test: `test/app_test.dart` (profiles on a phone and a desktop, the
lifecycle events, the NavigatorObserver, a failed start).

## 2. State in beans

The app's state is in beans, not in `State` objects, so any screen and any
service reads and changes the same object.

- **`@ChangeNotifierComponent`**: `Basket` (`lib/src/basket/basket.dart`),
  `Catalog` (`lib/src/catalog/catalog.dart`), `Session`
  (`lib/src/account/session.dart`), `LanguageSelection`
  (`lib/src/app/language.dart`). Plain classes: the generated proxy is the
  `ChangeNotifier` and notifies after every method (after the returned
  `Future` completes).
- **`@NotifyListeners`** on classes that extend `ChangeNotifier`
  themselves: `LiveStock` (`lib/src/stock/live_stock.dart`) and
  `SupportChat` (`lib/src/support/support_chat.dart`). Their news arrives
  in stream callbacks, not method calls, so they call
  `notifyListeners()` there; the annotation adds it after the public
  methods (`exclude:` leaves out `stop` and `join`).
- **`SpringStatelessWidget<(...)>`** gets the beans of its record as
  `beans`: `BasketBadge`, `BasketPage`, `MorePage`, `SettingsPage`, ...
  One bean stays in place (`<(Basket,)>`); several get a typedef named
  after the widget (`typedef BasketPageBeans = (Basket, Session,
  OrderService);`), which a stateful widget and its `State` share.
  **`SpringStatefulWidget<(...)>`** with a `SpringState` for screens with
  their own state: `CatalogPage` (the search field), `BookPage`,
  `LoginPage`, `AdminPage`, `ChatInput`.
- **`@BuildContextAccess`** generates `context.basket`, `context.catalog`,
  `context.session`, `context.languageSelection` (imported from
  `main.spring.dart`): `BookTile` calls `context.basket.add(book)`,
  `AccountButton` listens to `context.session` with a `ListenableBuilder`.
- **Only the widgets that read a bean rebuild.** `BasketBadge` reads
  `basket.count`, so a book added anywhere rebuilds it; the book tile only
  calls `basket.add` and is not rebuilt. `CatalogPage` only calls
  `catalog.search`, so a new answer rebuilds `CatalogList`, not the page
  with the text field. One rule to keep in mind: a read
  outside every build (in `initState`, in another bean) makes every widget
  holding the bean listen from then on; `CatalogRefresh` therefore calls
  `catalog.reload()` instead of reading `catalog.books`.

Try: add books from the catalog and watch the badge; search, then switch
sections.

Test: `test/state_test.dart` (which widgets rebuild, recorded with
Flutter's `debugOnRebuildDirtyWidget`; `context.basket`; a bean changed by
a service).

## 3. Themes

No `ThemeData` in the code. `lib/resources/application.yml` holds the
shared part of every theme (seed color, fonts per text role, shapes,
components, spacing, the app's own `brand` tokens) and the standard
`dark` theme's differences; it imports one file per custom theme
(`spring.config.import`):

| File | Theme |
|---|---|
| `lib/resources/themes/neon.yml` | the bookstore's pink and cyan, full-round buttons |
| `lib/resources/themes/neon-night.yml` | `extends: neon`, `brightness: dark` |
| `lib/resources/themes/sepia.yml` | own colors, flat shapes, no splash |
| `lib/resources/themes/high-contrast.yml` | `extends: light`, `contrast: 1.0` |
| `assets/remote/winter.yml` | a theme as the server could send it, loaded at run time |

- **Fonts from an asset folder.** `res/fonts/roboto/` and
  `res/fonts/condensed/` are listed under `flutter: assets:` only; the
  starter loads every font file by the family it names, the theme names
  families (`Roboto`, `Roboto Condensed`).
- **Tokens.** `ThemeBanner` and `ThemePreview`
  (`lib/src/settings/theme_preview.dart`) read `SpringTheme.of(context)`:
  `tokenColor('brand.accent')`, `tokenNumber('brand.banner-height')`,
  `space('m')`, `shape('large')`, `textStyle('code')`. The other screens
  use `space` and `shape` too.
- **Switching.** Settings (`lib/src/settings/settings_page.dart`) is a
  `SpringStatelessWidget<SettingsPageBeans>` (`ThemeSelection`,
  `SpringThemes`, ...): a tap
  calls `selection.select(name)`; "Load a theme from the server" calls
  `SpringThemes.loadYaml` with `assets/remote/winter.yml` and selects it.
- **Checked at the start.** A misspelled value fails the start, naming
  the property.

Try: More → Settings, pick each theme; `flutter run
--dart-define=SPRING_FLUTTER_THEME_ACTIVE=neon` starts in one.

Test: `test/themes_test.dart` (the themes and their order, `extends`,
fonts, switching, `loadYaml`, a broken property), and the screenshots of
Settings in every theme (chapter 11).

## 4. Texts

Every text is in `lib/resources/messages.properties` (English) and
`messages_ja.properties` (Japanese), read with
`context.message('basket.added', args: [book.title])`. The app's locales
are the languages of these files. Settings → Language picks one or
follows the device: `spring.flutter.app.*` has no locale property, so a
`FlutterAppCustomizer` bean (`LanguageCustomizer`,
`lib/src/app/language.dart`) wraps the app's routes in
`Localizations.override`, driven by the `LanguageSelection` bean.

The validation messages of the Admin form use Spring's error codes
(`Pattern.newBook.isbn`, `NotBlank`, `typeMismatch.newBook.price`), so
they are translated in the same files (chapter 9).

Try: Settings → 日本語, or a device in Japanese.

Test: `test/texts_test.dart`; screenshots `japanese.png`,
`about_japanese.png`.

## 5. Assets

`AppAssets` (`lib/src/about/app_assets.dart`) gets the app's assets
injected as `Resource`s: `@Value('asset:assets/images/leaf.png')` (the
logo, shown with `AssetImage(key)`), `@Value('asset:assets/texts/about.txt')`
(read with `readAsString()`; its Japanese file `about_ja.txt` found with
`createRelative`), the sample cover the Admin screen uploads and the
"server's" theme. The generator checks each `asset:` against
`pubspec.yaml`'s `flutter: assets:`. Config files and messages stay in
`lib/resources/` (the classpath, embedded into the generated code).

Try: More → About, in English and in Japanese.

Test: `test/assets_test.dart`; screenshots `about.png`,
`about_japanese.png`.

## 6. Server access

The server's API (see [API](#api)) as interfaces:

| Client | File | Shows |
|---|---|---|
| `CatalogClient` | `lib/src/api/catalog_client.dart` | `@FeignClient(url: r'${api.base-url}', path:)`, `@RequestParam`s left out when `null`, `@PathVariable`, bytes (`Future<Uint8List>`) |
| `AccountClient` | `lib/src/api/account_client.dart` | a form body (`consumes: applicationFormUrlencoded`), `Future<ResponseEntity<void>>` |
| `ShopClient` | `lib/src/api/shop_client.dart` | `PUT` with a JSON body, `Future<ResponseEntity<ShopOrder>>` (status, `Location`) |
| `AdminClient` | `lib/src/api/admin_client.dart` | a multipart upload (`@RequestPart('file') MultipartFile`), `DELETE`, raw JSON |
| `StockClient` | `lib/src/api/stock_client.dart` | `EventStream<StockChanged>`: server-sent events, reconnecting with `Last-Event-ID` |
| `SupportSocket` | `lib/src/api/support_socket.dart` | `@WebSocketClient`: `@OnMessage` stream, `@SendMessage`, `close()` |

- **The session.** The server keeps the user in an HTTP session and
  protects `POST`/`PUT`/`DELETE` with a CSRF token in the `XSRF-TOKEN`
  cookie. `SessionTransport` (`lib/src/api/session_transport.dart`) is an
  `HttpTransport` decorator that does what a browser does: it sends and
  stores the cookies of the `CookieJar` (`lib/src/api/cookie_jar.dart`)
  and puts the token into `X-XSRF-TOKEN`. `ApiConfig`
  (`lib/src/api/api_config.dart`) declares the platform transport as
  the bean `networkTransport` and the decorator as the `@Primary`
  `HttpTransport` every Feign client uses.
- **The chat's handshake** carries the session cookie:
  `SupportHandshake` (`lib/src/api/support_handshake.dart`) is a
  `WebSocketHandshakeInterceptor` bean.
- **Retries.** A `Retryer` bean (`DefaultRetryer(maxAttempts: 3)`) tries
  again what failed without an answer; the Logs screen shows the
  `---> RETRYING` lines when the server is down.
- **Errors.** `CatalogService.find` turns a 404 (`FeignNotFound`) into
  `null` ("There is no book ..."); the Admin form shows the field errors
  of a 400 ProblemDetail under its fields (`fieldErrorsOf`,
  `lib/src/api/problems.dart`); `errorMessage`
  (`lib/src/app/messages.dart`) says "The server cannot be reached" for a
  `RetryableException`.
- **Properties.** Read timeout, logger level, the event stream's
  reconnect delay and the socket's reconnect back-off are
  `spring.cloud.openfeign.client.config.*` and
  `spring.websocket.client.config.*` in `application.properties`.

Try: with the server running, open Live stock while the server's restock
job runs; open a book; stop the server and watch the catalog's error and
the retries in Logs.

Test: `test/server_access_test.dart` (query parameters and JSON, the
Retryer, `FeignNotFound`, cookies and the CSRF header, logout,
`ResponseEntity` with `Location`, the multipart upload, the event stream
on screen, the chat with the session cookie, server field errors in the
Admin form).

## 7. Login & roles

- The Login screen (`lib/src/account/login_page.dart`) calls
  `Session.login`. `Session` asks Spring Security's
  `AuthenticationManager`, which the security starter builds around the
  app's `ServerAuthenticationProvider`
  (`lib/src/account/server_authentication_provider.dart`): it posts the
  form login to `/api/login` (a `GET /api/me` first, when there is no CSRF
  token yet), then reads `/api/me` and returns a
  `UsernamePasswordAuthenticationToken` with the roles as authorities.
  A 401 becomes a `BadCredentialsException` ("Wrong user name or
  password").
- `Session` puts the result into `SecurityContextHolder` (outside any zone
  there is one context for the whole app) and publishes a `LoggedIn`
  payload event: `Basket` and `SupportChat` listen (`@EventListener`).
- `@PreAuthorize("hasRole('ADMIN')")` on `AdminService`
  (`lib/src/admin/admin_service.dart`) and
  `@PreAuthorize('isAuthenticated()')` on `OrderService`
  (`lib/src/orders/order_service.dart`): a call without the role fails
  with `AccessDeniedException` before any request is sent.
- The Admin entry of More appears for admins only (`session.isAdmin`).
- Logout (the account menu) posts `/api/logout`, clears the
  `SecurityContextHolder` and the cookies, closes the chat's socket and
  empties the basket (`LoggedOut`).

All of this is UI convenience: the app hides what a user may not do and
does not send what would fail, but the protection is the server's. It
checks the session and the role of every request again.

Try: log in as `ada`, then as `root`; More shows Admin only for `root`.

Test: `test/security_test.dart` (a wrong password, a USER, an ADMIN,
`@PreAuthorize` with `withMockUser`, logout).

## 8. Cache & scheduling

- `CatalogService` (`lib/src/catalog/catalog_service.dart`) is the
  catalog the screens read: `@Cacheable('catalog')` pages (keyed by query
  and page), `@Cacheable('books', unless: '#result == null')` books (a
  miss is not remembered), `@Cacheable('covers')` covers,
  `@CacheEvict.of(cacheNames: [...], allEntries: true)` `refresh()`,
  `@CacheEvict('covers', key: '#isbn')` after an upload. The caches are
  in memory (`spring.cache.*`, the covers limited to 50).
- `CatalogRefresh` (`lib/src/catalog/catalog_refresh.dart`) is
  `@Scheduled(fixedDelayString: r'${catalog.refresh-interval:5m}')`: it
  empties the caches and reloads the page on screen. Only in the
  foreground: in the background `SpringApplicationWidget` pauses the
  context, which stops `@Scheduled` tasks (and the chat's socket), and
  restarts them when the app is back
  (`spring.flutter.lifecycle.pause-in-background=false` keeps them
  running).

Try: `flutter run --dart-define=CATALOG_REFRESHINTERVAL=30s`, change a
price on the server, wait; background the app and watch Logs.

Test: `test/cache_scheduling_test.dart` (one request per page, misses not
cached, eviction, the schedule paused in the background).

## 9. Validation

The Admin form is checked in the app before anything is sent. `NewBook`
(`lib/src/api/models.dart`) carries the constraints (`@NotBlank`,
`@Matches`, `@SizeConstraint`, `@Positive`, `@Max`); `BookForm`
(`lib/src/admin/book_form.dart`) binds the form's texts onto a `NewBook`
with a `DataBinder` ("twelve" as a price is a `typeMismatch`) and checks
it with the auto-configured `BeanValidator`. The field errors carry
Spring's codes; the Admin screen asks the `MessageSource` for their texts
(`getMessageFromResolvable`), in English or Japanese. What the server
still refuses comes back as a ProblemDetail (chapter 6).

Try: Admin, "Add the book" with an empty form, then with `978-0`.

Test: `test/validation_test.dart` (codes, messages in both languages, the
form showing them without a request); screenshot `admin_errors.png`.

## 10. Logging

The app logs through `SpringLog` (`@Log` getters, fields:
`log.info('order placed', fields: {...})`); `logging.*` in
`application.properties` sets the levels (`neon` and `feign` at debug).
The logging starter writes Spring Boot's console lines (`flutter run`
shows them) and keeps the last 500 records in the `LogBuffer` bean. The
Logs screen (`lib/src/logs/logs_page.dart`) is a
`SpringStatefulWidget<(LogBuffer,)>` showing `buffer.watch(LogQuery(minLevel:
...))`, filtered by level. The Admin screen shows the server's own log
(`GET /api/admin/logs`).

Try: More → Logs, Debug: the Feign calls (`---> GET ...`), the screens
opened, the cookies stored.

Test: `test/logging_test.dart` (levels, `SpringLog.withFields`, the screen
and its filter).

## 11. Testing

The tests need no server, except the end-to-end ones.
`test/support/fake_server.dart` plays the server: a
`MockHttpTransport` and a `MockWebSocketTransport`, put in with
`BeanOverride` (`BeanOverride<HttpTransport>(http, name:
'networkTransport')`, so the app's own session transport and its cookies
are tested too).

- **`springBootTest`** with `SpringScope` + `SpringApp` for screens
  (`showPage`, `test/support/app.dart`) and plain `test`s for services;
  `app.markDirty()` gives every test a fresh context.
- **`SpringApplicationWidget`** for the whole app as `flutter run` starts
  it (`startApp`): profiles, lifecycle, fonts, a failed start. The fake
  server's `application()` adds the same `BeanOverride`s to a copy of
  `springApplication` (a `BeanOverrideProcessor` in an
  `ApplicationContextInitializer`): `SpringApplicationWidget` itself takes
  no overrides yet.
- **Goldens.** `test/golden_test.dart` compares screens with
  `test/goldens/*.png`: the catalog, a book, the basket, live stock, the
  chat, the Admin errors, Login, Japanese, About (English and Japanese),
  desktop, and Settings in every theme (the themes gallery). Real fonts:
  the app's Roboto files, the Material icons of the SDK and a Japanese
  subset (`test/fonts/`, `test/flutter_test_config.dart`). Tagged
  `golden`: made on macOS, compared only there.
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
| 7 | `test/security_test.dart` |
| 8 | `test/cache_scheduling_test.dart` |
| 9 | `test/validation_test.dart` |
| 10 | `test/logging_test.dart` |
| 11 | `test/golden_test.dart` |

```sh
(cd ../server_guide && dart run bin/main.dart) &  # for the e2e tests
flutter test --exclude-tags golden                # everywhere
flutter test --exclude-tags 'golden || e2e'       # without the server
flutter test --tags golden                        # macOS
flutter test --tags golden --update-goldens       # accept a new look
```

Tests see no system fonts, so the Japanese glyphs come from
`test/fonts/NotoSansJP-Subset.ttf`: only the characters of
`messages_ja.properties` and `assets/texts/about_ja.txt`, cut from Noto
Sans JP (SIL Open Font License, `test/fonts/NotoSansJP-OFL.txt`). After
changing the Japanese texts, cut it again
([fonttools](https://github.com/fonttools/fonttools)):

```sh
fonttools varLib.instancer 'NotoSansJP[wght].ttf' wght=400 -o NotoSansJP-Regular.ttf
pyftsubset NotoSansJP-Regular.ttf --layout-features='*' \
  --text="$(sed -n 's/^[^=]*=//p' lib/resources/messages_ja.properties)$(cat assets/texts/about_ja.txt)" \
  --output-file=test/fonts/NotoSansJP-Subset.ttf
```

The images only match on macOS: Linux and Windows draw the letters
differently. Small differences between macOS versions (0.5% of the
pixels) are tolerated (`test/flutter_test_config.dart`).

## Limits

- **The web.** `flutter build web --release` builds; the anonymous parts
  (catalog, books, live stock, themes, texts, logs) need nothing but the
  server's CORS settings for the page's origin. The session does not
  work there: a
  browser keeps the server's cookies itself and `FetchHttpTransport`
  sends no credentials across origins, so logging in from a page on
  another origin does not keep the session. The app leaves its cookie
  decorator and handshake interceptor out of the `web` profile.
- **Routes.** `spring.flutter.app.*` has no routes or router yet;
  navigation is `Navigator.push` with `NavigatorObserver` beans.
- **The language** is set with a `FlutterAppCustomizer`, as there is no
  locale property.

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

| Method | Path | Who | What |
|---|---|---|---|
| GET | `/api/books?q=&page=` | anyone | catalog page (`Page`-like JSON: items, page, total), `@RequestParam`s, cached |
| GET | `/api/books/{isbn}` | anyone | one book, 404 ProblemDetail if unknown |
| GET | `/api/books/{isbn}/cover` | anyone | the cover image (`Resource`, `Range`, `Cache-Control`) |
| POST | `/api/books` | ADMIN | add a book, `@Valid` body (400 with field errors), 201 + `Location` |
| PUT | `/api/books/{isbn}/cover` | ADMIN | upload a cover (multipart `@RequestPart MultipartFile`) |
| DELETE | `/api/books/{isbn}` | ADMIN | remove (method security `@PreAuthorize` on the service) |
| GET | `/api/stock/events` | anyone | server-sent events `StockChanged {isbn, available}` (`EventStream` or `SseEmitter`), `Last-Event-ID` resume |
| GET | `/api/me` | logged in | `{name, roles}` (`@AuthenticationPrincipal`) |
| GET | `/api/basket` | logged in | the user's basket (kept in the `HttpSession`) |
| PUT | `/api/basket/items/{isbn}` | logged in | set a quantity `{quantity}` |
| POST | `/api/orders` | logged in | order the basket: 201 `Order`; publishes `OrderPlaced` |
| GET | `/api/orders` | logged in | the user's orders (`@PostFilter` on the service: own orders; ADMIN sees all) |
| WS | `/ws/support` | logged in | support chat: JSON `ChatMessage {from, text, at}`; the handshake passes the security chain (session cookie); the server answers with a bot and broadcasts to admins |
| GET | `/actuator`-like `/api/admin/logs` | ADMIN | the last log lines from `LogBuffer` |

### The JSON the app reads and writes

The contract names the endpoints; the app's model classes
(`lib/src/api/models.dart`, all `@Introspected`) expect these bodies.
Unknown properties are ignored and every property but the first of each
line has a default, so a server sending more (or a little less) still
works:

| Body | JSON |
|---|---|
| a book | `{"isbn", "title", "author", "price", "available"}` |
| a catalog page | `{"items": [book...], "page", "size", "total"}` (`page` from 0; without `size`, the length of the page) |
| a new book (`POST /api/books`) | `{"isbn", "title", "author", "price"}` |
| a stock change (SSE data) | `{"isbn", "available"}` |
| `/api/me` | `{"name", "roles": ["USER", "ADMIN"]}` (`ROLE_USER` works too) |
| the basket | `{"items": [{"isbn", "title", "quantity"}]}` |
| a quantity (`PUT /api/basket/items/{isbn}`) | `{"quantity"}`, 0 removes the line |
| an order | `{"id", "user", "lines": [{"isbn", "title", "quantity"}], "total", "placedAt"}` (`id` a number or a text) |
| a chat message | `{"from", "text", "at"}` |
| `/api/admin/logs` | a JSON array of lines (strings, or objects with a `message`) |
| a 400 of `@Valid` | a ProblemDetail with `"errors": [{"field", "message"}]` (the web starter's format) |
