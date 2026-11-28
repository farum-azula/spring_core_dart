import 'package:spring_web_dart/src/client/rest/uri_template.dart';

/// Builds the URI of a `RestClient` call piece by piece: the path, query
/// parameters (some only when they have a value), the fragment. It starts
/// from the client's base URL, and its pieces may hold `{variables}`,
/// filled by [build].
///
/// ```dart
/// final books = await rest.get()
///     .uri((UriBuilder uri) => uri
///         .path('/books')
///         .queryParam('author', author)
///         .queryParamIfPresent('year', year) // left out when null
///         .build())
///     .retrieve()
///     .body<List<Book>>(const ListType(ClassType<Book>()));
/// ```
///
/// The text of each piece is encoded for its place (a `&` in a query
/// value, a `/` in a path segment); a `{variable}` value is encoded
/// strictly, as in a template.
///
/// Spring (Java): `UriBuilder` (from `UriComponentsBuilder` and
/// `DefaultUriBuilderFactory`), passed to
/// `uri(Function<UriBuilder, URI>)`.
final class UriBuilder {
  /// A builder starting from [base] (a URL or a URI template, `''` for
  /// none) and filling variables from [defaults] when [build] gets a map.
  UriBuilder([String base = '', Map<String, Object?> defaults = const {}])
    : _defaults = defaults {
    final hash = base.indexOf('#');
    final withoutFragment = hash < 0 ? base : base.substring(0, hash);
    if (hash >= 0) {
      _fragment = base.substring(hash + 1);
    }
    final question = withoutFragment.indexOf('?');
    _prefix = question < 0
        ? withoutFragment
        : withoutFragment.substring(0, question);
    if (question >= 0) {
      for (final pair in withoutFragment.substring(question + 1).split('&')) {
        if (pair.isEmpty) {
          continue;
        }
        final equals = pair.indexOf('=');
        _query.add(
          equals < 0
              ? (pair, null)
              : (pair.substring(0, equals), pair.substring(equals + 1)),
        );
      }
    }
  }

  final Map<String, Object?> _defaults;
  // The scheme, authority and path so far, already encoded.
  late String _prefix;
  final _query = <(String, String?)>[];
  String? _fragment;

  /// Sets the scheme (`https`), keeping the rest.
  UriBuilder scheme(String scheme) => _replaceOrigin(scheme: scheme);

  /// Sets the host, keeping the scheme, port and path.
  UriBuilder host(String host) => _replaceOrigin(host: host);

  /// Sets the port, keeping the scheme, host and path.
  UriBuilder port(int port) => _replaceOrigin(port: port);

  UriBuilder _replaceOrigin({String? scheme, String? host, int? port}) {
    final current = Uri.tryParse(_prefix.isEmpty ? '/' : _prefix);
    final path = current?.path ?? '';
    final origin = Uri(
      scheme: scheme ?? (current?.hasScheme ?? false ? current!.scheme : null),
      host: host ?? current?.host,
      port: port ?? (current?.hasPort ?? false ? current!.port : null),
    );
    _prefix = '$origin$path';
    return this;
  }

  /// Appends [path] (it may hold `/` and `{variables}`), with one `/`
  /// between it and what is there.
  UriBuilder path(String path) {
    final encoded = _encodePieces(path, _isPathOrSlash);
    if (encoded.isEmpty) {
      return this;
    }
    final endsWithSlash = _prefix.endsWith('/');
    final startsWithSlash = encoded.startsWith('/');
    _prefix = endsWithSlash && startsWithSlash
        ? '$_prefix${encoded.substring(1)}'
        : endsWithSlash || startsWithSlash || _prefix.isEmpty
        ? '$_prefix$encoded'
        : '$_prefix/$encoded';
    return this;
  }

  /// Replaces the path with [path].
  UriBuilder replacePath(String path) {
    final current = Uri.tryParse(_prefix);
    _prefix = current == null || !current.hasAuthority
        ? ''
        : '${current.replace(path: '')}';
    return this.path(path);
  }

