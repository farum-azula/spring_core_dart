import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// A file, like Spring's `FileSystemResource`. Unavailable on the web,
/// where it never exists.
///
/// Supports synchronous reading (on platforms with `dart:io`). A directory
/// exists but is not readable ([isReadable] is `false`), like in Spring.
///
/// ```dart
/// final resource = FileSystemResource('config/application.properties');
/// if (resource.exists()) {
///   final text = resource.readAsStringSync();
///   final dev = resource.createRelative('application-dev.properties');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// var resource = new FileSystemResource("config/application.properties");
/// if (resource.exists()) {
///   String text = resource.getContentAsString(StandardCharsets.UTF_8);
///   Resource dev = resource.createRelative("application-dev.properties");
/// }
/// ```
class FileSystemResource extends AbstractResource {
  /// [path] uses `/` separators; `\` is converted.
  ///
  /// The path is normalized: `.` segments and empty segments are removed
  /// and `..` collapses with the previous segment.
  FileSystemResource(String path) : path = _clean(path);

  /// The file of a `file:` URL, percent-decoded like Spring's
  /// `ResourceUtils.getFile` (`file:my%20dir/a.txt` is `my dir/a.txt`);
  /// `file:///abs` and `file:/abs` are absolute. Invalid escapes are kept
  /// as written.
  ///
  /// ```dart
  /// FileSystemResource.fromFileUrl('file:///srv/my%20app/a.properties')
  ///     .path; // /srv/my app/a.properties
  /// ```
  factory FileSystemResource.fromFileUrl(String url) {
    var rest = url.startsWith('file:') ? url.substring(5) : url;
    // `file://host/path`: only an empty (local) host is supported.
    if (rest.startsWith('///')) {
      rest = rest.substring(2);
    } else if (rest.startsWith('//localhost/')) {
      rest = rest.substring('//localhost'.length);
    }
    if (rest.contains('%')) {
      try {
        rest = Uri.decodeComponent(rest);
      } on ArgumentError {
        // Not a valid escape: a literal `%` in the path.
      }
    }
    return FileSystemResource(rest);
  }

  /// The normalized path, relative or absolute as given.
  final String path;

  // Like Spring's StringUtils.cleanPath: `.` and empty segments are
  // dropped and `..` removes the previous segment. Leading `..` segments of
  // a relative path are kept; at the root of an absolute path (`/` or a
  // Windows drive like `C:/`) they are dropped. An empty relative path
  // becomes `.`.
  static String _clean(String path) {
    var normalized = path.replaceAll(r'\', '/');
    var root = '';
    final drive = RegExp('^[a-zA-Z]:/').firstMatch(normalized);
    if (drive != null) {
      root = drive[0]!;
    } else if (normalized.startsWith('/')) {
      root = '/';
    }
    normalized = normalized.substring(root.length);
    final segments = <String>[];
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
          continue;
        }
        if (root.isNotEmpty) {
          continue;
        }
      }
      segments.add(segment);
    }
    final joined = segments.join('/');
    if (root.isNotEmpty) {
      return '$root$joined';
    }
    return joined.isEmpty ? '.' : joined;
  }

  @override
  bool exists() => FileAccess.isFile(path) || FileAccess.isDirectory(path);

  /// Whether this is a readable file (not a directory).
  @override
  bool get isReadable => FileAccess.isFile(path);

  /// Whether [path] is an existing directory.
  bool get isDirectory => FileAccess.isDirectory(path);

  @override
  String get filename => path.split('/').last;

  @override
  String get description => 'file [${FileAccess.absolute(path)}]';

  @override
  Uri get uri => Uri.file(FileAccess.absolute(path));

  @override
  bool get supportsSyncRead => FileAccess.isSupported;

  /// Size in bytes; throws if the file does not exist.
  int contentLength() => FileAccess.length(path);

  /// Last modification time; throws if the file does not exist.
  DateTime lastModified() => FileAccess.lastModified(path);

  @override
  Future<Uint8List> readAsBytes() => FileAccess.readBytes(path);

  /// The content from [start] (inclusive) to [end] (exclusive), streamed
  /// without reading the whole file (a download, a `Range` request).
  Stream<List<int>> openRead([int? start, int? end]) =>
      FileAccess.openRead(path, start, end);

  @override
  Uint8List readAsBytesSync() => FileAccess.readBytesSync(path);

  /// A file next to this one; [relativePath] may contain `..`.
  @override
  FileSystemResource createRelative(String relativePath) {
    final slash = path.lastIndexOf('/');
    final parent = slash < 0 ? '' : path.substring(0, slash + 1);
    return FileSystemResource('$parent$relativePath');
  }

  /// Equal when the normalized paths are equal.
  @override
  bool operator ==(Object other) =>
      other is FileSystemResource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
