import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_state.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_template.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/shell_state.dart';

/// The app's router: what `SpringApp` gives `MaterialApp.router` (or the
/// Cupertino or widgets one) when the navigation starter is there. The
/// platform's addresses (the browser's bar, deep links, Android's back
/// button) go through it to the [Navigation].
final class SpringRouterConfig extends RouterConfig<RouteLocation> {
  /// The router of [navigation]; [initial] is the platform's first
  /// address (the device's deep link, the browser's address), `/` by
  /// default.
  factory SpringRouterConfig(Navigation navigation, {String? initial}) {
    final delegate = SpringRouterDelegate(navigation);
    final uri = Uri.parse(
      initial ?? WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    // The language of the first address, known before the app is built, so
    // its first frame is already in that language.
    final first = RouteLocation.fromUri(uri);
    if (!Navigation.refusedPath(first.path)) {
      navigation.withoutLanguage(
        navigation.startLocation(first),
        platform: true,
      );
    }
    return SpringRouterConfig._(
      navigation,
      delegate,
      PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: uri),
      ),
    );
  }

  SpringRouterConfig._(
    this.navigation,
    SpringRouterDelegate delegate,
    PlatformRouteInformationProvider provider,
  ) : super(
        routerDelegate: delegate,
        routeInformationParser: const _LocationParser(),
        routeInformationProvider: provider,
        backButtonDispatcher: RootBackButtonDispatcher(),
      );

  /// The navigation the router shows.
  final Navigation navigation;
}

final class _LocationParser extends RouteInformationParser<RouteLocation> {
  const _LocationParser();

  @override
  Future<RouteLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) => SynchronousFuture(RouteLocation.fromUri(routeInformation.uri));

  @override
  RouteInformation restoreRouteInformation(RouteLocation configuration) =>
      RouteInformation(uri: configuration.uri);
}

/// Builds the navigators of the [Navigation]: the root one and, inside a
/// shell, one per branch.
final class SpringRouterDelegate extends RouterDelegate<RouteLocation>
    with ChangeNotifier {
  /// The delegate of [navigation].
  SpringRouterDelegate(this.navigation) {
    navigation.addListener(notifyListeners);
  }

  /// The navigation shown.
  final Navigation navigation;

  final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'spring root');

  @override
  RouteLocation? get currentConfiguration => switch (navigation.top) {
    final top? => navigation.withLanguage(top.state.location),
    null => null,
  };

  // On a device an address from the platform is a link from outside (a
  // deep link); in a browser it is the address bar and the history.
  @override
  Future<void> setInitialRoutePath(RouteLocation configuration) {
    if (!kIsWeb) {
      return navigation.openLink(navigation.startLocation(configuration));
    }
    // The browser's address: without a language prefix, the default
    // language's.
    final location = Navigation.refusedPath(configuration.path)
        ? configuration
        : navigation.withoutLanguage(configuration, platform: true);
    return navigation.go(navigation.startLocation(location));
  }

  @override
  Future<void> setNewRoutePath(RouteLocation configuration) {
    if (!kIsWeb) {
      return navigation.openLink(configuration);
    }
    final location = Navigation.refusedPath(configuration.path)
        ? configuration
        : navigation.withoutLanguage(configuration, platform: true);
    return navigation.go(location);
  }

  @override
  Future<bool> popRoute() async {
    // The deepest navigator first, so a PopScope there decides.
    if (navigation.root.lastOrNull case final ShellEntry shell) {
      final branch = shell.navigatorKeys[shell.index].currentState;
      if (branch != null && await branch.maybePop()) {
        return true;
      }
    }
    final root = _rootKey.currentState;
    if (root != null && await root.maybePop()) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (navigation.root.isEmpty) {
      return const SizedBox.shrink();
    }
    final kind = _PageKind.of(context);
    _scheduleTitle(context);
    final spring = SpringScope.maybeOf(context, listen: false);
    return Navigator(
      key: _rootKey,
      // The app's NavigatorObserver beans watch the screens over everything
      // (an observer belongs to one navigator).
      observers: spring == null
          ? const []
          : FlutterAppSettings.of(spring).navigatorObservers,
      pages: [
        for (final entry in navigation.root)
          switch (entry) {
            final ScreenEntry screen => _page(screen, kind),
            final ShellEntry shell => _SpringPage(
              key: ValueKey('shell ${shell.id}'),
              kind: kind,
              transition: PageTransition.none,
              child: _ShellHost(
                navigation: navigation,
                shell: shell,
                kind: kind,
              ),
            ),
          },
      ],
      onDidRemovePage: (page) {
        if (page case _SpringPage(:final ScreenEntry screen)) {
          navigation.removed(screen);
        }
      },
    );
  }

  _SpringPage _page(ScreenEntry screen, _PageKind kind) => _SpringPage(
    key: ValueKey('screen ${screen.id}'),
    name: screen.state.location.toString(),
    kind: kind,
    transition:
        screen.transition ??
        screen.state.route?.transition ??
        PageTransition.theme,
    screen: screen,
    child: _ScreenHost(navigation: navigation, screen: screen),
  );

  String? _shownTitle;

  // The browser tab and the task switcher show the top screen's title,
  // else the app's.
  void _scheduleTitle(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    final spring = SpringScope.maybeOf(context, listen: false);
    final app = spring == null ? '' : FlutterAppSettings.of(spring).title;
    final title = navigation.top?.state.title(locale) ?? app;
    if (title == _shownTitle || title.isEmpty) {
      return;
    }
    _shownTitle = title;
    // The theme shown; without one, the baseline palette's.
    final color =
        (SpringTheme.maybeOf(context)?.colorScheme ??
                SpringColorScheme.baseline(Brightness.light))
            .primary
            .toARGB32();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(label: title, primaryColor: color),
        ),
      );
    });
  }

  @override
  void dispose() {
    navigation.removeListener(notifyListeners);
    super.dispose();
  }
}

