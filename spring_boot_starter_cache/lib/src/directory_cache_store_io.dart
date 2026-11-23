import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A [CacheStore] in a folder of the disk (`spring.cache.disk.directory`):
/// the files of `spring.cache.type: disk` on a server or a desktop
/// program without Flutter.
///
/// A write goes to a new file of random name beside its target (made
/// exclusively, so it cannot be one planted there) and is renamed over it,
/// so a reader never sees half of one. A folder the store makes is private
/// to the user (`rwx------`: cached values may be personal), and a folder
/// that is a symbolic link is refused, as it could lead the entries
/// anywhere.
final class DirectoryCacheStore implements CacheStore {
  /// The store in the folder [path], made when first written.
  DirectoryCacheStore(this.path);

  /// The folder.
  final String path;

  static final _random = Random.secure();
  bool _rootReady = false;

  File _file(String relative) => File('$path/$relative');

  // The folder checked, and made private when the store makes it; a
  // failure is not kept, the next write tries again.
  Future<void> _checkedRoot() async {
    if (!_rootReady) {
      await _prepareRoot();
      _rootReady = true;
    }
  }

  Future<void> _prepareRoot() async {
    if (FileSystemEntity.isLinkSync(path)) {
      throw FileSystemException(
        'The cache folder is a symbolic link; give its real path',
        path,
      );
    }
    final root = Directory(path);
    if (root.existsSync()) {
      return;
    }
    await root.create(recursive: true);
    if (Platform.isWindows) {
      return;
    }
    // dart:io has no chmod; a plain mkdir leaves the folder readable by
    // every user of the machine with the usual umask.
    final chmod = await Process.run('chmod', ['700', path]);
    if (chmod.exitCode != 0 || root.statSync().mode & 0x1FF != 0x1C0) {
      throw FileSystemException(
        'Cannot make the cache folder private (rwx------)',
        path,
      );
    }
  }

  @override
  Future<Uint8List?> read(String relative) async {
    if (FileSystemEntity.isLinkSync(path)) {
      return null;
    }
    try {
      return await _file(relative).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String relative, List<int> bytes) async {
    await _checkedRoot();
    final file = _file(relative);
    await file.parent.create(recursive: true);
    final name = [
      for (var i = 0; i < 4; i++)
        _random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ].join();
    final temporary = File('${file.path}.$name.tmp');
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } on Object {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String relative) async {
    final type = FileSystemEntity.typeSync(
      '$path/$relative',
      followLinks: false,
    );
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
      await for (final entity in folder.list(
        recursive: true,
        followLinks: false,
      ))
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
