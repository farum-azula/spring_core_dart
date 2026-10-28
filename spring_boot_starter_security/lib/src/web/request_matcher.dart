import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The answer of [RequestMatcher.matcher]: whether the request matched,
/// and the path variables a pattern such as `/users/{id}` captured.
///
/// The access rules pass the variables on to their `AuthorizationManager`
/// in a `RequestAuthorizationContext`.
///
/// Spring (Java): `RequestMatcher.MatchResult`.
final class MatchResult {
  /// A match, with the captured path [variables] (none by default).
  const MatchResult.match([this.variables = const {}]) : isMatch = true;

  /// No match; [variables] is empty.
  const MatchResult.notMatch() : isMatch = false, variables = const {};

  /// `true` when the request matched.
  final bool isMatch;

  /// The path variables by name, percent-decoded: `{'id': '42'}` for
  /// `/users/42` and the pattern `/users/{id}`.
  final Map<String, String> variables;
}

/// A test on a request (its path, method or headers) that decides whether
/// a chain, a rule or a handler applies to it.
///
/// `HttpSecurity` builds them from path patterns, so applications rarely
/// create one. Implement it, or extend [SimpleRequestMatcher], for a rule
/// that depends on something else, and pass it to `requestMatchersOf` or
/// `securityMatcherOf`.
///
/// ```dart
/// // Requests coming through the internal load balancer.
/// final class InternalRequests extends SimpleRequestMatcher {
///   const InternalRequests();
///
///   @override
///   bool matches(ServerHttpRequest request) =>
///       request.headers['X-Internal'] == 'true';
/// }
/// ```
///
/// Spring (Java): `RequestMatcher`.
abstract interface class RequestMatcher {
  /// Whether [request] matches. It must not throw: a throwing matcher fails
  /// the request.
  bool matches(ServerHttpRequest request);

  /// Whether [request] matches, with the path variables it captured.
  MatchResult matcher(ServerHttpRequest request);
}

/// A base class for [RequestMatcher]s that capture no path variables:
/// implement [matches] only.
abstract class SimpleRequestMatcher implements RequestMatcher {
  /// Lets subclasses be `const`.
  const SimpleRequestMatcher();

  @override
  MatchResult matcher(ServerHttpRequest request) => matches(request)
      ? const MatchResult.match()
      : const MatchResult.notMatch();
}

/// The [RequestMatcher] that matches every request; behind
/// `anyRequest()` and a chain without `securityMatcher`.
///
/// Spring (Java): `AnyRequestMatcher.INSTANCE`.
final class AnyRequestMatcher extends SimpleRequestMatcher {
  const AnyRequestMatcher._();

  /// The only instance.
  static const instance = AnyRequestMatcher._();

  @override
  bool matches(ServerHttpRequest request) => true;

  @override
  String toString() => 'any request';
}

/// A [RequestMatcher] that tests the path against a `PathPattern`, and
/// optionally the method; it is behind `requestMatchers('/api/**')`.
///
/// It uses the router's own patterns (`/api/**`, `/users/{id}`) on the
/// same path the router sees, so a rule covers exactly the requests the
/// controllers mapped under it get. The path is case-sensitive and a
/// trailing slash counts, as in the router: `/admin/` is not `/admin`.
/// Protect both (`/admin`, `/admin/**`) when a controller maps both. The
/// path does not include the context path.
///
/// Spring (Java): `PathPatternRequestMatcher`.
final class PathPatternRequestMatcher implements RequestMatcher {
  /// Matches requests whose path matches [pattern] and, when [method] is
  /// given, whose method is [method]. A missing leading `/` is added.
  ///
  /// Throws when [pattern] is not a valid path pattern.
  PathPatternRequestMatcher(String pattern, {this.method})
    : pattern = PathPattern.parse(_absolute(pattern));

  /// The parsed path pattern.
  final PathPattern pattern;

  /// The method requests must have, or `null` for any method.
  final HttpMethod? method;

  static String _absolute(String pattern) =>
      pattern.startsWith('/') ? pattern : '/$pattern';

  @override
  bool matches(ServerHttpRequest request) => matcher(request).isMatch;

  @override
  MatchResult matcher(ServerHttpRequest request) {
    if (method != null && request.method != method) {
      return const MatchResult.notMatch();
    }
    final match = pattern.match(request.path);
    return match == null
        ? const MatchResult.notMatch()
        : MatchResult.match(match.variables);
  }

  @override
  String toString() =>
      'PathPattern [${method == null ? '' : '${method!.value} '}$pattern]';
}

/// A [RequestMatcher] that tests the method only, whatever the path.
///
/// Spring has no such class; there you pass a method and `/**`.
final class HttpMethodRequestMatcher extends SimpleRequestMatcher {
  /// Matches requests whose method is [method].
  const HttpMethodRequestMatcher(this.method);

  /// The method requests must have.
  final HttpMethod method;

  @override
  bool matches(ServerHttpRequest request) => request.method == method;

  @override
  String toString() => 'method ${method.value}';
}

/// A [RequestMatcher] that matches when all of its [matchers] do.
///
/// The path variables of all of them are merged.
///
/// Spring (Java): `AndRequestMatcher`.
final class AndRequestMatcher implements RequestMatcher {
  /// Matches when all of [matchers] do; an empty list matches every
  /// request.
  AndRequestMatcher(List<RequestMatcher> matchers)
    : matchers = List.unmodifiable(matchers);

