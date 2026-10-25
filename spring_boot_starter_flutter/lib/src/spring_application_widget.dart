import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/app_lifecycle.dart';
import 'package:spring_boot_starter_flutter/src/asset_resource.dart';
import 'package:spring_boot_starter_flutter/src/platform_profiles.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/spring_widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The root widget of a Spring app: starts the application, shows [splash]
/// until it is ready (runners included) or [failure] when the start
/// fails, then gives the context to its widgets (`context.bean<T>()`,
/// generated getters, `SpringStatelessWidget`).
///
/// With [home] it also builds the app widget from the configuration
/// ([SpringApp]: `WidgetsApp`, `MaterialApp` or `CupertinoApp` by
/// `spring.flutter.app.type`, title, debug banner, locales, theme beans);
/// with [child] the app builds its own:
///
/// ```dart
/// import 'main.spring.dart';
///
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(application: () => springApplication, home: const CounterPage()),
/// );
/// ```
///
/// [application] returns the generated `springApplication` (a function, so
/// a hot reload gets the new beans). Around the start:
///
/// - the platform's profiles are active ([platformProfiles]: `android` +
///   `mobile`, `web`, `macos` + `desktop`, ...), so
///   `application-android.properties` and `@Profile(['ios'])` beans just
///   work;
/// - the OS environment is not read (on a phone it is noise; values come
///   from `--dart-define`), unless the build defines
///   `spring.flutter.scan-os-environment=true`;
/// - a hot reload restarts the context when the generated code changed
///   (new or changed beans, annotations, `lib/resources/`), like Spring Boot
///   DevTools' restart, and rebuilds [child] from scratch; when only method
///   bodies changed the context and the beans' state stay (see the README,
///   *Hot reload*). [rerunRunnersOnReload] runs `ApplicationRunner`s again
///   after such a restart; `spring.devtools.restart.enabled=false` turns
///   the restarts off;
/// - the app's lifecycle states are published as
///   [AppLifecycleStateEvent]s; in the background the context is paused
///   (`@Scheduled` tasks and WebSocket connections stop) and restarted when
///   the app comes back, unless
///   `spring.flutter.lifecycle.pause-in-background=false`;
/// - the context is closed when this widget is removed.
class SpringApplicationWidget extends StatefulWidget {
  /// Runs the application [application] returns, then shows [home] in a
  /// [SpringApp] or [child]: exactly one of them.
  const SpringApplicationWidget({
    required this.application,
    this.child,
    this.home,
    this.splash,
    this.failure,
    this.args = const [],
    this.rerunRunnersOnReload = false,
    super.key,
  }) : assert(
         (child == null) != (home == null),
         'SpringApplicationWidget needs a home or a child, not both',
       );

  /// The application to run: `() => springApplication` (generated).
  final SpringApplication Function() application;

  /// The app, shown once the application has started; it builds its own
  /// app widget (`MaterialApp`, ...).
  final Widget? child;

  /// The first page of a [SpringApp] built from the configuration, shown
  /// once the application has started.
  final Widget? home;

  /// Shown while the application starts (nothing by default).
  final WidgetBuilder? splash;

  /// Shown when the start (or a restart after a hot reload) fails; by
  /// default the error on a plain screen. The failure is logged either way.
  final Widget Function(BuildContext context, Object error)? failure;

  /// Command-line arguments (`--name=value` properties), for desktop apps
  /// started with some.
  final List<String> args;

  /// Whether `ApplicationRunner` / `CommandLineRunner` beans run again
  /// when a hot reload restarts the context (Spring Boot DevTools does);
  /// off by default: the app did not really start again.
  final bool rerunRunnersOnReload;

  @override
  State<SpringApplicationWidget> createState() =>
      _SpringApplicationWidgetState();
}

