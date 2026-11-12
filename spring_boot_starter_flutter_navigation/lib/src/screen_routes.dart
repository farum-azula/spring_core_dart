import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_state.dart';
import 'package:spring_boot_starter_flutter_navigation/src/shell_state.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show PathPattern;

/// Builds a screen from its route.
typedef ScreenBuilder = Widget Function(RouteState route);

/// Builds a shell from its state (the current branch's screens in
/// `shell.child`).
typedef ShellBuilder = Widget Function(ShellState shell);

/// Whether the path (or pattern) [path] is [prefix] or below it:
/// `/catalog` covers `/catalog` and `/catalog/books/{isbn}`, not
/// `/catalogs`; `/` covers everything.
bool isPathUnder(String path, String prefix) {
  final base = prefix.length > 1 && prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return base == '/' || path == base || path.startsWith('$base/');
}

/// How a screen comes in and goes out.
///
/// [theme], the default, follows the theme's `motion.page-transition`
/// (kind, duration and curve); the other values choose the kind for one
/// screen (`@ScreenRoute(transition: PageTransition.none)`) or one
/// navigation (`context.route.go(path, transition: ...)`), with the
/// theme's duration and curve.
enum PageTransition {
  /// The theme's `motion.page-transition` (the platform's when it sets
  /// nothing, as in Flutter).
  /// The default.
  theme,

  /// The app type's own: Material's per platform, the iOS slide in a
  /// `CupertinoApp`, none in a `WidgetsApp`.
  platform,

  /// Material's fade with an upward slide.
  fadeUpwards,

  /// As the theme's `motion.content-change`: the screen comes in the way a
  /// part of a screen shows other content (`fade-up`).
  content,

  /// Material's zoom.
  zoom,

  /// The iOS slide, in any app type.
  cupertino,

  /// A fade.
  fade,

  /// None: the screen shows at once.
  none,
}

/// A navigation about to open a screen, for a [RouteFilter]: where to, on
/// which route, with which values.
final class RouteRequest {
  /// The request to open [state].
  const RouteRequest(this.state);

  /// The route the navigation opens, with the location and its values.
  final RouteState state;

  /// Where the navigation goes.
  RouteLocation get location => state.location;

  /// The route that matched, or `null` for an unknown address.
  ScreenRouteDefinition? get route => state.route;
}

/// Decides whether a navigation may open its screen: returns `null` to go
/// on, or a location to go to instead (the login, say).
///
/// Filters of a route run in the order they were declared, after the
/// `RouteFilter` beans (all routes), in `@Order`. A filter may be async.
///
/// ```dart
/// // Only for administrators; everyone else goes to the catalog.
/// final class AdminOnly implements RouteFilter {
///   AdminOnly(this.session);
///   final Session session;
///
///   @override
///   RouteLocation? filter(RouteRequest request) =>
///       session.isAdmin ? null : RouteLocation('/catalog');
/// }
/// ```
///
/// Spring (Java): `HandlerFilterFunction` of `RouterFunctions`.
abstract interface class RouteFilter {
  /// `null` to open the screen, or where to go instead.
  FutureOr<RouteLocation?> filter(RouteRequest request);
}

/// The attributes of a route the navigation and the starters know.
abstract final class RouteAttributes {
  /// A security expression the user must satisfy to open the route, in the
  /// language of `@PreAuthorize` (`hasRole('ADMIN')`). The generator sets
  /// it from `@PreAuthorize` on a screen; a [RouteAuthorizationFilter]
  /// (`spring_boot_starter_flutter_security`) enforces it, and without one
  /// the start fails rather than open the route to everyone.
  static const preAuthorize = 'preAuthorize';
}

/// A [RouteFilter] that enforces [RouteAttributes.preAuthorize] and the
/// [RouteAuthorizationRequirement]s of a route. The navigation refuses to
/// start when a route has either and no such filter is a bean.
abstract interface class RouteAuthorizationFilter implements RouteFilter {}

