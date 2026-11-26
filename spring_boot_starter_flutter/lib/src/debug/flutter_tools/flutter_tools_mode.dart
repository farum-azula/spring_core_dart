import 'package:flutter/foundation.dart';

/// The build the app runs in, as the Flutter tab of the debug panel sees
/// it: what Flutter's debug tools can do here.
@immutable
final class FlutterToolsMode {
  /// A build named [build], [debug] or not, on the [web] or not.
  const FlutterToolsMode({
    required this.build,
    required this.debug,
    required this.web,
  });

  /// The running app's build.
  static const FlutterToolsMode current = FlutterToolsMode(
    build: kDebugMode
        ? 'debug'
        : kProfileMode
        ? 'profile'
        : 'release',
    debug: kDebugMode,
    web: kIsWeb,
  );

  /// `debug`, `profile` or `release`.
  final String build;

  /// Whether Flutter's debug checks and `debugPaint*` flags are compiled in.
  final bool debug;

  /// Whether the app runs in a browser.
  final bool web;
}

/// What a tool of the Flutter tab needs from the build: asked in order,
/// the first unmet one names why the tool is off.
abstract interface class FlutterToolRequirement {
  /// Why the tool cannot work in [mode], `null` when it can.
  String? unmetIn(FlutterToolsMode mode);
}

/// A debug build: Flutter compiles the tool's code out of profile and
/// release builds.
final class DebugBuildRequirement implements FlutterToolRequirement {
  /// The requirement.
  const DebugBuildRequirement();

  @override
  String? unmetIn(FlutterToolsMode mode) => mode.debug
      ? null
      : 'Debug builds only: Flutter leaves it out of a ${mode.build} build.';
}

/// Not in a browser, for [reason].
final class NotOnWebRequirement implements FlutterToolRequirement {
  /// The requirement, unmet on the web for [reason].
  const NotOnWebRequirement(this.reason);

  /// Why the web lacks it.
  final String reason;

  @override
  String? unmetIn(FlutterToolsMode mode) => mode.web ? reason : null;
}

/// Why a tool needing [requirements] cannot work in [mode]: the first
/// unmet requirement's reason, `null` when every one is met.
String? unmetRequirement(
  List<FlutterToolRequirement> requirements,
  FlutterToolsMode mode,
) => requirements.map((r) => r.unmetIn(mode)).nonNulls.firstOrNull;
