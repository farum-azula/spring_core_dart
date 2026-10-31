import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:spring_boot_starter_flutter_security/src/secret_store/native_memory.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/platform_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show SpringLog, sha256Base64Url;

const _log = SpringLog('spring.security.oauth2.client');

/// The [PlatformSecretStore] of Windows: each value encrypted with DPAPI for
/// the current Windows user, in a file of its own.
///
/// `CryptProtectData` encrypts with a key Windows derives from the user's
/// logon secret: another user of the computer, or the same files copied
/// to another computer, cannot decrypt them. Any program running as the
/// same user can, as DPAPI separates users, not apps. The entropy (a
/// constant and the key's name) ties each file to its key, so files
/// swapped between keys do not decrypt either. A file that does not
/// decrypt is deleted and read as missing.
///
/// The files are in `%LOCALAPPDATA%\spring_secret_store\<app>`, `<app>`
/// being [applicationId] (`spring.flutter.security.application-id`; a
/// blank id counts as unset) or, without one, `<company>\<product>` of
/// the executable's version resource (`CompanyName` and `ProductName` of
/// the runner's `Runner.rc`, which `flutter create --org` fills), else the
/// executable's name. Not in `%LOCALAPPDATA%\<company>\<product>` itself:
/// that is the app's cache folder (`getApplicationCacheDirectory()` of
/// Flutter's `path_provider`), which an app may empty. Not in the roaming
/// `%APPDATA%` either: the files (the DPoP key among them) stay on this
/// computer and never follow a roaming profile to another. The file name
/// is the key in hexadecimal (key names are not secret, the values are);
/// a key longer than 64 bytes is a file named by its SHA-256, with the
/// key in a header (paths stay under Windows' 260 characters).
///
/// 0.4.x kept the files in `%LOCALAPPDATA%\<executable name>\spring_secret_store`
/// (two apps with the same executable name shared it). Its files are
/// moved to the new folder once, at the store's first call that finds no
/// record of the move: each value is copied unless one is already in the
/// new folder (that one wins), each old file is deleted, and the file
/// `migrated-from-0.4` in the new folder records the move. From then on
/// the old folder is never listed again, so another app of that
/// executable name (still on 0.4.x) no longer mixes its values in; that
/// app loses the files moved, its user logs in again. Windows refuses to
/// delete or replace a file another process or isolate has open (a
/// sharing violation), and an old folder may be read-only: such a file is
/// tried again for up to about a second at that first call, then left
/// with a warning, and the record names it. At each later start each file
/// the record names is tried once, without waiting, and nothing else of
/// the old folder is read: a value whose copy failed is copied (it reads
/// as missing until then), an old file already copied is only deleted,
/// never copied again. A value deleted through the store ([delete],
/// [deleteAll]) never comes back: a copy still pending for it is
/// cancelled, its old file only deleted. The move never fails a call.
final class WindowsDpapiSecretStore implements SecretStore {
  /// The store in [directory], by default the folder of [applicationId]
  /// (see above); the files of [legacyDirectory], by default the 0.4.x
  /// folder, are moved to it once.
  WindowsDpapiSecretStore({
    this._directory,
    this._legacyDirectory,
    String? applicationId,
  }) : applicationId = applicationId == null || applicationId.trim().isEmpty
           ? null
           : applicationId;

  /// The app's identifier, the folder's name under
  /// `%LOCALAPPDATA%\spring_secret_store`; when `null` (or given blank),
  /// the version resource's company and product, or the executable's
  /// name.
  final String? applicationId;

  final Directory? _directory;
  final Directory? _legacyDirectory;

  late final Directory _folder = _directory ?? _defaultDirectory();

  // The 0.4.x folder, when it is another one; with an explicit
  // [directory] and no legacy one, none.
  late final Directory? _legacy = () {
    final legacy =
        _legacyDirectory ?? (_directory == null ? _legacyDefault() : null);
    return legacy == null || _samePath(legacy, _folder) ? null : legacy;
  }();

