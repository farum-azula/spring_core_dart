# spring_boot_starter_flutter_navigation

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-flutter-navigation](https://farum-azula.org/components/spring-boot-starter-flutter-navigation)

Navigation for Flutter apps built on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter):
screens on routes, on the SDK's `Router` (the web's address bar, deep
links, Android's back button), without `go_router`.

- **Screens on routes**: `@ScreenRoute('/catalog/books/{isbn}')` on a
  widget, or `ScreenRoutes` beans in Dart configuration (like Spring
  WebFlux's `RouterFunctions`), merged and checked at the start: a path
  declared twice names both places.
- **Spring's path patterns**: `{isbn}`, `{isbn:\d+}`, `{*path}`, the
  syntax of the web starter's `@GetMapping`.
- **Shells**: `@RouteShell(branches: [...])` keeps the tabs while the
  screens of a branch change; each branch keeps its own stack.
- **`context.route`**: the screen's values (path variables, query
  parameters converted by the `ConversionService`, the extra object) and
  the navigation (`go`, `push` with a result, `pop`, `replaceParams`).
- **Generated constants**: `BookPageRoute.to(isbn: ..., page: 2)` and
  typed keys per screen, so a renamed path or parameter breaks the build,
  not the app.
- **Filters and guards**: `RouteFilter` beans send a navigation
  elsewhere; with `spring_boot_starter_flutter_security`,
  `@PreAuthorize` on a screen sends nobody logged in to the login and
  back.
- **Scopes**: beans that live as long as a screen or a branch.
- **Markdown screens**: `content:` and `RouteContentView` show a folder of
  Markdown files, one address per file.
- **The web and deep links**: addresses without `#`, a page per route for
  search engines, the deep link files of iOS, macOS and Android, all from
  properties.

## Contents

