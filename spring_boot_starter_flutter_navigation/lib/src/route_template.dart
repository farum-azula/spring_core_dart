import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_state.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart'
    show PageTransition;

/// Reads the current route and navigates: one bean, like `FileTemplate`
/// for files.
///
/// The bean (`context.bean<RouteTemplate>()`, or injected) reads the screen
/// on top; `context.route` is the same bound to the widget's own screen (a
/// book under another screen still sees its own `isbn`), and rebuilds the
/// widget when that screen's parameters change.
///
/// ```dart
/// route.pathVariable('isbn');            // 978-0
/// route.param<int>('page');              // through the ConversionService
/// route.go('/catalog/books/{isbn}', pathVariables: {'isbn': '978-0'});
/// route.go(BookPageRoute.to(isbn: '978-0', page: 2));
/// final paid = await route.push<bool>('/checkout');
/// route.pop(true);
/// route.replaceParams({'page': 3});
/// ```
///
/// Spring (Java) has no navigation; the name follows its templates
/// (`RestTemplate`, `JdbcTemplate`): one object for the common operations.
class RouteTemplate {
  /// The template of [navigation], reading the screen on top.
  RouteTemplate(this._navigation) : _screen = null;

  RouteTemplate._bound(this._navigation, ScreenEntry this._screen);

  final Navigation _navigation;
  final ScreenEntry? _screen;

  /// The template bound to the screen of [context]: its route, not the
  /// one on top. Throws a [FlutterError] when [context] is in no screen of
  /// the navigation.
  static RouteTemplate of(BuildContext context) => _of(context, listen: true);

  /// Like [of], without rebuilding the widget when the parameters change:
  /// usable in `State.initState` (the screen's values at its start).
  static RouteTemplate read(BuildContext context) =>
      _of(context, listen: false);

  static RouteTemplate _of(BuildContext context, {required bool listen}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<ScreenScope>()
        : context.getInheritedWidgetOfExactType<ScreenScope>();
    if (scope == null) {
      throw FlutterError.fromParts([
        ErrorSummary(
          'context.route needs a screen of spring_boot_starter_flutter_navigation '
          'above ${context.widget.runtimeType}.',
        ),
        ErrorHint(
          'Read it from a widget of a screen (a @ScreenRoute or a ScreenRoutes '
          'screen), or use the RouteTemplate bean for the screen on top.',
        ),
      ]);
    }
    return RouteTemplate._bound(scope.navigation, scope.notifier!);
  }

  /// The state this template reads: its screen's, or the top one's.
  /// Throws a [StateError] before the first navigation.
  RouteState get state {
    final screen = _screen ?? _navigation.top;
    if (screen == null) {
      throw StateError('No screen is open yet.');
    }
    return screen.state;
  }

  /// The address: path, query, fragment.
  Uri get uri => state.uri;

  /// The pattern that matched (`/catalog/books/{isbn}`), or `null`.
  String? get pattern => state.pattern;

  /// The route's name, or `null`.
  String? get name => state.name;

  /// The value [name] the pattern captured.
  String pathVariable(String name) => state.pathVariable(name);

  /// The query parameter [name] as a [T], or `null` when absent.
  T? param<T>(String name) => state.param<T>(name);

  /// Every value of the query parameter [name] as a [T].
  List<T> params<T>(String name) => state.params<T>(name);

  /// The extra object when it is a [T], else `null`.
  T? extra<T>() => state.extra<T>();

  /// The value of a typed key (`BookPageRoute.isbn`).
  T get<T>(RouteKey<T> key) => state.get(key);

  /// The attributes declared with the route.
  Map<String, Object?> get attributes => state.attributes;

  /// The resource the route's `content` names for this address, or `null`.
  String? get content => state.content;

  /// Whether the path matches [pattern] (`/catalog/**`).
  bool matches(String pattern) => state.matches(pattern);

  /// The screens the user sees under each other, bottom first.
  List<RouteState> get stack => [
    for (final screen in _navigation.visibleStack) screen.state,
  ];

