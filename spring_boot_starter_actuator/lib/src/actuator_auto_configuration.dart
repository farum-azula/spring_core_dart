import 'dart:convert';

import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_actuator/src/config/web_endpoint_properties.dart';
import 'package:spring_boot_starter_actuator/src/web/web_endpoint_handler_mapping.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog(
  'spring.boot.actuate.endpoint.web.EndpointLinksResolver',
);

const _health =
    'package:spring_boot_starter_actuator#HealthEndpointAutoConfiguration';
const _contributors =
    'package:spring_boot_starter_actuator#HealthContributorAutoConfiguration';
const _info =
    'package:spring_boot_starter_actuator#InfoEndpointAutoConfiguration';
const _infoContributors =
    'package:spring_boot_starter_actuator#InfoContributorAutoConfiguration';
const _mappings =
    'package:spring_boot_starter_actuator#MappingsEndpointAutoConfiguration';
const _web =
    'package:spring_boot_starter_actuator#WebEndpointAutoConfiguration';

const _buildLocation =
    r'${spring.info.build.location:resources:build-info.properties}';
const _gitLocation = r'${spring.info.git.location:resources:git.properties}';

/// The bean definitions of the actuator starter: the health
/// contributors and endpoint, the info contributors and endpoint, the
/// mappings endpoint, and their answers over HTTP. Applications do not
/// use the list; the generator adds it through
/// `springBootStarterActuatorAutoConfiguration`.
///
/// Health (Spring Boot's `HealthContributorAutoConfiguration`,
/// `HealthEndpointAutoConfiguration`, `AvailabilityProbesAutoConfiguration`):
///
/// - `pingHealthContributor` and `diskSpaceHealthIndicator`, unless
///   `management.health.<name>.enabled=false`;
/// - `livenessStateHealthIndicator` and `readinessStateHealthIndicator`
///   with the probes (`management.endpoint.health.probes.enabled`, on by
///   default on Kubernetes and Cloud Foundry) or their own
///   `management.health.livenessstate.enabled`;
/// - `healthContributorRegistry`, every `HealthContributor` bean by name;
/// - `healthEndpointGroups`, from `management.endpoint.health.*` and the
///   probes' `liveness` and `readiness` groups;
/// - `healthEndpoint` and `healthEndpointWebExtension`.
///
/// Info (`InfoContributorAutoConfiguration`, `ProjectInfoAutoConfiguration`):
///
/// - `buildProperties` and `gitProperties` when their files exist;
/// - `buildInfoContributor`, `gitInfoContributor` (on by default),
///   `envInfoContributor`, `osInfoContributor`, `dartInfoContributor` (off
///   by default), each switched by `management.info.<id>.enabled`;
/// - `infoEndpoint`.
///
/// Mappings: `mappingsEndpoint`, over every `MappingDescriptions` bean.
///
/// Web (`WebEndpointAutoConfiguration`,
/// `WebFluxEndpointManagementContextConfiguration`):
///
/// - `webEndpointDiscoverer`, the endpoint beans and their operations;
/// - `webEndpointHandlerMapping`, the enabled and exposed endpoints
///   under `management.endpoints.web.base-path`;
/// - `webEndpointRequestFilter`, which records the endpoint of a request
///   for `EndpointRequest`.
final actuatorAutoConfiguration = <BeanDefinition<Object>>[
  // Health contributors.
  BeanDefinition<PingHealthIndicator>(
    name: 'pingHealthContributor',
    factoryMethodName: 'pingHealthContributor',
    types: const [PingHealthIndicator, HealthIndicator, HealthContributor],
    source: _contributors,
    conditions: const [
      ConditionGroup('$_contributors.pingHealthContributor', [
        ConditionalOnEnabledHealthIndicator('ping'),
      ]),
    ],
    create: (_) => PingHealthIndicator(),
  ),
  BeanDefinition<DiskSpaceHealthIndicator>(
    name: 'diskSpaceHealthIndicator',
    factoryMethodName: 'diskSpaceHealthIndicator',
    types: const [
      DiskSpaceHealthIndicator,
      AbstractHealthIndicator,
      HealthIndicator,
      HealthContributor,
    ],
    source: _contributors,
    conditions: const [
      ConditionGroup('$_contributors.diskSpaceHealthIndicator', [
        ConditionalOnEnabledHealthIndicator('diskspace'),
        ConditionalOnMissingBean.named('diskSpaceHealthIndicator'),
      ]),
    ],
    create: (r) {
      final disk = r.dependency<ManagementHealthProperties>().diskspace;
      return DiskSpaceHealthIndicator(
        path: disk.path,
        threshold: disk.threshold,
      );
    },
  ),
  BeanDefinition<LivenessStateHealthIndicator>(
    name: 'livenessStateHealthIndicator',
    factoryMethodName: 'livenessStateHealthIndicator',
    types: const [
      LivenessStateHealthIndicator,
      HealthIndicator,
      HealthContributor,
    ],
    source: _contributors,
    conditions: const [
      ConditionGroup('$_contributors.livenessStateHealthIndicator', [
        _OnAvailabilityState('livenessstate'),
        ConditionalOnMissingBean(LivenessStateHealthIndicator),
      ]),
    ],
    create: (r) =>
        LivenessStateHealthIndicator(r.dependency<ApplicationAvailability>()),
  ),
  BeanDefinition<ReadinessStateHealthIndicator>(
    name: 'readinessStateHealthIndicator',
    factoryMethodName: 'readinessStateHealthIndicator',
    types: const [
      ReadinessStateHealthIndicator,
      HealthIndicator,
      HealthContributor,
    ],
    source: _contributors,
    conditions: const [
      ConditionGroup('$_contributors.readinessStateHealthIndicator', [
        _OnAvailabilityState('readinessstate'),
        ConditionalOnMissingBean(ReadinessStateHealthIndicator),
      ]),
    ],
    create: (r) =>
        ReadinessStateHealthIndicator(r.dependency<ApplicationAvailability>()),
  ),
  // The health endpoint.
  BeanDefinition<HealthContributorRegistry>(
    name: 'healthContributorRegistry',
    factoryMethodName: 'healthContributorRegistry',
    // Not a HealthContributor bean itself: it is made of them.
    types: const [HealthContributorRegistry],
    source: _health,
    conditions: const [
      ConditionGroup('$_health.healthContributorRegistry', [
        ConditionalOnMissingBean(HealthContributorRegistry),
      ]),
    ],
    create: (r) {
      final registry = DefaultHealthContributorRegistry();
      final beans = r
          .dependency<ListableBeanFactory>()
          .getBeansOfType<HealthContributor>();
      for (final MapEntry(key: name, value: bean) in beans.entries) {
        if (bean is! HealthContributorRegistry) {
          registry.registerContributor(healthContributorName(name), bean);
        }
      }
      return registry;
    },
  ),
  BeanDefinition<HealthEndpointGroups>(
    name: 'healthEndpointGroups',
    factoryMethodName: 'healthEndpointGroups',
    source: _health,
    conditions: const [
      ConditionGroup('$_health.healthEndpointGroups', [
        ConditionalOnMissingBean(HealthEndpointGroups),
      ]),
    ],
    create: (r) => healthEndpointGroupsOf(
      r.dependency<HealthEndpointProperties>(),
      registry: r.dependency<HealthContributorRegistry>(),
      probes: _probesEnabled(r.dependency<Environment>()),
    ),
  ),
  BeanDefinition<HealthEndpoint>(
    name: 'healthEndpoint',
    factoryMethodName: 'healthEndpoint',
    source: _health,
    annotations: const [Endpoint(id: 'health')],
    conditions: const [
      ConditionGroup('$_health.healthEndpoint', [
        ConditionalOnMissingBean(HealthEndpoint),
      ]),
    ],
    create: (r) => HealthEndpoint(
      r.dependency<HealthContributorRegistry>(),
      r.dependency<HealthEndpointGroups>(),
      slowIndicatorLoggingThreshold: r
          .dependency<HealthEndpointProperties>()
          .logging
          .slowIndicatorThreshold,
    ),
    annotatedMethods: [
      BeanMethod<HealthEndpoint>(
        'health',
        invoke: (bean, _) => bean.health(),
        annotations: const [ReadOperation()],
        isFuture: true,
      ),
      BeanMethod<HealthEndpoint>(
        'healthForPath',
        invoke: (bean, arguments) =>
            bean.healthForPath(arguments.single! as List<String>),
        parameters: const [_pathParameter],
        annotations: const [ReadOperation()],
        isFuture: true,
      ),
    ],
  ),
  BeanDefinition<HealthEndpointWebExtension>(
    name: 'healthEndpointWebExtension',
    factoryMethodName: 'healthEndpointWebExtension',
    source: _health,
    annotations: const [EndpointWebExtension(endpoint: HealthEndpoint)],
    conditions: const [
      ConditionGroup('$_health.healthEndpointWebExtension', [
        ConditionalOnBean(HealthEndpoint),
        ConditionalOnMissingBean(HealthEndpointWebExtension),
      ]),
    ],
    create: (r) => HealthEndpointWebExtension(
      r.dependency<HealthContributorRegistry>(),
      r.dependency<HealthEndpointGroups>(),
      slowIndicatorLoggingThreshold: r
          .dependency<HealthEndpointProperties>()
          .logging
          .slowIndicatorThreshold,
    ),
    annotatedMethods: [
      BeanMethod<HealthEndpointWebExtension>(
        'health',
        invoke: (bean, arguments) => bean.health(
          arguments[0]! as ApiVersion,
          arguments[1]! as SecurityContext,
        ),
        parameters: const [_apiVersionParameter, _securityContextParameter],
        annotations: const [ReadOperation()],
        isFuture: true,
      ),
      BeanMethod<HealthEndpointWebExtension>(
        'healthForPath',
        invoke: (bean, arguments) => bean.healthForPath(
          arguments[0]! as ApiVersion,
          arguments[1]! as SecurityContext,
          arguments[2]! as List<String>,
        ),
        parameters: const [
          _apiVersionParameter,
          _securityContextParameter,
          _pathParameter,
        ],
        annotations: const [ReadOperation()],
        isFuture: true,
      ),
    ],
  ),
  // Info.
  BeanDefinition<BuildProperties>(
    name: 'buildProperties',
    factoryMethodName: 'buildProperties',
    source: _infoContributors,
    conditions: const [
      ConditionGroup('$_infoContributors.buildProperties', [
        ConditionalOnResource([_buildLocation]),
        ConditionalOnMissingBean(BuildProperties),
      ]),
    ],
    create: (r) {
      final location = r.dependency<ProjectInfoProperties>().build;
      return BuildProperties.loadSync(
        _resource(r, location),
        encoding: _encoding(location.encoding),
      );
    },
  ),
  BeanDefinition<GitProperties>(
    name: 'gitProperties',
    factoryMethodName: 'gitProperties',
    source: _infoContributors,
    conditions: const [
      ConditionGroup('$_infoContributors.gitProperties', [
        ConditionalOnResource([_gitLocation]),
        ConditionalOnMissingBean(GitProperties),
      ]),
    ],
    create: (r) {
      final location = r.dependency<ProjectInfoProperties>().git;
      return GitProperties.loadSync(
        _resource(r, location),
        encoding: _encoding(location.encoding),
      );
    },
  ),
  BeanDefinition<EnvironmentInfoContributor>(
    name: 'envInfoContributor',
    factoryMethodName: 'envInfoContributor',
    types: const [EnvironmentInfoContributor, InfoContributor],
    source: _infoContributors,
    order: _infoContributorOrder,
    conditions: const [
      ConditionGroup('$_infoContributors.envInfoContributor', [
        ConditionalOnEnabledInfoContributor('env', enabledByDefault: false),
      ]),
    ],
    create: (r) =>
        EnvironmentInfoContributor(r.dependency<ConfigurableEnvironment>()),
  ),
  BeanDefinition<GitInfoContributor>(
    name: 'gitInfoContributor',
    factoryMethodName: 'gitInfoContributor',
    types: const [GitInfoContributor, InfoContributor],
    source: _infoContributors,
    order: _infoContributorOrder,
    conditions: const [
      ConditionGroup('$_infoContributors.gitInfoContributor', [
        ConditionalOnEnabledInfoContributor('git'),
        ConditionalOnBean(GitProperties),
        ConditionalOnMissingBean(GitInfoContributor),
      ]),
    ],
    create: (r) => GitInfoContributor(
      r.dependency<GitProperties>(),
      mode: r.dependency<ManagementInfoProperties>().git.mode,
    ),
  ),
  BeanDefinition<BuildInfoContributor>(
    name: 'buildInfoContributor',
    factoryMethodName: 'buildInfoContributor',
    types: const [BuildInfoContributor, InfoContributor],
    source: _infoContributors,
    order: _infoContributorOrder,
    conditions: const [
      ConditionGroup('$_infoContributors.buildInfoContributor', [
        ConditionalOnEnabledInfoContributor('build'),
        ConditionalOnBean(BuildProperties),
        ConditionalOnMissingBean(BuildInfoContributor),
      ]),
    ],
    create: (r) => BuildInfoContributor(r.dependency<BuildProperties>()),
  ),
  BeanDefinition<OsInfoContributor>(
    name: 'osInfoContributor',
    factoryMethodName: 'osInfoContributor',
    types: const [OsInfoContributor, InfoContributor],
    source: _infoContributors,
    order: _infoContributorOrder,
    conditions: const [
      ConditionGroup('$_infoContributors.osInfoContributor', [
        ConditionalOnEnabledInfoContributor('os', enabledByDefault: false),
      ]),
    ],
    create: (_) => OsInfoContributor(),
  ),
  BeanDefinition<DartInfoContributor>(
    name: 'dartInfoContributor',
    factoryMethodName: 'dartInfoContributor',
    types: const [DartInfoContributor, InfoContributor],
    source: _infoContributors,
    order: _infoContributorOrder,
    conditions: const [
      ConditionGroup('$_infoContributors.dartInfoContributor', [
        ConditionalOnEnabledInfoContributor('dart', enabledByDefault: false),
      ]),
    ],
    create: (_) => DartInfoContributor(),
  ),
  BeanDefinition<InfoEndpoint>(
    name: 'infoEndpoint',
    factoryMethodName: 'infoEndpoint',
    source: _info,
    annotations: const [Endpoint(id: 'info')],
    conditions: const [
      ConditionGroup('$_info.infoEndpoint', [
        ConditionalOnMissingBean(InfoEndpoint),
      ]),
    ],
    create: (r) => InfoEndpoint(
      r.optionalDependencyList<InfoContributor>() ?? const [],
    ),
    annotatedMethods: [
      BeanMethod<InfoEndpoint>(
        'info',
        invoke: (bean, _) => bean.info(),
        annotations: const [ReadOperation()],
        isFuture: true,
      ),
    ],
  ),
  // Mappings.
  BeanDefinition<MappingsEndpoint>(
    name: 'mappingsEndpoint',
    factoryMethodName: 'mappingsEndpoint',
    source: _mappings,
    annotations: const [Endpoint(id: 'mappings')],
    conditions: const [
      ConditionGroup('$_mappings.mappingsEndpoint', [
        ConditionalOnMissingBean(MappingsEndpoint),
      ]),
    ],
    create: (r) => MappingsEndpoint(
      r.optionalDependencyList<MappingDescriptions>() ?? const [],
      // Spring Boot's context id: spring.application.name, else
      // `application`.
      contextId: switch (r.dependency<ApplicationProperties>().name?.trim()) {
        final name? when name.isNotEmpty => name,
        _ => 'application',
      },
    ),
    annotatedMethods: [
      BeanMethod<MappingsEndpoint>(
        'mappings',
        invoke: (bean, _) => bean.mappings(),
        annotations: const [ReadOperation()],
      ),
    ],
  ),
  // Web.
  BeanDefinition<EndpointDiscoverer>(
    name: 'webEndpointDiscoverer',
    source: _web,
    create: (r) => EndpointDiscoverer(
      r.dependency<ListableBeanFactory>(),
      conversionService: r
          .dependency<ConfigurableEnvironment>()
          .conversionService,
    ),
  ),
  BeanDefinition<WebEndpointHandlerMapping>(
    name: 'webEndpointHandlerMapping',
    types: const [
      WebEndpointHandlerMapping,
      HandlerMapping,
      Ordered,
      DescribableHandlerMapping,
    ],
    source: _web,
    create: _handlerMapping,
  ),
  BeanDefinition<WebEndpointRequestFilter>(
    name: 'webEndpointRequestFilter',
    types: const [WebEndpointRequestFilter, WebFilter, Ordered],
    source: _web,
    create: (r) =>
        WebEndpointRequestFilter(r.dependency<WebEndpointHandlerMapping>()),
  ),
];

