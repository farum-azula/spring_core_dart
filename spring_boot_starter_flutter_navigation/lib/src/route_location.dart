import 'package:flutter/foundation.dart';

/// Where to navigate: a path, its query parameters and fragment, and an
/// optional object passed along that is not part of the address.
///
/// Usually made by the generated `<Page>Route.to(...)` or from a string by
/// `RouteTemplate.go`; two locations are equal when their addresses are
/// (the [extra] does not count).
///
/// ```dart
/// final location = RouteLocation('/catalog/books/978-0', params: {'page': 2});
/// location.uri; // /catalog/books/978-0?page=2
///
/// RouteLocation.expand('/catalog/books/{isbn}', pathVariables: {'isbn': '978-0'});
/// ```
@immutable
final class RouteLocation {
  /// The location of [path] with the query [params] (a value's
  /// `toString()`; an [Iterable] value repeats the parameter, `null` leaves
  /// it out), [fragment] and [extra].
  RouteLocation(
    String path, {
    Map<String, Object?> params = const {},
    this.fragment,
    this.extra,
  }) : path = _normalize(path),
       queryParameters = _query(params);

  /// The location of a written address (`/books/1?page=2#notes`), with
  /// [extra].
  factory RouteLocation.parse(String location, {Object? extra}) =>
      RouteLocation.fromUri(Uri.parse(location)).withExtra(extra);

  /// The location of [uri], an address the platform gave: the browser's
  /// address bar, a deep link. An `https` link gives its path; a link of
  /// the app's own scheme reads its host as the first segment
  /// (`neonbooks://catalog/books/1` is `/catalog/books/1`).
  factory RouteLocation.fromUri(Uri uri) {
    final custom =
        uri.hasScheme &&
        uri.scheme != 'http' &&
        uri.scheme != 'https' &&
        uri.host.isNotEmpty;
    final path = custom ? '/${uri.host}${uri.path}' : uri.path;
    return RouteLocation._(
      _normalize(path),
      {
        for (final MapEntry(:key, :value) in uri.queryParametersAll.entries)
          key: List.unmodifiable(value),
      },
      uri.hasFragment ? uri.fragment : null,
      null,
    );
  }

  /// The location of [pattern] with its variables replaced by
  /// [pathVariables] (each value's `toString()`, percent-encoded; a
  /// `{*rest}` value is the rest of the path, its `/` kept), with [params],
  /// [fragment] and [extra]. Throws an [ArgumentError] naming a variable
  /// [pathVariables] lacks.
  factory RouteLocation.expand(
    String pattern, {
    Map<String, Object?> pathVariables = const {},
    Map<String, Object?> params = const {},
    String? fragment,
    Object? extra,
  }) {
    final path = pattern.replaceAllMapped(_variable, (match) {
      final rest = match.group(1) == '*';
      final name = match.group(2)!;
      if (!pathVariables.containsKey(name) || pathVariables[name] == null) {
        throw ArgumentError.value(
          pathVariables,
          'pathVariables',
          'No value for the path variable "$name" of $pattern',
        );
      }
      final value = pathVariables[name].toString();
      if (rest) {
        final trimmed = value.startsWith('/') ? value.substring(1) : value;
        return trimmed.split('/').map(Uri.encodeComponent).join('/');
      }
      return Uri.encodeComponent(value);
    });
    // `/docs/{*path}` with `/core/a`: `/docs/` + `core/a`.
    return RouteLocation(
      path.replaceAll(RegExp('/+'), '/'),
      params: params,
      fragment: fragment,
      extra: extra,
    );
  }

  RouteLocation._(this.path, this.queryParameters, this.fragment, this.extra);

  // `{name}`, `{name:regex}`, `{*name}`.
  static final _variable = RegExp(
    r'\{(\*?)([A-Za-z_][A-Za-z0-9_]*)(?::[^}]*)?\}',
  );

  /// The path, starting with `/` (percent-encoded as in an address).
  final String path;

  /// The query parameters, each with its values in order.
  final Map<String, List<String>> queryParameters;

  /// The fragment after `#`, or `null`.
  final String? fragment;

  /// The object passed along with the navigation, not in the address.
  final Object? extra;

  /// The address: path, query and fragment.
  Uri get uri => Uri(
    path: path,
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
    fragment: fragment,
  );

  /// This location with its query parameters replaced by [params] (the
  /// same rules as the constructor); path, fragment and extra kept.
  RouteLocation withParams(Map<String, Object?> params) =>
      RouteLocation._(path, _query(params), fragment, extra);

  /// This location at [path]; its query, fragment and extra kept.
  RouteLocation withPath(String path) =>
      RouteLocation._(_normalize(path), queryParameters, fragment, extra);

  /// This location with [extra] instead of its own.
  RouteLocation withExtra(Object? extra) =>
      RouteLocation._(path, queryParameters, fragment, extra);

  // `/docs/beans/` is `/docs/beans`: static hosts (Cloudflare Pages,
  // GitHub Pages, nginx) send a folder's address with a `/` at its end
  // when the build wrote `docs/beans/index.html`.
  static String _normalize(String path) {
    final trimmed = path.replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      return '/';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static Map<String, List<String>> _query(Map<String, Object?> params) => {
    for (final MapEntry(:key, :value) in params.entries)
      if (value != null)
        key: List.unmodifiable(
          value is Iterable<Object?>
              ? [
                  for (final item in value)
                    if (item != null) item.toString(),
                ]
              : [value.toString()],
        ),
  };

  @override
  bool operator ==(Object other) => other is RouteLocation && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => uri.toString();
}

/// A typed key of something a screen reads from its route: a path
/// variable ([RouteVar]), a query parameter ([RouteParam]) or the extra
/// object ([RouteExtra]). The generator writes them per screen
/// (`BookPageRoute.isbn`), so a renamed variable breaks the build.
sealed class RouteKey<T> {
  const RouteKey();
}

/// A path variable of type [T]: `route.get(BookPageRoute.isbn)`.
final class RouteVar<T> extends RouteKey<T> {
  /// The variable [name].
  const RouteVar(this.name);

  /// The variable's name in the pattern.
  final String name;
}

/// A query parameter of type [T], `null` when absent:
/// `route.get(BookPageRoute.page)`.
final class RouteParam<T> extends RouteKey<T?> {
  /// The parameter [name].
  const RouteParam(this.name);

  /// The parameter's name in the address.
  final String name;
}

/// The extra object of type [T], `null` when the navigation passed none
/// (a reload, a deep link).
final class RouteExtra<T> extends RouteKey<T?> {
  /// The extra object.
  const RouteExtra();
}