  static bool _samePath(Directory a, Directory b) =>
      a.absolute.path.toLowerCase() == b.absolute.path.toLowerCase();

  static String _localAppData() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) {
      throw const PlatformSecretStoreException(
        'LOCALAPPDATA is not set: no folder for the secret files',
        code: 'dpapi',
      );
    }
    return base;
  }

  static String _executableName() {
    var app = Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
    if (app.toLowerCase().endsWith('.exe')) {
      app = app.substring(0, app.length - 4);
    }
    return app;
  }

  Directory _defaultDirectory() => Directory(
    '${_localAppData()}\\spring_secret_store'
    '\\${applicationFolder(applicationId)}',
  );

  /// The folder of the app under `%LOCALAPPDATA%\spring_secret_store`:
  /// [applicationId] made a folder name, else the version resource's
  /// company and product, else the executable's name.
  @visibleForTesting
  static String applicationFolder(String? applicationId) =>
      (applicationId == null ? null : folderName(applicationId)) ??
      _VersionInfo.companyAndProduct(Platform.resolvedExecutable) ??
      _executableName();

  static Directory _legacyDefault() => Directory(
    '${_localAppData()}\\${_executableName()}\\spring_secret_store',
  );

  /// The file in the folder that records the move of the 0.4.x files and
  /// the old files it left (a value not copied yet, a file not deleted).
  @visibleForTesting
  static const migrationMarker = 'migrated-from-0.4';

  /// [name] as a folder name: the characters Windows refuses in a path
  /// (`<>:"/\|?*`, control characters) as `_`, without trailing spaces
  /// and dots; `null` when nothing is left. A `\` in an application id
  /// separates folders (`Company\Product`).
  @visibleForTesting
  static String? folderName(String name) {
    final parts = [
      for (final part in name.split('\\')) ?_sanitized(part),
    ];
    return parts.isEmpty ? null : parts.join('\\');
  }

  static String? _sanitized(String part) {
    final clean = part
        .replaceAll(RegExp(r'[<>:"/|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return clean.isEmpty || clean == '..' ? null : clean;
  }

  /// The longest key (in UTF-8 bytes) whose file is named by the key in
  /// hexadecimal; longer keys are named by their hash.
  static const maxHexKeyBytes = 64;

  // The header of a file named by its key's hash: the magic, then the
  // key's length (two bytes, big-endian) and the key in UTF-8.
  static const _magic = [0x53, 0x53, 0x4b, 0x31]; // "SSK1"

  static String _hex(List<int> bytes) => [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();

  /// The file name of [key] (without the folder): its hexadecimal, or
  /// `k-<sha256 hex>` for a key longer than [maxHexKeyBytes].
  @visibleForTesting
  static String fileName(String key) {
    final bytes = utf8.encode(key);
    if (bytes.length <= maxHexKeyBytes) {
      return '${_hex(bytes)}.bin';
    }
    // Hexadecimal, not base64: Windows file names ignore case.
    final digest = base64Url.decode(base64Url.normalize(sha256Base64Url(key)));
    return 'k-${_hex(digest)}.bin';
  }

  static bool _hashed(String key) => utf8.encode(key).length > maxHexKeyBytes;

  // The separator of the system: `\` on Windows (the tests of the file
  // names run elsewhere too).
  static final _separator = Platform.pathSeparator;

  File _file(Directory folder, String key) =>
      File('${folder.path}$_separator${fileName(key)}');

  // The moves of 0.4.x folders done or running in this isolate, by the
  // new folder: one per folder, whatever the number of stores (other
  // isolates, engines or app instances may move at the same time: a file
  // another mover took is skipped).
  static final Map<String, Future<void>> _migrations = {};

  // The old files whose copy failed, by the new folder, as this start
  // left them: tried again at the next start, unless [delete] or
  // [deleteAll] cancels them first.
  static final Map<String, Set<String>> _copiesLeft = {};

  // The changes of the record of the move in this isolate, by the new
  // folder, one after the other.
  static final Map<String, Future<void>> _recordChanges = {};

  /// Forgets the moves done in this isolate, as a new start does: the
  /// next call looks for the record again; for tests.
  @visibleForTesting
  static void debugForgetMigrations() {
    _migrations.clear();
    _copiesLeft.clear();
    _recordChanges.clear();
  }

  /// Called before each file operation of the move of the 0.4.x files
  /// (`read` and `delete` of an old file, `write` of the moved one); it
  /// throws to make the operation fail, as Windows does on a file another
  /// process has open. For tests.
  @visibleForTesting
  static void Function(String operation, File file)? debugMoveOperation;

  /// How long the first move of the 0.4.x files tries again files that
  /// are in use, in all, before it leaves them for the next start.
  static const _moveRetryBudget = Duration(seconds: 1);

  String get _folderKey => _folder.absolute.path.toLowerCase();

  File get _record => File('${_folder.path}$_separator$migrationMarker');

  /// Moves the files of the 0.4.x folder here, once per isolate: the
  /// first time, every file of the old folder; then only what the record
  /// ([migrationMarker]) lists as left. It never throws: what it could
  /// not move is left for the next start, with a warning.
  Future<void> _migrated() {
    final legacy = _legacy;
    if (legacy == null) {
      return Future.value();
    }
    return _migrations[_folderKey] ??= () async {
      try {
        await _migrate(legacy);
      } on Object catch (error) {
        _log.warning(
          'The values of 0.4.x in ${legacy.path} could not be moved to '
          '${_folder.path}: $error; the next start tries again',
        );
      }
    }();
  }

  // The first move lists the old folder: each value not here yet is
  // copied as it is (sealed: nothing is decrypted; a long key gets its
  // hashed name and header), then its old file deleted. The record is
  // written whatever was left: from then on the old folder is never
  // listed again, only the files the record names are touched.
  Future<void> _migrate(Directory legacy) async {
    final recorded = _readRecord();
    if (recorded != null) {
      return _moveLeftovers(legacy, recorded);
    }
    final spent = Stopwatch()..start();
    final left = <String, _Left>{};
    if (legacy.existsSync()) {
      await for (final entry in legacy.list()) {
        if (entry is! File) {
          continue;
        }
        final key = _keyOf(entry, anyLength: true);
        if (key == null || !entry.existsSync()) {
          continue;
        }
        final state = await _moveFile(entry, key, budget: spent);
        if (state != null) {
          left[_name(entry)] = state;
        }
      }
    }
    await _writeRecord(legacy, left);
    _copiesLeft[_folderKey] = _copies(left);
    if (left.isNotEmpty) {
      final copies = _copies(left).length;
      _log.warning(
        '${left.length} file(s) of 0.4.x in ${legacy.path} could not be '
        'moved to ${_folder.path} (in use by another process, or not '
        'writable?): $copies value(s) not copied, ${left.length - copies} '
        'old file(s) not deleted; the next start tries again',
      );
    }
  }

  // A later start: each old file the record names is tried once, without
  // waiting: a value not copied yet is copied (unless one is here), a
  // file left over is deleted. Nothing else of the old folder is read.
  Future<void> _moveLeftovers(
    Directory legacy,
    Map<String, _Left> recorded,
  ) async {
    if (recorded.isEmpty) {
      _copiesLeft[_folderKey] = <String>{};
      return;
    }
    final left = <String, _Left>{};
    for (final MapEntry(key: name, value: state) in recorded.entries) {
      final old = File('${legacy.path}$_separator$name');
      final key = _keyOf(old, anyLength: true);
      if (key == null) {
        continue;
      }
      final now = await _moveFile(old, key, copy: state == _Left.copy);
      if (now != null) {
        left[name] = now;
      }
    }
    final copies = _copies(left);
    _copiesLeft[_folderKey] = copies;
    if (copies.isNotEmpty) {
      _log.warning(
        '${copies.length} value(s) of 0.4.x in ${legacy.path} still could '
        'not be copied to ${_folder.path}; the next start tries again',
      );
    }
    if (left.length != recorded.length ||
        left.entries.any((entry) => recorded[entry.key] != entry.value)) {
      // As on disk now: a value another isolate deleted since stays so.
      await _changeRecord((entries) {
        entries.removeWhere((name, _) => !left.containsKey(name));
        for (final name in entries.keys.toList()) {
          if (entries[name] == _Left.copy) {
            entries[name] = left[name]!;
          }
        }
      });
    }
  }

  static Set<String> _copies(Map<String, _Left> entries) => {
    for (final MapEntry(:key, :value) in entries.entries)
      if (value == _Left.copy) key,
  };

  // Copies [old] here ([copy]) and deletes it; `null` when done, else
  // what is left of it. With a [budget], a file in use is tried again
  // within it (the first move); without, once.
  Future<_Left?> _moveFile(
    File old,
    String key, {
    Stopwatch? budget,
    bool copy = true,
  }) async {
    if (copy) {
      final target = _file(_folder, key);
      final copied = await _attempt(budget, () async {
        if (target.existsSync() || !old.existsSync()) {
          return;
        }
        debugMoveOperation?.call('read', old);
        final sealed = await old.readAsBytes();
        await target.parent.create(recursive: true);
        debugMoveOperation?.call('write', target);
        await writeAtomically(
          target,
          _hashed(key) ? [..._header(key), ...sealed] : sealed,
        );
      });
      if (!copied) {
        return _Left.copy;
      }
    }
    final deleted = await _attempt(budget, () async {
      if (old.existsSync()) {
        debugMoveOperation?.call('delete', old);
        await old.delete();
      }
    });
    return deleted ? null : _Left.delete;
  }

  // Runs [step], one operation of the move, again while it fails because
  // the file is in use, within [_moveRetryBudget] for the whole move
  // ([spent] so far); once without [spent]. `false` when it failed.
  static Future<bool> _attempt(
    Stopwatch? spent,
    Future<void> Function() step,
  ) async {
    for (var delay = const Duration(milliseconds: 50); ; delay *= 2) {
      try {
        await step();
        return true;
      } on PathNotFoundException {
        // Another mover (another isolate, engine or instance of the app
        // at the first start after the update) took the file first.
        return true;
      } on FileSystemException catch (error) {
        if (spent == null ||
            !_inUse(error) ||
            spent.elapsed + delay > _moveRetryBudget) {
          return false;
        }
        await Future<void>.delayed(delay);
      }
    }
  }

  // What Windows answers for a file another process or isolate has open:
  // ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION, and ERROR_ACCESS_DENIED
  // for a file being deleted (or replaced) by another.
  static bool _inUse(FileSystemException error) =>
      const {5, 32, 33}.contains(error.osError?.errorCode);

  static String _name(File file) => file.path.split(RegExp(r'[\\/]')).last;

  // The record: the old folder's path on its first line, then a line per
  // old file left: `copy <name>` for a value whose copy failed, `delete
  // <name>` for a file copied (or whose value was deleted since) that
  // could not be deleted. `null` when there is none: no move ran yet.
  Map<String, _Left>? _readRecord() {
    final record = _record;
    if (!record.existsSync()) {
      return null;
    }
    final entries = <String, _Left>{};
    for (final line in record.readAsLinesSync().skip(1)) {
      final space = line.indexOf(' ');
      if (space < 0) {
        continue;
      }
      final state = switch (line.substring(0, space)) {
        'copy' => _Left.copy,
        'delete' => _Left.delete,
        _ => null,
      };
      final name = line.substring(space + 1).trim();
      if (state != null && _keyOf(File(name), anyLength: true) != null) {
        entries[name] = state;
      }
    }
    return entries;
  }

  Future<void> _writeRecord(Directory legacy, Map<String, _Left> left) async {
    final record = _record;
    await record.parent.create(recursive: true);
    await writeAtomically(
      record,
      utf8.encode(
        [
          legacy.path,
          for (final MapEntry(key: name, value: state) in left.entries)
            '${state.name} $name',
        ].map((line) => '$line\n').join(),
      ),
    );
  }

  // Changes the record as on disk now (another isolate may have changed
  // it), one change after the other in this isolate.
  Future<void> _changeRecord(void Function(Map<String, _Left> entries) change) {
    final legacy = _legacy!;
    final key = _folderKey;
    final next = (_recordChanges[key] ?? Future<void>.value()).then((_) async {
      final entries = _readRecord();
      if (entries == null) {
        return;
      }
      change(entries);
      await _writeRecord(legacy, entries);
    });
    _recordChanges[key] = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  // The values [delete] or [deleteAll] removed are never copied: their
  // old files, whose copy failed, are only deleted from now on.
  Future<void> _cancelCopies(bool Function(String name) which) async {
    final pending = _copiesLeft[_folderKey];
    if (pending == null || !pending.any(which)) {
      return;
    }
    pending.removeWhere(which);
    await _changeRecord((entries) {
      for (final name in entries.keys.toList()) {
        if (entries[name] == _Left.copy && which(name)) {
          entries[name] = _Left.delete;
        }
      }
    });
  }

  // The name of [key]'s file in the 0.4.x folder: its hexadecimal,
  // whatever its length.
  static String _legacyName(String key) => '${_hex(utf8.encode(key))}.bin';

  @override
  Future<String?> read(String key) async {
    await _migrated();
    final file = _file(_folder, key);
    if (!file.existsSync()) {
      return null;
    }
    return _readFile(file, key);
  }

  Future<String?> _readFile(File file, String key) async {
    var sealed = await file.readAsBytes();
    if (_hashed(key)) {
      final (stored, rest) = _readHeader(sealed);
      if (stored != key) {
        // Another key with the same hash, or a damaged file: not ours.
        return null;
      }
      sealed = rest;
    }
    final plain = _Dpapi.unprotect(sealed, _entropy(key));
    if (plain == null) {
      // Another user's or another computer's file: it can never be read.
      await file.delete();
      return null;
    }
    return utf8.decode(plain);
  }

  // The key of a hashed file's header and the sealed bytes after it;
  // `(null, bytes)` for a file without one.
  static (String?, Uint8List) _readHeader(Uint8List bytes) {
    if (bytes.length < _magic.length + 2) {
      return (null, bytes);
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        return (null, bytes);
      }
    }
    final length = bytes[_magic.length] << 8 | bytes[_magic.length + 1];
    final start = _magic.length + 2;
    if (bytes.length < start + length) {
      return (null, bytes);
    }
    try {
      return (
        utf8.decode(bytes.sublist(start, start + length)),
        Uint8List.sublistView(bytes, start + length),
      );
    } on FormatException {
      return (null, bytes);
    }
  }

  static List<int> _header(String key) {
    final bytes = utf8.encode(key);
    if (bytes.length > 0xffff) {
      throw ArgumentError.value(key.length, 'key', 'is too long');
    }
    return [..._magic, bytes.length >> 8, bytes.length & 0xff, ...bytes];
  }

  @override
  Future<void> write(String key, String value) async {
    await _migrated();
    final sealed = _Dpapi.protect(utf8.encode(value), _entropy(key));
    final file = _file(_folder, key);
    await file.parent.create(recursive: true);
    await writeAtomically(
      file,
      _hashed(key) ? [..._header(key), ...sealed] : sealed,
    );
  }

  /// Writes [bytes] to a file aside, with a name no other writer uses
  /// (another isolate, another process of the app), and renames it to
  /// [file], so a crash never leaves half a file and two writers never
  /// share the file aside.
  @visibleForTesting
  static Future<void> writeAtomically(File file, List<int> bytes) async {
    final unique =
        '$pid-${_random.nextInt(1 << 32).toRadixString(16)}'
        '-${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${file.path}.$unique.tmp');
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

  static final _random = Random.secure();

  @override
  Future<void> delete(String key) async {
    await _migrated();
    final file = _file(_folder, key);
    if (file.existsSync()) {
      await file.delete();
    }
    final legacyName = _legacyName(key).toLowerCase();
    await _cancelCopies((name) => name.toLowerCase() == legacyName);
  }

  @override
  Future<Set<String>> keys() async {
    await _migrated();
    return {
      if (_folder.existsSync())
        await for (final entry in _folder.list())
          if (entry is File) ?_keyOf(entry),
    };
  }

  @override
  Future<void> deleteAll() async {
    await _migrated();
    await _cancelCopies((_) => true);
    if (!_folder.existsSync()) {
      return;
    }
    await for (final entry in _folder.list()) {
      if (entry is File && _keyOf(entry) != null) {
        await entry.delete();
      }
    }
  }

  /// The key a file of the folder holds, or `null` for any other file (a
  /// temporary one, the record of the move, a foreign one). A plain
  /// hexadecimal name is at most [maxHexKeyBytes] long, except in the
  /// 0.4.x folder ([anyLength]), which named every key so.
  static String? _keyOf(File file, {bool anyLength = false}) {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    if (!name.endsWith('.bin')) {
      return null;
    }
    if (name.startsWith('k-') && !anyLength) {
      try {
        final (key, _) = _readHeader(file.readAsBytesSync());
        return key != null && fileName(key) == name ? key : null;
      } on FileSystemException {
        return null;
      }
    }
    final hex = name.substring(0, name.length - 4);
    if (hex.isEmpty ||
        hex.length.isOdd ||
        (!anyLength && hex.length > maxHexKeyBytes * 2)) {
      return null;
    }
    try {
      return utf8.decode([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    } on FormatException {
      return null;
    }
  }

  static Uint8List _entropy(String key) =>
      utf8.encode('spring_boot_starter_flutter_security.secret_store:$key');
}

// What the move left of an old file: its value not copied yet, or the
// file itself not deleted yet.
enum _Left { copy, delete }

// DATA_BLOB of wincrypt.h.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

// CryptProtectData and CryptUnprotectData have the same shape (the second
// argument is an input string or an output pointer; both are null here).
typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

abstract final class _Dpapi {
  // Never show a prompt: fail instead.
  static const _uiForbidden = 0x1;

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
    'CryptProtectData',
  );
  static final _unprotect = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
    'CryptUnprotectData',
  );
  static final _localAlloc = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)
      >('LocalAlloc');
  static final _localFree = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  static final _getLastError = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  // LMEM_FIXED | LMEM_ZEROINIT: a zeroed block, its handle a pointer.
  static const _zeroed = 0x40;

  static Uint8List protect(List<int> plain, List<int> entropy) {
    final (result, error) = _run(_protect, plain, entropy);
    if (result == null) {
      throw PlatformSecretStoreException(
        'CryptProtectData failed (Windows error $error)',
        code: 'dpapi',
      );
    }
    return result;
  }

  /// The plain bytes, or `null` when the data cannot be decrypted.
  static Uint8List? unprotect(List<int> sealed, List<int> entropy) =>
      _run(_unprotect, sealed, entropy).$1;

  /// The output bytes, or `null` and the Windows error code.
  static (Uint8List?, int) _run(
    _CryptDart function,
    List<int> data,
    List<int> entropy,
  ) {
    final arena = NativeArena(
      (size) => _localAlloc(_zeroed, size),
      (pointer) => _localFree(pointer),
    );
    Pointer<_DataBlob> blob(List<int> bytes) => arena<_DataBlob>()
      ..ref.cbData = bytes.length
      ..ref.pbData = arena.bytes(bytes);

    try {
      final input = blob(data);
      final output = arena<_DataBlob>();
      try {
        final ok = function(
          input,
          nullptr,
          blob(entropy),
          nullptr,
          nullptr,
          _uiForbidden,
          output,
        );
        if (ok == 0) {
          return (null, _getLastError());
        }
        return (
          Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData)),
          0,
        );
      } finally {
        // The copies in C memory are wiped before they are freed: the
        // input is the plain text when protecting, the output when not.
        wipe(input.ref.pbData, input.ref.cbData);
        if (output.ref.pbData != nullptr) {
          wipe(output.ref.pbData, output.ref.cbData);
          _localFree(output.ref.pbData.cast());
        }
      }
    } finally {
      arena.releaseAll();
    }
  }
}

