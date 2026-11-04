# spring_boot_starter_flutter_navigation

**The next release after 0.6.3** (the owner, November 2026). Declarative
navigation for Flutter apps as a starter of its own, like
`spring_boot_starter_flutter_security`: routes on the SDK's `Router`
(deep links, the web URL bar, Android's back button), no `go_router`.
The documentation site is built on it (see the site in
[README.md](README.md)): a site about Spring, made with Spring.

## Who does what

| Where | What |
|---|---|
| `spring_boot_starter_flutter` | only the hook: `SpringApp` uses a `RouterConfig` bean when there is one, else works as today |
| `spring_boot_starter_flutter_navigation` | `@Route`, `@RouteShell`, `ScreenRoutes` (routes in Dart configuration), `RouteTemplate`, the `route` and `branch` scopes, route filters, `spring.flutter.navigation.*`, the restored stack, test helpers |
| the generator | `lib/spring_gen/routes.spring.dart`, a part of `spring_gen/main.spring.dart` (like `spring_gen/theme.spring.dart`): the route table and a `<Page>Route` extension per page; written only when the starter is a dependency |
| `spring_boot_starter_flutter_security` | ready filters by user and role (`@PreAuthorize` on a route), the redirect to the login and back |

```yaml
dependencies:
  spring_boot_starter_flutter: ^0.x
  spring_boot_starter_flutter_navigation: ^0.x
```

## Routes on pages

Paths stay flat; a shell says where a route opens. Without `shell` a
route opens over everything (checkout, a full-screen picture).

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

@Route('/catalog/books/{isbn}', shell: MainTabs,
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
