import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A [CacheStore] in a folder of the disk (`spring.cache.disk.directory`):
/// the files of `spring.cache.type: disk` on a server or a desktop
/// program without Flutter.
///
/// A write goes to a file beside its target and is renamed over it, so a
/// reader never sees half of one.
final class DirectoryCacheStore implements CacheStore {
  /// The store in the folder [path], made when first written.
  DirectoryCacheStore(this.path);

  /// The folder.
  final String path;

  final _random = Random();

  File _file(String relative) => File('$path/$relative');

  @override
  Future<Uint8List?> read(String relative) async {
    try {
      return await _file(relative).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String relative, List<int> bytes) async {
    final file = _file(relative);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${_random.nextInt(1 << 32).toRadixString(16)}.tmp',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String relative) async {
    final type = FileSystemEntity.typeSync('$path/$relative');
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory('$path/$relative').delete(recursive: true);
    } else {
      await File('$path/$relative').delete();
    }
  }

  @override
  Future<List<String>> list(String relative) async {
    final folder = Directory(relative.isEmpty ? path : '$path/$relative');
    if (!folder.existsSync()) {
      return const [];
    }
    final root = Directory(path).absolute.path;
    return [
      await for (final entity in folder.list(recursive: true))
        if (entity is File && !entity.path.endsWith('.tmp'))
          entity.absolute.path.substring(root.length + 1).replaceAll(r'\', '/'),
    ];
  }

  @override
  Future<int?> size(String relative) async {
    try {
      return await _file(relative).length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  String toString() => 'DirectoryCacheStore($path)';
}
