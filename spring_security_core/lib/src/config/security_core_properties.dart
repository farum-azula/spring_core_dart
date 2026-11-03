import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.security.password-checks.*` properties: how many password
/// hash checks run and wait at once. Not in Spring Boot.
@ConfigurationProperties('spring.security.password-checks')
class PasswordChecksProperties {
  /// The most password hash checks running at once; more wait in the
  /// queue. Default: half the processors.
  int? maxConcurrent;

  /// The most password checks waiting; more are refused at once. Default:
  /// eight times the checks running at once.
  int? maxQueued;
}
