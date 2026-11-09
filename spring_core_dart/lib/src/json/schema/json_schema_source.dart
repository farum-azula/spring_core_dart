/// Names the JSON Schema that the JSON of an `@Introspected` class is
/// checked against.
///
/// Put it on a class whose JSON comes from outside and has a published
/// schema: an order from a partner, a configuration file. When the
/// `ObjectMapper` has a `schemaResolver`, it checks the decoded JSON
/// against the schema before it builds the object, and throws a
/// `JsonSchemaValidationException` listing every violation with its path.
///
/// The [location] is one of:
/// - `resources:schemas/order.json`: a file below `lib/resources/`;
/// - `https://example.com/schemas/order.json` (or `http://`);
/// - `github:owner/repo/path/to/order.json@ref` (`@ref` optional).
///
/// The build keeps a copy of a remote schema below `lib/resources/`, at
/// [JsonSchemaLocations.resourceOf], so it is read like a resource.
///
/// ```dart
/// @Introspected()
/// @JsonSchemaSource('resources:schemas/order.json')
/// class Order {
///   const Order({required this.id, required this.items});
///   final String id;
///   final List<OrderItem> items;
/// }
/// ```
///
/// Spring (Java): Spring has no counterpart.
class JsonSchemaSource {
  /// The schema at [location] (see the class description for the forms).
  const JsonSchemaSource(this.location);

  /// Where the schema is: `resources:...`, `https://...`, `http://...` or
  /// `github:owner/repo/path@ref`.
  final String location;
}

/// Where the schemas of `@JsonSchemaSource` locations are kept below
/// `lib/resources/`.
///
/// Spring (Java): Spring has no counterpart.
abstract final class JsonSchemaLocations {
  static const _resources = 'resources:';
  static const _github = 'github:';
  static const _folder = 'json-schemas';
  static final _unsafe = RegExp('[^A-Za-z0-9._@-]');

  /// Whether [location] is downloaded (`https://`, `http://`, `github:`)
  /// rather than a `resources:` file.
  static bool isRemote(String location) {
    final text = location.trim();
    return text.startsWith(_github) ||
        text.startsWith('https://') ||
        text.startsWith('http://');
  }

  /// The path below `lib/resources/` of the schema at [location].
  ///
  /// A `resources:` location gives its own path. A remote one gives the
  /// place where the build keeps its downloaded copy:
  /// `json-schemas/<host or github>/<path>`, ending in `.json`. The
  /// result is the same for the same location, and holds only
  /// `A-Z a-z 0-9 . _ @ -` and `/`: any other character becomes `_`, a
  /// `.` or `..` segment becomes `_` or `__`, empty segments are dropped.
  ///
  /// ```dart
  /// resourceOf('resources:schemas/order.json');
  /// // schemas/order.json
  /// resourceOf('https://example.com/schemas/order.json');
  /// // json-schemas/example.com/schemas/order.json
  /// resourceOf('https://example.com:8443/v1/order?v=2');
  /// // json-schemas/example.com_8443/v1/order_v_2.json
  /// resourceOf('github:acme/shop/schemas/order.json@v1.2');
  /// // json-schemas/github/acme/shop/schemas/order@v1.2.json
  /// resourceOf('github:acme/shop/schemas/order.json');
  /// // json-schemas/github/acme/shop/schemas/order.json
  /// ```
  ///
  /// Throws an [ArgumentError] for any other form of location, or one
  /// without a path.
  static String resourceOf(String location) {
    final text = location.trim();
    if (text.startsWith(_resources)) {
      final path = text
          .substring(_resources.length)
          .replaceFirst(
            RegExp('^/+'),
            '',
          );
      if (path.isEmpty) {
        throw ArgumentError.value(location, 'location', 'names no file');
      }
      return path;
    }
    if (text.startsWith(_github)) {
      return _githubPath(text, location);
    }
    if (text.startsWith('https://') || text.startsWith('http://')) {
      return _url(text, location);
    }
    throw ArgumentError.value(
      location,
      'location',
      'a JSON Schema location is resources:path, https://..., http://... or '
          'github:owner/repo/path@ref',
    );
  }

  static String _url(String text, String location) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError.value(location, 'location', 'is not a valid URL');
    }
    final host = uri.hasPort ? '${uri.host}_${uri.port}' : uri.host;
    final segments = _segments(uri.pathSegments);
    if (segments.isEmpty) {
      throw ArgumentError.value(location, 'location', 'names no file');
    }
    var last = segments.removeLast();
    if (uri.hasQuery && uri.query.isNotEmpty) {
      final query = _safe(Uri.decodeQueryComponent(uri.query));
      last = last.endsWith('.json')
          ? '${last.substring(0, last.length - 5)}_$query.json'
          : '${last}_$query';
    }
    return [
      _folder,
      _safe(host.toLowerCase()),
      ...segments,
      _json(last),
    ].join('/');
  }

  static String _githubPath(String text, String location) {
    final reference = text.substring(_github.length);
    final at = reference.lastIndexOf('@');
    final path = at < 0 ? reference : reference.substring(0, at);
    final ref = at < 0 ? null : reference.substring(at + 1);
    final parts = path.split('/');
    if (parts.length < 3 ||
        parts.any((p) => p.isEmpty) ||
        (ref != null && ref.isEmpty)) {
      throw ArgumentError.value(
        location,
        'location',
        'github: locations look like github:owner/repo/path/to/file@ref',
      );
    }
    final segments = _segments(parts);
    var last = segments.removeLast();
    if (ref != null) {
      final base = last.endsWith('.json')
          ? last.substring(0, last.length - 5)
          : last;
      last = '$base@${_safe(ref)}';
    }
    return [_folder, 'github', ...segments, _json(last)].join('/');
  }

  static List<String> _segments(Iterable<String> segments) => [
    for (final segment in segments)
      if (segment.isNotEmpty) _safeSegment(segment),
  ];

  static String _safeSegment(String segment) => switch (segment) {
    '.' => '_',
    '..' => '__',
    _ => _safe(segment),
  };

  static String _safe(String text) => text.replaceAll(_unsafe, '_');

  static String _json(String name) =>
      name.endsWith('.json') ? name : '$name.json';
}
