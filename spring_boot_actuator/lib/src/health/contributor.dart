import 'dart:async';

import 'package:spring_boot_actuator/src/health/health.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring.boot.actuate.health.AbstractHealthIndicator');

/// Something that tells the health of a part of the application: a
/// [HealthIndicator] for one part, a [CompositeHealthContributor] for
/// several under one name.
///
/// Every bean of this type is in the health report, under its bean name
/// without the suffix `HealthIndicator` or `HealthContributor`
/// (`diskSpaceHealthIndicator` is `diskSpace`).
///
/// Spring Boot (Java): `HealthContributor`.
sealed class HealthContributor {}

/// Tells the health of one part of the application: a database, a queue,
/// a service it calls.
///
/// Declare a bean that implements it, and its [health] is part of
/// `/actuator/health`. Ask quickly: the report waits for every indicator.
/// An indicator that throws reports `DOWN` with the error. Extend
/// [AbstractHealthIndicator] to have that done for you.
///
/// ```dart
/// // In the report as "inbox".
/// @Component()
/// class InboxHealthIndicator implements HealthIndicator {
///   InboxHealthIndicator(this.inbox);
///   final Inbox inbox;
///
///   @override
///   Future<Health> health() async => await inbox.ping()
///       ? Health.up().withDetail('pending', inbox.pending).build()
///       : Health.down().build();
/// }
/// ```
///
/// Spring Boot (Java): `HealthIndicator` and `ReactiveHealthIndicator`
/// together: [health] may answer now or later.
abstract class HealthIndicator implements HealthContributor {
  /// The health of the part, now or later.
  FutureOr<Health> health();
}

/// A [HealthIndicator] whose check fills a builder, and whose errors
/// become a `DOWN` with the error as detail (logged as a warning).
///
/// ```dart
/// @Component()
/// class QueueHealthIndicator extends AbstractHealthIndicator {
///   QueueHealthIndicator(this.queue);
///   final Queue queue;
///
///   @override
///   Future<void> doHealthCheck(HealthBuilder builder) async {
///     builder.up().withDetail('size', await queue.size());
///   }
/// }
/// ```
///
/// Spring Boot (Java): `AbstractHealthIndicator`.
abstract class AbstractHealthIndicator extends HealthIndicator {
  /// An indicator whose failures are logged with [healthCheckFailedMessage]
  /// (a generic text by default).
  AbstractHealthIndicator([this.healthCheckFailedMessage]);

  /// The warning logged when the check fails.
  final String? healthCheckFailedMessage;

  /// Checks the part and fills [builder]: its status and details.
  FutureOr<void> doHealthCheck(HealthBuilder builder);

  @override
  Future<Health> health() async {
    final builder = HealthBuilder();
    try {
      await doHealthCheck(builder);
    } on Object catch (error, stackTrace) {
      _log.warning(
        healthCheckFailedMessage ?? 'Health check failed',
        error: error,
        stackTrace: stackTrace,
      );
      builder.down(error);
    }
    return builder.build();
  }
}

/// Several [HealthContributor]s under one name: the report shows each
/// under its own name and their aggregated status.
///
/// The data starter's `db` is one when the application has several data
/// sources: `db.primary`, `db.reporting`.
///
/// ```dart
/// CompositeHealthContributor.fromMap({
///   'primary': DataSourceHealthIndicator(primary),
///   'reporting': DataSourceHealthIndicator(reporting),
/// })
/// ```
///
/// Spring Boot (Java): `CompositeHealthContributor`.
abstract class CompositeHealthContributor implements HealthContributor {
  /// A composite of [contributors], by name.
  factory CompositeHealthContributor.fromMap(
    Map<String, HealthContributor> contributors,
  ) = _MapCompositeHealthContributor;

  /// The contributor [name], or `null`.
  HealthContributor? getContributor(String name);

  /// The names of the contributors, in order.
  Iterable<String> get names;
}

final class _MapCompositeHealthContributor
    implements CompositeHealthContributor {
  _MapCompositeHealthContributor(Map<String, HealthContributor> contributors)
    : _contributors = Map.unmodifiable(contributors);

  final Map<String, HealthContributor> _contributors;

  @override
  HealthContributor? getContributor(String name) => _contributors[name];

  @override
  Iterable<String> get names => _contributors.keys;
}

/// The name of the health contributor bean [beanName] in the report: the
/// name without the suffix `HealthIndicator` or `HealthContributor` (in
/// any case).
///
/// ```dart
/// healthContributorName('diskSpaceHealthIndicator'); // diskSpace
/// ```
///
/// Spring Boot (Java): `HealthContributorNameFactory`.
String healthContributorName(String beanName) {
  for (final suffix in const ['healthindicator', 'healthcontributor']) {
    if (beanName.length > suffix.length &&
        beanName.toLowerCase().endsWith(suffix)) {
      return beanName.substring(0, beanName.length - suffix.length);
    }
  }
  return beanName;
}

/// The health contributors of the application, by name, to which code can
/// add contributors while it runs.
///
/// The actuator starter declares one with the [HealthContributor] beans;
/// inject it to add a contributor known only at run time (a tenant's
/// database).
///
/// ```dart
/// registry.registerContributor('tenant-42', DataSourceHealthIndicator(ds));
/// ```
///
/// Spring Boot (Java): `HealthContributorRegistry`.
abstract interface class HealthContributorRegistry
    implements CompositeHealthContributor {
  /// Adds [contributor] as [name]. Throws a [StateError] when the name is
  /// taken.
  void registerContributor(String name, HealthContributor contributor);

  /// Removes the contributor [name] and returns it, or `null` when there
  /// was none.
  HealthContributor? unregisterContributor(String name);
}

