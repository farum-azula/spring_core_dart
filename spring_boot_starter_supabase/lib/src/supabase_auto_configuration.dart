import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_supabase/src/cache/supabase_cache.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/data/postgrest_data_store.dart';
import 'package:spring_boot_starter_supabase/src/data/supabase_rls.dart';
import 'package:spring_boot_starter_supabase/src/expression/call_template.dart';
import 'package:spring_boot_starter_supabase/src/functions/edge_functions.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/ratelimit/supabase_rate_limit_store.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';
import 'package:spring_boot_starter_supabase/src/realtime/supabase_realtime.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_bucket.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_template.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_boot_starter_supabase/src/supabase_startup.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_supabase#SupabaseAutoConfiguration';

ObjectMapper _mapper(DependencyResolver r) =>
    r.optionalDependency<ObjectMapper>() ??
    ObjectMapper(introspector: r.dependency<BeanIntrospector>());

// The changes of rows of the store, from Realtime: of the whole table,
// since a subscription with a filter gets no delete and no update that
// takes a row out of the filter.
PostgrestChanges? _changes(SupabaseRealtime? realtime) => realtime == null
    ? null
    : ({required schema, required table}) => realtime
          .postgresChanges(schema: schema, table: table)
          .map(
            (change) => (
              kind: switch (change.kind) {
                RealtimeChangeKind.insert => RowChangeKind.insert,
                RealtimeChangeKind.update => RowChangeKind.update,
                RealtimeChangeKind.delete => RowChangeKind.delete,
              },
              // Realtime gives an empty row where there is none.
              record: change.record.isEmpty ? null : change.record,
              oldRecord: change.oldRecord.isEmpty ? null : change.oldRecord,
            ),
          );

