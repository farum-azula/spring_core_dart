import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The outcome of [RequestMatcher.matcher]: whether it matched, and the
/// path variables of a pattern (`/users/{id}`), like Spring's
/// `RequestMatcher.MatchResult`.
final class MatchResult {
  /// A match with [variables].
  const MatchResult.match([this.variables = const {}]) : isMatch = true;

  /// No match.
  const MatchResult.notMatch() : isMatch = false, variables = const {};

  /// Whether the request matched.
  final bool isMatch;

  /// The path variables, decoded.
  final Map<String, String> variables;
}

/// Decides whether a rule applies to a request, like Spring's
/// `RequestMatcher`.
abstract interface class RequestMatcher {
  /// Whether [request] matches.
  bool matches(ServerHttpRequest request);

  /// Whether [request] matches, with the path variables.
  MatchResult matcher(ServerHttpRequest request);
}

/// A matcher from [matches] alone.
abstract class SimpleRequestMatcher implements RequestMatcher {
  /// The matcher.
  const SimpleRequestMatcher();

  @override
  MatchResult matcher(ServerHttpRequest request) => matches(request)
      ? const MatchResult.match()
      : const MatchResult.notMatch();
}

/// Matches every request, like Spring's `AnyRequestMatcher`.
final class AnyRequestMatcher extends SimpleRequestMatcher {
  const AnyRequestMatcher._();

  /// The matcher.
  static const instance = AnyRequestMatcher._();

  @override
  bool matches(ServerHttpRequest request) => true;

  @override
  String toString() => 'any request';
}

/// Matches the path with a `PathPattern` — the router's own patterns, on
/// the same path the router sees, so a rule covers exactly the requests the
/// controllers mapped under it get (`/api/**`, `/users/{id}`) — and
/// optionally the method, like Spring's `PathPatternRequestMatcher`.
///
/// The path is case-sensitive and a trailing slash counts, as in the
/// router: `/admin/` is not `/admin`. Protect both (`/admin`, `/admin/**`)
/// when a controller maps both.
final class PathPatternRequestMatcher implements RequestMatcher {
  /// Requests whose path matches [pattern] (and whose method is [method]).
  PathPatternRequestMatcher(String pattern, {this.method})
    : pattern = PathPattern.parse(_absolute(pattern));

  /// The pattern.
  final PathPattern pattern;

  /// The method, or `null` for any.
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

/// Matches the method only.
final class HttpMethodRequestMatcher extends SimpleRequestMatcher {
  /// Requests with [method].
  const HttpMethodRequestMatcher(this.method);

  /// The method.
  final HttpMethod method;

  @override
  bool matches(ServerHttpRequest request) => request.method == method;

  @override
  String toString() => 'method ${method.value}';
}

/// All of [matchers], like Spring's `AndRequestMatcher`.
final class AndRequestMatcher implements RequestMatcher {
  /// Matches when all of [matchers] do.
  AndRequestMatcher(List<RequestMatcher> matchers)
    : matchers = List.unmodifiable(matchers);

  /// The matchers.
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

/// Any of [matchers], like Spring's `OrRequestMatcher`.
final class OrRequestMatcher implements RequestMatcher {
  /// Matches when one of [matchers] does.
  OrRequestMatcher(List<RequestMatcher> matchers)
    : matchers = List.unmodifiable(matchers);

  /// The matchers.
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

/// The opposite of [matcher], like Spring's `NegatedRequestMatcher`.
final class NegatedRequestMatcher extends SimpleRequestMatcher {
  /// Matches when [negated] does not.
  const NegatedRequestMatcher(this.negated);

  /// The negated matcher.
  final RequestMatcher negated;

  @override
  bool matches(ServerHttpRequest request) => !negated.matches(request);

  @override
  String toString() => 'Not [$negated]';
}

/// A header present (and equal to [value] when given), like Spring's
/// `RequestHeaderRequestMatcher`.
final class RequestHeaderRequestMatcher extends SimpleRequestMatcher {
  /// Requests with header [name] (equal to [value] when set).
  const RequestHeaderRequestMatcher(this.name, [this.value]);

  /// The header.
  final String name;

  /// The required value.
  final String? value;

  @override
  bool matches(ServerHttpRequest request) {
    final actual = request.headers[name];
    return actual != null && (value == null || actual == value);
  }

  @override
  String toString() => 'header $name${value == null ? '' : '=$value'}';
}

/// Matches the media types the client accepts (`Accept`), like Spring's
/// `MediaTypeRequestMatcher`: [ignoredMediaTypes] in `Accept` are skipped;
/// with [useEquals] only an exact type counts (no wildcards either way).
final class MediaTypeRequestMatcher extends SimpleRequestMatcher {
  /// Requests accepting one of [mediaTypes].
  const MediaTypeRequestMatcher(
    this.mediaTypes, {
    this.ignoredMediaTypes = const [],
    this.useEquals = false,
  });

  /// The media types (`text/html`).
  final List<String> mediaTypes;

  /// Accepted types skipped (`*/*`).
  final List<String> ignoredMediaTypes;

  /// Whether a type must be equal, not just compatible.
  final bool useEquals;

  /// The accepted types of [request]; `*/*` when it sends none, like
  /// Spring's content negotiation.
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