/// A filter of a route that only declares a security expression the user
/// must satisfy; the [RouteAuthorizationFilter] bean enforces it (it does
/// nothing by itself, and without that bean the start fails).
abstract interface class RouteAuthorizationRequirement implements RouteFilter {
  /// The expression, in the language of `@PreAuthorize`.
  String get expression;
}

/// A [RouteFilter] from a function: `RouteFilterFunction((request) => ...)`.
final class RouteFilterFunction implements RouteFilter {
  /// The filter [function].
  const RouteFilterFunction(this.function);

  /// What [filter] calls.
  final FutureOr<RouteLocation?> Function(RouteRequest request) function;

  @override
  FutureOr<RouteLocation?> filter(RouteRequest request) => function(request);
}

/// One screen: its path pattern and builder, and what the navigation needs
/// to know about it.
final class ScreenRouteDefinition {
  /// A screen at [pattern] built by [builder].
  ScreenRouteDefinition({
    required this.pattern,
    required this.builder,
    this.name,
    this.title,
    this.params = const {},
    this.extra,
    this.shell,
    this.branch,
    this.filters = const [],
    this.transition = PageTransition.theme,
    this.attributes = const {},
    this.content,
    this.source,
    this.notFound = false,
    this.link = true,
  });

  /// The path pattern (Spring's syntax).
  final PathPattern pattern;

  /// Builds the screen.
  final ScreenBuilder builder;

  /// The route's name, or `null`.
  final String? name;

  /// The title; `#{key}` is a message key.
  final String? title;

  /// The query parameters with their types, converted when it opens.
  final Map<String, Type> params;

  /// The type of the extra object, or `null`.
  final Type? extra;

  /// The shell the screen opens in when no branch's path covers it, or
  /// `null`.
  final Object? shell;

  /// The branch the screen opens in, named by its path (`/more`), when its
  /// own path is not under it: `/motion` in the branch `/more`. The
  /// branch's first screen is below it. `null`: the branch whose path
  /// covers the screen's.
  final String? branch;

  /// The filters of this route, in order.
  final List<RouteFilter> filters;

  /// How the screen comes in and goes out.
  final PageTransition transition;

  /// Values declared with the route, for filters and the screen.
  final Map<String, Object?> attributes;

  /// The resources the screen shows (`resources:content/docs/` or one
  /// file), or `null`.
  final String? content;

  /// Where the route was declared, for error messages.
  final String? source;

  /// Whether this is the screen for unknown addresses.
  final bool notFound;

  /// Whether a link from outside the app (a deep link) opens the screen;
  /// `false` opens the app's first screen instead.
  final bool link;

  /// The name of the pattern's `{*name}` variable, or `null`.
  String? get restVariable =>
      RegExp(r'\{\*([A-Za-z_][A-Za-z0-9_]*)\}\s*$')
          .firstMatch(pattern.pattern)
          ?.group(1);

  /// This definition with [filters] after its own.
  ScreenRouteDefinition withFilters(List<RouteFilter> filters) =>
      filters.isEmpty
      ? this
      : ScreenRouteDefinition(
          pattern: pattern,
          builder: builder,
          name: name,
          title: title,
          params: params,
          extra: extra,
          shell: shell,
          branch: branch,
          filters: [...this.filters, ...filters],
          transition: transition,
          attributes: attributes,
          content: content,
          source: source,
          notFound: notFound,
          link: link,
        );

  /// This definition in [shell].
  ScreenRouteDefinition inShell(Object shell) => ScreenRouteDefinition(
    pattern: pattern,
    builder: builder,
    name: name,
    title: title,
    params: params,
    extra: extra,
    shell: shell,
    branch: branch,
    filters: filters,
    transition: transition,
    attributes: attributes,
    content: content,
    source: source,
    notFound: notFound,
    link: link,
  );

  @override
  String toString() => 'screen ${pattern.pattern}';
}