// What a page route is made with: the type of the app and the routes of
// its design libraries (`DesignPageRoutes` beans), which the router itself
// does not know.
final class _PageKind {
  const _PageKind(this.appType, this.designs);

  static const none = _PageKind(WidgetsAppFactory.typeName, []);

  static _PageKind of(BuildContext context) {
    final spring = SpringScope.maybeOf(context, listen: false);
    return spring == null
        ? none
        : _kinds[spring] ??= _PageKind(
            FlutterAppSettings.of(spring).type,
            spring.getSortedBeans<DesignPageRoutes>(),
          );
  }

  static final _kinds = Expando<_PageKind>('page kind');

  final String appType;
  final List<DesignPageRoutes> designs;

  // The route a design library has for the page; `null` when none does.
  PageRoute<Object?>? route(
    PageTransitionType transition,
    SpringPageRequest page,
  ) {
    for (final design in designs) {
      final route = design.pageRoute(transition, appType, page);
      if (route != null) {
        return route;
      }
    }
    return null;
  }

  // The hero flights of a navigator: the design's of the app, else
  // Flutter's own.
  HeroController heroController() {
    for (final design in designs) {
      final controller = design.heroController(appType);
      if (controller != null) {
        return controller;
      }
    }
    return HeroController();
  }
}

final class _SpringPage extends Page<Object?> {
  const _SpringPage({
    required this.kind,
    required this.transition,
    required this.child,
    this.screen,
    super.key,
    super.name,
  });

  final _PageKind kind;
  final PageTransition transition;
  final Widget child;
  final ScreenEntry? screen;