class _SpringApplicationWidgetState extends State<SpringApplicationWidget> {
  ConfigurableApplicationContext? _context;
  Object? _error;
  late final AppLifecycleListener _lifecycle;
  bool _paused = false;
  Future<void> _lifecycleWork = Future.value();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // `asset:` resources: exists() needs the asset manifest.
      await AssetProtocolResolver.loadRootManifest();
      final application = widget.application();
      final context = await application.runAsync(
        widget.args,
        systemEnvironment: _scanOsEnvironment(application) ? null : const {},
        additionalProfiles: platformProfiles(),
      );
      SpringWidgetBindings.check(context);
      _checkApp(context);
      if (!mounted) {
        await context.closeAsync();
        return;
      }
      setState(() => _context = context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  // An invalid `spring.flutter.app.*` value fails the start.
  void _checkApp(ApplicationContext context) {
    if (widget.home != null) {
      FlutterAppSettings.of(context);
    }
  }

  static bool _scanOsEnvironment(SpringApplication application) {
    final defines = application.dartDefines;
    final value =
        defines['spring.flutter.scan-os-environment'] ??
        defines['SPRING_FLUTTER_SCANOSENVIRONMENT'];
    return value?.trim().toLowerCase() == 'true';
  }

  @override
  void reassemble() {
    super.reassemble();
    final running = _context;
    if (running == null) {
      if (_error != null) {
        // The start failed: try again with the reloaded code.
        setState(() => _error = null);
        unawaited(_start());
      }
      return;
    }
    if (!_restartEnabled(running)) {
      return;
    }
    try {
      final context = widget.application().reload(
        running,
        runners: widget.rerunRunnersOnReload,
      );
      if (!identical(context, running)) {
        SpringWidgetBindings.check(context);
        _checkApp(context);
        _paused = false;
        setState(() => _context = context);
      }
    } catch (error) {
      setState(() {
        _context = null;
        _error = error;
      });
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    final context = _context;
    if (context == null || !context.isActive) {
      return;
    }
    context.publishEvent(AppLifecycleStateEvent(context, state));
    final pause =
        state == AppLifecycleState.hidden || state == AppLifecycleState.paused;
    if ((!pause && state != AppLifecycleState.resumed) ||
        pause == _paused ||
        !_pauseInBackground(context)) {
      return;
    }
    _paused = pause;
    _lifecycleWork = _lifecycleWork.then((_) async {
      if (!context.isActive) {
        return;
      }
      try {
        if (pause) {
          await context.pauseAsync();
        } else {
          context.restart();
        }
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'spring_boot_starter_flutter',
            context: ErrorDescription(
              pause
                  ? 'while pausing the application context'
                  : 'while restarting the application context',
            ),
          ),
        );
      }
    });
  }

  // Spring Boot DevTools' switch for restarts after code changes.
  static bool _restartEnabled(ConfigurableApplicationContext context) =>
      context.environment
          .getProperty('spring.devtools.restart.enabled')
          ?.trim()
          .toLowerCase() !=
      'false';

  static bool _pauseInBackground(ConfigurableApplicationContext context) =>
      context.environment
          .getProperty('spring.flutter.lifecycle.pause-in-background')
          ?.trim()
          .toLowerCase() !=
      'false';

  @override
  void dispose() {
    _lifecycle.dispose();
    final context = _context;
    _context = null;
    if (context != null && context.isActive) {
      unawaited(context.closeAsync());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.failure?.call(context, error) ?? _Failure(error);
    }
    final running = _context;
    if (running == null) {
      return widget.splash?.call(context) ?? const SizedBox.shrink();
    }
    return SpringScope(
      applicationContext: running,
      // A new context starts the widgets afresh: none keeps a bean of the
      // closed one in its state.
      child: KeyedSubtree(
        key: ObjectKey(running),
        child: widget.child ?? SpringApp(home: widget.home!),
      ),
    );
  }
}

/// The default failure screen: the error in debug builds, a short note in
/// release builds (the details are in the log).
class _Failure extends StatelessWidget {
  const _Failure(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              kReleaseMode
                  ? 'The application failed to start.'
                  : 'The application failed to start:\n\n$error',
              style: const TextStyle(color: Color(0xFF000000), fontSize: 14),
            ),
          ),
        ),
      ),
    ),
  );
}
