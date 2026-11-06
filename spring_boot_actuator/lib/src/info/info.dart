import 'dart:async';

import 'package:spring_boot_actuator/src/endpoint/annotations.dart';

/// What the `info` endpoint shows: free-form details by key (`build`,
/// `git`, `app`, ...).
///
/// Spring Boot (Java): `Info`.
final class Info {
  /// The info of [details].
  Info(Map<String, Object?> details) : details = Map.unmodifiable(details);

  /// The details, as the contributors added them.
  final Map<String, Object?> details;

  /// The detail [key], or `null`.
  Object? get(String key) => details[key];
}

/// Collects the details of the [Info], filled by every [InfoContributor].
///
/// Spring Boot (Java): `Info.Builder`.
final class InfoBuilder {
  final _details = <String, Object?>{};

  /// Adds the detail [key] with [value] (replacing an earlier one).
  InfoBuilder withDetail(String key, Object? value) {
    _details[key] = value;
    return this;
  }

  /// Adds every entry of [details].
  InfoBuilder withDetails(Map<String, Object?> details) {
    _details.addAll(details);
    return this;
  }

  /// The info built so far.
  Info build() => Info(_details);
}

/// Adds details to the `info` endpoint: the version, the build, the
/// commit, anything an operator wants to see.
///
/// Every bean of this type is asked, in `@Order`. The actuator starter
/// declares the `build`, `git`, `env`, `os` and `dart` contributors,
/// switched by `management.info.<id>.enabled`.
///
/// ```dart
/// @Component()
/// class TenantInfoContributor implements InfoContributor {
///   @override
///   void contribute(InfoBuilder builder) =>
///       builder.withDetail('tenants', tenants.count);
/// }
/// ```
///
/// Spring Boot (Java): `InfoContributor`.
abstract interface class InfoContributor {
  /// Adds this contributor's details to [builder].
  FutureOr<void> contribute(InfoBuilder builder);
}

/// The `info` endpoint: `GET /actuator/info` answers the details of every
/// [InfoContributor].
///
/// ```json
/// {"build": {"name": "shop", "version": "1.4.0",
///   "time": "2026-11-05T09:12:44Z"},
///  "git": {"branch": "main", "commit": {"id": "4faa522",
///   "time": "2026-11-04T18:02:11Z"}}}
/// ```
///
/// Spring Boot (Java): `InfoEndpoint`.
@Endpoint(id: 'info')
class InfoEndpoint {
  /// The endpoint of [contributors], asked in order.
  InfoEndpoint(List<InfoContributor> contributors)
    : contributors = List.unmodifiable(contributors);

  /// The contributors.
  final List<InfoContributor> contributors;

  /// The details of every contributor.
  @ReadOperation()
  Future<Map<String, Object?>> info() async {
    final builder = InfoBuilder();
    for (final contributor in contributors) {
      await contributor.contribute(builder);
    }
    return builder.build().details;
  }
}
