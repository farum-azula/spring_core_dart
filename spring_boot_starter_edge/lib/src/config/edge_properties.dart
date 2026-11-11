import 'package:spring_boot_dart/spring_boot_dart.dart';

/// `spring.edge.*`: the application as a function behind the fetch API
/// (Supabase Edge Functions, Cloudflare Workers, AWS Lambda).
///
/// ```yaml
/// spring:
///   edge:
///     warnings: false
/// ```
@ConfigurationProperties('spring.edge')
class EdgeProperties {
  /// The platform the function runs on (`supabase`, `cloudflare`, `aws`),
  /// set by the platform's entry file when the function starts; not set
  /// when the application runs as an ordinary server. Read it, do not
  /// write it.
  String? runtime;

  /// Whether the starter says once, when the function starts, which parts
  /// of the application work differently in a function (in-memory caches,
  /// `@Scheduled` methods, an in-memory rate limiter).
  bool warnings = true;

  /// What applies to a Supabase Edge Function only.
  EdgeSupabaseProperties supabase = EdgeSupabaseProperties();

  /// What applies to a Cloudflare Worker only.
  EdgeCloudflareProperties cloudflare = EdgeCloudflareProperties();
}

/// `spring.edge.cloudflare.*`.
class EdgeCloudflareProperties {
  /// The rate limiter's counters in a D1 database.
  EdgeCloudflareRateLimitProperties rateLimit =
      EdgeCloudflareRateLimitProperties();
}

/// `spring.edge.cloudflare.rate-limit.*`.
class EdgeCloudflareRateLimitProperties {
  /// The binding (`wrangler.toml`, `[[d1_databases]]`) of the D1 database
  /// the rate limiter counts in. With it, the default store of the rate
  /// limiter in a Worker is that database (`spring.web.rate-limit.store:
  /// d1`), shared by every instance.
  String? database;

  /// The table of the buckets, created when it is missing.
  String table = 'rate_limit';
}

/// `spring.edge.supabase.*`.
class EdgeSupabaseProperties {
  /// Whether a request whose bearer token is the project's anon key
  /// (`spring.supabase.anon-key`) is a request without a token. The
  /// Supabase clients send that key as the bearer token of everyone who
  /// is not signed in; it is public and names nobody, so the request is
  /// anonymous, as if it had no `Authorization` header. With `false` the
  /// key reaches the resource server, which answers 401 to it.
  bool anonKeyAsAnonymous = true;
}
