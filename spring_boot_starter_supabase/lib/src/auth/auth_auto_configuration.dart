import 'package:spring_boot_starter_supabase/src/auth/supabase_auth.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_auth_admin.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_auth_exception.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_supabase#SupabaseAutoConfiguration';

const _enabled = ConditionalOnProperty(
  'spring.supabase.auth.enabled',
  matchIfMissing: true,
);

/// The beans of Supabase Auth, unless `spring.supabase.auth.enabled` is
/// false:
///
/// - `supabaseAuthErrors`, a [SupabaseAuthErrors]: Auth's errors as
///   Spring Security's exceptions, the application's
///   [SupabaseAuthErrorTranslator] beans asked first;
/// - `supabaseAuth`, a [SupabaseAuth], also the application's
///   `LoginSession`: it takes the `SecretStore`, the `AuthorizationWindow`
///   and the `ApplicationEventPublisher` of the application when there
///   are any, restores the session of the last run at startup
///   (`AsyncStartup`) and stops its timer when the application stops
///   (`DisposableBean`);
/// - `supabaseAuthAdmin`, a [SupabaseAuthAdmin]: the admin API, as the
///   service role.
///
/// Each steps back for a bean of its type declared by the application.
final supabaseAuthAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<SupabaseAuthErrors>(
    name: 'supabaseAuthErrors',
    factoryMethodName: 'supabaseAuthErrors',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseAuthErrors', [
        _enabled,
        ConditionalOnMissingBean(SupabaseAuthErrors),
      ]),
    ],
    create: (r) => SupabaseAuthErrors(
      r.optionalDependencyList<SupabaseAuthErrorTranslator>() ??
          const <SupabaseAuthErrorTranslator>[],
    ),
  ),
  BeanDefinition<SupabaseAuth>(
    name: 'supabaseAuth',
    factoryMethodName: 'supabaseAuth',
    source: _source,
    types: const [SupabaseAuth, LoginSession, AsyncStartup, DisposableBean],
    conditions: const [
      ConditionGroup('$_source.supabaseAuth', [
        _enabled,
        ConditionalOnMissingBean(SupabaseAuth),
      ]),
    ],
    create: (r) => SupabaseAuth(
      http: r.dependency<SupabaseHttp>(),
      secretStore: r.optionalDependency<SecretStore>(),
      authorizationWindow: r.optionalDependency<AuthorizationWindow>(),
      eventPublisher: r.optionalDependency<ApplicationEventPublisher>(),
      errors: r.dependency<SupabaseAuthErrors>(),
    ),
  ),
  BeanDefinition<SupabaseAuthAdmin>(
    name: 'supabaseAuthAdmin',
    factoryMethodName: 'supabaseAuthAdmin',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseAuthAdmin', [
        _enabled,
        ConditionalOnMissingBean(SupabaseAuthAdmin),
      ]),
    ],
    create: (r) => SupabaseAuthAdmin(
      http: r.dependency<SupabaseHttp>(),
      errors: r.dependency<SupabaseAuthErrors>(),
    ),
  ),
];
