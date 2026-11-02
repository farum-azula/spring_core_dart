import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter/src/files/file_paths.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';

/// A [FileStore] in memory: nothing outlives the object.
///
/// For tests, and the stand-in where nothing else exists (a browser
/// without IndexedDB). Its temporary files are in memory too and have no
/// [TempFile.path]; it has no temporary folders.
class InMemoryFileStore implements FileStore {
  /// An empty store; [clock] gives the modification times.
  InMemoryFileStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _files = <String, (Uint8List, DateTime)>{};
  // Not `1 << 32`: that is 0 when compiled to JavaScript.
  static const _randomRange = 0x100000000;
  final _random = Random();

  String _key(FilePlace place, String path) =>
      '${place.name}/${normalizeFilePath(path)}';

  @override
  Future<void> write(FilePlace place, String path, List<int> bytes) async {
    _files[_key(place, path)] = (Uint8List.fromList(bytes), _clock());
  }

  @override
  Future<Uint8List?> read(FilePlace place, String path) async {
    final entry = _files[_key(place, path)];
    return entry == null ? null : Uint8List.fromList(entry.$1);
  }

  @override
  Future<bool> exists(FilePlace place, String path) async =>
      _files.containsKey(_key(place, path));

  @override
  Future<bool> delete(FilePlace place, String path) async {
    final key = _key(place, path);
    var deleted = _files.remove(key) != null;
    final folder = '$key/';
    final below = _files.keys.where((k) => k.startsWith(folder)).toList();
    for (final k in below) {
      _files.remove(k);
      deleted = true;
    }
    return deleted;
  }

  @override
  Future<List<String>> list(FilePlace place, String prefix) async {
    final wanted = FilePrefix(prefix);
    final start = '${place.name}/';
    return [
      for (final key in _files.keys)
        if (key.startsWith(start) &&
            wanted.matches(key.substring(start.length)))
          key.substring(start.length),
    ]..sort();
  }

  @override
  Future<DateTime?> modifiedAt(FilePlace place, String path) async =>
      _files[_key(place, path)]?.$2;

  @override
  Future<TempFile> createTemp({String suffix = ''}) async {
    final name =
        '${_random.nextInt(_randomRange).toRadixString(36)}'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$suffix';
    return _MemoryTempFile(name);
  }

  @override
  Future<TempDirectory> createTempDir() => Future.error(
    UnsupportedError(
      'Temporary folders need a file system; this store keeps files in '
      'memory (a browser has none). Use temp() with a file instead.',
    ),
  );

  @override
  Future<void> close() async {}
}

final class _MemoryTempFile implements TempFile {
  _MemoryTempFile(this._name);

  final String _name;
  Uint8List? _bytes = Uint8List(0);

  @override
  String get path => throw UnsupportedError(
    'A temporary file in memory ($_name) has no path: a browser has no '
    'file system. Read and write it through the TempFile methods.',
  );

  @override
  Future<void> writeAsBytes(List<int> bytes) async =>
      _bytes = Uint8List.fromList(bytes);

  @override
  Future<void> writeAsString(String text) => writeAsBytes(utf8.encode(text));

  @override
  Future<Uint8List> readAsBytes() async =>
      _bytes ?? (throw StateError('The temporary file $_name was deleted'));

  @override
  Future<String> readAsString() async => utf8.decode(await readAsBytes());

  @override
  Future<bool> exists() async => _bytes != null;

  @override
  Future<void> delete() async => _bytes = null;
}
