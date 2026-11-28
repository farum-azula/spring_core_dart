import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_restclient/src/allowed_addresses_contributor.dart';
import 'package:spring_boot_starter_restclient/src/config/http_client_properties.dart';
import 'package:spring_boot_starter_restclient/src/http_service_groups.dart';
import 'package:spring_boot_starter_restclient/src/rest_client_customizer.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source =
    'package:spring_boot_starter_restclient#RestClientAutoConfiguration';

/// What a denied call's message tells to do.
const allowedAddressesRemedy =
    'add it to spring.http.clients.allowed-addresses (or set the '
    'base-url of its spring.http.serviceclient group)';

/// The bean definitions the starter adds to every application that lists
/// it:
///
/// - `httpClientAllowedAddresses` ([AllowedAddresses]): the hosts and
///   addresses the transport may call, from
///   `spring.http.clients.allowed-addresses`, the hosts of the groups'
///   base URLs and the entries of the [AllowedAddressesContributor] beans
///   (the OAuth2 client's providers), narrowed by an [InetAddressFilter]
///   bean when there is one; everything else is denied. An application
///   may declare its own.
/// - `httpTransport` ([HttpTransport]): `platformHttpTransport()` with
///   those addresses and `spring.http.clients.connect-timeout` (the
///   longest of it and the groups'), unless the application declares a
///   transport (a mock in tests, a decorator); closed with the context.
///   The family's other clients (OAuth2, Supabase) send through it too.
/// - `restClientBuilderConfigurer` ([RestClientBuilderConfigurer]).
/// - `restClientBuilder` ([RestClientBuilder]), prototype: a new builder
///   for each injection, set up by the configurer.
/// - `httpServiceGroups` ([HttpServiceGroups]): the client of each HTTP
///   service group.
///
/// Spring (Java): Spring Boot's `RestClientAutoConfiguration`,
/// `HttpClientAutoConfiguration` and
/// `HttpServiceClientAutoConfiguration`.
final restClientAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<AllowedAddresses>(
    name: 'httpClientAllowedAddresses',
    factoryMethodName: 'httpClientAllowedAddresses',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.httpClientAllowedAddresses', [
        ConditionalOnMissingBean(AllowedAddresses),
      ]),
    ],
    create: (r) => allowedAddressesOf(
      r.dependency<HttpClientsProperties>(),
      r.dependency<HttpServiceClientProperties>(),
      filter: r.optionalDependency<InetAddressFilter>(),
      contributors:
          r.optionalDependencyList<AllowedAddressesContributor>() ?? const [],
    ),
  ),
  BeanDefinition<HttpTransport>(
    name: 'httpTransport',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'httpTransport',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.httpTransport', [
        ConditionalOnMissingBean(HttpTransport),
      ]),
    ],
    create: (r) => platformHttpTransport(
      connectTimeout: transportConnectTimeout(
        r.dependency<HttpClientsProperties>(),
        r.dependency<HttpServiceClientProperties>(),
      ),
      allowedAddresses: r.dependency<AllowedAddresses>(),
    ),
    destroyMethod: (transport) => transport.close(),
  ),
  BeanDefinition<RestClientBuilderConfigurer>(
    name: 'restClientBuilderConfigurer',
    factoryMethodName: 'restClientBuilderConfigurer',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.restClientBuilderConfigurer', [
        ConditionalOnMissingBean(RestClientBuilderConfigurer),
      ]),
    ],
    create: (r) => RestClientBuilderConfigurer(
      transport: r.dependency<HttpTransport>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<Introspector>()),
      properties: r.dependency<HttpClientsProperties>(),
      customizers: r.optionalDependencyList<RestClientCustomizer>() ?? const [],
    ),
  ),
  BeanDefinition<RestClientBuilder>(
    name: 'restClientBuilder',
    factoryMethodName: 'restClientBuilder',
    source: _source,
    // Builders are stateful: each injection gets its own, as in Spring
    // Boot.
    scope: ScopeType.prototype,
    conditions: const [
      ConditionGroup('$_source.restClientBuilder', [
        ConditionalOnMissingBean(RestClientBuilder),
      ]),
    ],
    create: (r) => r.dependency<RestClientBuilderConfigurer>().configure(
      RestClient.builder(),
    ),
  ),
  BeanDefinition<HttpServiceGroups>(
    name: 'httpServiceGroups',
    factoryMethodName: 'httpServiceGroups',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.httpServiceGroups', [
        ConditionalOnMissingBean(HttpServiceGroups),
      ]),
    ],
    create: (r) {
      final configurer = r.dependency<RestClientBuilderConfigurer>();
      return HttpServiceGroups(
        properties: r.dependency<HttpServiceClientProperties>(),
        newBuilder: () => configurer.configure(RestClient.builder()),
        declared: r.optionalDependencyList<HttpServiceGroup>() ?? const [],
        configurers:
            r.optionalDependencyList<RestClientHttpServiceGroupConfigurer>() ??
            const [],
      );
    },
  ),
];

/// The allow list of the transport: `spring.http.clients.allowed-addresses`,
/// the hosts of the groups' base URLs and the entries of [contributors],
/// with [filter].
AllowedAddresses allowedAddressesOf(
  HttpClientsProperties clients,
  HttpServiceClientProperties serviceClients, {
  InetAddressFilter? filter,
  Iterable<AllowedAddressesContributor> contributors = const [],
}) => AllowedAddresses(
  [
    ...clients.allowedAddresses,
    for (final contributor in contributors) ...contributor.allowedAddresses(),
    for (final group in serviceClients.serviceclient.values)
      if (Uri.tryParse(group.baseUrl?.trim() ?? '')?.host case final host?
          when host.isNotEmpty)
        host,
  ],
  filter: filter,
  remedy: allowedAddressesRemedy,
);

/// The transport's connect timeout: the longest of
/// `spring.http.clients.connect-timeout` and the groups' (a group's
/// request then waits as long as its own); `null` when none is set.
Duration? transportConnectTimeout(
  HttpClientsProperties clients,
  HttpServiceClientProperties serviceClients,
) {
  var longest = RestClientBuilderConfigurer.positiveOrNull(
    clients.connectTimeout,
  );
  for (final group in serviceClients.serviceclient.values) {
    final own = RestClientBuilderConfigurer.positiveOrNull(
      group.connectTimeout,
    );
    if (own != null && (longest == null || own > longest)) {
      longest = own;
    }
  }
  return longest;
}
