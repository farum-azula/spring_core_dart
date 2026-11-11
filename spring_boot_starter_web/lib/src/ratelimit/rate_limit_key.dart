import 'dart:async';
import 'dart:collection';

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
  /// client's address. Throws a [RateLimitKeyException] when the key
  /// itself is at fault, whatever the request.
  FutureOr<RateLimitSubject?> resolve(String key, RateLimitRequest request);
}

/// The error of a rule key that cannot give a value because of how it is
/// written, not because of the request: an expression that reads a
/// property nothing has.
///
/// A [RateLimitKeyResolver] throws it from `resolve`. The limiter then
/// counts the request by the client's address, as for a key without a
/// value, and says so once per rule at WARN on `spring.web.ratelimit`: a
/// rule that silently counts by something else than it says is a limit
/// nobody has. A value that is only missing in one request (a header the
/// client did not send, no user) is no error: `resolve` answers `null`.
///
/// ```dart
/// @override
/// RateLimitSubject? resolve(String key, RateLimitRequest request) =>
///     throw const RateLimitKeyException('no tenant table is configured');
/// ```
final class RateLimitKeyException implements Exception {
  /// A key at fault for the reason [message], which must not hold a
  /// value of the request: it is logged.
  const RateLimitKeyException(this.message);

  /// What is wrong with the key.
  final String message;

  @override
  String toString() => 'RateLimitKeyException: $message';
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
/// The expression reads `request` (its `path`, `method`, `remoteAddress`,
/// `headers`), `headers` (a map of the request's headers, whose names
/// are found in any case, as HTTP has them), `principal` and
/// `authentication` (the authenticated user, `null` without one: write
/// `authentication?.name`), `address` (the client's address), `method`
/// and `path`; properties of `@Introspected` classes can be read.
///
/// A result of `null` or an empty text, and an expression that fails on
/// a missing value (a header the request does not have, no user), count
/// the request by its address: that is what a key without a value means.
/// An expression that fails for another reason (it reads a property or
/// calls a method that does not exist) throws a [RateLimitKeyException]:
/// the request is counted by its address too, and the limiter warns once
/// for the rule.
///
/// ```yaml
/// key: "#{request.headers['X-Api-Key']}"
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
    } on SpelEvaluationException catch (error) {
      if (!_missingValue.contains(error.messageCode) &&
          !_missingHeader(error)) {
        throw RateLimitKeyException(_reason(error));
      }
      // The value of the key is not logged: it may name a user.
      _log.debug(
        () =>
            'A rate limit key expression gave no value '
            '(${error.messageCode.name}): counted by address',
      );
      return null;
    } on Object catch (error) {
      throw RateLimitKeyException('${error.runtimeType}');
    }
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : RateLimitSubject('key', text);
  }

  // The failures of a request without the value: something is read from
  // a null. Every other failure is the expression's own.
  static const Set<SpelMessage> _missingValue = {
    SpelMessage.propertyOrFieldNotReadableOnNull,
    SpelMessage.methodCallOnNullObjectNotAllowed,
    SpelMessage.cannotIndexIntoNullValue,
  };

  // `headers.name` of a header the request does not have: a map has no
  // property of a key it does not hold. The request is without the
  // value, as with `headers['name']`; the expression is not at fault.
  static bool _missingHeader(SpelEvaluationException error) =>
      error.messageCode == SpelMessage.propertyOrFieldNotReadable &&
      error.inserts.lastOrNull == _Headers;

  // The failures whose message names only what the expression names (a
  // property, a method, a type): safe to log. Of the others only the
  // code is given, as their message may quote a value of the request.
  static const Set<SpelMessage> _named = {
    SpelMessage.propertyOrFieldNotReadable,
    SpelMessage.methodNotFound,
    SpelMessage.functionNotDefined,
    SpelMessage.typeNotFound,
    SpelMessage.indexingNotSupportedForType,
  };

  static String _reason(SpelEvaluationException error) =>
      _named.contains(error.messageCode)
      ? error.simpleMessage
      : error.messageCode.name;

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
      'headers': (request) => _Headers(request.headers),
    },
  );

  static final _principalAccessor = FunctionPropertyAccessor<Principal>(
    getters: {'name': (principal) => principal.name},
  );
}

final class _Root {
  _Root(this.request);

  final RateLimitRequest request;

  late final headers = _Headers(request.request.headers);
}

// The headers of a request as the map an expression reads: a name is
// found in any case (`headers['X-Api-Key']`, `headers['x-api-key']`),
// as HTTP header names are, and also as a property (`headers.host`).
final class _Headers extends UnmodifiableMapBase<String, String> {
  _Headers(this._headers);

  final HttpHeaders _headers;

  @override
  Iterable<String> get keys => _headers.names;

  @override
  String? operator [](Object? key) => key is String ? _headers[key] : null;

  @override
  bool containsKey(Object? key) => key is String && _headers.contains(key);
}
