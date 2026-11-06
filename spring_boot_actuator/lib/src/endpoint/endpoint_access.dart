import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// What may be done with an endpoint, set by
/// `management.endpoint.<id>.access` and
/// `management.endpoints.access.default`.
///
/// The endpoints have read operations only so far, so [readOnly] and
/// [unrestricted] both enable an endpoint and [none] disables it.
///
/// Spring Boot (Java): `Access` (Spring Boot 3.4 and later, where it
/// replaces `management.endpoint.<id>.enabled`).
enum EndpointAccess {
  /// The endpoint is off.
  none,

  /// Only its read operations.
  readOnly,

  /// Every operation.
  unrestricted,
}

/// Whether an endpoint is enabled, from the properties, in this order:
///
/// 1. `management.endpoint.<id>.access` (`none` disables);
/// 2. `management.endpoint.<id>.enabled`;
/// 3. `management.endpoints.access.default`;
/// 4. `management.endpoints.enabled-by-default`;
/// 5. the endpoint's own `enableByDefault` (`true` for the built-in
///    endpoints).
///
/// A disabled endpoint is neither exposed nor listed. Both spellings are
/// read: `enabled` of Spring Boot 2 and 3, `access` of Spring Boot 3.4 and
/// later.
///
/// ```properties
/// management.endpoints.enabled-by-default=false
/// management.endpoint.health.enabled=true
/// ```
///
/// Spring Boot (Java): `@ConditionalOnAvailableEndpoint` (its enablement
/// part).
bool isEndpointEnabled(
  PropertyResolver environment,
  EndpointId id, {
  bool enableByDefault = true,
}) {
  final key = id.toLowerCaseString();
  final access = _access(environment, 'management.endpoint.$key.access');
  if (access != null) {
    return access != EndpointAccess.none;
  }
  final enabled = environment.getPropertyAs<bool>(
    'management.endpoint.$key.enabled',
  );
  if (enabled != null) {
    return enabled;
  }
  final defaultAccess = _access(
    environment,
    'management.endpoints.access.default',
  );
  if (defaultAccess != null) {
    return defaultAccess != EndpointAccess.none;
  }
  return environment.getPropertyAs<bool>(
        'management.endpoints.enabled-by-default',
      ) ??
      enableByDefault;
}

EndpointAccess? _access(PropertyResolver environment, String key) {
  final text = environment.getProperty(key)?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  final wanted = text.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  for (final value in EndpointAccess.values) {
    if (value.name.toLowerCase() == wanted) {
      return value;
    }
  }
  throw ArgumentError.value(
    text,
    key,
    'must be one of none, read-only, unrestricted',
  );
}

/// Which endpoints a technology exposes: those [include] names (`*` for
/// all; the default includes when it is empty) that [exclude] does not
/// name.
///
/// The actuator starter builds one from
/// `management.endpoints.web.exposure.include` and `.exclude`; over HTTP
/// the default is `health` alone, as in Spring Boot.
///
/// ```dart
/// final filter = IncludeExcludeEndpointFilter(
///   include: ['*'],
///   exclude: ['env'],
/// );
/// filter.match(EndpointId.of('health')); // true
/// ```
///
/// Spring Boot (Java): `IncludeExcludeEndpointFilter`.
final class IncludeExcludeEndpointFilter {
  /// A filter of [include] minus [exclude] (ids or `*`).
  IncludeExcludeEndpointFilter({
    List<String> include = const [],
    List<String> exclude = const [],
    List<String> defaultIncludes = const ['health'],
  }) : include = _clean(include.isEmpty ? defaultIncludes : include),
       exclude = _clean(exclude);

  /// The included ids in lower case, or `*`.
  final Set<String> include;

  /// The excluded ids in lower case, or `*`.
  final Set<String> exclude;

  static Set<String> _clean(List<String> ids) => {
    for (final id in ids)
      if (id.trim() == '*')
        '*'
      else if (id.trim().isNotEmpty)
        EndpointId.toLowerCaseKey(id.trim()),
  };

  /// Whether the endpoint [id] is exposed.
  bool match(EndpointId id) {
    final key = id.toLowerCaseString();
    return (include.contains('*') || include.contains(key)) &&
        !(exclude.contains('*') || exclude.contains(key));
  }
}

/// Registers a health indicator's bean only when it is enabled:
/// `management.health.<name>.enabled`, else
/// `management.health.defaults.enabled`, else on.
///
/// ```dart
/// BeanDefinition<HealthIndicator>(
///   name: 'pingHealthContributor',
///   conditions: const [ConditionalOnEnabledHealthIndicator('ping')],
///   create: (_) => PingHealthIndicator(),
/// )
/// ```
///
/// Spring Boot (Java): `@ConditionalOnEnabledHealthIndicator("ping")`.
class ConditionalOnEnabledHealthIndicator implements Condition {
  /// The condition of the indicator [name].
  const ConditionalOnEnabledHealthIndicator(this.name);

  /// The indicator's name in the properties (`db`, `diskspace`).
  final String name;

  @override
  bool matches(ConditionContext context) =>
      context.environment.getPropertyAs<bool>(
        'management.health.$name.enabled',
      ) ??
      context.environment.getPropertyAs<bool>(
        'management.health.defaults.enabled',
      ) ??
      true;

  @override
  String toString() => '@ConditionalOnEnabledHealthIndicator($name)';
}

/// Registers an info contributor's bean only when it is enabled:
/// `management.info.<name>.enabled`, else (for the contributors on by
/// default, [enabledByDefault]) `management.info.defaults.enabled`.
///
/// `build` and `git` follow the defaults; `env`, `os` and `dart` are off
/// unless their own property says otherwise, as in Spring Boot 2.6 and
/// later.
///
/// Spring Boot (Java): `@ConditionalOnEnabledInfoContributor`.
class ConditionalOnEnabledInfoContributor implements Condition {
  /// The condition of the contributor [name]; off by default unless
  /// [enabledByDefault].
  const ConditionalOnEnabledInfoContributor(
    this.name, {
    this.enabledByDefault = true,
  });

  /// The contributor's name in the properties (`build`, `env`).
  final String name;

  /// Whether `management.info.defaults.enabled` decides when the
  /// contributor's own property is not set; otherwise it is off.
  final bool enabledByDefault;

  @override
  bool matches(ConditionContext context) {
    final own = context.environment.getPropertyAs<bool>(
      'management.info.$name.enabled',
    );
    if (own != null) {
      return own;
    }
    if (!enabledByDefault) {
      return false;
    }
    return context.environment.getPropertyAs<bool>(
          'management.info.defaults.enabled',
        ) ??
        true;
  }

  @override
  String toString() => '@ConditionalOnEnabledInfoContributor($name)';
}