  /// The path of the current shell branch (`/catalog`), or `null` when the
  /// screen on top is in no shell.
  String? get branch {
    final screen = _screen ?? _navigation.top;
    final shell = screen?.shell;
    return shell == null || screen!.branch < 0
        ? null
        : shell.definition.branches[screen.branch];
  }

  /// Every navigation's new state on top, as it happens.
  Stream<RouteState> get changes => _navigation.changes;

  /// The language of the addresses (`spring.flutter.navigation.languages`):
  /// the default one, or the one the address names (`/ja/...`); `null`
  /// without languages.
  String? get language => _navigation.language;

  /// Shows the app in [language] at the same screen: its address gets the
  /// language's prefix (`/ja/catalog`; none for the default language) and
  /// the app's locale follows.
  void switchLanguage(String language) => _navigation.switchLanguage(language);

  /// Whether [pop] would close a screen.
  bool get canPop => _navigation.canPop;

  /// Makes [location] the app's state: its screen with the screens of its
  /// path below it, in its shell's branch (the other branches kept).
  ///
  /// [location] is a [RouteLocation] (`BookPageRoute.to(...)`) or a
  /// string: an address (`/catalog?page=2`) or a pattern whose variables
  /// [pathVariables] fills; [params] and [extra] are added. [transition]
  /// replaces the screen's for this navigation: a menu that switches pages
  /// at once passes `PageTransition.none`.
  Future<void> go(
    Object location, {
    Map<String, Object?> pathVariables = const {},
    Map<String, Object?> params = const {},
    Object? extra,
    PageTransition? transition,
  }) => _navigation.go(
    _location(location, pathVariables, params, extra),
    transition: transition,
  );

  /// Opens [location] on top (see [go] for its forms) and completes with
  /// what that screen is popped with, `null` when it is closed otherwise.
  Future<T?> push<T extends Object?>(
    Object location, {
    Map<String, Object?> pathVariables = const {},
    Map<String, Object?> params = const {},
    Object? extra,
    PageTransition? transition,
  }) => _navigation.push<T>(
    _location(location, pathVariables, params, extra),
    transition: transition,
  );

  /// Closes the screen on top with [result]; `false` when there is nothing
  /// to close.
  bool pop([Object? result]) => _navigation.pop(result);

  /// Replaces the query parameters of this template's screen without
  /// opening a new one (`?page=3`); the screen rebuilds.
  void replaceParams(Map<String, Object?> params) {
    final screen = _screen ?? _navigation.top;
    if (screen != null) {
      _navigation.replaceParams(screen, params);
    }
  }

  static RouteLocation _location(
    Object location,
    Map<String, Object?> pathVariables,
    Map<String, Object?> params,
    Object? extra,
  ) {
    final RouteLocation base = switch (location) {
      final RouteLocation given => given,
      final String text when text.contains('{') => RouteLocation.expand(
        text.split('?').first,
        pathVariables: pathVariables,
      ),
      final String text => RouteLocation.parse(text),
      _ => throw ArgumentError.value(
        location,
        'location',
        'Not a RouteLocation or a String',
      ),
    };
    final query = params.isEmpty
        ? base
        : base.withParams({...base.queryParameters, ...params});
    return extra == null ? query : query.withExtra(extra);
  }
}

/// Gives a screen's widgets their [ScreenEntry]: what `context.route` reads.
class ScreenScope extends InheritedNotifier<ScreenEntry> {
  /// The scope of [screen] in [navigation].
  const ScreenScope({
    required this.navigation,
    required ScreenEntry screen,
    required super.child,
    super.key,
  }) : super(notifier: screen);

  /// The navigation the screen belongs to.
  final Navigation navigation;
}

/// `context.route`: the route of the widget's own screen.
extension RouteBuildContext on BuildContext {
  /// The [RouteTemplate] bound to this widget's screen; the widget
  /// rebuilds when the screen's parameters change.
  RouteTemplate get route => RouteTemplate.of(this);
}