// Spring Boot's InfoContributorAutoConfiguration.DEFAULT_ORDER.
const int _infoContributorOrder = Ordered.highestPrecedence + 10;

const _pathParameter = BeanParameter(
  'path',
  type: ListType<String>(ClassType<String>()),
  isRequired: true,
  annotations: [Selector(match: SelectorMatch.allRemaining)],
);
const _apiVersionParameter = BeanParameter(
  'apiVersion',
  type: EnumType<ApiVersion>(ApiVersion.values),
  isRequired: true,
);
const _securityContextParameter = BeanParameter(
  'securityContext',
  type: ClassType<SecurityContext>(),
  isRequired: true,
);

Resource _resource(DependencyResolver r, ProjectInfoLocation location) =>
    r.dependency<ResourceLoader>().getResource(
      r.dependency<Environment>().resolvePlaceholders(location.location),
    );

Encoding _encoding(String name) =>
    switch (name.trim().toLowerCase().replaceAll('_', '-')) {
      'iso-8859-1' || 'latin1' || 'latin-1' => latin1,
      'us-ascii' || 'ascii' => ascii,
      _ => utf8,
    };

// management.endpoint.health.probes.enabled, else on on Kubernetes and
// Cloud Foundry (Spring Boot's ProbesCondition).
bool _probesEnabled(PropertyResolver environment) =>
    environment.getPropertyAs<bool>(
      'management.endpoint.health.probes.enabled',
    ) ??
    switch (CloudPlatform.getActive(environment)) {
      CloudPlatform.kubernetes || CloudPlatform.cloudFoundry => true,
      _ => false,
    };

