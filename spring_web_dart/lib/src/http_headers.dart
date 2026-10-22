/// HTTP headers: names are case-insensitive, a name may have several
/// values, insertion order and the original casing are kept. Like Spring's
/// `HttpHeaders`.
///
/// ```dart
/// final headers = HttpHeaders({'Accept': 'application/json'})
///   ..add('X-Tag', 'a')
///   ..add('x-tag', 'b');
/// headers['accept'];          // 'application/json'
/// headers.getAll('X-TAG');    // ['a', 'b']
/// headers.toMap();            // {Accept: application/json, X-Tag: a, b}
/// ```
///
/// Spring (Java):
/// ```java
/// HttpHeaders headers = new HttpHeaders();
/// headers.setAccept(List.of(MediaType.APPLICATION_JSON));
/// headers.add("X-Tag", "a");
/// headers.get("x-tag");
/// ```
class HttpHeaders {
  /// Headers with one value per name of [values].
  HttpHeaders([Map<String, String>? values]) {
    values?.forEach(set);
  }

  /// Headers from [entries] (a name may repeat).
  HttpHeaders.fromEntries(Iterable<MapEntry<String, String>> entries) {
    for (final entry in entries) {
      add(entry.key, entry.value);
    }
  }

  /// `Content-Type`.
  static const contentType = 'Content-Type';

  /// `Accept`.
  static const accept = 'Accept';

  /// `Authorization`.
  static const authorization = 'Authorization';

  /// `Content-Length`.
  static const contentLength = 'Content-Length';

  /// `User-Agent`.
  static const userAgent = 'User-Agent';

  final _entries = <MapEntry<String, String>>[];

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// The first value of [name], or `null`.
  String? operator [](String name) {
    for (final entry in _entries) {
      if (_same(entry.key, name)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Every value of [name], in insertion order.
  List<String> getAll(String name) => [
    for (final entry in _entries)
      if (_same(entry.key, name)) entry.value,
  ];

  /// Replaces the values of [name] with [value].
  void set(String name, String value) {
    final index = _entries.indexWhere((e) => _same(e.key, name));
    remove(name);
    final entry = MapEntry(name, value);
    if (index < 0 || index > _entries.length) {
      _entries.add(entry);
    } else {
      _entries.insert(index, entry);
    }
  }

  /// Adds [value] to the values of [name].
  void add(String name, String value) => _entries.add(MapEntry(name, value));

  /// Removes every value of [name].
  void remove(String name) => _entries.removeWhere((e) => _same(e.key, name));

  /// Whether [name] has a value.
  bool contains(String name) => _entries.any((e) => _same(e.key, name));

  /// The header names, each once, as first added.
  Iterable<String> get names {
    final seen = <String>{};
    return [
      for (final entry in _entries)
        if (seen.add(entry.key.toLowerCase())) entry.key,
    ];
  }

  /// Calls [action] for every value (a name with several values is passed
  /// once per value).
  void forEach(void Function(String name, String value) action) {
    for (final entry in [..._entries]) {
      action(entry.key, entry.value);
    }
  }

  /// One entry per name; several values are joined with `, `.
  Map<String, String> toMap() => {
    for (final name in names) name: getAll(name).join(', '),
  };

  /// An independent copy.
  HttpHeaders copy() => HttpHeaders.fromEntries(_entries);

  /// Whether there are no headers.
  bool get isEmpty => _entries.isEmpty;

  @override
  String toString() => toMap().toString();
}
