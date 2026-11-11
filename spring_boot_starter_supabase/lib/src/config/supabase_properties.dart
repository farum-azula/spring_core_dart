import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.supabase.*` properties.
///
/// ```yaml
/// spring:
///   supabase:
///     url: https://abcd.supabase.co
///     anon-key: ${SUPABASE_ANON_KEY}
/// ```
///
/// Differs from Spring: Spring has no Supabase support; the keys are this
/// project's own.
@ConfigurationProperties('spring.supabase')
class SupabaseProperties {
  /// The project's address (`https://<ref>.supabase.co`, or the local
  /// stack's `http://127.0.0.1:54321`). Every service is called under it
  /// (`/rest/v1`, `/auth/v1`, `/storage/v1`, `/functions/v1`,
  /// `/realtime/v1`), and a key or a token is only ever sent to it.
  String? url;

  /// The project's anon (publishable) key: sent as `apikey` with every
  /// call, and as the bearer token while nobody is signed in. It is meant
  /// to be public; what it may read and write is decided by the database's
  /// row-level security.
  String? anonKey;

  /// The project's service role (secret) key, used only inside
  /// `SupabaseCredentials.asServiceRole`. It passes row-level security:
  /// keep it on a server. An application that ships it (a Flutter app) is
  /// warned at build time and at startup, since whoever has the app has
  /// the key.
  String? serviceRoleKey;

  /// How long the connection of Realtime may take to open. The HTTP calls
  /// go through the application's `HttpTransport` bean, whose own connect
  /// timeout applies to them; [timeout] limits each of them as a whole.
  Duration connectTimeout = const Duration(seconds: 10);

  /// How long a call may take, the answer's body included. Downloads and
  /// uploads of Storage are not limited by it.
  Duration timeout = const Duration(seconds: 30);

  /// The database (`spring.supabase.db.*`).
  SupabaseDbProperties db = SupabaseDbProperties();

  /// Auth (`spring.supabase.auth.*`).
  SupabaseAuthProperties auth = SupabaseAuthProperties();

  /// Realtime (`spring.supabase.realtime.*`).
  SupabaseRealtimeProperties realtime = SupabaseRealtimeProperties();

  /// Storage (`spring.supabase.storage.*`).
  SupabaseStorageProperties storage = SupabaseStorageProperties();

  /// Edge Functions (`spring.supabase.functions.*`).
  SupabaseFunctionsProperties functions = SupabaseFunctionsProperties();

  /// Caches (`spring.supabase.cache.*`).
  SupabaseCacheProperties cache = SupabaseCacheProperties();

  /// The rate limiter's store (`rate-limit.*`).
  SupabaseRateLimitProperties rateLimit = SupabaseRateLimitProperties();
}

/// As whom the SQL path talks to the database
/// (`spring.supabase.db.rls`).
enum SupabaseRls {
  /// As the user of `spring.supabase.db.url` (usually `postgres`, which
  /// passes row-level security). The default.
  off,

  /// As the current user: every transaction sets the role `authenticated`
  /// (or `anon` when nobody is signed in) and the user's token claims, so
  /// the policies of row-level security apply with transactions and locks
  /// too.
  user,
}

/// How the repositories reach the database (`spring.supabase.db.*`).
@Introspected()
class SupabaseDbProperties {
  /// The PostgreSQL address of the project
  /// (`postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres`,
  /// or a pooler's). When it is set, the repositories use SQL over it
  /// (transactions, `@Lock`, SQL `@Query` and `JdbcClient` work); when it
  /// is not (the default), they use the project's REST API (PostgREST),
  /// where those do not exist.
  String? url;

  /// As whom SQL runs. See [SupabaseRls].
  SupabaseRls rls = SupabaseRls.off;

  /// The schema the REST API reads and writes (PostgREST's
  /// `Accept-Profile` / `Content-Profile`). Default: the API's own default
  /// (`public`).
  String? schema;

  /// The most rows the REST API returns in one answer: the project's
  /// "Max rows" (API settings), `max_rows` of the local stack. An answer
  /// that long may have been cut there, without any sign of it, so a query
  /// that asks for more (or for everything) reads on in further calls,
  /// ordered by the id. Set it to the project's value when that one was
  /// changed: with a larger number here a cut answer is taken for whole.
  int maxRows = 1000;
}

/// Auth (`spring.supabase.auth.*`).
@Introspected()
class SupabaseAuthProperties {
  /// Whether the starter plugs Supabase Auth into Spring Security: on a
  /// server its tokens are accepted as bearer tokens, in a client
  /// application `SupabaseAuth` signs users in.
  bool enabled = true;

  /// The addresses a login through a provider, a magic link or a password
  /// reset may come back to. A redirect to any other address is refused
  /// before the request is made. The first one is the default.
  List<String> redirectUrls = [];

  /// The issuer of the project's tokens (their `iss`). Default:
  /// `<url>/auth/v1`.
  String? issuer;

  /// The JWT secret of a project that still signs its tokens with HS256
  /// (the legacy secret). Server only: with it tokens can be forged for
  /// any user. Projects with signing keys (ES256, RS256) leave it unset
  /// and the server reads the project's public keys.
  String? jwtSecret;

  /// Whether the session is kept across restarts (in the application's
  /// secret store when it has one).
  bool persistSession = true;

  /// Whether the access token is refreshed in the background before it
  /// expires. Without it, it is refreshed when the next call needs it.
  bool autoRefresh = true;

  /// How long before its expiry an access token counts as expired.
  Duration refreshMargin = const Duration(seconds: 30);
}

/// Realtime (`spring.supabase.realtime.*`).
@Introspected()
class SupabaseRealtimeProperties {
  /// How often the connection says it is alive.
  Duration heartbeatInterval = const Duration(seconds: 25);

  /// How long a join or a message waits for its answer.
  Duration timeout = const Duration(seconds: 10);

  /// The largest message read from Realtime (a change of a row can be
  /// 1 MB, a broadcast 3 MB); a larger one closes the connection.
  DataSize maxMessageSize = DataSize.ofMegabytes(4);
}

/// Storage (`spring.supabase.storage.*`).
@Introspected()
class SupabaseStorageProperties {
  /// How long a signed URL is valid when the call does not say.
  Duration signedUrlExpiry = const Duration(hours: 1);
}

/// Edge Functions (`spring.supabase.functions.*`).
@Introspected()
class SupabaseFunctionsProperties {
  /// The region the functions run in (the `x-region` header); the nearest
  /// one when not set.
  String? region;

  /// How long a function may take. Default: `spring.supabase.timeout`.
  Duration? timeout;
}

/// Caches (`spring.supabase.cache.*`).
@Introspected()
class SupabaseCacheProperties {
  /// The caches whose entries are the same for every user. Every other
  /// cache keeps the entries of each user (and of the anon key and of the
  /// service role) apart, because with row-level security one call answers
  /// differently per user.
  List<String> shared = [];
}

/// The `spring.supabase.rate-limit.*` properties: the rate limiter's
/// store over a database function (`spring.web.rate-limit.store:
/// procedure`, the default of an application on the REST path).
@Introspected()
class SupabaseRateLimitProperties {
  /// The database function an acquisition calls; the one of the
  /// package's `sql/rate_limit.sql` unless that was renamed.
  String function = 'rate_limit_acquire';
}
