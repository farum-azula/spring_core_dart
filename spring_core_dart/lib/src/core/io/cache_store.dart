import 'dart:typed_data';

/// Where a cache keeps what it may lose: bytes by a path of `/`-separated
/// names, read and written asynchronously, kept across restarts when the
/// store can (a folder on a disk, the browser's IndexedDB), cleared by the
/// system when it needs the room.
///
/// The cache starter keeps `@Cacheable` results in one (`spring.cache.type:
/// disk`), the Flutter starter the resources it downloads; an app that has
/// both shares the place, each cache in a folder of its own with a limit
/// of its own, the other's files not counted. The Flutter
/// starter gives one on the app's files (the `cache` place of
/// `FileTemplate`), the cache starter one on a folder elsewhere; an app
/// declares a bean of its own for another place.
abstract interface class CacheStore {
  /// The bytes at [path], `null` when there is none.
  Future<Uint8List?> read(String path);

  /// Writes [bytes] at [path], replacing what was there, whole or not at
  /// all.
  Future<void> write(String path, List<int> bytes);

  /// Deletes the file at [path], or the folder with everything in it; no
  /// error when there is none.
  Future<void> delete(String path);

  /// The paths of the files under the folder [path], at any depth,
  /// relative to the store; empty when there is none.
  Future<List<String>> list(String path);

  /// The size of the file at [path] in bytes, `null` when there is none.
  Future<int?> size(String path);
}

/// A [CacheStore] in memory: for tests, and where nothing may outlive the
/// run.
final class InMemoryCacheStore implements CacheStore {
  final Map<String, Uint8List> _files = {};

  @override
  Future<Uint8List?> read(String path) async => _files[path];

  @override
  Future<void> write(String path, List<int> bytes) async =>
      _files[path] = Uint8List.fromList(bytes);

  @override
  Future<void> delete(String path) async =>
      _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));

  @override
  Future<List<String>> list(String path) async => [
    for (final key in _files.keys)
      if (path.isEmpty || key.startsWith('$path/')) key,
  ];

  @override
  Future<int?> size(String path) async => _files[path]?.length;
}
