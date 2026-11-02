import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter/src/files/file_paths.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/memory_file_store.dart';

// The browser's IndexedDB through dart:js_interop only: package:web is not a
// dependency of the starter. One database, one object store; the key is
// `<place>/<path>`, the value `{data: Uint8Array, modified: ms}`.

@JS('indexedDB')
external JSObject? get _indexedDb;

extension type _Factory._(JSObject _) implements JSObject {
  external _Request open(String name, int version);
}

extension type _Request._(JSObject _) implements JSObject {
  external JSAny? get result;
  external JSAny? get error;
  external set onsuccess(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external set onupgradeneeded(JSFunction? handler);
}

extension type _Database._(JSObject _) implements JSObject {
  external _Transaction transaction(String store, String mode);
  external void createObjectStore(String name);
}

extension type _Transaction._(JSObject _) implements JSObject {
  external _Store objectStore(String name);
}

extension type _Store._(JSObject _) implements JSObject {
  external _Request get(String key);
  external _Request put(JSAny value, String key);
  external _Request delete(String key);
  external _Request getAllKeys();
}

extension type _Record._(JSObject _) implements JSObject {
  external factory _Record({JSUint8Array data, double modified});
  external JSUint8Array get data;
  external double get modified;
}

Future<JSAny?> _done(_Request request) {
  final completer = Completer<JSAny?>();
  request
    ..onsuccess = ((JSAny _) => completer.complete(request.result)).toJS
    ..onerror = ((JSAny _) => completer.completeError(
      StateError('IndexedDB failed: ${request.error}'),
    )).toJS;
  return completer.future;
}

/// The [FileStore] of a browser: the files in IndexedDB, so they outlive
/// the page; temporary files in memory (a browser has no file system, so
/// they have no path and there are no temporary folders).
///
/// All places share one database (`spring_files`): a browser has no
/// system-cleared or user-visible folders. Where IndexedDB is missing or
/// refuses to open (some private modes) the files are kept in memory.
///
/// Internal to the starter.
class IndexedDbFileStore implements FileStore {
  /// A store on the database [name].
  // ignore: prefer_initializing_formals, a named parameter cannot be private
  IndexedDbFileStore({String name = 'spring_files'}) : _name = name;

  static const _storeName = 'files';

  final String _name;
  final _fallback = InMemoryFileStore();
  Future<_Database?>? _database;

  Future<_Database?> _open() => _database ??= () async {
    final factory = _indexedDb;
    if (factory == null) {
      return null;
    }
    try {
      final request = _Factory._(factory).open(_name, 1);
      request.onupgradeneeded = ((JSAny _) {
        _Database._(request.result! as JSObject).createObjectStore(_storeName);
      }).toJS;
      return _Database._(await _done(request) as JSObject);
    } on Object {
      return null;
    }
  }();

  String _key(FilePlace place, String path) =>
      '${place.name}/${normalizeFilePath(path)}';

  Future<_Store?> _store(bool write) async {
    final database = await _open();
    return database
        ?.transaction(_storeName, write ? 'readwrite' : 'readonly')
        .objectStore(_storeName);
  }

  @override
  Future<void> write(FilePlace place, String path, List<int> bytes) async {
    final key = _key(place, path);
    final store = await _store(true);
    if (store == null) {
      return _fallback.write(place, path, bytes);
    }
    final data = Uint8List.fromList(bytes).toJS;
    final record = _Record(
      data: data,
      modified: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _done(store.put(record, key));
  }

  Future<_Record?> _record(_Store store, String key) async =>
      switch (await _done(store.get(key))) {
        final JSObject found => _Record._(found),
        _ => null,
      };

  @override
  Future<Uint8List?> read(FilePlace place, String path) async {
    final key = _key(place, path);
    final store = await _store(false);
    if (store == null) {
      return _fallback.read(place, path);
    }
    return (await _record(store, key))?.data.toDart;
  }

  @override
  Future<bool> exists(FilePlace place, String path) async =>
      await read(place, path) != null;

  Future<List<String>> _keys() async {
    final store = await _store(false);
    final keys = await _done(store!.getAllKeys());
    return [
      for (final key in (keys! as JSArray).toDart) (key! as JSString).toDart,
    ];
  }

  @override
  Future<bool> delete(FilePlace place, String path) async {
    final key = _key(place, path);
    if (await _open() == null) {
      return _fallback.delete(place, path);
    }
    var deleted = false;
    for (final candidate in await _keys()) {
      if (candidate == key || candidate.startsWith('$key/')) {
        await _done((await _store(true))!.delete(candidate));
        deleted = true;
      }
    }
    return deleted;
  }

  @override
  Future<List<String>> list(FilePlace place, String prefix) async {
    final wanted = FilePrefix(prefix);
    if (await _open() == null) {
      return _fallback.list(place, prefix);
    }
    final start = '${place.name}/';
    return [
      for (final key in await _keys())
        if (key.startsWith(start) &&
            wanted.matches(key.substring(start.length)))
          key.substring(start.length),
    ]..sort();
  }

  @override
  Future<DateTime?> modifiedAt(FilePlace place, String path) async {
    final key = _key(place, path);
    final store = await _store(false);
    if (store == null) {
      return _fallback.modifiedAt(place, path);
    }
    final record = await _record(store, key);
    return record == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(record.modified.round());
  }

  @override
  Future<TempFile> createTemp({String suffix = ''}) =>
      _fallback.createTemp(suffix: suffix);

  @override
  Future<TempDirectory> createTempDir() => _fallback.createTempDir();

  @override
  Future<void> close() async {}
}
