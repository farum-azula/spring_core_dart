import 'dart:async';

import 'package:flutter/foundation.dart'
    show SynchronousFuture, ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show ThemeFonts;
import 'package:spring_boot_starter_flutter_navigation/src/language_changed_event.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_state.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_table.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show PathPattern;

const _log = SpringLog('spring.flutter.navigation');

/// An entry of the app's stack: an opened screen or a shell.
sealed class NavigationEntry {
  NavigationEntry(this.id);

  /// Unique for the life of the navigation; the page's key and the
  /// `route` scope's id.
  final int id;
}

/// An opened screen. Notifies when its state changes in place
/// (`replaceParams`).
final class ScreenEntry extends NavigationEntry with ChangeNotifier {
  /// The screen [id] showing [state], in [shell]'s [branch] (or over
  /// everything without a shell).
  ScreenEntry(
    super.id,
    this._state, {
    this.shell,
    this.branch = -1,
    this.transition,
  });

  RouteState _state;

  /// The shell the screen is in, or `null`.
  final ShellEntry? shell;

  /// The branch of [shell] the screen is in, or -1.
  final int branch;

  /// The transition the navigation that opened the screen asked for
  /// (`go(path, transition: ...)`), or `null`: the route's.
  final PageTransition? transition;

  final _result = Completer<Object?>();

  /// The route's state.
  RouteState get state => _state;

  set state(RouteState value) {
    _state = value;
    notifyListeners();
  }

  /// Completes with what the screen was popped with (`null` when it was
  /// removed by another navigation).
  Future<Object?> get result => _result.future;

  /// Completes [result] once.
  void complete(Object? value) {
    if (!_result.isCompleted) {
      _result.complete(value);
    }
  }

  @override
  String toString() => 'screen $id ${state.location}';
}

/// An opened shell: a stack of screens per branch and the current branch.
final class ShellEntry extends NavigationEntry {
  /// The shell [id] of [definition].
  ShellEntry(super.id, this.definition)
    : stacks = [for (final _ in definition.branches) <ScreenEntry>[]],
      navigatorKeys = [
        for (final branch in definition.branches)
          GlobalKey<NavigatorState>(debugLabel: 'branch $branch'),
      ];

  /// What the shell is.
  final ShellRouteDefinition definition;

  /// The screens of each branch, bottom first.
  final List<List<ScreenEntry>> stacks;

  /// The navigator of each branch.
  final List<GlobalKey<NavigatorState>> navigatorKeys;

  /// The branches visited, whose navigators are built.
  final visited = <int>{};

  /// The current branch.
  int index = 0;

  @override
  String toString() => 'shell $id ${definition.key}';
}

/// The app's navigation: the stack of screens and shells, how a location
/// becomes a screen (redirects, filters, conversions), and the changes.
///
/// One per application context (the `navigation` bean); `RouteTemplate`
/// and the router work on it.
final class Navigation extends ChangeNotifier {
  /// The navigation of [table]; [filters] run for every route before its
  /// own, [conversion] converts the values, [messages] translates titles,
  /// [scopes] keep the `route` and `branch` beans.
  Navigation({
    required this.table,
    required this.conversion,
    required this.scopes,
    this.filters = const [],
    this.messages,
    this.initial,
    this.linkExclude = const [],
    this.languages = const [],
    this.events,
  }) : _language = ValueNotifier(languages.firstOrNull) {
    _checkAuthorization();
    scopes.attach(this);
    _published = _language.value;
    _language.addListener(_languageChanged);
  }

  /// Where [LanguageChangedEvent]s go; `null` publishes none.
  final ApplicationEventPublisher? events;

  String? _published;

  void _languageChanged() {
    final language = _language.value;
    if (language == null || language == _published) {
      return;
    }
    final from = _published;
    _published = language;
    events?.publishEvent(
      LanguageChangedEvent(this, from: from, to: language),
    );
  }