/// A shell: the widget around the screens of its branches, with a stack of
/// screens per branch.
final class ShellRouteDefinition {
  /// The shell [key] with [branches], built by [builder].
  ShellRouteDefinition({
    required this.key,
    required this.branches,
    required this.builder,
    this.source,
  }) : assert(branches.isNotEmpty, 'A shell needs at least one branch');

  /// What names the shell: its widget type for `@RouteShell`, else any
  /// value unique among the shells.
  final Object key;

  /// The paths that start the branches.
  final List<String> branches;

  /// Builds the shell.
  final ShellBuilder builder;

  /// Where the shell was declared, for error messages.
  final String? source;

  /// The branch whose path covers [path] (`/catalog` covers `/catalog` and
  /// `/catalog/books/1`), or -1.
  int branchOf(String path) {
    for (var i = 0; i < branches.length; i++) {
      if (isPathUnder(path, branches[i])) {
        return i;
      }
    }
    return -1;
  }

  @override
  String toString() => 'shell $key ${branches.join(', ')}';
}

/// Routes of the app declared in Dart configuration, like Spring WebFlux's
/// `RouterFunctions`: a bean (any number of them, merged with the
/// annotated screens) built with [ScreenRoutes.route].
///
/// Paths are written in full; a shell's branches say which screens open in
/// it. A path declared twice stops the start and names both places.
///
/// ```dart
/// @Configuration()
/// class AppRoutes {
///   @Bean()
///   ScreenRoutes routes() => ScreenRoutes.route()
///       .shell((shell) => MainTabs(shell), (tabs) => tabs
///           .branch('/catalog', (b) => b
///               .screen('/catalog', (r) => const CatalogPage())
///               .screen('/catalog/books/{isbn}', (r) => const BookPage()))
///           .branch('/profile', (b) => b
///               .screen('/profile', (r) => const ProfilePage())))
///       .screen('/checkout', (r) => const CheckoutPage(),
///           transition: PageTransition.fade)
///       .nest((admin) => admin
///           .screen('/admin', (r) => const AdminPage())
///           .filter(AdminOnly()))
///       .redirect('/', '/catalog')
///       .notFound((r) => const NotFoundPage())
///       .build();
/// }
/// ```
///
/// Spring (Java): `RouterFunctions.route().GET("/books/{isbn}", handler)
/// .filter(filter).build()`.
final class ScreenRoutes {
  /// Routes made of [screens], [shells], [redirects] (from path to path),
  /// a [notFound] screen and an [error] screen; [source] names where they
  /// were declared.
  ScreenRoutes({
    this.screens = const [],
    this.shells = const [],
    this.redirects = const {},
    this.notFound,
    this.error,
    this.source,
  });

  /// A builder of routes.
  static ScreenRoutesBuilder route({String? source}) =>
      ScreenRoutesBuilder._(source);

  /// The screens.
  final List<ScreenRouteDefinition> screens;

  /// The shells.
  final List<ShellRouteDefinition> shells;

  /// Addresses that lead elsewhere (`/` to `/catalog`).
  final Map<String, String> redirects;

  /// The screen for unknown addresses, or `null`.
  final ScreenBuilder? notFound;

  /// The screen for a navigation that failed (a value that did not
  /// convert, a filter that threw), or `null`; the state's `error` says
  /// why.
  final ScreenBuilder? error;

  /// Where the routes were declared, for error messages.
  final String? source;
}

/// Builds [ScreenRoutes]; see there.
final class ScreenRoutesBuilder {
  ScreenRoutesBuilder._(this._source, [this._shell, this._branch]);

  final String? _source;
  final Object? _shell;
  final String? _branch;
  final _screens = <ScreenRouteDefinition>[];
  final _shells = <ShellRouteDefinition>[];
  final _redirects = <String, String>{};
  final _filters = <RouteFilter>[];
  ScreenBuilder? _notFound;
  ScreenBuilder? _error;

