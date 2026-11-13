import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The followed state of the app's beans, `spring.flutter.signals.*`.
@ConfigurationProperties('spring.flutter.signals')
final class SignalsProperties {
  /// Settings with these values.
  const SignalsProperties({this.debug = const SignalsDebugProperties()});

  /// The state's tab of the debug panel.
  final SignalsDebugProperties debug;
}

/// The state's tab of the debug panel, `spring.flutter.signals.debug.*`.
final class SignalsDebugProperties {
  /// Settings with these values.
  const SignalsDebugProperties({this.enabled});

  /// Whether the app has the tab: `true` in every build, `false` in none
  /// (the build leaves its code out), not set in debug and profile builds
  /// only (a release build compiles it away).
  final bool? enabled;
}