  // A route that asks for a user must not open to everyone because nothing
  // enforces it: fail the start instead.
  void _checkAuthorization() {
    if (filters.any((f) => f is RouteAuthorizationFilter)) {
      return;
    }
    final guarded = [
      for (final screen in table.screens)
        if (screen.attributes.containsKey(RouteAttributes.preAuthorize) ||
            screen.filters.any((f) => f is RouteAuthorizationRequirement))
          screen,
    ];
    if (guarded.isNotEmpty) {
      throw StateError(
        'The routes ${guarded.map((s) => s.source ?? s.pattern.pattern).join(', ')} '
        'require a user (@PreAuthorize) but no RouteAuthorizationFilter '
        'enforces it: add spring_boot_starter_flutter_security.',
      );
    }
  }

  /// The routes.
  final RouteTable table;

  /// The filters of every route (`RouteFilter` beans).
  final List<RouteFilter> filters;

  /// Converts the values of the addresses.
  final ConversionService conversion;

  /// Translates `#{key}` titles.
  final MessageSource? messages;

  /// The `route` and `branch` scopes.
  final RouteScopes scopes;

  /// Where the app starts when the platform gives `/`
  /// (`spring.flutter.navigation.initial`), or `null`.
  final String? initial;

  /// Path patterns whose links from outside do not open their screen
  /// (`spring.flutter.navigation.deep-links.exclude`).
  final List<String> linkExclude;

  /// The languages with their own addresses, the default first
  /// (`spring.flutter.navigation.languages`); empty for one language.
  final List<String> languages;

  final ValueNotifier<String?> _language;

  /// The language of the addresses (and of the app's locale): the default
  /// one, or the one the last address named (`/ja/...`); `null` without
  /// [languages].
  String? get language => _language.value;

  /// [language], to listen to (the app's locale follows it).
  ValueListenable<String?> get languageListenable => _language;

  /// Shows the app in [language] at the same screen: the address gets the
  /// language's prefix (none for the default one). Throws an
  /// [ArgumentError] for a language that is not one of [languages]. The
  /// fonts declared for the language (`spring.flutter.fonts.families`)
  /// load first, when they are not loaded yet, so no text shows without
  /// them.
  void switchLanguage(String language) {
    if (!languages.contains(language)) {
      throw ArgumentError.value(language, 'language', 'not one of $languages');
    }
    if (language == _language.value) {
      return;
    }
    void switched() {
      if (language != _language.value) {
        _language.value = language;
        _changed();
      }
    }

    final fonts = ThemeFonts.loadLanguage(language);
    if (fonts == null) {
      switched();
    } else {
      unawaited(fonts.then((_) => switched()));
    }
  }

  /// The language [path] names with its first segment (`/ja/catalog` is
  /// `ja`), else the default one; `null` without [languages].
  String? languageOf(String path) {
    if (languages.isEmpty) {
      return null;
    }
    final segments = path.split('/');
    final first = segments.length > 1 ? segments[1] : '';
    return languages.contains(first) ? first : languages.first;
  }

  /// [location] without its language prefix (`/ja/catalog` is `/catalog`),
  /// the language it names made the current one. Without a prefix, an
  /// address of the platform ([platform]: the browser's bar, a link) is
  /// the default language's, an address of the app's own code keeps the
  /// current language.
  RouteLocation withoutLanguage(
    RouteLocation location, {
    bool platform = false,
  }) {
    if (languages.isEmpty) {
      return location;
    }
    final segments = location.path.split('/');
    final first = segments.length > 1 ? segments[1] : '';
    if (languages.contains(first)) {
      _language.value = first;
      final rest = segments.skip(2).join('/');
      return location.withPath('/$rest');
    }
    if (platform) {
      _language.value = languages.first;
    }
    return location;
  }

  /// The address of [location] in the current language: with its prefix
  /// unless the language is the default one.
  RouteLocation withLanguage(RouteLocation location) {
    final language = _language.value;
    if (languages.length < 2 ||
        language == null ||
        language == languages.first) {
      return location;
    }
    return location.withPath(
      location.path == '/' ? '/$language' : '/$language${location.path}',
    );
  }

  late final _excluded = [
    for (final pattern in linkExclude) PathPattern.parse(pattern),
  ];

  /// The app's stack, bottom first: screens over everything and shells.
  final List<NavigationEntry> root = [];