  /// Adds the screen at [path] built by [builder]; [source] names where
  /// it is declared, for errors (the builder's source by default).
  ScreenRoutesBuilder screen(
    String path,
    ScreenBuilder builder, {
    String? name,
    String? title,
    Map<String, Type> params = const {},
    Type? extra,
    Object? shell,
    String? branch,
    PageTransition transition = PageTransition.theme,
    Map<String, Object?> attributes = const {},
    String? content,
    String? source,
    bool link = true,
  }) {
    // Declared in a branch but not under its path (`/motion` in `/more`):
    // in that branch all the same.
    final inBranch = _branch;
    final placed =
        branch ??
        (inBranch != null && !isPathUnder(path, inBranch) ? inBranch : null);
    _screens.add(
      ScreenRouteDefinition(
        pattern: PathPattern.parse(path),
        builder: builder,
        name: name,
        title: title,
        params: params,
        extra: extra,
        shell: shell ?? _shell,
        branch: placed,
        transition: transition,
        attributes: attributes,
        content: content,
        source: source ?? _source,
        link: link,
      ),
    );
    return this;
  }

  /// Adds a shell built by [builder] whose branches [branches] declares.
  /// [key] names it (a screen's `shell:` names a shell by it); a new key
  /// by default. [source] names where it is declared, for errors.
  ScreenRoutesBuilder shell(
    ShellBuilder builder,
    void Function(ShellBranchesBuilder tabs) branches, {
    Object? key,
    String? source,
  }) {
    final shellKey = key ?? Object();
    final tabs = ShellBranchesBuilder._(_source, shellKey);
    branches(tabs);
    _shells.add(
      ShellRouteDefinition(
        key: shellKey,
        branches: [for (final (path, _) in tabs._branches) path],
        builder: builder,
        source: source ?? _source,
      ),
    );
    for (final (_, routes) in tabs._branches) {
      _screens.addAll(routes._built());
    }
    return this;
  }

  /// Adds the routes [nested] declares; its filters apply to them only.
  ScreenRoutesBuilder nest(void Function(ScreenRoutesBuilder nested) nested) {
    final inner = ScreenRoutesBuilder._(_source, _shell, _branch);
    nested(inner);
    _screens.addAll(inner._built());
    _shells.addAll(inner._shells);
    _redirects.addAll(inner._redirects);
    return this;
  }

  /// Adds [filter] to every screen of this builder.
  ScreenRoutesBuilder filter(RouteFilter filter) {
    _filters.add(filter);
    return this;
  }

  /// Sends the address [from] to [to].
  ScreenRoutesBuilder redirect(String from, String to) {
    _redirects[from] = to;
    return this;
  }

  /// The screen for unknown addresses.
  ScreenRoutesBuilder notFound(ScreenBuilder builder) {
    _notFound = builder;
    return this;
  }

  /// The screen for a navigation that failed.
  ScreenRoutesBuilder error(ScreenBuilder builder) {
    _error = builder;
    return this;
  }

  /// The routes.
  ScreenRoutes build() => ScreenRoutes(
    screens: _built(),
    shells: List.unmodifiable(_shells),
    redirects: Map.unmodifiable(_redirects),
    notFound: _notFound,
    error: _error,
    source: _source,
  );

  List<ScreenRouteDefinition> _built() => [
    for (final screen in _screens) screen.withFilters(_filters),
  ];
}

/// Declares the branches of a shell; see [ScreenRoutesBuilder.shell].
final class ShellBranchesBuilder {
  ShellBranchesBuilder._(this._source, this._key);

  final String? _source;
  final Object _key;
  final _branches = <(String, ScreenRoutesBuilder)>[];

  /// Adds the branch starting at [path] with the screens [screens]
  /// declares (their paths under [path]).
  ShellBranchesBuilder branch(
    String path,
    void Function(ScreenRoutesBuilder branch) screens,
  ) {
    final routes = ScreenRoutesBuilder._(_source, _key, path);
    screens(routes);
    _branches.add((path, routes));
    return this;
  }
}
