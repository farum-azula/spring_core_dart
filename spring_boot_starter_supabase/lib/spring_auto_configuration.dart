/// The auto-configuration modules of the Supabase starter, found by the
/// generator in every application that depends on it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart'
    show
        DataStoreCapabilities,
        DataStoreCapability,
        DataStoreDeclaration,
        DataStoreDefault,
        DataStoreDescriptor;
import 'package:spring_boot_starter_supabase/src/auth/auth_auto_configuration.dart';
import 'package:spring_boot_starter_supabase/src/config/config.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_auto_configuration.dart';
import 'package:spring_boot_starter_supabase/src/supabase_auto_configuration.dart';

export 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
export 'package:spring_boot_starter_data/spring_auto_configuration.dart';
export 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
export 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
export 'package:spring_security_core/spring_auto_configuration.dart';

/// The store over the project's REST API (`PostgrestDataStore`), as the
/// build knows it: database functions (`@Procedure`) and the changes of rows
/// (Realtime); no transactions, no row locks, no SQL of `@Query`. It is
/// the default store when `spring.supabase.url` is set and neither
/// `spring.supabase.db.url`, `spring.datasource.url` nor
/// `spring.data.store` is: what
/// [springBootStarterSupabaseDataAutoConfiguration] decides when the
/// application starts.
///
/// With it a repository on this store that uses what it lacks (`@Lock`,
/// `@Query`, `@Transactional`) fails the build, and so does a
/// `@Transactional` bean of an application whose default store it is.
@DataStoreDeclaration()
const supabaseStore = DataStoreDescriptor(
  'supabase',
  capabilities: DataStoreCapabilities(functions: true, changes: true),
  defaultWhen: DataStoreDefault(
    whenProperty: ['spring.supabase.url'],
    unlessProperty: [
      'spring.supabase.db.url',
      'spring.datasource.url',
      'spring.data.store',
    ],
  ),
  fixes: {
    DataStoreCapability.transactions: _overSql,
    DataStoreCapability.locks: _overSql,
    DataStoreCapability.queries: _overSql,
  },
);

const _overSql = 'set spring.supabase.db.url to run the repositories over SQL';

/// How the repositories reach the database, as defaults of the data
/// starter's own properties (of the lowest precedence: what the
/// application sets itself wins):
///
/// - `spring.supabase.db.url` set: `spring.datasource.url` is that
///   address, so the repositories use SQL over it;
/// - not set (and no `spring.datasource.url` of the application's own):
///   `spring.data.store` is `supabase`, the store over the project's REST
///   API.
///
/// A module of its own, before the data starter's, whose beans are
/// decided by these properties.
@AutoConfigurationModule(before: ['springBootStarterDataAutoConfiguration'])
final BeanModule springBootStarterSupabaseDataAutoConfiguration = BeanModule(
  'springBootStarterSupabaseDataAutoConfiguration',
  const [],
  propertySources: const [
    PropertySourceDeclaration(
      ['resources:supabase/sql-store.properties'],
      name: 'supabaseDataDefaults',
      conditions: [OnSupabaseData(sql: true)],
    ),
    PropertySourceDeclaration(
      ['resources:supabase/rest-store.properties'],
      name: 'supabaseDataDefaults',
      conditions: [OnSupabaseData(sql: false)],
    ),
  ],
  resources: const {
    'supabase/sql-store.properties': EmbeddedResource.text(
      r'spring.datasource.url=${spring.supabase.db.url}'
      '\n',
    ),
    'supabase/rest-store.properties': EmbeddedResource.text(
      'spring.data.store=supabase\n',
    ),
  },
);

/// The beans of the starter on every platform: the credentials, the HTTP
/// client, the data store, Storage, Edge Functions, the cache keys.
@AutoConfigurationModule(
  after: [
    'springBootStarterFeignAutoConfiguration',
    'springBootStarterWebsocketAutoConfiguration',
    'springBootStarterDataAutoConfiguration',
    'springSecurityCoreAutoConfiguration',
  ],
)
final BeanModule springBootStarterSupabaseAutoConfiguration = BeanModule(
  'springBootStarterSupabaseAutoConfiguration',
  [
    ...supabaseAutoConfiguration,
    ...supabaseAuthAutoConfiguration,
    ...supabaseRealtimeAutoConfiguration,
  ],
  imports: [supabaseConfigBeans],
);

