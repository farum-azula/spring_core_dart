import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';

/// The routes of the app put together and checked: every `ScreenRoutes`
/// bean (the annotated screens are one), the redirects of the
/// configuration. Made once at the start.
///
/// Throws a [StateError] that names both places for a path declared twice,
/// a shell key used twice, a screen under the branches of two shells, a
/// screen naming an unknown shell, or two not-found or error screens.
final class RouteTable {
  /// The table of [routes], with the [redirects] of the configuration
  /// first (a route's own redirect of the same path wins).
  factory RouteTable(
    List<ScreenRoutes> routes, {
    Map<String, String> redirects = const {},
  }) {
    final screens = <ScreenRouteDefinition>[];
    final shells = <ShellRouteDefinition>[];
    final allRedirects = <String, String>{...redirects};
    (ScreenBuilder, String?)? notFound;
    (ScreenBuilder, String?)? error;
    for (final group in routes) {
      for (final screen in group.screens) {
        if (screen.notFound) {
          notFound = _single(notFound, (
            screen.builder,
            screen.source,
          ), 'a not-found screen');
          continue;
        }
        final twin = screens
            .where((s) => s.pattern.pattern == screen.pattern.pattern)
            .firstOrNull;
        if (twin != null) {
          throw StateError(
            'The path ${screen.pattern.pattern} is declared twice: '
            '${_where(twin.source)} and ${_where(screen.source)}.',
          );
        }
        screens.add(screen);
      }
      for (final shell in group.shells) {
        final twin = shells.where((s) => s.key == shell.key).firstOrNull;
        if (twin != null) {
          throw StateError(
            'The shell ${shell.key} is declared twice: ${_where(twin.source)} '
            'and ${_where(shell.source)}.',
          );
        }
        shells.add(shell);
      }
      allRedirects.addAll(group.redirects);
      if (group.notFound case final builder?) {
        notFound = _single(notFound, (
          builder,
          group.source,
        ), 'a not-found screen');
      }
      if (group.error case final builder?) {
        error = _single(error, (builder, group.source), 'an error screen');
      }
    }
    final places = <ScreenRouteDefinition, (ShellRouteDefinition, int)>{};
    for (final screen in screens) {
      if (screen.branch case final branch?) {
        // An explicit branch, by its path: the shell that has it.
        final owners = [
          for (final shell in shells)
            if (shell.branches.contains(branch)) shell,
        ];
        if (owners.length != 1) {
          throw StateError(
            'The screen ${screen.pattern.pattern} (${_where(screen.source)}) '
            'opens in the branch $branch, which '
            '${owners.isEmpty ? 'no shell has' : 'several shells have: ${owners.join(' and ')}'}.',
          );
        }
        final shell = owners.single;
        places[screen] = (shell, shell.branches.indexOf(branch));
        continue;
      }
      final covering = [
        for (final shell in shells)
          if (shell.branchOf(screen.pattern.pattern) >= 0) shell,
      ];
      final named = screen.shell;
      if (named != null) {
        final shell = shells.where((s) => s.key == named).firstOrNull;
        if (shell == null) {
          throw StateError(
            'The screen ${screen.pattern.pattern} (${_where(screen.source)}) '
            'opens in the shell $named, which is not declared.',
          );
        }
        places[screen] = (shell, shell.branchOf(screen.pattern.pattern));
        continue;
      }
      if (covering.length > 1) {
        throw StateError(
          'The screen ${screen.pattern.pattern} (${_where(screen.source)}) is '
          'under the branches of two shells: ${covering.join(' and ')}.',
        );
      }
      if (covering case [final shell]) {
        places[screen] = (shell, shell.branchOf(screen.pattern.pattern));
      }
    }
    // The most specific pattern first, as the web starter sorts handlers.
    screens.sort((a, b) => a.pattern.compareTo(b.pattern));
    return RouteTable._(
      List.unmodifiable(screens),
      List.unmodifiable(shells),
      Map.unmodifiable(allRedirects),
      places,
      notFound?.$1,
      error?.$1,
    );
  }

  RouteTable._(
    this.screens,
    this.shells,
    this.redirects,
    this._places,
    this.notFound,
    this.error,
  );

  /// The screens, the most specific pattern first.
  final List<ScreenRouteDefinition> screens;

  /// The shells.
  final List<ShellRouteDefinition> shells;

  /// Addresses that lead elsewhere.
  final Map<String, String> redirects;

  final Map<ScreenRouteDefinition, (ShellRouteDefinition, int)> _places;

  /// The screen for unknown addresses, or `null` (a plain one is shown).
  final ScreenBuilder? notFound;

  /// The screen for a failed navigation, or `null` (a plain one is shown).
  final ScreenBuilder? error;

  /// The screen whose pattern matches [path] with the values it captured,
  /// or `null`.
  (ScreenRouteDefinition, Map<String, String>)? match(String path) {
    for (final screen in screens) {
      if (screen.pattern.match(path) case final match?) {
        return (screen, match.variables);
      }
    }
    return null;
  }

  /// The shell [screen] opens in and the branch (-1: the shell's current
  /// one), or `null` for a screen over everything.
  (ShellRouteDefinition, int)? placeOf(ScreenRouteDefinition screen) =>
      _places[screen];

  static (ScreenBuilder, String?) _single(
    (ScreenBuilder, String?)? first,
    (ScreenBuilder, String?) second,
    String what,
  ) {
    if (first != null) {
      throw StateError(
        'The app declares $what twice: ${_where(first.$2)} and '
        '${_where(second.$2)}.',
      );
    }
    return second;
  }

  static String _where(String? source) => source ?? 'a ScreenRoutes bean';
}