/// The default [HealthContributorRegistry]: the contributors in a map, in
/// the order they were added.
///
/// Spring Boot (Java): `DefaultHealthContributorRegistry`.
final class DefaultHealthContributorRegistry
    implements HealthContributorRegistry {
  /// A registry of [contributors].
  DefaultHealthContributorRegistry([
    Map<String, HealthContributor> contributors = const {},
  ]) {
    contributors.forEach(registerContributor);
  }

  final _contributors = <String, HealthContributor>{};

  @override
  void registerContributor(String name, HealthContributor contributor) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (_contributors.containsKey(name)) {
      throw StateError(
        "A health contributor named '$name' has already been registered",
      );
    }
    _contributors[name] = contributor;
  }

  @override
  HealthContributor? unregisterContributor(String name) =>
      _contributors.remove(name);

  @override
  HealthContributor? getContributor(String name) => _contributors[name];

  @override
  Iterable<String> get names => List.unmodifiable(_contributors.keys);
}

/// Combines the statuses of several parts into one: the first of them in
/// an order of severity.
///
/// Spring Boot (Java): `StatusAggregator`.
abstract interface class StatusAggregator {
  /// The default aggregator: `DOWN`, `OUT_OF_SERVICE`, `UP`, `UNKNOWN`.
  static const StatusAggregator defaults = SimpleStatusAggregator();

  /// The status of the parts with [statuses]; `UNKNOWN` for none.
  Status getAggregateStatus(Iterable<Status> statuses);
}

/// A [StatusAggregator] by an [order] of status codes: the aggregate is
/// the status that comes first. Codes are compared in upper case without
/// other characters than letters and digits (`out-of-service` is
/// `OUT_OF_SERVICE`); statuses not in the order are left out.
///
/// ```properties
/// management.endpoint.health.status.order=fatal,down,out-of-service,unknown,up
/// ```
///
/// Spring Boot (Java): `SimpleStatusAggregator`.
final class SimpleStatusAggregator implements StatusAggregator {
  /// An aggregator by [order]; Spring Boot's default order when it is
  /// empty.
  const SimpleStatusAggregator([this.order = defaultOrder]);

  /// An aggregator by the codes of [order] (`management.endpoint.health.
  /// status.order`); the default order when it is empty.
  factory SimpleStatusAggregator.of(List<String> order) =>
      SimpleStatusAggregator(
        order.isEmpty ? defaultOrder : [for (final code in order) code],
      );

  /// `DOWN`, `OUT_OF_SERVICE`, `UP`, `UNKNOWN`.
  static const defaultOrder = ['DOWN', 'OUT_OF_SERVICE', 'UP', 'UNKNOWN'];

  /// The codes, most severe first.
  final List<String> order;

  int _index(Status status) {
    final code = uniformCode(status.code);
    for (var i = 0; i < order.length; i++) {
      if (uniformCode(order[i]) == code) {
        return i;
      }
    }
    return -1;
  }

  @override
  Status getAggregateStatus(Iterable<Status> statuses) {
    Status? best;
    var bestIndex = -1;
    for (final status in statuses) {
      final index = _index(status);
      if (index < 0) {
        continue;
      }
      if (best == null ||
          index < bestIndex ||
          (index == bestIndex && status.code.compareTo(best.code) < 0)) {
        best = status;
        bestIndex = index;
      }
    }
    return best ?? Status.unknown;
  }

  /// [code] in upper case, letters and digits only.
  static String uniformCode(String code) =>
      code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}

/// The HTTP status of a health status: what a load balancer or Kubernetes
/// reads from `/actuator/health`.
///
/// Spring Boot (Java): `HttpCodeStatusMapper`.
abstract interface class HttpCodeStatusMapper {
  /// `DOWN` and `OUT_OF_SERVICE` are `503`, every other status `200`.
  static const HttpCodeStatusMapper defaults = SimpleHttpCodeStatusMapper();

  /// The HTTP status of [status].
  int getStatusCode(Status status);
}

/// An [HttpCodeStatusMapper] by a map of status codes (compared as by
/// [SimpleStatusAggregator.uniformCode]); `200` for a status it does not
/// name.
///
/// ```properties
/// management.endpoint.health.status.http-mapping.down=500
/// ```
///
/// Spring Boot (Java): `SimpleHttpCodeStatusMapper`.
final class SimpleHttpCodeStatusMapper implements HttpCodeStatusMapper {
  /// A mapper of [mappings]; Spring Boot's (`DOWN` and `OUT_OF_SERVICE`
  /// are `503`) when it is empty.
  const SimpleHttpCodeStatusMapper([this.mappings = const {}]);

  /// The HTTP status by health status code; empty for the defaults.
  final Map<String, int> mappings;

  static const _defaults = {'DOWN': 503, 'OUTOFSERVICE': 503};

  @override
  int getStatusCode(Status status) {
    final code = SimpleStatusAggregator.uniformCode(status.code);
    if (mappings.isEmpty) {
      return _defaults[code] ?? 200;
    }
    for (final MapEntry(:key, :value) in mappings.entries) {
      if (SimpleStatusAggregator.uniformCode(key) == code) {
        return value;
      }
    }
    return 200;
  }
}