  final _changes = StreamController<RouteState>.broadcast();
  var _nextId = 0;

  // A navigation that finishes after a newer one started is dropped.
  var _generation = 0;

  /// The screen on top: of the top shell's current branch, or the top
  /// screen; `null` before the first navigation.
  ScreenEntry? get top => switch (root.lastOrNull) {
    final ScreenEntry screen => screen,
    final ShellEntry shell => shell.stacks[shell.index].lastOrNull,
    null => null,
  };

  /// The screens the user sees under each other: the screens over
  /// everything and, under them, the current branch of the shell.
  List<ScreenEntry> get visibleStack => [
    for (final entry in root)
      ...switch (entry) {
        final ScreenEntry screen => [screen],
        final ShellEntry shell => shell.stacks[shell.index],
      },
  ];

  /// The state of every navigation, as it happens.
  Stream<RouteState> get changes => _changes.stream;

  /// The location the app starts at for the platform's [location].
  RouteLocation startLocation(RouteLocation location) {
    final initial = this.initial;
    return location.path == '/' &&
            location.queryParameters.isEmpty &&
            initial != null &&
            initial.isNotEmpty
        ? RouteLocation.parse(initial)
        : location;
  }

  /// Whether [path] is refused before any route is matched: an encoded
  /// slash or backslash (`%2F`, `%5C`), a backslash, `%00`, or a `.` or
  /// `..` segment once decoded. Such an address could stay on one route
  /// while its `{*rest}` value names a file of another route's folder
  /// (`/docs/..%2Fprivate%2Fx`), past that route's guard.
  ///
  /// Spring (Java): what `StrictHttpFirewall` refuses on a server.
  static bool refusedPath(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('%2f') ||
        lower.contains('%5c') ||
        lower.contains('%00') ||
        path.contains(r'\')) {
      return true;
    }
    for (final segment in path.split('/')) {
      final String decoded;
      try {
        decoded = Uri.decodeComponent(segment);
      } on ArgumentError {
        return true;
      }
      if (decoded == '.' || decoded == '..') {
        return true;
      }
    }
    return false;
  }

  /// Opens [location] from a link from outside the app (a deep link): as
  /// [go], unless the screen does not open by a link (`@RouteInfo(link:
  /// false)`, `deep-links.exclude`), when the app's first screen opens.
  Future<void> openLink(RouteLocation link) {
    if (refusedPath(link.path)) {
      _log.debug(() => 'The link $link is refused: its path could escape');
      return go(startLocation(RouteLocation('/')));
    }
    final location = startLocation(withoutLanguage(link, platform: true));
    if (refusedPath(location.path)) {
      _log.debug(() => 'The link $location is refused: its path could escape');
      return go(startLocation(RouteLocation('/')));
    }
    final matched = table.match(location.path)?.$1;
    final refused =
        (matched != null && !matched.link) ||
        _excluded.any((pattern) => pattern.matches(location.path));
    if (refused) {
      _log.debug(() => 'The link $location does not open its screen');
      return go(startLocation(RouteLocation('/')));
    }
    return go(location);
  }

  /// Opens [location] as the app's state: its screen with the screens of
  /// its path below it (`/catalog` under `/catalog/books/1`), in its shell's
  /// branch (the other branches kept), or over nothing.
  ///
  /// Synchronous when the redirects and filters are (the result is then a
  /// `SynchronousFuture`), so the first screen is built in the app's first
  /// frame. [transition] replaces the route's for the screens this
  /// navigation opens (a menu that switches pages at once:
  /// `PageTransition.none`).
  Future<void> go(RouteLocation address, {PageTransition? transition}) {
    var location = refusedPath(address.path)
        ? address
        : withoutLanguage(address);
    if (refusedPath(location.path)) {
      // An address that could read outside a route's folder: the app stays
      // where it is, or opens its first screen when nothing is open yet.
      _log.debug(
        () => 'The address $location is refused: its path could escape',
      );
      if (top != null) {
        _changed();
        return SynchronousFuture(null);
      }
      location = startLocation(RouteLocation('/'));
    }
    final generation = ++_generation;
    return _done(
      _then(
        _resolve(location),
        (target) => _then(_ancestors(target), (ancestors) {
          if (generation == _generation) {
            _apply(target, [...ancestors, target], transition);
          }
        }),
      ),
    );
  }

