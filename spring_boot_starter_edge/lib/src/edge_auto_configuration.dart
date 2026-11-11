import 'package:spring_boot_starter_edge/src/cloudflare/cloudflare.dart';
import 'package:spring_boot_starter_edge/src/cloudflare/cloudflare_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_edge/src/cloudflare/cloudflare_js.dart'
    as cloudflare;
import 'package:spring_boot_starter_edge/src/config/edge_properties.dart';
import 'package:spring_boot_starter_edge/src/edge_runtime.dart';
import 'package:spring_boot_starter_edge/src/edge_warnings.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_web_server.dart';
import 'package:spring_boot_starter_edge/src/supabase_anon_key_filter.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _source = 'package:spring_boot_starter_edge#EdgeAutoConfiguration';

const _function = ConditionalOnProperty('spring.edge.runtime');

const _cloudflare = ConditionalOnProperty(
  'spring.edge.runtime',
  havingValue: 'cloudflare',
);

/// The beans of the edge starter.
///
/// Always:
///
/// - `edgeRuntime` ([EdgeRuntime]): the platform, and `waitUntil`.
///
/// Only in a function (`spring.edge.runtime` is set, which
/// `runFetchApplication` does on a fetch platform):
///
/// - `webServerFactory` ([FetchWebServerFactory]) with `server.*` and the
///   `WebServerFactoryCustomizer` beans, unless the application declares
///   a `WebServerFactory`; the web starter's `dart:io` factory then backs
///   off;
/// - `edgeWarnings` ([EdgeWarnings]) and its contributors
///   (`rateLimitStoreEdgeWarning`, `timerWorkEdgeWarning`,
///   `instanceStateEdgeWarning`), unless `spring.edge.warnings` is `false`.
///
/// Only in a Cloudflare Worker:
///
/// - `cloudflareBindings` ([CloudflareBindings]): the Worker's KV
///   namespaces and D1 databases;
/// - `rateLimitStore` ([D1RateLimitStore]) when the rate limiter is on,
///   the application has no store of its own and
///   `spring.edge.cloudflare.rate-limit.database` names a D1 binding (or
///   `spring.web.rate-limit.store` is `d1`).
///
/// Only in a Supabase Edge Function of a project with an anon key:
///
/// - `supabaseAnonKeyFilter` ([SupabaseAnonKeyFilter]), unless
///   `spring.edge.supabase.anon-key-as-anonymous` is `false`.
final edgeAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<EdgeRuntime>(
    name: 'edgeRuntime',
    source: _source,
    create: (r) {
      final runtime = r.dependency<EdgeProperties>().runtime?.trim();
      return EdgeRuntime(runtime == null || runtime.isEmpty ? null : runtime);
    },
  ),
  BeanDefinition<WebServerFactory>(
    name: 'webServerFactory',
    factoryMethodName: 'webServerFactory',
    types: const [
      FetchWebServerFactory,
      WebServerFactory,
      ConfigurableWebServerFactory,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.webServerFactory', [
        _function,
        ConditionalOnMissingBean(WebServerFactory),
      ]),
    ],
    create: (r) {
      final factory = FetchWebServerFactory(
        ServerProperties.from(r.dependency<ServerSettings>()),
      );
      for (final customizer
          in r.optionalDependencyList<WebServerFactoryCustomizer>() ??
              const <WebServerFactoryCustomizer>[]) {
        customizer.customize(factory);
      }
      return factory;
    },
  ),
  BeanDefinition<CloudflareBindings>(
    name: 'cloudflareBindings',
    factoryMethodName: 'cloudflareBindings',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.cloudflareBindings', [
        _cloudflare,
        ConditionalOnMissingBean(CloudflareBindings),
      ]),
    ],
    create: (_) => cloudflare.createCloudflareBindings(),
  ),
  BeanDefinition<RateLimitStore>(
    name: 'rateLimitStore',
    factoryMethodName: 'd1RateLimitStore',
    types: const [D1RateLimitStore, RateLimitStore],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.d1RateLimitStore', [
        _cloudflare,
        ConditionalOnRateLimitStore('d1', byDefault: OnD1RateLimitDatabase()),
      ]),
    ],
    create: (r) {
      final settings = r.dependency<EdgeProperties>().cloudflare.rateLimit;
      final binding = settings.database?.trim() ?? '';
      if (binding.isEmpty) {
        throw StateError(
          'spring.web.rate-limit.store: d1 needs '
          'spring.edge.cloudflare.rate-limit.database, the binding of a D1 '
          'database',
        );
      }
      final bindings = r.dependency<CloudflareBindings>();
      return D1RateLimitStore(
        () => bindings.d1(binding),
        table: settings.table,
      );
    },
  ),
  BeanDefinition<SupabaseAnonKeyFilter>(
    name: 'supabaseAnonKeyFilter',
    types: const [SupabaseAnonKeyFilter, WebFilter, Ordered],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseAnonKeyFilter', [
        ConditionalOnProperty('spring.edge.runtime', havingValue: 'supabase'),
        ConditionalOnProperty('spring.supabase.anon-key'),
        ConditionalOnProperty(
          'spring.edge.supabase.anon-key-as-anonymous',
          havingValue: 'true',
          matchIfMissing: true,
        ),
      ]),
    ],
    create: (r) => SupabaseAnonKeyFilter(
      r.dependency<Environment>().getProperty('spring.supabase.anon-key') ?? '',
    ),
  ),
  for (final (name, create)
      in <(String, EdgeWarningContributor Function(DependencyResolver))>[
        ('rateLimitStoreEdgeWarning', (_) => const RateLimitStoreEdgeWarning()),
        (
          'timerWorkEdgeWarning',
          (r) => TimerWorkEdgeWarning(
            r.dependency<ConfigurableListableBeanFactory>(),
          ),
        ),
        (
          'instanceStateEdgeWarning',
          (r) => InstanceStateEdgeWarning(
            r.dependency<ConfigurableListableBeanFactory>(),
          ),
        ),
      ])
    BeanDefinition<EdgeWarningContributor>(
      name: name,
      source: _source,
      conditions: [
        ConditionGroup('$_source.$name', const [_function]),
      ],
      create: create,
    ),
  BeanDefinition<EdgeWarnings>(
    name: 'edgeWarnings',
    types: const [
      EdgeWarnings,
      ApplicationContextAware,
      SmartInitializingSingleton,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.edgeWarnings', [
        _function,
        ConditionalOnProperty(
          'spring.edge.warnings',
          havingValue: 'true',
          matchIfMissing: true,
        ),
      ]),
    ],
    create: (r) => EdgeWarnings(
      r.optionalDependencyList<EdgeWarningContributor>() ??
          const <EdgeWarningContributor>[],
    ),
  ),
];

/// Whether the application names the D1 database the rate limiter counts
/// in (`spring.edge.cloudflare.rate-limit.database`).
final class OnD1RateLimitDatabase implements Condition {
  /// The condition.
  const OnD1RateLimitDatabase();

  @override
  bool matches(ConditionContext context) =>
      (context.environment
                  .getProperty('spring.edge.cloudflare.rate-limit.database')
                  ?.trim() ??
              '')
          .isNotEmpty;
}

/// Whether the function runs on Supabase and the platform gave the
/// project's address: then `spring.supabase.*` defaults to the function's
/// environment.
final class OnSupabaseFunction implements Condition {
  /// The condition.
  const OnSupabaseFunction();

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    return environment.getProperty('spring.edge.runtime') == 'supabase' &&
        (environment.getProperty('SUPABASE_URL')?.trim() ?? '').isNotEmpty;
  }
}