  @override
  Route<Object?> createRoute(BuildContext context) {
    final theme =
        SpringTheme.maybeOf(context)?.pageTransitions ??
        const PageTransitionSpec();
    final type = switch (transition) {
      PageTransition.theme => theme.type,
      PageTransition.platform => PageTransitionType.platform,
      PageTransition.fadeUpwards => PageTransitionType.fadeUpwards,
      PageTransition.zoom => PageTransitionType.zoom,
      PageTransition.cupertino => PageTransitionType.cupertino,
      PageTransition.fade => PageTransitionType.fade,
      PageTransition.content => PageTransitionType.content,
      PageTransition.none => PageTransitionType.none,
    };
    // Reduced motion on the device: every transition at once.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = still ? Duration.zero : theme.duration;
    final curve = theme.curve;
    final content =
        SpringTheme.maybeOf(context)?.contentChange ??
        const ContentChangeSpec();
    // The route of a design library: Material's for `platform` in its
    // app, Cupertino's for `cupertino` and for `platform` in its app.
    PageRoute<Object?>? designed() => kind.route(
      type,
      SpringPageRequest(
        settings: this,
        child: child,
        // The page of a route is replaced in place: its child then.
        content: (settings) => (settings as _SpringPage).child,
        duration: duration,
        curve: curve,
      ),
    );
    final Route<Object?> route = switch (type) {
      PageTransitionType.none => _PlainRoute(
        this,
        builder: null,
        duration: Duration.zero,
      ),
      // Without a design library the platform has no transition.
      PageTransitionType.platform =>
        designed() ?? _PlainRoute(this, builder: null, duration: Duration.zero),
      PageTransitionType.cupertino => designed() ?? _missing(type, 'cupertino'),
      PageTransitionType.fadeUpwards => _PlainRoute(
        this,
        builder: const FadeUpwardsPageTransitionsBuilder(),
        duration: duration ?? const Duration(milliseconds: 300),
        curve: curve,
      ),
      PageTransitionType.zoom => switch (_designs(context).pageTransition(
        type,
      )) {
        final builder? => _PlainRoute(
          this,
          builder: builder,
          duration: duration ?? const Duration(milliseconds: 300),
          curve: curve,
        ),
        null => _missing(type, 'material'),
      },
      PageTransitionType.fade => _PlainRoute(
        this,
        builder: const _Fade(),
        duration: duration ?? const Duration(milliseconds: 250),
        curve: curve,
      ),
      PageTransitionType.content => _PlainRoute(
        this,
        builder: const ContentPageTransitionsBuilder(),
        duration: still ? Duration.zero : duration ?? content.duration,
        curve: curve ?? content.curve,
      ),
    };
    final screen = this.screen;
    if (screen != null) {
      unawaited(route.popped.then(screen.complete));
    }
    return route;
  }

  // The designs of the application: those the shown theme was read with,
  // else those of its themes (an app widget of the app's own may have no
  // SpringTheme above the router).
  static ThemeDesigns _designs(BuildContext context) =>
      SpringTheme.maybeOf(context)?.designs ??
      switch (SpringScope.maybeOf(context, listen: false)) {
        final spring? => SpringThemes.of(spring).designs,
        null => ThemeDesigns.none,
      };

  // A transition of a design library the application does not have (a
  // screen's own `transition:`; the theme's is checked at the start): the
  // error is reported, and the page shows without one. Thrown here, while
  // the navigator updates its pages, it would leave the widget tree broken.
  Route<Object?> _missing(PageTransitionType type, String design) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: _needsStarter(type, design),
        library: 'spring_boot_starter_flutter_navigation',
        context: ErrorDescription('while making the route of page $name'),
      ),
    );
    return _PlainRoute(this, builder: null, duration: Duration.zero);
  }

  static FlutterError _needsStarter(PageTransitionType type, String design) =>
      FlutterError.fromParts([
        ErrorSummary(
          'The page transition ${type.name} needs '
          'spring_boot_starter_flutter_$design.',
        ),
        ErrorHint(
          "It is the $design library's own transition: add "
          'spring_boot_starter_flutter_$design to the dependencies, or '
          'choose platform, fadeUpwards, fade, content or none.',
        ),
      ]);
}

// [animation] along [curve], when the theme gives one.
Animation<double> _curved(Animation<double> animation, Curve? curve) =>
    curve == null
    ? animation
    : CurvedAnimation(parent: animation, curve: curve);

// The theme's `fade`.
final class _Fade extends PageTransitionsBuilder {
  const _Fade();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

// A route of any app type: [builder]'s transition over [duration], or
// none.
final class _PlainRoute extends PageRoute<Object?> {
  _PlainRoute(
    _SpringPage page, {
    required this.builder,
    required this.duration,
    this.curve,
  }) : super(settings: page);

  final PageTransitionsBuilder? builder;
  final Duration duration;
  final Curve? curve;