/// The server half: the defaults of Spring Security's resource server, so
/// that a server accepts the tokens of the project's Auth as bearer
/// tokens. They are properties of the lowest precedence (below the
/// application's files, above its `defaultProperties`): whatever the
/// application sets itself under
/// `spring.security.oauth2.resourceserver.jwt.*` wins.
///
/// Not in a browser build: only a server checks tokens.
@AutoConfigurationModule(
  before: [
    'springBootStarterSecurityAutoConfiguration',
    'springBootStarterSecurityOAuth2ClientAutoConfiguration',
  ],
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterSupabaseServerAutoConfiguration = BeanModule(
  'springBootStarterSupabaseServerAutoConfiguration',
  const [],
  propertySources: const [
    PropertySourceDeclaration(
      ['resources:supabase/resource-server.properties'],
      name: 'supabaseResourceServerDefaults',
      conditions: [OnSupabaseResourceServer(legacy: false)],
    ),
    PropertySourceDeclaration(
      ['resources:supabase/resource-server-legacy.properties'],
      name: 'supabaseResourceServerDefaults',
      conditions: [OnSupabaseResourceServer(legacy: true)],
    ),
  ],
  resources: const {
    'supabase/resource-server.properties': EmbeddedResource.text(
      _resourceServer,
    ),
    'supabase/resource-server-legacy.properties': EmbeddedResource.text(
      _legacyResourceServer,
    ),
  },
);

// The security starter's properties, which this package sets defaults of
// without depending on it.
const _prefix = 'spring.security.oauth2.resourceserver.jwt';

// What both kinds of project have in common. A user's token only: its
// audience and its role are `authenticated` (the anon key and the service
// role key are signed tokens too, and are refused as bearer tokens).
// Roles from `app_metadata` only, which a user cannot change;
// `user_metadata`, which they can, is never read.
const _common =
    '$_prefix.issuer-uri='
    r'${spring.supabase.auth.issuer:${spring.supabase.url}/auth/v1}'
    '\n'
    '$_prefix.audiences=authenticated\n'
    '$_prefix.required-claims.role=authenticated\n'
    '$_prefix.require-expiry=true\n'
    '$_prefix.authorities-claim-name=app_metadata.roles\n'
    '$_prefix.authority-prefix=ROLE_\n';

// A project with signing keys: its public keys, asymmetric algorithms
// only.
const _resourceServer =
    '$_prefix.jwk-set-uri='
    r'${spring.supabase.url}/auth/v1/.well-known/jwks.json'
    '\n'
    '$_prefix.jws-algorithms=ES256,RS256\n'
    '$_common';

// A project that still signs with its legacy secret.
const _legacyResourceServer =
    '$_prefix.secret-key='
    r'${spring.supabase.auth.jwt-secret}'
    '\n'
    '$_prefix.jws-algorithms=HS256\n'
    '$_common';

/// Which way the repositories reach the database: with [sql], when
/// `spring.supabase.db.url` is set; without, when it is not, the project's
/// address is, and the application has no `spring.datasource.url` of its
/// own.
final class OnSupabaseData implements Condition {
  /// The condition of one of the two ways.
  const OnSupabaseData({required this.sql});

  /// Whether this is the condition of SQL over `spring.supabase.db.url`.
  final bool sql;

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    bool has(String key) =>
        (environment.getProperty(key)?.trim() ?? '').isNotEmpty;
    if (sql) {
      return has('spring.supabase.db.url');
    }
    return has('spring.supabase.url') &&
        !has('spring.supabase.db.url') &&
        !has('spring.datasource.url');
  }
}

/// Whether the server half configures Spring Security's resource server:
/// `spring.supabase.url` is set and `spring.supabase.auth.enabled` is not
/// `false`; [legacy] says for which kind of project (with
/// `spring.supabase.auth.jwt-secret` or without).
final class OnSupabaseResourceServer implements Condition {
  /// The condition of the defaults of one kind of project.
  const OnSupabaseResourceServer({required this.legacy});

  /// Whether this is the condition of a project with a legacy JWT secret.
  final bool legacy;

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    bool has(String key) =>
        (environment.getProperty(key)?.trim() ?? '').isNotEmpty;
    return has('spring.supabase.url') &&
        environment.getProperty('spring.supabase.auth.enabled')?.trim() !=
            'false' &&
        has('spring.supabase.auth.jwt-secret') == legacy;
  }
}
