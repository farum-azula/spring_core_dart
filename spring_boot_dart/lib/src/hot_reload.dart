import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _log = SpringLog('spring_boot_dart.devtools.RestartApplicationListener');

/// Restarts a running server or command-line application when its beans
/// change during a hot reload on the Dart VM.
///
/// A VM hot reload swaps method bodies in place, but it does not run
/// `main` again: a new bean, a new `@GetMapping` or a changed config file
/// would not take effect, because the context was built from the old
/// generated code. This class closes such a context and starts the
/// application again, with the same arguments, from the new generated
/// code. When only method bodies changed, the context keeps running and
/// its beans keep their state.
///
/// Applications do nothing to get it: the generated `runApplication` and
/// `runApplicationAsync` register their context. The development tool
/// that reloads the program calls it: after the VM's `reloadSources`, it
/// calls the VM service extension [extensionName]. The `dart run` tasks of
/// the Zed extensions do this on save (`dart --enable-vm-service ...
/// bin/main.dart`, then `build_runner build`, `reloadSources` and
/// [extensionName]).
///
/// It only works in debug runs on the Dart VM. In an AOT or product build
/// and on the web it does nothing, and in Flutter the root widget
/// restarts the context itself when Flutter hot reloads.
///
/// To keep a context running whatever changed (the server, its open
/// connections and the beans' state then live until the program
/// restarts), set:
///
/// ```properties
/// spring.devtools.restart.enabled=false
/// ```
///
/// Spring (Java): the restart of Spring Boot DevTools, which reacts to
/// class files changing on disk instead of a service call.
abstract final class SpringHotReload {
  /// The name of the VM service extension a development tool calls after
  /// `reloadSources`.
  ///
  /// It runs [reloadAll] and answers `{"restarted": <count>}`, or a
  /// service extension error when a restart fails (the failure is logged
  /// too).
  static const extensionName = 'ext.spring_boot.reload';

  static const bool _enabled =
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.library.ui') &&
      !bool.fromEnvironment('dart.library.js_interop');

  static final _tracked =
      <(ConfigurableApplicationContext, SpringApplication Function())>[];
  // Contexts closed by a restart whose new start failed: the next reload
  // starts them again (with their arguments) instead of forgetting them.
  static final _failed = Set<ConfigurableApplicationContext>.identity();
  static var _registered = false;

  /// Whether restarts on hot reload are possible in this program: true in
  /// a debug run on the Dart VM, false in AOT and product builds, on the
  /// web and in Flutter. When false, [track] does nothing.
  static bool get isEnabled => _enabled;

  /// Registers [context] for restarts on hot reload.
  ///
  /// [application] must return the application as the code is now: the
  /// generated `springApplication` getter, which after a reload builds the
  /// new beans. `SpringApplication.run(hotReload:)` calls this, so code
  /// that uses the generated `runApplication` never does. The first call
  /// also registers [extensionName]. Contexts that were closed in the
  /// meantime are forgotten.
  static void track(
    ConfigurableApplicationContext context,
    SpringApplication Function() application,
  ) {
    if (!_enabled) {
      return;
    }
    _tracked
      ..removeWhere((entry) => !_isTracked(entry.$1))
      ..add((context, application));
    if (!_registered) {
      _registered = true;
      try {
        developer.registerExtension(extensionName, _handle);
      } on ArgumentError {
        // Registered already (another copy of this library).
      }
    }
  }

  /// Restarts every registered context whose generated code changed and
  /// returns how many were restarted.
  ///
  /// Each restart goes through [SpringApplication.reloadAsync], so the old
  /// context is closed (its asynchronous destroy callbacks awaited) before
  /// the new one starts, and the runners run again. Closed contexts and
  /// those with `spring.devtools.restart.enabled=false` are skipped. The
  /// extension [extensionName] calls this; a test can call it directly. A
  /// failing restart throws; the application is then started again at
  /// the next reload (once the code is fixed), as DevTools restarts at
  /// the next change.
  static Future<int> reloadAll() async {
    var restarted = 0;
    for (var i = 0; i < _tracked.length; i++) {
      final (context, application) = _tracked[i];
      if (!_isTracked(context) || !_restartEnabled(context)) {
        continue;
      }
      final ConfigurableApplicationContext next;
      try {
        next = await application().reloadAsync(context);
      } on Object {
        // The old context is closed (reloadAsync closed it before the new
        // start failed): keep it, to start the application again from
        // its arguments next time.
        if (!context.isActive) {
          _failed.add(context);
        }
        rethrow;
      }
      _failed.remove(context);
      if (!identical(next, context)) {
        restarted++;
        _tracked[i] = (next, application);
        _log.info('Restarted the application: its generated code changed');
      }
    }
    _tracked.removeWhere((entry) => !_isTracked(entry.$1));
    return restarted;
  }

  static bool _isTracked(ConfigurableApplicationContext context) =>
      context.isActive || _failed.contains(context);

  // Spring Boot DevTools' switch for restarts after code changes.
  static bool _restartEnabled(ConfigurableApplicationContext context) =>
      context.environment
          .getProperty('spring.devtools.restart.enabled')
          ?.trim()
          .toLowerCase() !=
      'false';

  static Future<developer.ServiceExtensionResponse> _handle(
    String method,
    Map<String, String> parameters,
  ) async {
    try {
      final restarted = await reloadAll();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'restarted': restarted}),
      );
    } on Object catch (error, stackTrace) {
      _log.error(
        'Restarting the application after a hot reload failed',
        error: error,
        stackTrace: stackTrace,
      );
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        '$error',
      );
    }
  }
}
