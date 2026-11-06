import 'dart:async';

import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_boot_actuator/src/health/contributor.dart';
import 'package:spring_boot_actuator/src/health/groups.dart';
import 'package:spring_boot_actuator/src/health/health.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring.boot.actuate.health.HealthEndpointSupport');

/// What builds a health report: the contributors of the [registry], the
/// [groups] and their rules. [HealthEndpoint] and
/// [HealthEndpointWebExtension] share it.
///
/// Spring Boot (Java): `HealthEndpointSupport`.
abstract class HealthEndpointSupport {
  /// The report of [registry] by [groups]; an indicator slower than
  /// [slowIndicatorLoggingThreshold] is logged as a warning.
  HealthEndpointSupport(
    this.registry,
    this.groups, {
    this.slowIndicatorLoggingThreshold = const Duration(seconds: 10),
  });

  /// The contributors.
  final HealthContributorRegistry registry;

  /// The primary group and the named groups.
  final HealthEndpointGroups groups;

  /// The time after which an indicator is logged as slow
  /// (`management.endpoint.health.logging.slow-indicator-threshold`).
  final Duration? slowIndicatorLoggingThreshold;

  /// The report at [path] for a request of [securityContext], with the
  /// group that decides its HTTP status; `null` when there is nothing at
  /// [path] or the user may not see it.
  ///
  /// An empty [path] is the whole report; `[name]` a group or a
  /// contributor; longer paths a contributor inside a group or a
  /// composite. With [showAll] the details and components are shown
  /// whatever the group says.
  Future<(HealthDescriptor, HealthEndpointGroup)?> getHealth(
    ApiVersion apiVersion,
    SecurityContext securityContext,
    List<String> path, {
    bool showAll = false,
  }) async {
    if (path.isNotEmpty) {
      if (groups.get(path.first) case final group?) {
        return await _result(
          apiVersion,
          group,
          securityContext,
          showAll,
          path,
          1,
        );
      }
    }
    return await _result(
      apiVersion,
      groups.primary,
      securityContext,
      showAll,
      path,
      0,
    );
  }

  Future<(HealthDescriptor, HealthEndpointGroup)?> _result(
    ApiVersion apiVersion,
    HealthEndpointGroup group,
    SecurityContext securityContext,
    bool showAll,
    List<String> path,
    int offset,
  ) async {
    final showComponents = showAll || group.showComponents(securityContext);
    final showDetails = showAll || group.showDetails(securityContext);
    final isSystemHealth = identical(group, groups.primary) && offset == 0;
    final isRoot = path.length == offset;
    if (!showComponents && !isRoot) {
      return null;
    }
    final name = path.sublist(offset).join('/');
    // A part of a group must be one of its members.
    if (!isRoot && !group.isMember(name)) {
      return null;
    }
    HealthContributor? contributor = registry;
    for (final segment in path.skip(offset)) {
      contributor = switch (contributor) {
        final CompositeHealthContributor composite => composite.getContributor(
          segment,
        ),
        _ => null,
      };
      if (contributor == null) {
        return null;
      }
    }
    final health = await _contribution(
      apiVersion,
      group,
      name,
      contributor!,
      showComponents: showComponents,
      showDetails: showDetails,
      groupNames: isSystemHealth ? groups.names : null,
    );
    return health == null ? null : (health, group);
  }

  Future<HealthDescriptor?> _contribution(
    ApiVersion apiVersion,
    HealthEndpointGroup group,
    String name,
    HealthContributor contributor, {
    required bool showComponents,
    required bool showDetails,
    List<String>? groupNames,
  }) async {
    switch (contributor) {
      case final HealthIndicator indicator:
        final health = await _health(name, indicator);
        return showDetails ? health : health.withoutDetails();
      case final CompositeHealthContributor composite:
        final prefix = name.isEmpty ? '' : '$name/';
        final names = [
          for (final child in composite.names)
            if (group.isMember('$prefix$child')) child,
        ];
        final results = await Future.wait([
          for (final child in names)
            switch (composite.getContributor(child)) {
              final part? => _contribution(
                apiVersion,
                group,
                '$prefix$child',
                part,
                showComponents: showComponents,
                showDetails: showDetails,
              ),
              null => Future<HealthDescriptor?>.value(),
            },
        ]);
        final contributions = <String, HealthDescriptor>{
          for (final (index, child) in names.indexed) child: ?results[index],
        };
        if (contributions.isEmpty) {
          return null;
        }
        final status = group.statusAggregator.getAggregateStatus(
          contributions.values.map((c) => c.status),
        );
        final components = showComponents ? contributions : null;
        return groupNames != null
            ? SystemHealthDescriptor(
                status,
                components,
                groups: groupNames,
                apiVersion: apiVersion,
              )
            : CompositeHealthDescriptor(
                status,
                components,
                apiVersion: apiVersion,
              );
    }
  }

