import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart'
    show PageTransition;

/// Makes a widget class a screen of the app, opened at [path].
///
/// The path uses Spring's path patterns, the syntax of the web starter's
/// `@GetMapping`: `{isbn}` is one segment captured as `isbn`,
/// `{isbn:\d+}` one that matches the regex, `{*path}` the rest of the
/// address with its leading `/` (at the end only). Paths are written in
/// full; a screen whose path starts with a branch of a [RouteShell] opens
/// inside that shell (`/catalog/books/{isbn}` in the shell with the branch
/// `/catalog`).
///
/// The generator reads the annotation and registers the screen; the widget
/// gets what it needs from `context.route`.
///
/// ```dart
/// @ScreenRoute('/catalog/books/{isbn}', title: 'Book',
///     params: {'page': int}, extra: BookSummary)
/// class BookPage extends StatelessWidget {
///   const BookPage({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final isbn = context.route.pathVariable('isbn');
///     final page = context.route.param<int>('page') ?? 1;
///     ...
///   }
/// }
/// ```
///
/// Not called `Route`: Flutter's `Route` class would clash with it in every
/// file that imports Flutter.
///
/// Spring (Java) has no screens; the closest is a controller method with
/// `@GetMapping("/books/{isbn}")`.
class ScreenRoute {
  /// A screen opened at [path].
  const ScreenRoute(
    this.path, {
    this.title,
    this.name,
    this.params = const {},
    this.extra,
    this.shell,
    this.branch,
    this.transition = PageTransition.theme,
    this.content,
  }) : notFound = false;

  /// The screen shown for an address no route matches.
  const ScreenRoute.notFound()
    : path = '',
      title = null,
      name = null,
      params = const {},
      extra = null,
      shell = null,
      branch = null,
      transition = PageTransition.theme,
      content = null,
      notFound = true;

  /// The path pattern, Spring's syntax (`/catalog/books/{isbn}`).
  final String path;

  /// The screen's title: the browser tab, the screen reader, the search
  /// result. `#{key}` is a message key, translated (`#{book.title}`).
  final String? title;

  /// The route's name; the class name in kebab case by default
  /// (`BookPage` is `book-page`).
  final String? name;

  /// The query parameters the screen reads, with their types
  /// (`{'page': int}`): converted when the screen opens, so a wrong value
  /// shows the error screen instead of failing in `build`.
  final Map<String, Type> params;

  /// The type of the object passed along with the navigation, not in the
  /// address (lost on a reload or a deep link, so always optional).
  final Type? extra;

  /// The shell the screen opens in when its path is under none of the
  /// shell's branches; usually left out.
  final Type? shell;

  /// The branch the screen opens in, by its path, when the screen's own
  /// path is not under it: `@ScreenRoute('/motion', branch: '/more')`
  /// opens in the `/more` tab, over its first screen. Usually left out:
  /// a screen opens in the branch whose path covers its own.
  final String? branch;

  /// How the screen comes in and goes out: the theme's
  /// `motion.page-transition` by default, or [PageTransition.none] for
  /// none.
  final PageTransition transition;

  /// Resources the screen shows: a folder for a path ending in `{*name}`
  /// (`resources:content/docs/`: the rest of the path plus `.md` is the
  /// file), or one `.md` file.
  final String? content;

  /// Whether this is the screen for unknown addresses.
  final bool notFound;
}

/// Makes a widget class a shell: the part of the app that stays while the
/// screens of its branches change (tabs, a side menu), with a stack of
/// screens per branch.
///
/// The widget gets a `ShellState`: its `child` is the current branch's
/// screens, `select` switches to another branch as it was left.
///
/// ```dart
/// @RouteShell(branches: ['/catalog', '/basket', '/profile'])
/// class MainTabs extends StatelessWidget {
///   const MainTabs(this.shell, {super.key});
///   final ShellState shell;
///
///   @override
///   Widget build(BuildContext context) => Scaffold(
///     body: shell.child,
///     bottomNavigationBar: NavigationBar(
///       selectedIndex: shell.index,
///       onDestinationSelected: shell.select,
///       destinations: const [...],
///     ),
///   );
/// }
/// ```
class RouteShell {
  /// A shell with [branches], the paths that start each branch.
  const RouteShell({required this.branches});

  /// The paths that start the branches; a screen whose path starts with
  /// one of them opens in that branch.
  final List<String> branches;
}

/// What describes a screen beyond navigation: the search result and link
/// preview of its web page, whether a link from outside opens it.
///
/// ```dart
/// @ScreenRoute('/', title: 'Spring Dart')
/// @RouteInfo(description: 'Spring Boot for Dart servers and Flutter apps.')
/// class HomePage extends StatelessWidget { ... }
///
/// @ScreenRoute('/checkout')
/// @RouteInfo(index: false, link: false)
/// class CheckoutPage extends StatelessWidget { ... }
/// ```
///
/// Like springdoc's `@Operation` next to Spring's `@GetMapping`.
class RouteInfo {
  /// The screen's description, preview image and flags.
  const RouteInfo({
    this.description,
    this.image,
    this.index = true,
    this.paths = const [],
    this.link = true,
  });

  /// The text under the title in a search result and a link preview.
  /// `#{key}` is a message key.
  final String? description;

  /// The preview picture (`resources:images/book.png`).
  final String? image;

  /// Whether search engines may list the page (`false`: `noindex`, not in
  /// the sitemap).
  final bool index;

  /// Addresses of a screen with path variables, which the build cannot
  /// know (`['/catalog/books/978-0']`).
  final List<String> paths;

  /// Whether a link from outside the app (a deep link) opens the screen.
  final bool link;
}

/// Marks a class whose static constants name routes declared only in Dart
/// configuration (`ScreenRoutes`), so they get generated constants too;
/// the start checks that each one is registered.
class RouteDeclarations {
  /// Marks the class.
  const RouteDeclarations();
}