  _SpringPage get _page => settings as _SpringPage;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => switch (builder) {
    null => child,
    final builder => builder.buildTransitions(
      this,
      context,
      _curved(animation, curve),
      _curved(secondaryAnimation, curve),
      child,
    ),
  };

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}

// A screen: its widget from the route, under the scope `context.route`
// reads, with its bean lookups resolving to its own `route` and `branch`
// beans. The screen's beans go when it leaves for good (after the exit
// animation: the page's widget stays until its route is gone).
final class _ScreenHost extends StatefulWidget {
  const _ScreenHost({required this.navigation, required this.screen});

  final Navigation navigation;
  final ScreenEntry screen;

  @override
  State<_ScreenHost> createState() => _ScreenHostState();
}

final class _ScreenHostState extends State<_ScreenHost> {
  @override
  void dispose() {
    widget.navigation.scopes.destroyScreen(widget.screen.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = widget.screen;
    return ScreenScope(
      navigation: widget.navigation,
      screen: screen,
      child: BeanLookupScope(
        zoneValues: RouteScopes.zoneValues(
          screen.id,
          shell: screen.shell?.id,
          branch: screen.branch,
        ),
        child: ListenableBuilder(
          listenable: screen,
          builder: (context, _) =>
              RouteScopes.runFor(screen, () => _build(screen.state)),
        ),
      ),
    );
  }

  Widget _build(RouteState state) {
    final table = widget.navigation.table;
    final route = state.route;
    if (state.error != null) {
      return table.error?.call(state) ?? _Problem(state, error: true);
    }
    if (route == null || route.notFound) {
      return (route?.builder ?? table.notFound)?.call(state) ??
          _Problem(state, error: false);
    }
    return route.builder(state);
  }
}

// A shell: its widget with the current branch's navigator, the others
// kept offstage once visited.
final class _ShellHost extends StatefulWidget {
  const _ShellHost({
    required this.navigation,
    required this.shell,
    required this.kind,
  });

  final Navigation navigation;
  final ShellEntry shell;
  final _PageKind kind;

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

final class _ShellHostState extends State<_ShellHost> implements ShellState {
  // One hero controller per branch navigator, for the life of the shell.
  late final _heroes = [
    for (final _ in widget.shell.stacks) widget.kind.heroController(),
  ];

  @override
  void dispose() {
    for (final hero in _heroes) {
      hero.dispose();
    }
    widget.navigation.scopes.destroyShell(widget.shell.id);
    super.dispose();
  }

  ShellEntry get _shell => widget.shell;

  @override
  int get index => _shell.index;

  @override
  List<String> get branches => _shell.definition.branches;

  @override
  String get branch => branches[index];

  @override
  void select(int index) => unawaited(widget.navigation.select(_shell, index));

  @override
  Widget get child => IndexedStack(
    index: _shell.index,
    children: [
      for (var i = 0; i < _shell.stacks.length; i++)
        if (_shell.visited.contains(i) && _shell.stacks[i].isNotEmpty)
          HeroControllerScope(
            controller: _heroes[i],
            child: Navigator(
              key: _shell.navigatorKeys[i],
              pages: [
                for (final screen in _shell.stacks[i])
                  _SpringPage(
                    key: ValueKey('screen ${screen.id}'),
                    name: screen.state.location.toString(),
                    kind: widget.kind,
                    transition:
                        screen.transition ??
                        screen.state.route?.transition ??
                        PageTransition.theme,
                    screen: screen,
                    child: _ScreenHost(
                      navigation: widget.navigation,
                      screen: screen,
                    ),
                  ),
              ],
              onDidRemovePage: (page) {
                if (page case _SpringPage(:final ScreenEntry screen)) {
                  widget.navigation.removed(screen);
                }
              },
            ),
          )
        else
          const SizedBox.shrink(),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.navigation,
    builder: (context, _) => _shell.definition.builder(this),
  );
}

// The plain not-found and error screens, for an app that declares none.
final class _Problem extends StatelessWidget {
  const _Problem(this.state, {required this.error});

  final RouteState state;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final text = error
        ? 'This address cannot be opened: ${state.location}\n${state.error}'
        : 'Nothing is at ${state.location}';
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Color(0xFF202020), fontSize: 16),
          ),
        ),
      ),
    );
  }
}
