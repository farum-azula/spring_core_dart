import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/expression/call_template.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_channel.dart';
import 'package:spring_boot_starter_supabase/src/realtime/supabase_realtime.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _source =
    'package:spring_boot_starter_supabase#SupabaseAutoConfiguration';

/// The Realtime beans of the starter, for every application:
///
/// - `supabaseRealtime`: [SupabaseRealtime], unless the application
///   declares its own; over the WebSocket starter's
///   `PhoenixSocketFactory` (its transport, handshake interceptors and
///   wire formats), with the application's `LoginSession` when it has
///   one. It closes its connection when the application stops.
/// - `realtimeChannelFactory`: makes the beans of the `@RealtimeChannel`
///   interfaces, with every [RealtimeChannelOperation] bean.
final supabaseRealtimeAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<SupabaseRealtime>(
    name: 'supabaseRealtime',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'supabaseRealtime',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.supabaseRealtime', [
        ConditionalOnMissingBean(SupabaseRealtime),
      ]),
    ],
    create: (r) => SupabaseRealtime(
      http: r.dependency<SupabaseHttp>(),
      credentials: r.dependency<SupabaseCredentials>(),
      sockets: r.dependency<PhoenixSocketFactory>(),
      // Looked up when the connection is first needed: the login may
      // need beans that need this one.
      session: r.provider<LoginSession>().getIfAvailable,
      maxMessageSize: r
          .dependency<SupabaseProperties>()
          .realtime
          .maxMessageSize,
    ),
  ),
  BeanDefinition<RealtimeChannelFactory>(
    name: 'realtimeChannelFactory',
    source: _source,
    types: const [RealtimeChannelFactory, InvocationHandlerFactory],
    create: (r) => RealtimeChannelFactory(
      realtime: r.dependency<SupabaseRealtime>(),
      templates: r.dependency<CallTemplates>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      operations:
          r.optionalDependencyList<RealtimeChannelOperation>() ??
          const <RealtimeChannelOperation>[],
    ),
  ),
];
