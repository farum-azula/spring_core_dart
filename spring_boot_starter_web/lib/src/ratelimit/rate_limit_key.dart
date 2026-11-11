import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Who a request is counted as: a [kind] (`ip`, `user`, ...) and its
/// [value].
final class RateLimitSubject {
  /// A subject of the [kind] with [value].
  const RateLimitSubject(this.kind, this.value);

  /// The client's address.
  const RateLimitSubject.address(this.value) : kind = addressKind;

  /// The authenticated user of the name [value].
  const RateLimitSubject.user(this.value) : kind = 'user';

  /// The kind of an address: the one whose values are hashed with
  /// `spring.web.rate-limit.hash-addresses`.
  static const addressKind = 'ip';

  /// What the value is: `ip`, `user`, or what a resolver calls its own.
  final String kind;

  /// The address, the user's name, the value of an expression.
  final String value;

  /// Whether the value is an address.
  bool get isAddress => kind == addressKind;
}

/// A request as the key resolvers see it: the request and the client's
/// address, worked out once.
final class RateLimitRequest {
  /// The [request], whose address `address` gives when it is asked for.
  RateLimitRequest(this.request, {required this._address});

  /// The request.
  final ServerHttpRequest request;

  final String? Function() _address;

  /// The client's address (`ClientAddressResolver`); `null` when the
  /// server does not know it.
  late final String? address = _address();

  /// The authenticated user; `null` before authentication and for an
  /// anonymous request.
  Principal? get principal => request.principal;
}

/// Turns the `key` of a rule into who a request is counted as: the
/// extension point for keys.
///
/// The resolvers are asked in order ([supports]); the first that knows a
/// key resolves it. The application's beans come first, then the
/// built-in ones: `ip` ([AddressRateLimitKeyResolver]), `user`
/// ([UserRateLimitKeyResolver]) and `#{...}`
/// ([ExpressionRateLimitKeyResolver]).
///
/// ```dart
/// // `key: tenant` counts all users of a tenant together.
/// @Component()
/// class TenantKeyResolver implements RateLimitKeyResolver {
///   @override
///   bool supports(String key) => key == 'tenant';
///
///   @override
///   bool beforeAuthentication(String key) => true; // reads a header only
///
///   @override
///   RateLimitSubject? resolve(String key, RateLimitRequest request) =>
///       switch (request.request.headers['X-Tenant']) {
///         final tenant? => RateLimitSubject('tenant', tenant),
///         null => null, // counted by address
///       };
/// }
/// ```
///
/// Spring (Java): Spring Cloud Gateway's `KeyResolver`.
abstract interface class RateLimitKeyResolver {
  /// Whether this resolver knows the rule key [key].
  bool supports(String key);

  /// Whether [key] can be resolved before the request is authenticated:
  /// its rules then refuse a request before any authentication work. A
  /// key that reads the user answers `false`; its rules run right after
  /// the security filters.
  bool beforeAuthentication(String key);

  /// Who [request] is counted as under [key]; `null` to count it by the
  /// client's address.
  FutureOr<RateLimitSubject?> resolve(String key, RateLimitRequest request);
}

/// The key `ip`: the client's address ([RateLimitRequest.address]),
/// before authentication.
final class AddressRateLimitKeyResolver implements RateLimitKeyResolver {
  /// The resolver.
  const AddressRateLimitKeyResolver();

  /// The key it resolves.
  static const key = 'ip';

  @override
  bool supports(String key) => key == AddressRateLimitKeyResolver.key;

  @override
  bool beforeAuthentication(String key) => true;

  @override
  RateLimitSubject? resolve(String key, RateLimitRequest request) => null;
}

/// The key `user`, the default: the authenticated user's name
/// (`request.principal`, which the security starter sets), else the
/// client's address. After authentication.
final class UserRateLimitKeyResolver implements RateLimitKeyResolver {
  /// The resolver.
  const UserRateLimitKeyResolver();

