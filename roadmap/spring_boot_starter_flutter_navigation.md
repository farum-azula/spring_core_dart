# spring_boot_starter_flutter_navigation

**The release after 0.7.0** (the owner, November
2026), together with deep links, SEO, Markdown and the screen map. Declarative
navigation for Flutter apps as a starter of its own, like
`spring_boot_starter_flutter_security`: routes on the SDK's `Router`
(deep links, the web URL bar, Android's back button), no `go_router`.
The documentation site is built on it (see the site in
[README.md](README.md)): a site about Spring, made with Spring.

## The release: what goes where

The release after 0.7.0 (the owner, November 2026).
Static resources in the web starter and the actuator's first part come
with it. Three new packages: `spring_boot_starter_flutter_navigation`,
`spring_boot_actuator`, `spring_boot_starter_actuator`.

| Package | What it gets |
|---|---|
| `spring_web_dart` | nothing new for routes: `PathPattern` (`{name}`, `{name:regex}`, `{*rest}`) is reused by the navigation starter and the generator, no second parser; `MappingDescriptions`, the interface "describe your routes" that the web starter's handler table and the router's screen table implement (one source for the screen map now, `/actuator/mappings` and OpenAPI later) |
| `spring_boot_starter_web` | static resources (`ResourceHttpRequestHandler`): `file:` locations, `ETag` / `304`, `Cache-Control`, `Range`, precompressed files, `index.html`, the single-page-app fallback, `.well-known/`, `ResourceHandlerRegistry`, `spring.web.resources.*`; verified in Docker (differential against Spring Boot, fuzzing, the active ZAP scan); the handler table behind `MappingDescriptions` |
| `spring_boot_starter_flutter` | the plugin's native part of deep links on macOS; the hook (`SpringApp` uses a `RouterConfig` bean when there is one); `spring.flutter.web.seo.*` (`FlutterWebSeoProperties`, read by the generator); the dev server's keys moved to `spring.flutter.web.dev-server.*` (breaking); `spring.flutter.app.description` for the page's `<head>` and the manifest; `MarkdownView` with `styles.markdown.*` and the code tokenizer (Dart, YAML, properties, shell) colored by `styles.code.tokens.*`, on the Dart team's `markdown` package |
| `spring_boot_starter_flutter_navigation` (new) | `@Route` (`title:`, `content:`, `params:`, `extra:`), `@RouteShell`, `@RouteInfo` (`description`, `image`, `index`, `paths`, `link`), `@RouteDeclarations`, `ScreenRoutes`, `RouteTemplate` / `context.route`, `RouteVar` / `RouteParam` / `RouteExtra` / `RouteLocation`, the `route` and `branch` scopes, route filters, the restored stack, the path URL strategy on the web, `<title>` / `description` / `og:*` on navigation, deep links at run time, the screen table behind `MappingDescriptions`, `spring.flutter.navigation.*` (with `deep-links.*`), test helpers (`openDeepLink`) |
| `spring_boot_actuator` (new) | `@Endpoint`, `@ReadOperation`, the `health` endpoint (`HealthIndicator`, `Status`, groups, `liveness` / `readiness`, `show-details` / `show-components`; `ping`, `diskSpace`), `info` (`InfoContributor`: `build`, `git`, `env`, `os`, `dart`), `mappings` over `MappingDescriptions`; pure Dart, no HTTP |
| `spring_boot_starter_actuator` (new) | the endpoints over HTTP through the web starter: `/actuator` with its `_links`, `management.endpoints.web.*`, `management.endpoint.<id>.*`, `management.info.*`, `EndpointRequest` for the security chain, the `db` indicator when the data starter is there |
| `spring_boot_starter_flutter_security` | filters by user and role, `@PreAuthorize` on a route, the redirect to the login and back |
| `spring_core_dart_generator` | the build info for the actuator's `info` (name and version from `pubspec.yaml`, the build time, the git branch and commit when there is one); `lib/spring_gen/routes.spring.dart` (a part of `main.spring.dart`: the route table, `<Page>Route` with `path` and `to(...)`, the constants per Markdown file such as `Docs.core.configuration`), checked at build time; the SEO pages in `web/` (`<path>/index.html` with the hidden text, `<path>.md`, `sitemap.xml`, `robots.txt`, `llms.txt`, `llms-full.txt`, `_headers`, `404.html`); the `<head>` and `manifest.json` of the app from `spring.flutter.app.*` and the theme; the deep links' native files (`Info.plist` and `Runner.entitlements` of iOS, `Info.plist` of macOS, `AndroidManifest.xml`, between markers) and domain files (`apple-app-site-association`, `assetlinks.json`); `web_dev_config.yaml` from the renamed keys |
| `extensions/language_server` | completion and checks of `spring.flutter.web.seo.*`, `spring.flutter.navigation.*` and the route paths in `route.go('...')`, go to the page of a path |
| examples | `example/flutter_guide` on the navigation starter (tabs, a deep link, a guarded route); the site is the first real app, made right after |

```yaml
dependencies:
  spring_boot_starter_flutter: ^0.x
  spring_boot_starter_flutter_navigation: ^0.x
```

## Routes on pages

Paths stay full; a route whose path starts with a shell's branch opens
in that shell (the owner, November 2026: `/catalog/books/{isbn}` is in
`MainTabs` because of its `/catalog` branch), so `shell:` is written only
for a route outside every branch that still opens in a shell; a path
under the branches of two shells fails the build. A route under no branch
opens over everything (checkout, a full-screen picture).

```dart
@RouteShell(branches: ['/catalog', '/basket', '/profile'])
class MainTabs extends StatelessWidget {
  const MainTabs(this.shell, {super.key});
  final ShellState shell;   // the current branch; each branch has its own stack

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell.child,                       // only this part changes
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.index,
      onDestinationSelected: shell.select,   // back to the branch as it was
      destinations: const [...],
    ),
  );
}

@Route('/catalog/books/{isbn}',
    params: {'tab': String, 'page': int}, extra: BookSummary)
class BookPage extends StatelessWidget { ... }

@Route('/checkout')
@PreAuthorize('isAuthenticated()')
class CheckoutPage extends StatelessWidget { ... }

@Route.notFound()
class NotFoundPage extends StatelessWidget { ... }
```

Why shells and not just paths: the tab bar must stay while the tab's
content changes; each tab keeps its own history; some routes open over
the tabs; master-detail on a wide window is the same idea.

## Routes in Dart configuration

Like Spring WebFlux's `RouterFunctions`; any number of `ScreenRoutes`
beans, merged with the annotated routes (the generator turns `@Route`
into one more `ScreenRoutes`). A path declared twice stops the start and
names both places. Libraries can bring screens the way they bring a
theme; conditions and profiles switch route sets.

```dart
@Configuration()
class AppRoutes {
  @Bean()
  ScreenRoutes routes(Session session) => ScreenRoutes.route()
      .shell((shell) => MainTabs(shell), (tabs) => tabs
          .branch('/catalog', (b) => b
              .screen(CatalogPageRoute.path, (r) => const CatalogPage())
              .screen(BookPageRoute.path, (r) => const BookPage()))
          .branch('/profile', (b) => b
              .screen('/profile', (r) => const ProfilePage())
              .filter(authenticated())))
      .screen('/checkout', (r) => const CheckoutPage(),
          transition: PageTransition.fade)
      .nest('/admin', (a) => a
          .screen('/admin', (r) => const AdminPage())
          .filter(hasRole('ADMIN')))
      .redirect('/', '/catalog')
      .notFound((r) => const NotFoundPage())
      .build();
}
```

Filters work like `HandlerFilterFunction`: given the request, they go on
or return a redirect.

## `RouteTemplate`: the current route

One bean, like `FileTemplate`, that reads the current route and
navigates. From a widget or a `route`-scoped bean it is that screen's
route (a book under another screen still sees its own `isbn`); from a
singleton it is the top screen. `context.route` is the same, bound to the
screen, and rebuilds the widget when the parameters change.

```dart
route.uri;                         // /catalog/books/978-0?page=2
route.pattern;                     // /catalog/books/{isbn}
route.pathVariable('isbn');        // String
route.param<int>('page');          // through the ConversionService
route.params<String>('tag');       // ?tag=a&tag=b
route.extra<BookSummary>();        // not in the URL
route.attributes;                  // declared with the route
route.stack; route.branch;
route.matches('/catalog/**');
route.changes;                     // Stream of navigations

route.go('/catalog/books/{isbn}', pathVariables: {'isbn': '978-0'},
    params: {'page': 2}, extra: summary);
final paid = await route.push<bool>('/checkout');
route.pop(true);
route.replaceParams({'page': 3});
```

A wrong value (`?page=abc`) opens the route error page, not a crash.

## Generated constants per page

Paths, variable and parameter names otherwise live as strings in three
places, and a rename fixes one of them. The generator writes a
`<Page>Route` extension per page in `spring_gen/routes.spring.dart`, so a renamed
path, parameter or type breaks the build:

```dart
extension BookPageRoute on BookPage {
  static const path = '/catalog/books/{isbn}';
  static const name = 'book-page';
  static const isbn = RouteVar<String>('isbn');
  static const tab = RouteParam<String>('tab');
  static const page = RouteParam<int>('page');
  static const preview = RouteExtra<BookSummary>();
  static RouteLocation to({required String isbn, String? tab, int? page,
      BookSummary? preview}) => ...;
}

final page = route.get(BookPageRoute.page) ?? 1;   // int?
route.go(BookPageRoute.to(isbn: '978-0', page: 2, preview: summary));
```

Static extension members are read through the extension's name
(`BookPageRoute.path`), which also names the page. Routes only in Dart
configuration get their constants from `@RouteDeclarations()` holders;
the start checks that every declared route is registered.

## Extra values

Not in the URL, so lost on a web reload, a deep link and a restored
stack. An extra is always optional (`extra:` types are nullable when
read); a screen must load from its path and parameters, the extra only
speeds it up. With `restore: true` an extra that `ObjectMapper` can write
is saved with the stack; another one comes back `null`, with a warning.

## Scopes

| Scope | Created | Destroyed |
|---|---|---|
| `route` | when the screen opens | when it closes, after the exit animation |
| `branch` | on the first visit of a shell's branch | when the shell closes (leaving the tabs, logout) |

The same screen opened twice has two instances. Switching tabs destroys
nothing. Dialogs and sheets opened from a screen see its `route` beans.
A singleton taking a `route` bean directly stops the start (it would
keep a dead screen); `ObjectProvider<T>` gives the current one or
`null`. Hot reload keeps them; with `restore: true` they are made again
from the route (and their state, when `@RestoreState` and serializable).

## Properties

```yaml
spring:
  flutter:
    navigation:
      initial: /catalog
      login: /login              # where @PreAuthorize sends
      restore: true              # the stacks survive a restart
      redirects:
        /: /catalog
```

The page transition comes from the theme (`motion.page-transition`); a
route may set its own.

## Search engines (SEO) and title

The web needs URLs without `#` (the path URL strategy, the default on the
web) and, per route, what a search result and a link preview show. With
`spring.flutter.web.seo.from-routes: true` the generator makes every
route a page of the site's HTML (keys, merging and the written files:
[spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#search-engines-previews-and-models-springflutterwebseo)).
Like springdoc's `@Operation` next to `@GetMapping`, what describes a
route beyond navigation is an annotation of its own, `@RouteInfo` (it
also feeds the link previews, the screen map and the deep
links, so not `@Seo`):

```dart
@Route('/', title: 'Spring Dart')
@RouteInfo(
  description: 'Spring Boot for Dart servers and Flutter apps.',
  image: 'resources:images/og.png',
)
class HomePage extends StatelessWidget { ... }

// A page per Markdown file: {*path} is Spring's "the rest of the path"
// (PathPattern, as in spring_web_dart), so /docs/core/configuration has
// path = /core/configuration and shows content/docs/core/configuration.md;
// its title and description come from the file's front matter.
@Route('/docs/{*path}', content: 'resources:content/docs/')
class DocPage extends StatelessWidget { ... }

@Route('/about', content: 'resources:content/about.md')   // one file
class AboutPage extends StatelessWidget { ... }

@Route('/checkout')
@RouteInfo(index: false)                     // noindex, not in the sitemap
class CheckoutPage extends StatelessWidget { ... }

@Route('/catalog/books/{isbn}')
@RouteInfo(paths: ['/catalog/books/978-0'])  // values the build cannot know
class BookPage extends StatelessWidget { ... }
```

- `title` is on `@Route`: it is also the browser tab's title and the
  screen's label for screen readers, not only SEO. `title` and
  `description` may be message keys (translated at `/ja/...`).
- `@RouteInfo`: `description`, `image`, `index` (default `true`), `paths`,
  `link` (default `true`: opened by a deep link).
- `content:` binds the route to resources: a folder for a route ending in
  `{*name}` (the rest of the path plus `.md` is the file; `/docs` itself is
  the folder's `index.md`), or one `.md` file for a route without
  variables; anything else fails the build. The page reads the file, the
  build lists the files; `RouteTemplate.content` gives the page its file.
- Route patterns are Spring's `PathPattern` syntax, the one the web starter
  already has: `{name}`, `{name:regex}`, `{*rest}` at the end; no syntax of
  our own.
- On navigation the app sets `<title>` and the `description` / `og:*` tags
  of the route it opened.

## The screen map

Spring has `/actuator/mappings` for controllers; the same table for
screens. Not Swagger: no OpenAPI, no Swagger UI, no dependency. Not a
file of the build either: routes in Dart configuration (`ScreenRoutes`)
are code the build cannot see, so the running app describes its screens
through `MappingDescriptions` (`spring_web_dart`), the interface the web
starter's handler table implements too; the build writes only what must
exist before the start (the SEO pages, the deep links' files, the
constants).

```json
{
  "path": "/catalog/books/{isbn}",
  "page": "BookPage",
  "title": "Book",
  "shell": "MainTabs", "branch": "/catalog",
  "variables": {"isbn": "String"},
  "params": {"tab": "String", "page": "int"},
  "extra": "BookSummary",
  "security": "isAuthenticated()",
  "info": {"index": true, "link": true}
}
```

What it is for: a "Screens" page (on the documentation site first); the
editor; a test that opens every screen; `/actuator/mappings` (in this
release). Later, on the same interface, the server's OpenAPI
(`/v3/api-docs`).

## Deep links

```yaml
spring:
  flutter:
    navigation:
      deep-links:
        enabled: true
        scheme: neonbooks                     # neonbooks://catalog/books/978-0
        domains: [books.example.com]          # Universal Links / App Links
        exclude: ['/checkout', '/admin/**']
```

```yaml
# application-ios.yml (default: from the Xcode project)
spring.flutter.navigation.deep-links.app-id: ABCDE12345.com.example.neonbooks
# application-android.yml (package default: from build.gradle)
spring.flutter.navigation.deep-links:
  package: com.example.neonbooks
  sha256-cert-fingerprints: ['AB:CD:...:EF']
```

- Every route opens by a link except `exclude` and `@RouteInfo(link:
  false)`; filters (`@PreAuthorize`) run on a deep link like on any
  navigation; an extra is `null`; a wrong value opens the route error page.
- A scheme is not verified (another app may claim it); domains are, so
  everything people share goes through `domains`. No token or secret in
  any link.
- The generator writes, between markers, the keys of `ios/Runner/Info.plist`
  (`CFBundleURLTypes`, `FlutterDeepLinkingEnabled`),
  `ios/Runner/Runner.entitlements` (`applinks:`), `macos/Runner/Info.plist`
  (the scheme) and `AndroidManifest.xml` (the intent filters, `autoVerify`,
  `flutter_deeplinking_enabled`; paths from the route patterns); never
  `project.pbxproj` (entitlements not linked: a warning).
- The domain files: `apple-app-site-association` and `assetlinks.json` in
  `web/.well-known/` for an app with a web version (with a `_headers` rule
  for the JSON type of Apple's file), else in `build/spring/well-known/`.
- Profiles as for `web_dev_config.yaml` (`application-staging.yml` with
  other domains); flavors with their own bundle IDs later.
- A native file changed by hand between the markers fails the build (the
  owner, November 2026).
- In this release: iOS, Android, macOS (the scheme in `Info.plist`, the
  URL event to the plugin when Flutter does not pass it to the router
  itself), each checked by opening a link from the OS.
- Windows and Linux later (the owner, November 2026): a scheme only
  (verified web links need MSIX on Windows and do not exist on Linux).
  Windows: the scheme under `HKCU\Software\Classes`, a second start with
  a link hands it to the running instance and exits before its engine
  starts (a generated block in `windows/runner/main.cpp`). Linux:
  `MimeType=x-scheme-handler/<scheme>` in the `.desktop` file and the
  runner's `GtkApplication` handling `open` (a generated block in
  `linux/runner/my_application.cc`). Checked locally on Windows 11 ARM in
  UTM over SSH and on Linux in Docker.

## Tests

```dart
springBootTest('the profile asks to log in', (tester, context) async {
  await tester.pumpSpringApp();
  context.bean<RouteTemplate>().go(ProfilePageRoute.to());
  await tester.pumpAndSettle();
  expect(find.byType(LoginPage), findsOneWidget);
});
```

## Open

- A shell next to master-detail on a wide window.
- Translated route titles (messages) for the web tab title and semantics.
- The exact shape of `spring_gen/routes.spring.dart` and of `ShellState`.
- The documentation site as the first real app on it: what it needs that
  this design misses.
