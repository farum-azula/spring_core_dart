/// Supabase for spring_boot_dart, on a server and in Flutter apps: its
/// database through Spring Data, its Auth through Spring Security,
/// Realtime as streams, Storage as a template and as declared buckets,
/// Edge Functions as declared interfaces.
///
/// ```yaml
/// spring:
///   supabase:
///     url: https://abcd.supabase.co
///     anon-key: ${SUPABASE_ANON_KEY}
/// ```
///
/// ```dart
/// abstract interface class Todos implements ListCrudRepository<Todo, int> {
///   Future<List<Todo>> findByDoneOrderByCreatedAtDesc(bool done);
/// }
///
/// @StorageBucket('avatars')
/// abstract interface class Avatars {
///   @Upload('#{authentication.name}/avatar.png', upsert: true)
///   Future<void> put(Uint8List bytes);
/// }
///
/// @EdgeFunctions()
/// abstract interface class Functions {
///   @EdgeFunction('send-invite')
///   Future<InviteResult> sendInvite(@RequestBody() Invite invite);
/// }
/// ```
///
/// Every call is made as the same user: the bean `SupabaseCredentials`
/// gives each of them its key and token, and what a user may read and
/// write is decided by the database (row-level security).
///
/// Its own client, over the `HttpTransport` and the WebSocket starter: no
/// third-party package, and it compiles to WebAssembly.
library;

export 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
export 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
export 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
export 'package:spring_security_core/spring_security_core.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/auth/supabase_auth.dart';
export 'src/auth/supabase_auth_admin.dart';
export 'src/auth/supabase_auth_exception.dart';
export 'src/auth/supabase_authentication_token.dart';
export 'src/auth/supabase_pkce.dart';
export 'src/auth/supabase_session.dart';
export 'src/auth/supabase_user.dart';
export 'src/cache/supabase_cache.dart';
export 'src/config/supabase_properties.dart';
export 'src/data/postgrest_data_store.dart';
export 'src/data/postgrest_query.dart';
export 'src/data/supabase_rls.dart';
export 'src/expression/call_template.dart';
export 'src/functions/edge_functions.dart';
export 'src/http/supabase_http.dart';
export 'src/ratelimit/supabase_rate_limit_store.dart';
export 'src/realtime/realtime_channel.dart';
export 'src/realtime/realtime_model.dart';
export 'src/realtime/realtime_presence_state.dart';
export 'src/realtime/supabase_realtime.dart';
export 'src/storage/storage_bucket.dart';
export 'src/storage/storage_exception.dart';
export 'src/storage/storage_model.dart';
export 'src/storage/storage_template.dart';
export 'src/supabase_credentials.dart';
export 'src/supabase_exception.dart';
export 'src/supabase_startup.dart';