  /// Appends one path segment for each of [segments], a `/` inside one
  /// encoded (`a/b` stays one segment).
  UriBuilder pathSegment(List<String> segments) {
    for (final segment in segments) {
      path('/${_encodePieces(segment, UriTemplate.isPathCharacter)}');
    }
    return this;
  }

  /// Adds the query parameter [name] with [value]: an `Iterable` gives one
  /// parameter per item, `null` the name alone (`?flag`). Values are
  /// written as URI variables are (`DateTime` in ISO-8601, enums by name).
  ///
  /// A value is data: its `{` and `}` are encoded, so text from a user
  /// cannot become a variable. Only a value that is one variable as a
  /// whole (`'{isbn}'`) is filled by [build].
  UriBuilder queryParam(String name, [Object? value]) {
    final encodedName = _encodeValue(name);
    if (value == null) {
      _query.add((encodedName, null));
      return this;
    }
    for (final item in value is Iterable<Object?> ? value : [value]) {
      _query.add((encodedName, _encodeValue(UriTemplate.uriValueText(item))));
    }
    return this;
  }

  static final _wholeVariable = RegExp(r'^\{[^{}]+\}$');

  static String _encodeValue(String text) => _wholeVariable.hasMatch(text)
      ? text
      : UriTemplate.encodeAllowing(text, _isQueryCharacter);

  /// Adds a query parameter for each entry of [params], as [queryParam]
  /// does (an `Iterable` value gives one parameter per item); a `null`
  /// value, or a `null` item, adds nothing, as for the entries of a `Map`
  /// parameter of Spring's HTTP service clients.
  ///
  /// ```dart
  /// uri.path('/books').queryParams({'author': author, 'tag': ['sf', 'classic']})
  /// ```
  ///
  /// Spring (Java): `queryParams(MultiValueMap<String, String>)`.
  UriBuilder queryParams(Map<String, Object?> params) {
    for (final MapEntry(key: name, :value) in params.entries) {
      if (value is Iterable<Object?>) {
        for (final item in value) {
          if (item != null) {
            queryParam(name, item);
          }
        }
      } else if (value != null) {
        queryParam(name, value);
      }
    }
    return this;
  }

  /// Adds the query parameter [name] when [value] is not `null`; as
  /// [queryParam] otherwise.
  ///
  /// Spring (Java): `queryParamIfPresent(String, Optional<?>)`.
  UriBuilder queryParamIfPresent(String name, Object? value) =>
      value == null ? this : queryParam(name, value);

  /// Replaces every query parameter [name] with [value] (none when
  /// [value] is `null`).
  UriBuilder replaceQueryParam(String name, [Object? value]) {
    final encodedName = _encodeValue(name);
    _query.removeWhere((pair) => pair.$1 == encodedName);
    return value == null ? this : queryParam(name, value);
  }

  /// Sets the fragment (`#part`); `null` removes it.
  UriBuilder fragment(String? fragment) {
    _fragment = fragment == null ? null : _encodeValue(fragment);
    return this;
  }

  /// The URI, its `{variables}` filled from [variables] as
  /// `UriTemplate.expand` fills them (a `List` in order, a `Map` by name,
  /// one value for one variable).
  Uri build([Object? variables]) =>
      UriTemplate(toTemplate()).expand(variables, _defaults);

  /// The URI template the builder holds so far.
  String toTemplate() {
    final out = StringBuffer(_prefix);
    for (var i = 0; i < _query.length; i++) {
      final (name, value) = _query[i];
      out
        ..write(i == 0 ? '?' : '&')
        ..write(name);
      if (value != null) {
        out
          ..write('=')
          ..write(value);
      }
    }
    if (_fragment case final fragment?) {
      out
        ..write('#')
        ..write(fragment);
    }
    return out.toString();
  }

  static bool _isPathOrSlash(int unit) =>
      UriTemplate.isPathCharacter(unit) || unit == 0x2F;

  // A query name or value: pchar, `/` and `?`, without `&`, `=`, `+` and
  // `#`, which would change what the query says.
  static bool _isQueryCharacter(int unit) =>
      unit != 0x26 &&
      unit != 0x3D &&
      unit != 0x2B &&
      (UriTemplate.isPathCharacter(unit) || unit == 0x2F || unit == 0x3F);