  void _apply(
    RouteState target,
    List<RouteState> chain, [
    PageTransition? transition,
  ]) {
    final place = _placeOf(target);
    if (place == null) {
      _setRoot(
        _reuse(
          _rootScreens(),
          [
            for (final state in chain)
              if (_placeOf(state) == null) state,
          ],
          null,
          -1,
          transition,
        ),
      );
    } else {
      final (definition, wanted) = place;
      final shell =
          root
              .whereType<ShellEntry>()
              .where((s) => s.definition == definition)
              .firstOrNull ??
          ShellEntry(_nextId++, definition);
      final branch = wanted >= 0 ? wanted : shell.index;
      final kept = shell.stacks[branch];
      shell.stacks[branch] = _reuse(
        kept,
        [
          for (final state in chain)
            if (_placeOf(state)?.$1 == definition) state,
        ],
        shell,
        branch,
        transition,
      );
      _drop(kept.where((e) => !shell.stacks[branch].contains(e)));
      shell
        ..index = branch
        ..visited.add(branch);
      _setRoot([shell]);
    }
    _changed();
  }

  /// Opens [location] on top of the current stack; completes with what
  /// its screen is popped with. [transition] replaces the route's.
  Future<T?> push<T extends Object?>(
    RouteLocation location, {
    PageTransition? transition,
  }) {
    if (refusedPath(location.path)) {
      _log.debug(
        () => 'The address $location is refused: its path could escape',
      );
      return SynchronousFuture<T?>(null);
    }
    final generation = ++_generation;
    final entry = _then<RouteState, ScreenEntry?>(_resolve(location), (
      target,
    ) {
      if (generation != _generation) {
        return null;
      }
      final place = _placeOf(target);
      final top = root.lastOrNull;
      if (place != null && top is ShellEntry && top.definition == place.$1) {
        final branch = place.$2 >= 0 ? place.$2 : top.index;
        return _then<List<RouteState>, ScreenEntry?>(_ancestors(target), (
          ancestors,
        ) {
          final screen = ScreenEntry(
            _nextId++,
            target,
            shell: top,
            branch: branch,
            transition: transition,
          );
          if (top.stacks[branch].isEmpty) {
            top.stacks[branch].addAll(
              _reuse(
                const [],
                [
                  for (final state in ancestors)
                    if (_placeOf(state)?.$1 == top.definition) state,
                ],
                top,
                branch,
              ),
            );
          }
          top.stacks[branch].add(screen);
          top
            ..index = branch
            ..visited.add(branch);
          _changed();
          return screen;
        });
      }
      final screen = ScreenEntry(_nextId++, target, transition: transition);
      root.add(screen);
      _changed();
      return screen;
    });
    return _done(entry).then((screen) async {
      final result = await screen?.result;
      return result is T ? result : null;
    });
  }

  /// Removes the screen on top (of the current branch when a shell is on
  /// top and its branch has more than one screen) and completes it with
  /// [result]. `false` when there is nothing to pop.
  bool pop([Object? result]) {
    final top = root.lastOrNull;
    if (top is ShellEntry && top.stacks[top.index].length > 1) {
      final screen = top.stacks[top.index].removeLast();
      screen.complete(result);
      _changed();
      return true;
    }
    if (root.length > 1) {
      final entry = root.removeLast();
      if (entry is ScreenEntry) {
        entry.complete(result);
      } else {
        _dropShell(entry as ShellEntry);
      }
      _changed();
      return true;
    }
    return false;
  }

  /// Whether [pop] would remove a screen.
  bool get canPop =>
      root.length > 1 ||
      switch (root.lastOrNull) {
        final ShellEntry shell => shell.stacks[shell.index].length > 1,
        _ => false,
      };