- [Setup](#setup)
- [Screens](#screens)
- [Opening a screen](#opening-a-screen)
- [Transitions](#transitions)
- [Shells and tabs](#shells-and-tabs)
- [Unknown addresses and errors](#unknown-addresses-and-errors)
- [Routes in Dart configuration](#routes-in-dart-configuration)
- [Filters](#filters)
- [Guarded screens](#guarded-screens)
- [Beans per screen or branch](#beans-per-screen-or-branch)
- [Markdown screens](#markdown-screens)
- [Languages](#languages)
- [The web, search engines and deep links](#the-web-search-engines-and-deep-links)
- [Properties](#properties)
- [Tests](#tests)

## Setup

```yaml
dependencies:
  spring_boot_starter_flutter_navigation: ^0.7.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.7.1
```

The starter brings and re-exports `spring_boot_starter_flutter`; an app
lists only this package (`spring_boot_starter_flutter_security` brings it
too). One import is enough:

```dart
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
```

`SpringApplicationWidget` without a `home` builds the app widget on the
router (`MaterialApp.router`, `CupertinoApp.router` or `WidgetsApp.router`,
from `spring.flutter.app.type`):

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(application: () => springApplication),
);
```

Then `dart run build_runner build`: the generator registers the screens
and writes their constants into `lib/spring_gen/main.spring.dart`.

## Screens

`@ScreenRoute` makes a widget class a screen, opened at its path:

```dart
@ScreenRoute(
  '/catalog/books/{isbn}',
  title: 'Book',
  params: {'page': int},
  extra: BookSummary,
)
class BookPage extends StatelessWidget {
  const BookPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = context.route;
    final isbn = route.get(BookPageRoute.isbn);          // String
    final page = route.get(BookPageRoute.page) ?? 1;     // int?
    final summary = route.get(BookPageRoute.extra);      // BookSummary?
    return Text('${summary?.title ?? isbn}, page $page');
  }
}
```

| Argument | Meaning |
|---|---|
| `path` | Spring's path pattern, written in full |
| `title` | The browser tab, the screen reader, the search result. `#{key}` is a message key (`#{book.title}`) |
| `name` | The route's name; the class name in kebab case by default (`BookPage` is `book-page`) |
| `params` | The query parameters the screen reads, with their types: converted when the screen opens, so `?page=abc` shows the error screen instead of failing in `build` |
| `extra` | The type of an object passed along, not in the address: lost on a reload or a deep link, so always optional |
| `shell` | The shell the screen opens in when its path is under none of its branches; usually left out |
| `branch` | The branch the screen opens in, by its path, when its own path is not under it: `branch: '/more'` puts `/motion` in the More tab, over its first screen |
| `transition` | How the screen comes in and goes out: the theme's by default, `PageTransition.none` for none ([Transitions](#transitions)) |
| `content` | A Markdown resource, or a folder of them for a path ending in `{*name}` ([Markdown screens](#markdown-screens)) |

The patterns are the web starter's:

| Pattern | Matches | Value |
|---|---|---|
| `/catalog/books/{isbn}` | one segment | `isbn` |
| `/orders/{id:\d+}` | one segment that matches the regex | `id` |
| `/docs/{*path}` | the rest of the address, at the end only | `path`, with its leading `/` (`/core/beans`) |

The widget reads its route from `context.route`, the `RouteTemplate`
bound to its own screen (a screen under another one still sees its own
values), and rebuilds when its parameters change. In `State.initState`,
use `RouteTemplate.read(context)`, which does not rebuild.

| `context.route` | |
|---|---|
| `get(BookPageRoute.isbn)` | A typed value: a path variable, a parameter, the extra object |
| `pathVariable('isbn')`, `param<int>('page')`, `params<String>('tag')`, `extra<T>()` | The same by name |
| `uri`, `pattern`, `name`, `matches('/catalog/**')` | The address and the route |
| `stack`, `branch`, `canPop`, `changes` | The screens under each other, the shell's branch, whether `pop` closes one, a stream of navigations |

## Opening a screen

For each screen the generator writes an extension with its constants:
`BookPageRoute.pattern`, `BookPageRoute.routeName`, a key per value
(`isbn`, `page`, `extra`), and `to(...)` with the values as parameters
(path variables required, the rest optional).

```dart
// The app's state becomes this screen, with the screens of its path below.
context.route.go(BookPageRoute.to(isbn: '978-0441013593', page: 2));

// On top, waiting for a result.
final paid = await context.route.push<bool>(CheckoutPageRoute.to());

// Back with a result.
context.route.pop(true);

// The same screen with other parameters (?page=3), without a new screen.
context.route.replaceParams({'page': 3});
```

`go` and `push` also take a string: an address (`'/catalog?page=2'`), or
a pattern with `pathVariables:`; `params:` and `extra:` add values, and
`transition:` replaces the screen's transition for this navigation.

A `go` to another address of the route on screen (`/books/1` to
`/books/2`) keeps the screen: its `State`, its scroll and the shell stay,
and it rebuilds with the new values.

## Transitions

Screens show at once by default, in every app type. The theme turns a
transition on for every screen:
`spring.flutter.theme.motion.page-transition`
([page transitions](../docs/flutter/theme/motion-and-animations.md#page-transitions)).
`platform` is the app type's own: Material's, the iOS slide in a
`CupertinoApp`, none in an app of type `widgets`.

```yaml
# The platform's transition for every screen.
spring:
  flutter:
    theme:
      motion:
        page-transition: platform
---
# A fade of the theme's own duration and curve.
spring:
  flutter:
    theme:
      motion:
        page-transition: { type: fade, duration: 200ms, curve: ease-out }
```

One screen chooses its own; one navigation too, for example a menu that
switches pages at once:

```dart
@ScreenRoute('/settings', transition: PageTransition.none)
class SettingsPage extends StatelessWidget { ... }

context.route.go('/motion', transition: PageTransition.none);
```

| `PageTransition` | |
|---|---|
| `theme` | The theme's `motion.page-transition`, none when it sets nothing (the default) |
| `platform` | The app type's own |
| `fadeUpwards`, `zoom`, `cupertino`, `fade` | That kind, in any app type |
| `none` | At once |

The kinds take the theme's duration and curve when it sets them. With
reduced motion on the device every transition is instant. Switching the
branches of a shell never animates.

Outside widgets, inject the `RouteTemplate` bean: it reads the screen on
top.

## Shells and tabs

A shell is the part of the app that stays while the screens of its
branches change: tabs, a side menu. Each branch keeps its own stack, and
a screen whose path starts with a branch opens in it (with the screens of
its path below):

```dart
@RouteShell(branches: ['/catalog', '/profile'])
class MainTabs extends StatelessWidget {
  const MainTabs(this.shell, {super.key});
  final ShellState shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell.child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.index,
      onDestinationSelected: shell.select,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.book), label: 'Catalog'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    ),
  );
}
```

`shell.select(1)` switches to a branch as it was left. A screen outside
every branch (`/checkout`) opens over the shell.

A screen can live in a branch its path is not under, so addresses stay
flat: `@ScreenRoute('/motion', branch: '/more')` opens in the `/more` tab,
over the tab's first screen (`/more`), and back returns to it. In Dart
configuration, a screen declared in a branch but outside its path does the
same (`.branch('/more', (b) => b.screen('/more', ...).screen('/motion', ...))`),
or pass `branch: '/more'` to `screen(...)`. A branch no shell has stops
the start.

## Unknown addresses and errors

```dart
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Nothing at ${context.route.uri}'));
}
```

A navigation that fails (a value that does not convert, a filter that
throws) shows the error screen: `.error(...)` in Dart configuration, else
a plain one. Its `RouteState.error` says why.

**Refused addresses.** An address with an encoded slash or backslash, a
backslash, an encoded NUL, or a `.` / `..` segment (once decoded) opens
nothing: the app stays on its screen, or opens its first screen when it
was opened by such a link. Such an address could otherwise stay on one
route while its `{*rest}` value named a file of another route's folder,
past that route's guard. Plain dot segments in a typed address are
resolved first, so they reach the screen they name, guard included.

## Routes in Dart configuration

The same in code, for routes built from data or kept in one place;
`ScreenRoutes` beans and annotated screens are merged:

```dart
@Configuration()
class AppRoutes {
  @Bean()
  ScreenRoutes routes() => ScreenRoutes.route()
      .shell((shell) => MainTabs(shell), (tabs) => tabs
          .branch('/catalog', (b) => b
              .screen('/catalog', (r) => const CatalogPage())
              .screen('/catalog/books/{isbn}', (r) => const BookPage()))
          .branch('/profile', (b) => b
              .screen('/profile', (r) => const ProfilePage())))
      .screen('/checkout', (r) => const CheckoutPage(),
          transition: PageTransition.fade)
      .redirect('/', '/catalog')
      .notFound((r) => const NotFoundPage())
      .build();
}
```

`transition` is one of [the `PageTransition` values](#transitions); the theme's (`PageTransition.theme`) by default.
A class marked `@RouteDeclarations()` gets generated constants for routes
declared only in code.

## Filters

A `RouteFilter` decides whether a navigation opens its screen: it returns
`null` to go on, or a location to go to instead. `RouteFilter` beans run
for every route, in `@Order`; `.filter(...)` in Dart configuration for the
routes of a `nest`:

```dart
@Component()
final class AdminOnly implements RouteFilter {
  AdminOnly(this.session);
  final Session session;

  @override
  RouteLocation? filter(RouteRequest request) =>
      request.state.matches('/admin/**') && !session.isAdmin
          ? RouteLocation('/catalog')
          : null;
}
```

## Guarded screens

With `spring_boot_starter_flutter_security`, `@PreAuthorize` on a screen
takes the expressions of method security:

```dart
@ScreenRoute('/admin', title: 'Admin')
@PreAuthorize("hasRole('ADMIN')")
class AdminPage extends StatelessWidget { ... }
```

```properties
spring.flutter.navigation.login=/login
```

Nobody logged in goes to `spring.flutter.navigation.login`, and back to
the screen after the login; a logged-in user without the role gets the
error screen. After a logout, the screen on top is opened again through
the guards. In Dart configuration, `.filter(RouteSecurity.preAuthorize(
"hasRole('ADMIN')"))`. A guard hides screens on the device; the server
still checks every request.

## Beans per screen or branch

```dart
@Component()
@Scope(NavigationScopes.route)   // or NavigationScopes.branch
class BookForm extends ChangeNotifier { ... }
```

A `route` bean is created when its screen opens and destroyed when it
closes; a `branch` bean lives while the branch of a shell lives (until
the shell closes).

## Markdown screens

`content:` names Markdown resources of `lib/resources/`: one file, or a
folder for a path ending in `{*name}`, where the rest of the address plus
`.md` is the file. `RouteContentView` shows it with the theme
(`MarkdownView`); a link to another Markdown file of the site opens its
screen:

```dart
@ScreenRoute('/docs/{*path}', title: 'Docs', content: 'resources:content/docs/')
class DocPage extends StatelessWidget {
  const DocPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SingleChildScrollView(child: RouteContentView());
}
```

`/docs/core/beans` shows `lib/resources/content/docs/core/beans.md`;
`index.md` is the folder's own address (`content/docs/guides/index.md` at
`/docs/guides`), and an address with a `/` at its end (`/docs/beans/`, as
static hosts send it) is the page without it. `RouteContentView.fileOf`
says which file an address shows.

Another address of the same route keeps the screen: its state, its
scroll and the shell around it stay, and `RouteContentView` changes the
page the theme's way (`motion.content-change`), opening it at the top
(`scrollToTop: true`, the default, the theme's `motion.scroll-to-top`).
`RouteContentView(outline: MarkdownOutline())` hands the page's headings
to an "On this page" list, and an address's `#anchor`
(`/docs/core/beans#scopes`) scrolls to its heading.

## Languages

`spring.flutter.navigation.languages` gives each language its addresses:
the first is the default, without a prefix; the others put theirs under
`/<language>`.

```yaml
spring:
  flutter:
    navigation:
      languages: [en, ja]
```

- `/ja/catalog` opens the `/catalog` screen with the app's locale set to
  Japanese: `context.message`, `@ScreenRoute(title: '#{key}')` and
  Flutter's own widgets follow.
- The app's code writes its paths without a prefix (`go('/catalog')`); the
  current language stays and the browser's bar shows `/ja/catalog`. A path
  with a prefix (`go('/ja/catalog')`) changes the language.
- An address from the platform without a prefix (the browser's bar, a link)
  is the default language's.
- `context.route.language` is the current language;
  `context.route.switchLanguage('en')` shows the same screen in another
  language. Each switch publishes a `LanguageChangedEvent` (`from`, `to`)
  for `@EventListener` methods.
- A Markdown screen (`content:`) shows `<file>.ja.md` next to the file under
  `/ja`, the default file when there is no translation.

The build writes the pages for search engines in every language, with
`hreflang` alternates
([Configuration, languages of the site's pages](../docs/configuration.md#languages)).

## The web, search engines and deep links

- **Addresses**: `/catalog/books/1` in the browser's address bar
  (`spring.flutter.navigation.web.url-strategy: path`, the default), or
  `/#/catalog/books/1` (`hash`). A host must answer every address of the
  app with `index.html`.
- **Search engines**: with `spring.flutter.web.seo.from-routes`, the build
  writes a page per route, with its title, description (`@RouteInfo`) and
  Markdown text. See
  [the site's pages](../docs/configuration.md#the-sites-pages-springflutterwebseo).
- **Deep links**: `spring.flutter.navigation.deep-links.*` writes the
  scheme and the domains into iOS, macOS and Android, and the files each
  domain serves. Every link goes through the routes, the guards included;
  `@RouteInfo(link: false)` keeps a screen from opening by a link. See
  [Navigation](../docs/configuration.md#navigation).

## Properties

| Key | Default | Meaning |
|---|---|---|
| `spring.flutter.navigation.initial` | none | Where the app starts when the platform gives `/` |
| `spring.flutter.navigation.login` | none | Where a guarded screen sends nobody logged in |
| `spring.flutter.navigation.redirects[<from>]` | none | An address that leads to another |
| `spring.flutter.navigation.languages` | none | The languages with their own addresses, the default first (`en, ja`) |
| `spring.flutter.navigation.web.url-strategy` | `path` | `path` or `hash` |
| `spring.flutter.navigation.deep-links.*` | | The deep links |

Every key, with the deep links, is in
[Configuration, Navigation](../docs/configuration.md#navigation).

## Tests

A widget test starts the app as `flutter run` does, and navigates
through the `RouteTemplate` bean:

```dart
testWidgets('an unknown address shows the not-found screen', (tester) async {
  await tester.pumpWidget(
    SpringApplicationWidget(application: () => springApplication),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(CatalogPage)));
  await context.getBean<RouteTemplate>().go('/nope');
  await tester.pumpAndSettle();
  expect(find.byType(NotFoundPage), findsOneWidget);
});
```

The [example](example/example.dart) is a whole app: tabs, a book screen
with a path variable, a parameter and an extra object, a payment over the
tabs that returns a result, and a not-found screen.

Spring (Java) has no navigation for apps; the names follow Spring where
there is something to follow: path patterns, `RouterFunctions`,
`*Template`, scopes.