  // [text] with its literal parts encoded for [allowed] and its
  // `{variables}` kept, for the template.
  static String _encodePieces(String text, bool Function(int unit) allowed) {
    if (!text.contains('{')) {
      return UriTemplate.encodeAllowing(text, allowed);
    }
    final out = StringBuffer();
    var start = 0;
    while (start < text.length) {
      final open = text.indexOf('{', start);
      if (open < 0) {
        out.write(UriTemplate.encodeAllowing(text.substring(start), allowed));
        break;
      }
      final close = text.indexOf('}', open);
      if (close < 0) {
        throw FormatException('A "{" without its "}"', text, open);
      }
      out
        ..write(
          UriTemplate.encodeAllowing(text.substring(start, open), allowed),
        )
        ..write(text.substring(open, close + 1));
      start = close + 1;
    }
    return out.toString();
  }

  @override
  String toString() => toTemplate();
}

/// Makes the [UriBuilder] instances of one base URL, and expands URI
/// templates against it: what an HTTP service method's `UriBuilderFactory`
/// parameter gives its call instead of the group's base URL (another host
/// per call; the host must still be among the allowed addresses).
///
/// ```dart
/// @GetExchange('/books/{isbn}')
/// Future<Book> find(UriBuilderFactory mirror, @PathVariable() String isbn);
///
/// await books.find(UriBuilderFactory('https://mirror.neon.books'), '978-0');
/// // GET https://mirror.neon.books/books/978-0
/// ```
///
/// Spring (Java): `UriBuilderFactory` with its `DefaultUriBuilderFactory`
/// (a base URI template and default URI variables; the encoding is that
/// of `UriTemplate`, not a setting).
final class UriBuilderFactory {
  /// The factory of [baseUrl] (a URL or a URI template, `''` for none),
  /// filling variables from [defaultUriVariables].
  const UriBuilderFactory([
    this.baseUrl = '',
    this.defaultUriVariables = const {},
  ]);

  /// The base of every URI it makes.
  final String baseUrl;

  /// The values of the variables a call does not give.
  final Map<String, Object?> defaultUriVariables;

  static final _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');

  /// A builder starting from the base URL.
  ///
  /// Spring (Java): `builder()`.
  UriBuilder builder() => UriBuilder(baseUrl, defaultUriVariables);

  /// A builder starting from [template] put after the base URL (one `/`
  /// between the paths, the base's query first); a whole URL
  /// (`https://...`) stays as it is.
  ///
  /// Spring (Java): `uriString(String)`.
  UriBuilder uriString(String template) =>
      UriBuilder(_withBase(template), defaultUriVariables);

  /// [template] put after the base URL and expanded with [variables], as
  /// `UriTemplate.expand` fills them (a `List` in order, a `Map` by name,
  /// one value for one variable).
  ///
  /// Spring (Java): `expand(String, Map)` and `expand(String, Object...)`.
  Uri expand(String template, [Object? variables]) =>
      UriTemplate(_withBase(template)).expand(variables, defaultUriVariables);

  String _withBase(String template) {
    final base = baseUrl;
    if (base.isEmpty || _scheme.hasMatch(template)) {
      return template;
    }
    final (basePath, baseQuery) = _splitQuery(base);
    final (path, query) = _splitQuery(template);
    final String joined;
    if (path.isEmpty) {
      joined = basePath;
    } else if (basePath.endsWith('/') && path.startsWith('/')) {
      joined = '$basePath${path.substring(1)}';
    } else if (basePath.endsWith('/') || path.startsWith('/')) {
      joined = '$basePath$path';
    } else {
      joined = '$basePath/$path';
    }
    final queries = [?baseQuery, ?query];
    return queries.isEmpty ? joined : '$joined?${queries.join('&')}';
  }

  static (String, String?) _splitQuery(String text) {
    final question = text.indexOf('?');
    return question < 0
        ? (text, null)
        : (text.substring(0, question), text.substring(question + 1));
  }

  @override
  String toString() => 'UriBuilderFactory($baseUrl)';
}