// The version resource of the executable (VERSIONINFO of the runner's
// Runner.rc), through version.dll, as Flutter's path_provider_windows
// reads it.
abstract final class _VersionInfo {
  // en-US with the code pages Flutter's Runner.rc and Visual Studio use.
  static const _blocks = ['040904e4', '040904b0'];

  /// `<CompanyName>\<ProductName>` (or the product alone) of
  /// [executable]'s version resource, each made a folder name; `null`
  /// when it has no product name or cannot be read.
  static String? companyAndProduct(String executable) {
    try {
      final values = _read(executable, const ['CompanyName', 'ProductName']);
      final company = _clean(values['CompanyName']);
      final product = _clean(values['ProductName']);
      if (product == null) {
        return null;
      }
      return company == null ? product : '$company\\$product';
    } on Object {
      // No version.dll (not Windows), no resource: the fallback decides.
      return null;
    }
  }

  static String? _clean(String? value) => value == null
      ? null
      : WindowsDpapiSecretStore.folderName(value.replaceAll('\\', '_'));

  static Map<String, String> _read(String executable, List<String> names) {
    final version = DynamicLibrary.open('version.dll');
    final sizeOf = version
        .lookupFunction<
          Uint32 Function(Pointer<Uint16>, Pointer<Uint32>),
          int Function(Pointer<Uint16>, Pointer<Uint32>)
        >('GetFileVersionInfoSizeW');
    final infoOf = version
        .lookupFunction<
          Int32 Function(Pointer<Uint16>, Uint32, Uint32, Pointer<Void>),
          int Function(Pointer<Uint16>, int, int, Pointer<Void>)
        >('GetFileVersionInfoW');
    final query = version
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Uint16>,
            Pointer<Pointer<Uint16>>,
            Pointer<Uint32>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Uint16>,
            Pointer<Pointer<Uint16>>,
            Pointer<Uint32>,
          )
        >('VerQueryValueW');
    final arena = NativeArena(
      (size) => _Dpapi._localAlloc(_Dpapi._zeroed, size),
      (pointer) => _Dpapi._localFree(pointer),
    );
    try {
      final path = _utf16(arena, executable);
      final size = sizeOf(path, arena<Uint32>());
      if (size == 0) {
        return const {};
      }
      final info = arena.allocate<Void>(size);
      if (infoOf(path, 0, size, info) == 0) {
        return const {};
      }
      final values = <String, String>{};
      for (final name in names) {
        for (final block in _blocks) {
          final value = arena<Pointer<Uint16>>();
          final length = arena<Uint32>();
          final key = _utf16(arena, '\\StringFileInfo\\$block\\$name');
          // The value points into [info]; [length] counts its UTF-16
          // units, the terminating zero included or not: read up to it.
          if (query(info, key, value, length) != 0 &&
              value.value != nullptr &&
              length.value > 0) {
            final units = value.value.asTypedList(length.value);
            final end = units.indexOf(0);
            final text = String.fromCharCodes(
              end < 0 ? units : units.sublist(0, end),
            ).trim();
            if (text.isNotEmpty) {
              values[name] = text;
              break;
            }
          }
        }
      }
      return values;
    } finally {
      arena.releaseAll();
    }
  }

  // [text] as a zero-terminated UTF-16 string.
  static Pointer<Uint16> _utf16(NativeArena arena, String text) {
    final units = text.codeUnits;
    final pointer = arena.allocate<Uint16>((units.length + 1) * 2);
    pointer.asTypedList(units.length + 1)
      ..setAll(0, units)
      ..[units.length] = 0;
    return pointer;
  }
}