  /// Switches [shell] to [branch]: as it was left, at its path when never
  /// visited, back to its first screen when it is the current one.
  Future<void> select(ShellEntry shell, int branch) async {
    if (branch == shell.index && shell.stacks[branch].length > 1) {
      final removed = shell.stacks[branch].sublist(1);
      shell.stacks[branch] = shell.stacks[branch].sublist(0, 1);
      _drop(removed);
      _changed();
      return;
    }
    if (shell.stacks[branch].isNotEmpty) {
      shell.index = branch;
      _changed();
      return;
    }
    await go(RouteLocation.parse(shell.definition.branches[branch]));
  }

  /// Replaces the query parameters of [entry] in place (no new screen); the
  /// screen rebuilds.
  void replaceParams(ScreenEntry entry, Map<String, Object?> params) {
    entry.state = entry.state.withLocation(
      entry.state.location.withParams(params),
    );
    _changed();
  }

  /// The navigator removed [entry] by itself (a back gesture,
  /// `Navigator.pop`): the state follows.
  void removed(ScreenEntry entry) {
    final shell = entry.shell;
    if (shell != null && entry.branch >= 0) {
      if (shell.stacks[entry.branch].remove(entry)) {
        entry.complete(null);
        _changed();
      }
      return;
    }
    if (root.remove(entry)) {
      entry.complete(null);
      _changed();
    }
  }

  /// The shell entry left the stack for good: its screens' beans go.
  void _dropShell(ShellEntry shell) {
    for (final stack in shell.stacks) {
      _drop(stack);
    }
  }

  void _drop(Iterable<ScreenEntry> entries) {
    for (final entry in entries.toList()) {
      entry.complete(null);
    }
  }

  void _setRoot(List<NavigationEntry> entries) {
    for (final old in root) {
      if (!entries.contains(old)) {
        switch (old) {
          case final ScreenEntry screen:
            screen.complete(null);
          case final ShellEntry shell:
            _dropShell(shell);
        }
      }
    }
    root
      ..clear()
      ..addAll(entries);
  }

  List<ScreenEntry> _rootScreens() => root.whereType<ScreenEntry>().toList();

  // The entries for [states]: the existing entry kept where the screen at
  // that position shows the same address, so it keeps its state.
  List<ScreenEntry> _reuse(
    List<ScreenEntry> existing,
    List<RouteState> states,
    ShellEntry? shell,
    int branch, [
    PageTransition? transition,
  ]) => [
    for (var i = 0; i < states.length; i++)
      if (i < existing.length &&
          existing[i].state.error == null &&
          states[i].error == null &&
          existing[i].state.route == states[i].route)
        _moved(existing[i], states[i])
      else
        ScreenEntry(
          _nextId++,
          states[i],
          shell: shell,
          branch: branch,
          transition: transition,
        ),
  ];

  // A screen of the same route at another address (`/docs/a` to
  // `/docs/b`): the same screen, its state and scroll kept, rebuilt with
  // the new address.
  ScreenEntry _moved(ScreenEntry entry, RouteState state) {
    if (entry.state.location != state.location) {
      entry.state = state;
    }
    return entry;
  }

  (ShellRouteDefinition, int)? _placeOf(RouteState state) {
    final route = state.route;
    return route == null || state.error != null ? null : table.placeOf(route);
  }

  void _changed() {
    notifyListeners();
    final top = this.top;
    if (top != null) {
      _log.debug(() => 'Navigated to ${top.state.location}');
      _changes.add(top.state);
    }
  }

  // The screens of the path's prefixes that are routes of their own, in
  // the same place as [target]: `/catalog` for `/catalog/books/1`.
  FutureOr<List<RouteState>> _ancestors(RouteState target) {
    final route = target.route;
    if (route == null || target.error != null) {
      return const [];
    }
    // The prefixes of the path, after those of the screen's explicit
    // branch when its path is not under it (`/more` below `/motion`).
    List<String> prefixes(String path, {required bool whole}) {
      final segments = path.split('/')..removeWhere((s) => s.isEmpty);
      return [
        for (var i = 1; i < segments.length + (whole ? 1 : 0); i++)
          '/${segments.take(i).join('/')}',
      ];
    }

    final branch = route.branch;
    final paths = [
      if (branch != null && !isPathUnder(target.location.path, branch))
        ...prefixes(branch, whole: true),
      ...prefixes(target.location.path, whole: false),
    ];
    final candidates = <(String, ScreenRouteDefinition)>[
      for (final path in paths)
        if (table.match(path)
            case (
              final matched,
              _,
            )
            when matched != route &&
                table.placeOf(matched)?.$1 == table.placeOf(route)?.$1)
          (path, matched),
    ];
    final ancestors = <RouteState>[];
    FutureOr<List<RouteState>> next(int i) {
      if (i == candidates.length) {
        return ancestors;
      }
      final (path, matched) = candidates[i];
      return _then(_resolve(RouteLocation(path), redirects: false), (state) {
        // An ancestor a filter turns away is left out.
        if (state.route == matched &&
            state.error == null &&
            state.location.path == path) {
          ancestors.add(state);
        }
        return next(i + 1);
      });
    }

    return next(0);
  }

