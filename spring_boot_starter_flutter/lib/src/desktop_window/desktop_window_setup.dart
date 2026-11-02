import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/desktop_window/desktop_window.dart';
import 'package:spring_boot_starter_flutter/src/desktop_window/desktop_window_settings.dart';

/// Reads `spring.flutter.desktop.window.*` once the application's
/// environment is ready (as the SQLite directories are) and applies it to
/// the native window with one call of the plugin's method channel.
///
/// An invalid value fails the start (the listener throws). On the web and
/// on a phone nothing is read: the keys are desktop-only, and one set there
/// is ignored.
///
/// Internal to the starter.
final class DesktopWindowSetup {
  /// A setup that applies through [apply] (the plugin's channel by
  /// default) where [supported] says there is a desktop window.
  DesktopWindowSetup({
    bool? supported,
    Future<DesktopWindowInsets> Function(DesktopWindowSettings)? apply,
  }) : _supported = supported ?? DesktopWindowChannel.isSupported,
       _apply = apply ?? DesktopWindowChannel.apply;

  static const _timeout = Duration(seconds: 5);
  static const _log = SpringLog('spring_boot_starter_flutter.DesktopWindow');

  final bool _supported;
  final Future<DesktopWindowInsets> Function(DesktopWindowSettings) _apply;
  final _ready = Completer<void>();
  final _provided = Expando<bool>('DesktopWindowSetup provided');

  Future<void> _pending = Future.value();
  DesktopWindowSettings? _applied;
  DesktopWindowData _data = DesktopWindowData.none;

  /// Whether there is a window to set up on this platform.
  bool get isSupported => _supported;

  /// Completes once the window is set (or there is nothing to set, or the
  /// start ended before the environment was ready): the first frame may be
  /// shown.
  Future<void> get ready => _ready.future;

  /// The window as applied so far.
  DesktopWindowData get data => _data;

  /// Makes [application] read and apply the properties once its
  /// environment is ready. Calling it twice on the same one does nothing.
  void provideTo(SpringApplication application) {
    if (!_supported || (_provided[application] ?? false)) {
      return;
    }
    _provided[application] = true;
    application.addListener<ApplicationEnvironmentPreparedEvent>(
      (event) => prepare(event.environment),
    );
  }

  /// Reads the properties of [environment] and starts applying them;
  /// throws for an invalid value.
  void prepare(Environment environment) {
    final settings = DesktopWindowSettings.fromEnvironment(environment);
    if (settings.isEmpty || settings.toString() == _applied?.toString()) {
      _complete();
      return;
    }
    _applied = settings;
    _log.debug(() => 'Applying $settings');
    _pending = _applyTo(settings);
    unawaited(_pending.whenComplete(_complete));
  }

  Future<void> _applyTo(DesktopWindowSettings settings) async {
    try {
      // The first frame waits for this: a plugin that never answers must
      // not leave the window blank.
      final insets = await _apply(settings).timeout(_timeout);
      _data = DesktopWindowData(titleBar: settings.titleBar, insets: insets);
    } on Object catch (error) {
      // The window stays as the runner made it; the app runs.
      _log.warning(() => 'The window could not be set up: $error');
    }
  }

  /// Waits for the window to be set and answers it; also lets the first
  /// frame go when the start ended without an environment (a failure).
  Future<DesktopWindowData> settle() async {
    await _pending;
    _complete();
    return _data;
  }

  void _complete() {
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }
}