  /// The matchers, in order; cannot be modified.
  final List<RequestMatcher> matchers;

  @override
  bool matches(ServerHttpRequest request) =>
      matchers.every((m) => m.matches(request));

  @override
  MatchResult matcher(ServerHttpRequest request) {
    final variables = <String, String>{};
    for (final m in matchers) {
      final result = m.matcher(request);
      if (!result.isMatch) {
        return const MatchResult.notMatch();
      }
      variables.addAll(result.variables);
    }
    return MatchResult.match(variables);
  }

  @override
  String toString() => 'And $matchers';
}

/// A [RequestMatcher] that matches when any of its [matchers] does.
///
/// The path variables are those of the first matcher that matched.
///
/// Spring (Java): `OrRequestMatcher`.
final class OrRequestMatcher implements RequestMatcher {
  /// Matches when one of [matchers] does; an empty list matches nothing.
  OrRequestMatcher(List<RequestMatcher> matchers)
    : matchers = List.unmodifiable(matchers);

  /// The matchers, in order; cannot be modified.
  final List<RequestMatcher> matchers;

  @override
  bool matches(ServerHttpRequest request) =>
      matchers.any((m) => m.matches(request));

  @override
  MatchResult matcher(ServerHttpRequest request) {
    for (final m in matchers) {
      final result = m.matcher(request);
      if (result.isMatch) {
        return result;
      }
    }
    return const MatchResult.notMatch();
  }

  @override
  String toString() => 'Or $matchers';
}

/// A [RequestMatcher] that matches exactly when [negated] does not.
///
/// Spring (Java): `NegatedRequestMatcher`.
final class NegatedRequestMatcher extends SimpleRequestMatcher {
  /// Matches the requests [negated] does not match.
  const NegatedRequestMatcher(this.negated);

  /// The matcher whose answer is reversed.
  final RequestMatcher negated;

  @override
  bool matches(ServerHttpRequest request) => !negated.matches(request);

  @override
  String toString() => 'Not [$negated]';
}

/// A [RequestMatcher] that tests a request header: present, or equal to
/// a given value.
///
/// Spring (Java): `RequestHeaderRequestMatcher`.
final class RequestHeaderRequestMatcher extends SimpleRequestMatcher {
  /// Matches requests with the header [name], whose value equals [value]
  /// when one is given.
  const RequestHeaderRequestMatcher(this.name, [this.value]);

  /// The header name.
  final String name;

  /// The exact value the header must have, or `null` for any value.
  final String? value;

  @override
  bool matches(ServerHttpRequest request) {
    final actual = request.headers[name];
    return actual != null && (value == null || actual == value);
  }

  @override
  String toString() => 'header $name${value == null ? '' : '=$value'}';
}

/// A [RequestMatcher] that tests the media types the client accepts (the
/// `Accept` header).
///
/// The starter uses it to tell browsers, which accept `text/html` and get
/// a redirect to the login page, from programs, which get a 401. Types in
/// [ignoredMediaTypes] are skipped in `Accept`; with [useEquals] only an
/// exact type counts, with no wildcards on either side.
///
/// Spring (Java): `MediaTypeRequestMatcher`.
final class MediaTypeRequestMatcher extends SimpleRequestMatcher {
  /// Matches requests that accept one of [mediaTypes].
  const MediaTypeRequestMatcher(
    this.mediaTypes, {
    this.ignoredMediaTypes = const [],
    this.useEquals = false,
  });

  /// The media types looked for, such as `text/html`.
  final List<String> mediaTypes;

  /// Types in `Accept` that are skipped, such as `*/*`, so a client that
  /// accepts anything does not match everything.
  final List<String> ignoredMediaTypes;

  /// Whether an accepted type must equal a wanted one, rather than just
  /// be compatible (`text/*` with `text/html`).
  final bool useEquals;

  /// The types [request] accepts, in `Accept` order; `*/*` when it sends
  /// none, as in Spring's content negotiation. Unreadable entries are
  /// skipped.
  static List<MediaType> accepted(ServerHttpRequest request) {
    final header = request.headers.getAll(HttpHeaders.acceptHeader);
    final types = <MediaType>[];
    for (final value in header) {
      for (final part in value.split(',')) {
        final text = part.trim();
        if (text.isEmpty) {
          continue;
        }
        try {
          types.add(MediaType.parse(text));
        } on Object {
          // An unreadable entry is skipped, like Spring's lenient parsing.
        }
      }
    }
    return types.isEmpty ? [MediaType.parse('*/*')] : types;
  }

  @override
  bool matches(ServerHttpRequest request) {
    final ignored = [for (final t in ignoredMediaTypes) MediaType.parse(t)];
    final wanted = [for (final t in mediaTypes) MediaType.parse(t)];
    for (final accepted in accepted(request)) {
      if (ignored.any((i) => _same(i, accepted))) {
        continue;
      }
      for (final type in wanted) {
        if (useEquals
            ? _same(type, accepted)
            : type.isCompatibleWith(accepted)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _same(MediaType a, MediaType b) =>
      a.type == b.type && a.subtype == b.subtype;

  @override
  String toString() => 'Accept $mediaTypes';
}