// The livenessState / readinessState indicator: its own
// management.health.<name>.enabled, or the probes.
final class _OnAvailabilityState implements Condition {
  const _OnAvailabilityState(this.name);

  final String name;

  @override
  bool matches(ConditionContext context) =>
      context.environment.getPropertyAs<bool>(
        'management.health.$name.enabled',
      ) ??
      _probesEnabled(context.environment);

  @override
  String toString() => '@ConditionalOnAvailabilityState($name)';
}

/// The groups of the health report from [properties]: the primary group
/// (`show-details`, `show-components`, `roles`, `status.*`), each
/// `group.<name>`, and with [probes] the `liveness` and `readiness`
/// groups (unless the application defines groups of these names), at
/// `/livez` and `/readyz` too with `probes.add-additional-paths`.
///
/// With `validate-group-membership` (the default) a group that includes
/// or excludes a contributor [registry] does not have stops the start.
///
/// Spring Boot (Java): `AutoConfiguredHealthEndpointGroups` and
/// `AvailabilityProbesHealthEndpointGroups`.
HealthEndpointGroups healthEndpointGroupsOf(
  HealthEndpointProperties properties, {
  HealthContributorRegistry? registry,
  bool probes = false,
}) {
  StatusAggregator aggregator(HealthStatusProperties status) =>
      SimpleStatusAggregator.of(status.order);
  HttpCodeStatusMapper mapper(HealthStatusProperties status) =>
      SimpleHttpCodeStatusMapper(status.httpMapping);
  final defaultAggregator = aggregator(properties.status);
  final defaultMapper = mapper(properties.status);
  final primary = SimpleHealthEndpointGroup(
    showDetailsMode: properties.showDetails,
    showComponentsMode: properties.showComponents,
    roles: properties.roles,
    statusAggregator: defaultAggregator,
    httpCodeStatusMapper: defaultMapper,
  );
  final named = <String, HealthEndpointGroup>{};
  for (final MapEntry(key: name, value: group) in properties.group.entries) {
    if (properties.validateGroupMembership && registry != null) {
      for (final (kind, members) in [
        ('Included', group.include),
        ('Excluded', group.exclude),
      ]) {
        for (final member in members) {
          if (member.trim() != '*' && !_exists(registry, member.trim())) {
            throw StateError(
              "$kind health contributor '${member.trim()}' in group "
              "'$name' does not exist",
            );
          }
        }
      }
    }
    named[name] = SimpleHealthEndpointGroup(
      include: group.include,
      exclude: group.exclude,
      showDetailsMode: group.showDetails ?? properties.showDetails,
      showComponentsMode: group.showComponents ?? properties.showComponents,
      roles: group.roles?.isNotEmpty ?? false ? group.roles! : properties.roles,
      statusAggregator: group.status.order.isEmpty
          ? defaultAggregator
          : aggregator(group.status),
      httpCodeStatusMapper: group.status.httpMapping.isEmpty
          ? defaultMapper
          : mapper(group.status),
      additionalPath: group.additionalPath,
    );
  }
  if (probes) {
    final paths = properties.probes.addAdditionalPaths;
    named
      ..putIfAbsent(
        'liveness',
        () => SimpleHealthEndpointGroup(
          include: const ['livenessState'],
          additionalPath: paths ? 'server:/livez' : null,
        ),
      )
      ..putIfAbsent(
        'readiness',
        () => SimpleHealthEndpointGroup(
          include: const ['readinessState'],
          additionalPath: paths ? 'server:/readyz' : null,
        ),
      );
  }
  return HealthEndpointGroups.of(primary, named);
}

