import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _log = SpringLog('spring_boot_dart.devtools.RestartApplicationListener');

/// Hot reload of an application running on the Dart VM, like Spring Boot
/// DevTools' restart: after the VM reloaded the code (a tool calls
/// `reloadSources`), the tool calls the service extension
/// [extensionName]; contexts whose generated code changed (new or changed
/// beans, annotations, `lib/resources/`) are closed and started again with
/// the same arguments, the others keep running with the new method bodies.
///
/// `spring.devtools.restart.enabled=false` (Spring Boot DevTools' switch)
/// keeps a context running whatever changed: the server, its connections
/// and the beans' state live until the program restarts.
///
/// The generated `runApplication` / `runApplicationAsync` register their
/// context. Only in debug runs on the Dart VM: not in an AOT or product
/// build, not on the web, and not in Flutter, whose root widget restarts
/// the context itself when Flutter hot reloads.
///
/// The `dart run` tasks of the Zed extensions reload on save this way:
/// `dart --enable-vm-service ... bin/main.dart`, then after a change
/// `build_runner build`, `reloadSources` and [extensionName].
abstract final class SpringHotReload {
  /// The service extension a tool calls after `reloadSources`; it answers
  /// `{"restarted": <number of restarted contexts>}`.
  static const extensionName = 'ext.spring_boot.reload';

  static const bool _enabled =
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.library.ui') &&
      !bool.fromEnvironment('dart.library.js_interop');

  static final _tracked =
      <(ConfigurableApplicationContext, SpringApplication Function())>[];
  static var _registered = false;

  /// Whether hot reload is available in this program.
  static bool get isEnabled => _enabled;

  /// Restarts [context] with the application [application] returns (the
  /// generated `springApplication`, up to date after a reload) when its
  /// generated code changed.
  static void track(
    ConfigurableApplicationContext context,
    SpringApplication Function() application,
  ) {
    if (!_enabled) {
      return;
    }
    _tracked
      ..removeWhere((entry) => !entry.$1.isActive)
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

  /// Restarts the tracked contexts whose generated code changed, unless
  /// `spring.devtools.restart.enabled=false`; the number restarted.
  static Future<int> reloadAll() async {
    var restarted = 0;
    for (var i = 0; i < _tracked.length; i++) {
      final (context, application) = _tracked[i];
      if (!context.isActive || !_restartEnabled(context)) {
        continue;
      }
      final next = await application().reloadAsync(context);
      if (!identical(next, context)) {
        restarted++;
        _tracked[i] = (next, application);
        _log.info('Restarted the application: its generated code changed');
      }
    }
    _tracked.removeWhere((entry) => !entry.$1.isActive);
    return restarted;
  }

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