/// The beans of the starter that every application gets; among them
/// `supabaseRateLimitStore` ([SupabaseRateLimitStore]), the web starter's
/// rate limiter's buckets behind a database function: when the rate
/// limiter is on and `spring.web.rate-limit.store` is `procedure`, or is
/// not set and the application reaches the database through the REST API
/// only; never when a `RateLimitStore` is declared already.
final supabaseAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<SupabaseStartup>(
    name: 'supabaseStartup',
    source: _source,
    create: (r) => SupabaseStartup(
      r.dependency<SupabaseProperties>(),
      dataSourceUrl: r.dependency<Environment>().getProperty(
        'spring.datasource.url',
      ),
    ),
  ),
  BeanDefinition<SupabaseCredentials>(
    name: 'supabaseCredentials',
    factoryMethodName: 'supabaseCredentials',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseCredentials', [
        ConditionalOnMissingBean(SupabaseCredentials),
      ]),
    ],
    create: (r) => DefaultSupabaseCredentials(
      properties: r.dependency<SupabaseProperties>(),
      // Looked up at each call: the login needs the credentials itself.
      session: r.provider<LoginSession>().getIfAvailable,
    ),
  ),
  BeanDefinition<SupabaseHttp>(
    name: 'supabaseHttp',
    factoryMethodName: 'supabaseHttp',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseHttp', [
        ConditionalOnMissingBean(SupabaseHttp),
      ]),
    ],
    create: (r) => SupabaseHttp(
      properties: r.dependency<SupabaseProperties>(),
      transport: r.dependency<HttpTransport>(),
      credentials: r.dependency<SupabaseCredentials>(),
      observations: r.optionalDependency<ObservationRegistry>(),
    ),
  ),
  BeanDefinition<PostgrestDataStore>(
    name: 'supabaseDataStore',
    factoryMethodName: 'supabaseDataStore',
    source: _source,
    types: const [PostgrestDataStore, DataStore],
    conditions: const [
      ConditionGroup('$_source.supabaseDataStore', [
        ConditionalOnProperty('spring.supabase.url'),
        ConditionalOnMissingBean(PostgrestDataStore),
      ]),
    ],
    create: (r) => PostgrestDataStore(
      http: r.dependency<SupabaseHttp>(),
      converter: r.dependency<EntityConverter>(),
      schema: r.dependency<SupabaseProperties>().db.schema,
      maxRows: r.dependency<SupabaseProperties>().db.maxRows,
      changes: _changes(r.optionalDependency<SupabaseRealtime>()),
    ),
  ),
  BeanDefinition<SupabaseRateLimitStore>(
    name: 'supabaseRateLimitStore',
    factoryMethodName: 'supabaseRateLimitStore',
    source: _source,
    types: const [SupabaseRateLimitStore, RateLimitStore],
    conditions: const [
      ConditionGroup('$_source.supabaseRateLimitStore', [
        ConditionalOnRateLimitStore('procedure', byDefault: _OnRestPath()),
      ]),
    ],
    create: (r) {
      final properties = r.dependency<SupabaseProperties>();
      final credentials = r.dependency<SupabaseCredentials>();
      // Credentials of the application's own know their service role.
      if (credentials is DefaultSupabaseCredentials &&
          (properties.serviceRoleKey?.trim() ?? '').isEmpty) {
        throw StateError(
          'The rate limiter keeps its buckets behind the database function '
          '${properties.rateLimit.function}, which only the service role '
          'may call: set spring.supabase.service-role-key (on a server), '
          'or spring.web.rate-limit.store to another store',
        );
      }
      return SupabaseRateLimitStore(
        store:
            r.optionalDependency<PostgrestDataStore>() ??
            (throw StateError(
              'spring.web.rate-limit.store=procedure needs the REST API of '
              'the project: set spring.supabase.url',
            )),
        credentials: credentials,
        function: properties.rateLimit.function,
      );
    },
  ),
  BeanDefinition<SupabaseRlsSessionHook>(
    name: 'supabaseRlsSessionHook',
    factoryMethodName: 'supabaseRlsSessionHook',
    source: _source,
    types: const [SupabaseRlsSessionHook, JdbcSessionHook],
    conditions: const [
      ConditionGroup('$_source.supabaseRlsSessionHook', [
        ConditionalOnProperty('spring.supabase.db.rls', havingValue: 'user'),
      ]),
    ],
    create: (r) => SupabaseRlsSessionHook(
      properties: r.dependency<SupabaseProperties>(),
      credentials: r.dependency<SupabaseCredentials>(),
    ),
  ),
  BeanDefinition<CallTemplates>(
    name: 'callTemplates',
    factoryMethodName: 'callTemplates',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.callTemplates', [
        ConditionalOnMissingBean(CallTemplates),
      ]),
    ],
    create: (r) => CallTemplates(
      environment: r.dependency<Environment>(),
      beanFactory: r.dependency<ListableBeanFactory>(),
      introspector: r.dependency<BeanIntrospector>(),
      security: r.optionalDependency<MethodSecurityExpressionHandler>(),
    ),
  ),
  BeanDefinition<StorageTemplate>(
    name: 'storageTemplate',
    factoryMethodName: 'storageTemplate',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.storageTemplate', [
        ConditionalOnMissingBean(StorageTemplate),
      ]),
    ],
    create: (r) =>
        StorageTemplate(http: r.dependency<SupabaseHttp>(), mapper: _mapper(r)),
  ),
  BeanDefinition<StorageBucketFactory>(
    name: 'storageBucketFactory',
    source: _source,
    types: const [StorageBucketFactory, InvocationHandlerFactory],
    create: (r) => StorageBucketFactory(
      storage: r.dependency<StorageTemplate>(),
      templates: r.dependency<CallTemplates>(),
      environment: r.dependency<Environment>(),
      operations:
          r.optionalDependencyList<StorageBucketOperation>() ??
          const <StorageBucketOperation>[],
    ),
  ),
  BeanDefinition<EdgeFunctionsInterceptor>(
    name: 'edgeFunctionsInterceptor',
    source: _source,
    // Not a RequestInterceptor bean of the context: it must not run for
    // the application's other Feign clients.
    types: const [EdgeFunctionsInterceptor],
    create: (r) => EdgeFunctionsInterceptor(
      credentials: r.dependency<SupabaseCredentials>(),
      properties: r.dependency<SupabaseProperties>().functions,
    ),
  ),
  BeanDefinition<EdgeFunctionsFactory>(
    name: 'edgeFunctionsFactory',
    source: _source,
    types: const [EdgeFunctionsFactory, InvocationHandlerFactory],
    create: (r) => EdgeFunctionsFactory(
      http: r.dependency<SupabaseHttp>(),
      environment: r.dependency<Environment>(),
      feign: r.dependency<FeignProperties>(),
      mapper: _mapper(r),
      transport: r.dependency<HttpTransport>(),
      interceptor: r.dependency<EdgeFunctionsInterceptor>(),
      interceptors:
          r.optionalDependencyList<RequestInterceptor>() ??
          const <RequestInterceptor>[],
      errorDecoder:
          r.provider<ErrorDecoder>().getIfUnique() ??
          const DefaultErrorDecoder(),
      observations: r.optionalDependency<ObservationRegistry>(),
    ),
  ),
  BeanDefinition<SupabaseKeyGenerator>(
    name: 'supabaseKeyGenerator',
    source: _source,
    types: const [SupabaseKeyGenerator, KeyGenerator],
    create: (r) => SupabaseKeyGenerator(r.dependency<SupabaseCredentials>()),
  ),
  BeanDefinition<SupabaseCacheResolver>(
    name: 'supabaseCacheResolver',
    source: _source,
    types: const [SupabaseCacheResolver, CacheResolver],
    create: (r) => SupabaseCacheResolver(
      cacheManager: r.dependency<CacheManager>(),
      credentials: r.dependency<SupabaseCredentials>(),
      properties: r.dependency<SupabaseProperties>().cache,
    ),
  ),
  BeanDefinition<SupabaseCachingConfigurer>(
    name: 'supabaseCachingConfigurer',
    factoryMethodName: 'supabaseCachingConfigurer',
    source: _source,
    types: const [SupabaseCachingConfigurer, CachingConfigurer],
    conditions: const [
      ConditionGroup('$_source.supabaseCachingConfigurer', [
        ConditionalOnMissingBean(CachingConfigurer),
      ]),
    ],
    create: (r) => SupabaseCachingConfigurer(
      generator: r.dependency<SupabaseKeyGenerator>(),
      resolver: r.dependency<SupabaseCacheResolver>(),
    ),
  ),
];

// The application reaches the database through the REST API only:
// `spring.supabase.url` without `spring.supabase.db.url` and without a
// data source of its own.
final class _OnRestPath implements Condition {
  const _OnRestPath();

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    bool has(String key) =>
        (environment.getProperty(key)?.trim() ?? '').isNotEmpty;
    return has('spring.supabase.url') &&
        !has('spring.supabase.db.url') &&
        !has('spring.datasource.url');
  }

  @override
  String toString() => 'the database is reached through the REST API';
}
