import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/file_path.dart';

/// The [CacheStore] of a Flutter app: the `cache` place of its files (a
/// folder the system may clear on iOS, Android and the desktops,
/// IndexedDB in a browser). Each cache keeps a folder of its own in it,
/// with a limit of its own: the resources downloaded `spring/resources/`
/// (`spring.flutter.resources.cache.max-size`), the `@Cacheable` caches of
/// `spring.cache.type: disk` `spring/caches/` (`spring.cache.disk.max-size`).
final class FileCacheStore implements CacheStore {
  /// The store on [files]' `cache` place.
  FileCacheStore(this.files);

  /// Where the files are.
  final FileStore files;

  static const FilePlace _place = FilePlace.cache;

  @override
  Future<Uint8List?> read(String path) => files.read(_place, path);

  @override
  Future<void> write(String path, List<int> bytes) =>
      files.write(_place, path, bytes);

  @override
  Future<void> delete(String path) async {
    await files.delete(_place, path);
  }

  @override
  Future<List<String>> list(String path) =>
      files.list(_place, path.isEmpty ? '' : '$path/');

  @override
  Future<int?> size(String path) async => (await read(path))?.length;

  /// The file of [path] on the disk, for a player that wants a file; `null`
  /// where there is none (a browser) or the file is not there.
  Future<String?> filePath(String path) => filePathOf(files, _place, path);

  @override
  String toString() => 'FileCacheStore(cache)';
}

/// A [CacheStore] around another that keeps the folder [root] of it under
/// [maxBytes]: past it, the files least recently read or written go first.
/// What is outside [root] is neither counted nor dropped: another cache's.
///
/// What it knows of the files (their sizes, when they were last used) is
/// kept in the folder too, in [indexPath], written a moment after it
/// changes; a folder without one is measured once.
final class LimitedCacheStore implements CacheStore {
  /// [root] of [inner] kept under [maxBytes]; [clock] is the time, for a
  /// test's own.
  LimitedCacheStore(
    this.inner, {
    required this.root,
    required this.maxBytes,
    DateTime Function()? clock,
    this.saveAfter = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  /// The store kept.
  final CacheStore inner;

  /// The folder kept under the limit.
  final String root;

  /// The most bytes it keeps.
  final int maxBytes;

  /// How long after a change the index is written.
  final Duration saveAfter;

  /// Where the index is kept.
  String get indexPath => '$root/index.json';

  bool _counted(String path) => path.startsWith('$root/') && path != indexPath;

  final DateTime Function() _clock;
  final Map<String, ({int size, int used})> _files = {};
  Future<void>? _loaded;
  Timer? _save;

  Future<void> _load() => _loaded ??= () async {
    final bytes = await inner.read(indexPath);
    if (bytes != null) {
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        for (final MapEntry(:key, :value) in json.entries) {
          final entry = value! as List<Object?>;
          _files[key] = (size: entry[0]! as int, used: entry[1]! as int);
        }
        return;
      } on Object {
        _files.clear();
      }
    }
    // No index yet: what is there is measured once.
    for (final path in await inner.list(root)) {
      if (!_counted(path)) {
        continue;
      }
      final size = await inner.size(path);
      if (size != null) {
        _files[path] = (size: size, used: 0);
      }
    }
  }();

  int get _now => _clock().millisecondsSinceEpoch;

  /// The bytes it keeps now.
  Future<int> get used async {
    await _load();
    return _files.values.fold<int>(0, (sum, file) => sum + file.size);
  }

  @override
  Future<Uint8List?> read(String path) async {
    if (!_counted(path)) {
      return inner.read(path);
    }
    await _load();
    final bytes = await inner.read(path);
    if (bytes != null) {
      _files[path] = (size: bytes.length, used: _now);
      _changed();
    } else {
      _files.remove(path);
    }
    return bytes;
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    if (!_counted(path)) {
      return inner.write(path, bytes);
    }
    await _load();
    await inner.write(path, bytes);
    _files[path] = (size: bytes.length, used: _now);
    await _trim(keep: path);
    _changed();
  }

  @override
  Future<void> delete(String path) async {
    await _load();
    await inner.delete(path);
    _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    _changed();
  }

  @override
  Future<List<String>> list(String path) async => [
    for (final file in await inner.list(path))
      if (file != indexPath) file,
  ];

  @override
  Future<int?> size(String path) async {
    if (!_counted(path)) {
      return inner.size(path);
    }
    await _load();
    return _files[path]?.size ?? await inner.size(path);
  }

  // The least recently used go until it fits; [keep], just written, last.
  Future<void> _trim({required String keep}) async {
    var total = _files.values.fold<int>(0, (sum, file) => sum + file.size);
    if (total <= maxBytes) {
      return;
    }
    final order = _files.entries.where((e) => e.key != keep).toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));
    for (final MapEntry(:key, :value) in order) {
      if (total <= maxBytes) {
        return;
      }
      await inner.delete(key);
      _files.remove(key);
      total -= value.size;
    }
  }

  void _changed() {
    _save?.cancel();
    _save = Timer(saveAfter, () => unawaited(flush()));
  }

  /// Writes the index now.
  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    await inner.write(
      indexPath,
      utf8.encode(
        jsonEncode({
          for (final MapEntry(:key, :value) in _files.entries)
            key: [value.size, value.used],
        }),
      ),
    );
  }

  @override
  String toString() => 'LimitedCacheStore($inner, $root, $maxBytes bytes)';
}
