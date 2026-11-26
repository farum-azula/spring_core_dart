import 'package:spring_core_dart/spring_core_dart.dart';

// The keys only the generator reads, when it writes the application. They
// are described here for the editors (`spring_gen/spring_metadata.json` is
// read from every library of `lib/`) and bound by nothing: this file is
// outside the `@ComponentScan` of `properties/`, so no module binds it, and
// an application carries no code for a key it never reads at run time.

/// The starters' startup checks: `spring.main.startup-checks.*`.
///
/// The generator reads the key from `application.yml` or
/// `application.properties` (without a profile) when it writes the
/// application, and leaves the startup checks' modules in or out of the
/// build. At run time, `false` (on the command line, in the environment,
/// in a profile) turns off the checks the build kept
/// (`startupChecksEnabled`). The class describes the key for editors; it
/// is abstract, so it is no bean either.
@ConfigurationProperties('spring.main.startup-checks')
abstract final class MainStartupChecksProperties {
  /// Whether the starters' startup checks are in the build (the
  /// `@Transactional` and cache annotations checked when the beans are
  /// created, the explanations of a database that fails the start, the
  /// edge starter's warning list): `true` in every build, `false` in none.
  /// Default: in debug builds only, so a profile or a release build ships
  /// none of their code and its mistakes fail at the first call. Read by
  /// the generator.
  bool? enabled;
}