  /// The key it resolves.
  static const key = 'user';

  @override
  bool supports(String key) => key == UserRateLimitKeyResolver.key;

  @override
  bool beforeAuthentication(String key) => false;

  @override
  RateLimitSubject? resolve(String key, RateLimitRequest request) =>
      switch (request.principal?.name) {
        final name? when name.isNotEmpty => RateLimitSubject.user(name),
        _ => null,
      };
}

/// A key written as a SpEL expression in `#{...}`, after authentication.
///
/// The expression reads `request` (its `path`, `method`, `remoteAddress`),
/// `headers` (a map, names in lower case), `principal` and
/// `authentication` (the authenticated user, `null` without one: write
/// `authentication?.name`), `address` (the client's address), `method`
/// and `path`; properties of `@Introspected` classes can be read. A
/// result of `null` or an empty text, and an expression that fails on a
/// missing value, count the request by its address.
///
/// ```yaml
/// key: "#{headers['x-api-key']}"
/// ```
///
/// ```dart
/// @RateLimiter('10/1m', key: '#{authentication.name}')
/// ```
final class ExpressionRateLimitKeyResolver implements RateLimitKeyResolver {
  /// A resolver whose expressions read `@Introspected` classes through
  /// [introspector].
  ExpressionRateLimitKeyResolver({BeanIntrospector? introspector})
    : _introspector = introspector ?? BeanIntrospector.shared;

  static const _log = SpringLog('spring.web.ratelimit');

  final BeanIntrospector _introspector;
  final _parser = SpelExpressionParser();
  final _expressions = <String, Expression>{};

  @override
  bool supports(String key) => key.contains('#{');

  @override
  bool beforeAuthentication(String key) => false;

  Expression _expression(String key) => _expressions[key] ??=
      key.startsWith('#{') && key.endsWith('}') && key.indexOf('#{', 2) < 0
      ? _parser.parseExpression(key.substring(2, key.length - 1))
      : _parser.parseExpression(key, ParserContext.template);

  /// Parses [key] now, so that a rule with a malformed expression stops
  /// the start. Throws the parser's error.
  void validate(String key) => _expression(key);

  @override
  RateLimitSubject? resolve(String key, RateLimitRequest request) {
    final context = StandardEvaluationContext(_Root(request))
      ..addPropertyAccessor(_rootAccessor)
      ..addPropertyAccessor(_requestAccessor)
      ..addPropertyAccessor(_principalAccessor)
      ..addPropertyAccessor(IntrospectionPropertyAccessor(_introspector));
    Object? value;
    try {
      value = _expression(key).getValue(context);
    } on Object catch (error) {
      // The value of the key is not logged: it may name a user.
      _log.debug(
        () =>
            'A rate limit key expression gave no value '
            '(${error.runtimeType}): counted by address',
      );
      return null;
    }
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : RateLimitSubject('key', text);
  }

  static final _rootAccessor = FunctionPropertyAccessor<_Root>(
    getters: {
      'request': (root) => root.request.request,
      'headers': (root) => root.headers,
      'principal': (root) => root.request.principal,
      'authentication': (root) => root.request.principal,
      'address': (root) => root.request.address,
      'method': (root) => root.request.request.method.value,
      'path': (root) => root.request.request.path,
    },
  );

  static final _requestAccessor = FunctionPropertyAccessor<ServerHttpRequest>(
    getters: {
      'path': (request) => request.path,
      'method': (request) => request.method.value,
      'remoteAddress': (request) => request.remoteAddress,
      'principal': (request) => request.principal,
    },
  );

  static final _principalAccessor = FunctionPropertyAccessor<Principal>(
    getters: {'name': (principal) => principal.name},
  );
}

final class _Root {
  _Root(this.request);

  final RateLimitRequest request;

  late final Map<String, String> headers = {
    for (final name in request.request.headers.names)
      name.toLowerCase(): request.request.headers[name] ?? '',
  };
}
