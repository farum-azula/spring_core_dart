import 'package:spring_core_dart/spring_core_dart.dart';

/// What happens to a request when the rate limiter's store cannot be
/// reached (`on-store-failure`).
enum RateLimitStoreFailure {
  /// The request is refused with a 503 and `Retry-After`. The default: a
  /// limit that guards a login must not open when the database is down.
  deny,

  /// The request goes on, not counted.
  allow,
}

/// The `spring.web.rate-limit.*` properties: the web starter's rate
/// limiter and where it keeps its buckets.
///
/// They live here, not in the web starter, because the starters that
/// bring a store (data, Supabase) read `store` and `enabled` to decide
/// whether theirs is the one, and do not depend on the web starter.
///
/// ```yaml
/// spring:
///   web:
///     rate-limit:
///       trusted-proxies: [173.245.48.0/20]
///       rules:
///         - path: /api/auth/**
///           methods: [POST]
///           key: ip
///           limit: 5/1m
///         - path: /api/**
///           limit: 120/1m
/// ```
///
/// Spring Boot has none; Spring Cloud Gateway's
/// `spring.cloud.gateway.routes[*].filters: RequestRateLimiter` and
/// Resilience4j's `resilience4j.ratelimiter.instances.*` are the nearest.
@ConfigurationProperties('spring.web.rate-limit')
class RateLimitProperties {
  /// Whether requests are limited. Not set: on when [rules] has a rule,
  /// else off; an application that only uses `@RateLimiter` on its
  /// controllers sets it to `true` (the start fails when it does not).
  /// `false` turns the rules and the annotations off.
  bool? enabled;

  /// Where the buckets are kept: `memory` (this isolate), `primary-isolate`
  /// (the first isolate, for all of a pool), `jdbc` (the primary
  /// `DataSource`, data starter), `procedure` (a database function,
  /// Supabase starter), or the name another library gives its store. Not
  /// set: the most specific the application has, in that order from the
  /// last. A `RateLimitStore` bean of the application wins over all.
  @PropertyValues(['memory', 'primary-isolate', 'jdbc', 'procedure'])
  String? store;

  /// What happens to a request when the store cannot be reached; a rule
  /// may say otherwise for itself.
  RateLimitStoreFailure onStoreFailure = RateLimitStoreFailure.deny;

  /// Whether the store is asked at startup that what it keeps its buckets
  /// in is there (the table or the function of its migration, its
  /// binding): the application does not start without it, and says what to
  /// run. A store that cannot be reached at that moment is a warning, not
  /// a failed start. `false` skips the check (and its one call to the
  /// store).
  bool verifyStore = true;

  /// The `Retry-After` of the 503 a request gets when the store cannot be
  /// reached and the failure denies.
  Duration storeFailureRetryAfter = const Duration(seconds: 5);

  /// The reverse proxies in front of the server: addresses and CIDR
  /// ranges (IPv4 and IPv6). Only a connection from one of them has its
  /// [clientAddressHeader] read, and the client is the entry the first
  /// trusted proxy added, counting from the right. Empty (the default):
  /// no header is ever read, the client is the connection's own address.
  List<String> trustedProxies = [];

  /// The header a trusted proxy puts the client's address in:
  /// `X-Forwarded-For` (a list, read from the right), or a header with
  /// one address such as `CF-Connecting-IP`.
  String clientAddressHeader = 'X-Forwarded-For';

  /// How many bits of an IPv6 address say who a client is, 1 to 128: a
  /// client is counted by that prefix of its address, the rest zeroed.
  /// 64 (the default) is the network a provider gives one client, who
  /// chooses the other 64 bits and may change them for every request;
  /// 128 counts every address by itself. IPv4 addresses are counted
  /// whole, and the trusted proxies are compared by their whole address.
  int ipv6PrefixLength = 64;

  /// Whether keys made of an address are stored as their HMAC-SHA-256
  /// under [hashSecret], so that the store holds no address in clear.
  bool hashAddresses = false;

  /// The secret of [hashAddresses]; required with it. Every server that
  /// shares a store needs the same.
  String? hashSecret;

  /// Whether the answers carry `RateLimit-Limit`, `RateLimit-Remaining`
  /// and `RateLimit-Reset` (of the rule that leaves the least).
  bool headers = true;

  /// The store in memory (`memory.*`).
  RateLimitMemoryProperties memory = RateLimitMemoryProperties();

  /// The rules, each for the requests of a path. Every rule that matches
  /// a request applies: it passes only when all of them allow it.
  List<RateLimitRuleProperties> rules = [];

  /// Whether the limiter is on: [enabled], or a rule when that is not
  /// set.
  bool get isOn => enabled ?? rules.isNotEmpty;
}

/// The `spring.web.rate-limit.memory.*` properties.
@Introspected()
class RateLimitMemoryProperties {
  /// The most keys the stores in memory (`memory`, `primary-isolate`)
  /// keep; past it the buckets that are full again go, then the keys not
  /// used for the longest.
  int maxEntries = 100000;
}

/// One rule of `spring.web.rate-limit.rules`.
@Introspected()
class RateLimitRuleProperties {
  /// The rule's name: part of its keys in the store, and what the logs
  /// call it. Default: `rule-<n>`, its place in the list from 1. Name a
  /// rule so that reordering the list does not start its buckets anew.
  String? name;

  /// The paths the rule is for, as a mapping's pattern (`/api/**`,
  /// `/api/users/{id}`), inside the context path.
  String path = '/**';

  /// The HTTP methods the rule is for; empty for all.
  List<String> methods = [];

  /// Who a bucket belongs to: `user` (the authenticated user, else the
  /// client's address; the default), `ip` (the client's address, decided
  /// before any authentication work), or a SpEL expression in `#{...}`
  /// over `request`, `headers`, `principal`, `authentication`, `address`,
  /// `method` and `path` (`#{request.headers['X-Api-Key']}`, header
  /// names in any case); an expression that gives nothing counts by
  /// address. One that cannot be parsed fails the start; one that names
  /// what does not exist counts by address too, with one warning.
  String? key;

  /// The limit as `<count>/<duration>`: `5/1m`, `120/1m`, `10/s`.
  String? limit;

  /// The most requests at once (the size of the bucket) when it is not
  /// the count of [limit].
  int? burst;

  /// What happens to a request of this rule when the store cannot be
  /// reached; not set: `spring.web.rate-limit.on-store-failure`.
  RateLimitStoreFailure? onStoreFailure;
}
