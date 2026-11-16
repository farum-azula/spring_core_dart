import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A [CacheStore] in a folder: none where there are no folders (a browser).
/// A Flutter app has the Flutter starter's store on its files instead; an
/// app elsewhere declares a `CacheStore` bean.
final class DirectoryCacheStore implements CacheStore {
  /// The store in the folder [path].
  DirectoryCacheStore(this.path);

  /// The folder.
  final String path;

  Never _none() => throw UnsupportedError(
    'No folders here for spring.cache.type=disk: declare a CacheStore bean '
    '(a Flutter app gets one from spring_boot_starter_flutter)',
  );

  @override
  Future<Uint8List?> read(String path) async => _none();

  @override
  Future<void> write(String path, List<int> bytes) async => _none();

  @override
  Future<void> delete(String path) async => _none();

  @override
  Future<List<String>> list(String path) async => _none();

  @override
  Future<int?> size(String path) async => _none();
}
