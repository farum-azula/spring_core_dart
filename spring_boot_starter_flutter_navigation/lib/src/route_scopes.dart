import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';

/// The names of the navigation's bean scopes, for `@Scope(...)`.
///
/// ```dart
/// // One per opened screen: two book screens have two.
/// @Component()
/// @Scope(NavigationScopes.route)
/// class BookState { ... }
///
/// // One per branch of a shell, from its first visit until the shell
/// // closes; switching tabs keeps it.
/// @Component()
/// @Scope(NavigationScopes.branch)
/// class CatalogFilters { ... }
/// ```
abstract final class NavigationScopes {
  /// A screen: created when the screen opens, destroyed when it closes,
  /// after its exit animation.
  static const route = 'route';

  /// A branch of a shell: created on its first visit, destroyed when the
  /// shell closes (leaving the tabs, a logout).
  static const branch = 'branch';
}

// The zone values the screens' bean lookups run with (see
// `BeanLookupScope` of the Flutter starter), naming their screen and branch.
const _screenKey = #springNavigationScreen;
const _branchKey = #springNavigationBranch;

/// The `route` and `branch` scopes of one navigation. A lookup from a
/// widget gets the beans of that widget's screen and branch; any other
/// lookup (a singleton, a service) those of the screen on top.
final class RouteScopes {
  /// Empty scopes, attached to their navigation when it is made.
  RouteScopes();

  Navigation? _navigation;
  final _screens = <int, SimpleMapScope>{};
  final _branches = <(int, int), SimpleMapScope>{};

  /// The `route` scope.
  late final CustomScope route = _Scope(
    'route',
    () => _screens[_currentScreen()] ??= SimpleMapScope(),
  );

  /// The `branch` scope.
  late final CustomScope branch = _Scope(
    'branch',
    () => _branches[_currentBranch()] ??= SimpleMapScope(),
  );

  /// Ties the scopes to [navigation]; once.
  void attach(Navigation navigation) => _navigation = navigation;

  /// The zone values that make lookups resolve to screen [screen] in
  /// branch [branch] of shell [shell].
  static Map<Object?, Object?> zoneValues(
    int screen, {
    int? shell,
    int branch = -1,
  }) => {
    _screenKey: screen,
    if (shell != null && branch >= 0) _branchKey: (shell, branch),
  };

  /// Runs [body] with the lookups resolving to [screen]'s beans.
  static T runFor<T>(ScreenEntry screen, T Function() body) => runZoned(
    body,
    zoneValues: zoneValues(
      screen.id,
      shell: screen.shell?.id,
      branch: screen.branch,
    ),
  );

  /// Destroys the beans of screen [id] (after it left the screen).
  void destroyScreen(int id) => _screens.remove(id)?.destroy();

  /// Destroys the beans of every branch of shell [id].
  void destroyShell(int id) {
    for (final key in _branches.keys.where((k) => k.$1 == id).toList()) {
      _branches.remove(key)?.destroy();
    }
  }

  /// Destroys everything (the context closes).
  void destroyAll() {
    for (final scope in [..._screens.values, ..._branches.values]) {
      scope.destroy();
    }
    _screens.clear();
    _branches.clear();
  }

  int _currentScreen() {
    if (Zone.current[_screenKey] case final int id) {
      return id;
    }
    final top = _navigation?.top;
    if (top == null) {
      throw StateError('No screen is open, so there is no route scope.');
    }
    return top.id;
  }

  (int, int) _currentBranch() {
    if (Zone.current[_branchKey] case final (int, int) branch) {
      return branch;
    }
    final top = _navigation?.top;
    final shell = top?.shell;
    if (top == null || shell == null) {
      throw StateError(
        'The screen on top is in no shell, so there is no branch scope.',
      );
    }
    return (shell.id, top.branch);
  }
}

final class _Scope implements CustomScope {
  _Scope(this._name, this._current);

  final String _name;
  final SimpleMapScope Function() _current;

  @override
  Object get(String name, Object Function() objectFactory) =>
      _current().get(name, objectFactory);

  @override
  Object? remove(String name) => _current().remove(name);

  @override
  void registerDestructionCallback(String name, void Function() callback) =>
      _current().registerDestructionCallback(name, callback);

  @override
  String? get conversationId => _name;
}
