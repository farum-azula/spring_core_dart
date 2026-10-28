import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter/src/secure_storage/native_memory.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/secure_token_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The [SecureTokenStore] of Windows: each value encrypted with DPAPI for
/// the current Windows user, in a file of its own.
///
/// `CryptProtectData` encrypts with a key Windows derives from the user's
/// logon secret: another user of the computer, or the same files copied
/// to another computer, cannot decrypt them. The entropy (a constant and
/// the key's name) ties each file to its key, so files swapped between
/// keys do not decrypt either. A file that does not decrypt is deleted
/// and read as missing.
///
/// The files are in `%LOCALAPPDATA%\<app>\spring_token_store`, `<app>`
/// being the name of the app's executable; the file name is the key in
/// hexadecimal (key names are not secret, the values are).
final class WindowsDpapiTokenStore implements TokenStore {
  /// The store in [directory], by default the one above.
  WindowsDpapiTokenStore({this._directory});

  final Directory? _directory;

  Directory get _folder => _directory ?? _defaultDirectory();

  static Directory _defaultDirectory() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) {
      throw const SecureTokenStoreException(
        'LOCALAPPDATA is not set: no folder for the token files',
        code: 'dpapi',
      );
    }
    var app = Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
    if (app.toLowerCase().endsWith('.exe')) {
      app = app.substring(0, app.length - 4);
    }
    return Directory('$base\\$app\\spring_token_store');
  }

  File _file(String key) {
    final name = [
      for (final byte in utf8.encode(key))
        byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return File('${_folder.path}\\$name.bin');
  }

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) {
      return null;
    }
    final sealed = await file.readAsBytes();
    final plain = _Dpapi.unprotect(sealed, _entropy(key));
    if (plain == null) {
      // Another user's or another computer's file: it can never be read.
      await file.delete();
      return null;
    }
    return utf8.decode(plain);
  }

  @override
  Future<void> write(String key, String value) async {
    final sealed = _Dpapi.protect(utf8.encode(value), _entropy(key));
    final file = _file(key);
    await file.parent.create(recursive: true);
    // Written aside and renamed, so a crash never leaves half a file.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(sealed, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static Uint8List _entropy(String key) =>
      utf8.encode('spring_boot_starter_flutter.token_store:$key');
}

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
      throw SecureTokenStoreException(
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
