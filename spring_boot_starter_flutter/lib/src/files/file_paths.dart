/// Checks a path given to the file API and returns it in one form:
/// segments joined by `/`, no `.` segments, no empty ones.
///
/// A path stays inside its place: an absolute path (`/etc/hosts`,
/// `\x`, `C:\x`), a `..` segment and a NUL character throw an
/// `ArgumentError`, whatever the platform; `\` counts as `/`. [allowEmpty]
/// admits the place itself (`''`), for listings.
///
/// Internal to the starter.
String normalizeFilePath(String path, {bool allowEmpty = false}) {
  if (path.contains('\u0000')) {
    throw ArgumentError.value(path, 'path', 'must not contain a NUL');
  }
  final unified = path.replaceAll('\\', '/');
  if (unified.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(unified)) {
    throw ArgumentError.value(
      path,
      'path',
      'must be relative to its place, not absolute',
    );
  }
  final segments = <String>[];
  for (final segment in unified.split('/')) {
    if (segment == '..') {
      throw ArgumentError.value(
        path,
        'path',
        'must stay inside its place: ".." is refused',
      );
    }
    if (segment.isNotEmpty && segment != '.') {
      segments.add(segment);
    }
  }
  if (segments.isEmpty && !allowEmpty) {
    throw ArgumentError.value(path, 'path', 'must not be empty');
  }
  return segments.join('/');
}

/// The suffix of the temporary file an atomic write goes through before
/// the rename; listings skip such files.
const atomicWriteSuffix = '.spring-tmp';

/// How a prefix given to a listing matches the (normalized) [path] of a
/// file.
///
/// A [prefix] ending in `/` (or empty) names a folder: every file below it.
/// Any other prefix is the start of a path (`thumb-` finds `thumb-1.png`
/// and `thumb-2.png`).
class FilePrefix {
  FilePrefix._(this.value, this.isFolder);

  /// The prefix as the file API takes it; throws an `ArgumentError` for a
  /// prefix that leaves its place.
  factory FilePrefix(String prefix) {
    final normalized = normalizeFilePath(prefix, allowEmpty: true);
    final unified = prefix.replaceAll('\\', '/');
    return FilePrefix._(
      normalized,
      normalized.isEmpty || unified.endsWith('/'),
    );
  }

  /// The normalized prefix, without a trailing `/`.
  final String value;

  /// Whether the prefix names a folder.
  final bool isFolder;

  /// The folder to look in: the prefix itself for a folder, else the
  /// folder holding it (empty for the place's root).
  String get directory => isFolder
      ? value
      : value.contains('/')
      ? value.substring(0, value.lastIndexOf('/'))
      : '';

  /// Whether [path] starts with the prefix.
  bool matches(String path) => value.isEmpty
      ? true
      : isFolder
      ? path.startsWith('$value/')
      : path.startsWith(value);
}