bool _exists(HealthContributorRegistry registry, String member) {
  HealthContributor? contributor = registry;
  for (final segment in member.split('/')) {
    contributor = switch (contributor) {
      final CompositeHealthContributor composite => composite.getContributor(
        segment,
      ),
      _ => null,
    };
    if (contributor == null) {
      return false;
    }
  }
  return true;
}

WebEndpointHandlerMapping _handlerMapping(DependencyResolver r) {
  final web = r.dependency<WebEndpointProperties>();
  final environment = r.dependency<Environment>();
  final exposure = IncludeExcludeEndpointFilter(
    include: web.exposure.include,
    exclude: web.exposure.exclude,
  );
  final endpoints = [
    for (final endpoint in r.dependency<EndpointDiscoverer>().getEndpoints())
      if (isEndpointEnabled(
            environment,
            endpoint.id,
            enableByDefault: endpoint.enableByDefault,
          ) &&
          exposure.match(endpoint.id))
        endpoint,
  ];
  final health = EndpointId.of('health');
  final additionalPaths = <AdditionalEndpointPath>[];
  if (endpoints.any((endpoint) => endpoint.id == health)) {
    final groups = r.optionalDependency<HealthEndpointGroups>();
    for (final name in groups?.names ?? const <String>[]) {
      final path = groups!.get(name)?.additionalPath?.trim();
      if (path == null || path.isEmpty) {
        continue;
      }
      // Only the main server: there is no management port yet.
      if (path.startsWith('server:')) {
        additionalPaths.add(
          AdditionalEndpointPath(path.substring('server:'.length), health, [
            name,
          ]),
        );
      } else {
        _log.warning(
          "Health group '$name' has the additional path '$path'; only "
          "'server:' paths are supported",
        );
      }
    }
  }
  final basePath = web.cleanBasePath;
  _log.info(
    'Exposing ${endpoints.length} endpoint${endpoints.length == 1 ? '' : 's'}'
    " beneath base path '$basePath'",
  );
  return WebEndpointHandlerMapping(
    endpoints: endpoints,
    mapper:
        r.optionalDependency<ObjectMapper>() ??
        ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
    basePath: basePath,
    pathMappings: web.pathMapping,
    linksEnabled: web.discovery.enabled,
    roleChecker: r.provider<PrincipalRoleChecker>().getIfUnique(),
    additionalPaths: additionalPaths,
  );
}