  // [location] after the redirects and filters, with its route and values;
  // the not-found or error state when that is what it comes to.
  // Synchronous unless a filter is not.
  FutureOr<RouteState> _resolve(
    RouteLocation location, {
    int depth = 0,
    bool redirects = true,
  }) {
    if (depth > 10) {
      return _state(
        location,
        null,
        const {},
        StateError('More than 10 redirects, the last to $location'),
      );
    }
    final redirect = redirects ? table.redirects[location.path] : null;
    if (redirect != null) {
      final target = RouteLocation.parse(redirect, extra: location.extra);
      return _resolve(
        target.queryParameters.isEmpty
            ? target.withParams(location.queryParameters)
            : target,
        depth: depth + 1,
      );
    }
    final matched = table.match(location.path);
    if (matched == null) {
      return _state(location, null, const {});
    }
    final (route, variables) = matched;
    final state = _state(location, route, variables);
    try {
      state.checkDeclared();
    } on RouteValueException catch (e) {
      return _state(location, route, variables, e);
    }
    return _filter(state, [...filters, ...route.filters], 0, depth);
  }

  // The filters of [chain] from [i] on, for [state].
  FutureOr<RouteState> _filter(
    RouteState state,
    List<RouteFilter> chain,
    int i,
    int depth,
  ) {
    final request = RouteRequest(state);
    for (var at = i; at < chain.length; at++) {
      final filter = chain[at];
      final FutureOr<RouteLocation?> next;
      try {
        next = filter.filter(request);
      } on Object catch (e, stack) {
        return _failed(state, filter, e, stack);
      }
      if (next is Future<RouteLocation?>) {
        return next.then(
          (location) => location != null
              ? _redirected(state, location, depth)
              : _filter(state, chain, at + 1, depth),
          onError: (Object e, StackTrace stack) =>
              _failed(state, filter, e, stack),
        );
      }
      if (next != null) {
        return _redirected(state, next, depth);
      }
    }
    return state;
  }

  FutureOr<RouteState> _redirected(
    RouteState state,
    RouteLocation next,
    int depth,
  ) {
    _log.debug(() => 'A route filter sent ${state.location} to $next');
    return _resolve(next, depth: depth + 1);
  }

  RouteState _failed(
    RouteState state,
    RouteFilter filter,
    Object error,
    StackTrace stack,
  ) {
    // The error screen shows it; a denied access is no failure.
    _log.debug(
      () =>
          'The route filter $filter stopped ${state.location}: $error\n$stack',
    );
    return _state(state.location, state.route, state.variables, error);
  }

  static FutureOr<B> _then<A, B>(
    FutureOr<A> value,
    FutureOr<B> Function(A) f,
  ) => value is Future<A> ? value.then(f) : f(value);

  static Future<T> _done<T>(FutureOr<T> value) =>
      value is Future<T> ? value : SynchronousFuture(value);

  RouteState _state(
    RouteLocation location,
    ScreenRouteDefinition? route,
    Map<String, String> variables, [
    Object? error,
  ]) => RouteState(
    location: location,
    route: route,
    variables: variables,
    conversion: conversion,
    messages: messages,
    error: error,
  );

  @override
  void dispose() {
    _setRoot(const []);
    unawaited(_changes.close());
    _language.dispose();
    super.dispose();
  }
}