  // The indicator's health; an indicator that throws is DOWN with the
  // error (Spring Boot lets the error fail the request).
  Future<Health> _health(String name, HealthIndicator indicator) async {
    final watch = Stopwatch()..start();
    try {
      return await indicator.health();
    } on Object catch (error, stackTrace) {
      _log.warning(
        "Health indicator '$name' failed",
        error: error,
        stackTrace: stackTrace,
      );
      return Health.down().withException(error).build();
    } finally {
      final threshold = slowIndicatorLoggingThreshold;
      if (threshold != null && watch.elapsed > threshold) {
        _log.warning(
          'Health contributor ${indicator.runtimeType} ($name) took '
          '${watch.elapsedMilliseconds}ms to respond',
        );
      }
    }
  }
}

/// The `health` endpoint: whether the application works, from every
/// health contributor, aggregated into one status.
///
/// Over HTTP its [HealthEndpointWebExtension] answers; this endpoint
/// itself shows everything (it is what code in the application asks).
///
/// ```dart
/// final health = await context.getBean<HealthEndpoint>().health();
/// print(health?.status); // UP
/// ```
///
/// Spring Boot (Java): `HealthEndpoint`.
@Endpoint(id: 'health')
class HealthEndpoint extends HealthEndpointSupport {
  /// The endpoint over [registry] and [groups].
  HealthEndpoint(
    super.registry,
    super.groups, {
    super.slowIndicatorLoggingThreshold,
  });

  /// The whole report, with every detail.
  @ReadOperation()
  Future<HealthDescriptor?> health() => healthForPath(const []);

  /// The report of a group or contributor at [path], with every detail;
  /// `null` when there is none.
  @ReadOperation()
  Future<HealthDescriptor?> healthForPath(
    @Selector(match: SelectorMatch.allRemaining) List<String> path,
  ) async => (await getHealth(
    ApiVersion.latest,
    SecurityContext.none,
    path,
    showAll: true,
  ))?.$1;
}

/// The `health` endpoint over HTTP: `/actuator/health` and
/// `/actuator/health/{*path}`, with the HTTP status of the group's
/// status (`503` for `DOWN` and `OUT_OF_SERVICE`) and the details and
/// components shown as `show-details` and `show-components` say for the
/// request's user.
///
/// Spring Boot (Java): `HealthEndpointWebExtension`.
@EndpointWebExtension(endpoint: HealthEndpoint)
class HealthEndpointWebExtension extends HealthEndpointSupport {
  /// The web extension over [registry] and [groups].
  HealthEndpointWebExtension(
    super.registry,
    super.groups, {
    super.slowIndicatorLoggingThreshold,
  });

  /// `GET /actuator/health`.
  @ReadOperation()
  Future<WebEndpointResponse<HealthDescriptor>> health(
    ApiVersion apiVersion,
    SecurityContext securityContext,
  ) => healthForPath(apiVersion, securityContext, const []);

  /// `GET /actuator/health/{*path}`: a group, a contributor, or a
  /// contributor inside them; `404` when there is none or the user may not
  /// see the components.
  @ReadOperation()
  Future<WebEndpointResponse<HealthDescriptor>> healthForPath(
    ApiVersion apiVersion,
    SecurityContext securityContext,
    @Selector(match: SelectorMatch.allRemaining) List<String> path,
  ) async {
    final result = await getHealth(apiVersion, securityContext, path);
    if (result == null) {
      // No contributor at all: the application is up, as in Spring Boot.
      return path.isEmpty
          ? WebEndpointResponse(body: Health.up().build())
          : const WebEndpointResponse(status: WebEndpointResponse.notFound);
    }
    final (health, group) = result;
    return WebEndpointResponse(
      body: health,
      status: group.httpCodeStatusMapper.getStatusCode(health.status),
    );
  }
}
