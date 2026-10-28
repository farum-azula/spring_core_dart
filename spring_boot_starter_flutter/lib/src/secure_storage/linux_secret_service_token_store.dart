import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_flutter/src/secure_storage/native_memory.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/secure_token_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The [SecureTokenStore] of Linux: the Secret Service of the desktop
/// (GNOME Keyring, KWallet, KeePassXC) through `libsecret`.
///
/// Each value is a password item of the default collection (the login
/// keyring), found by two attributes: `application` (the app's
/// executable name, or [application]) and `key`. The Secret Service keeps
/// it encrypted and unlocks it with the user's login.
///
/// `libsecret-1.so.0` must be installed (the `libsecret-1-0` package on
/// Debian and Ubuntu, `libsecret` on Fedora and Arch) and a Secret
/// Service must run. Without them every call throws a
/// [SecureTokenStoreException]; the values are never written to a plain
/// file instead. The calls block (the keyring may ask the user to unlock
/// it), so each runs in a short-lived isolate, not on the UI's.
final class LinuxSecretServiceTokenStore implements TokenStore {
  /// The store of [application], by default the executable's name.
  LinuxSecretServiceTokenStore({String? application})
    : application = application ?? Platform.resolvedExecutable.split('/').last;

  /// The value of the `application` attribute of the items.
  final String application;

  @override
  Future<String?> read(String key) {
    final application = this.application;
    return Isolate.run(() => _LibSecret.lookup(application, key));
  }

  @override
  Future<void> write(String key, String value) {
    final application = this.application;
    return Isolate.run(() => _LibSecret.store(application, key, value));
  }

  @override
  Future<void> delete(String key) {
    final application = this.application;
    return Isolate.run(() => _LibSecret.clear(application, key));
  }
}

// SecretSchemaAttribute of libsecret/secret-schema.h.
final class _SchemaAttribute extends Struct {
  external Pointer<Uint8> name;

  @Int32()
  external int type;
}

// SecretSchema of libsecret/secret-schema.h (with its reserved fields).
final class _Schema extends Struct {
  external Pointer<Uint8> name;

  @Int32()
  external int flags;

  @Array(32)
  external Array<_SchemaAttribute> attributes;

  @Int32()
  external int reserved;

  external Pointer<Void> reserved1;
  external Pointer<Void> reserved2;
  external Pointer<Void> reserved3;
  external Pointer<Void> reserved4;
  external Pointer<Void> reserved5;
  external Pointer<Void> reserved6;
  external Pointer<Void> reserved7;
}

// GError of glib/gerror.h.
final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Uint8> message;
}

typedef _StoreNative = Int32 Function(
  Pointer<_Schema>,
  Pointer<Void> attributes,
  Pointer<Uint8> collection,
  Pointer<Uint8> label,
  Pointer<Uint8> password,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _StoreDart = int Function(
  Pointer<_Schema>,
  Pointer<Void>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _LookupNative = Pointer<Uint8> Function(
  Pointer<_Schema>,
  Pointer<Void> attributes,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _LookupDart = Pointer<Uint8> Function(
  Pointer<_Schema>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);
typedef _ClearNative = Int32 Function(
  Pointer<_Schema>,
  Pointer<Void> attributes,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _ClearDart = int Function(
  Pointer<_Schema>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);

/// The calls, each made inside the isolate that runs it.
abstract final class _LibSecret {
  static const _schemaName = 'dev.farumazula.SpringBootStarterFlutter.Token';

  static final DynamicLibrary _secret = _open('libsecret-1.so.0');
  static final DynamicLibrary _glib = _open('libglib-2.0.so.0');

  static DynamicLibrary _open(String name) {
    try {
      return DynamicLibrary.open(name);
    } on ArgumentError {
      throw SecureTokenStoreException(
        '$name could not be loaded: install libsecret (libsecret-1-0 on '
        'Debian and Ubuntu, libsecret on Fedora and Arch) to keep tokens '
        'in the Secret Service',
        code: 'libsecret',
      );
    }
  }

  static String? lookup(String application, String key) =>
      _withAttributes(application, key, (arena, schema, attributes, error) {
        final lookup = _secret.lookupFunction<_LookupNative, _LookupDart>(
          'secret_password_lookupv_sync',
        );
        final free = _secret
            .lookupFunction<
              Void Function(Pointer<Uint8>),
              void Function(Pointer<Uint8>)
            >('secret_password_free');
        final password = lookup(schema, attributes, nullptr, error);
        _check(error, 'read');
        if (password == nullptr) {
          return null;
        }
        try {
          return readCString(password);
        } finally {
          free(password); // wipes the copy before freeing it
        }
      });

  static void store(String application, String key, String value) =>
      _withAttributes(application, key, (arena, schema, attributes, error) {
        final store = _secret.lookupFunction<_StoreNative, _StoreDart>(
          'secret_password_storev_sync',
        );
        final label = arena.string('Token "$key" of $application');
        final password = arena.string(value);
        try {
          final ok = store(
            schema,
            attributes,
            nullptr, // the default collection
            label,
            password,
            nullptr,
            error,
          );
          _check(error, 'write');
          if (ok == 0) {
            throw const SecureTokenStoreException(
              'the Secret Service did not store the value',
              code: 'libsecret',
            );
          }
        } finally {
          // The C copy of the secret is wiped before it is freed.
          wipe(password, cStringLength(password));
        }
      });

  static void clear(String application, String key) =>
      _withAttributes(application, key, (arena, schema, attributes, error) {
        final clear = _secret.lookupFunction<_ClearNative, _ClearDart>(
          'secret_password_clearv_sync',
        );
        clear(schema, attributes, nullptr, error);
        _check(error, 'delete');
      });

  /// Calls [body] with an arena of glib memory, the schema, the
  /// attributes of [key] (a `GHashTable` of strings) and an empty
  /// `GError*`, and frees them after.
  static T _withAttributes<T>(
    String application,
    String key,
    T Function(
      NativeArena arena,
      Pointer<_Schema> schema,
      Pointer<Void> attributes,
      Pointer<Pointer<_GError>> error,
    )
    body,
  ) {
    final allocateZeroed = _glib
        .lookupFunction<
          Pointer<Void> Function(UintPtr),
          Pointer<Void> Function(int)
        >('g_malloc0');
    final release = _glib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('g_free');
    final newTable = _glib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
        >('g_hash_table_new');
    final insert = _glib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
          int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
        >('g_hash_table_insert');
    final unref = _glib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('g_hash_table_unref');
    final arena = NativeArena(allocateZeroed, release);
    try {
      // Zeroed memory: the unused attributes end the list.
      final schema = arena<_Schema>();
      schema.ref.name = arena.string(_schemaName);
      schema.ref.flags = 0; // SECRET_SCHEMA_NONE: the name is checked too
      final names = ['application', 'key'];
      for (var i = 0; i < names.length; i++) {
        schema.ref.attributes[i].name = arena.string(names[i]);
        schema.ref.attributes[i].type = 0; // SECRET_SCHEMA_ATTRIBUTE_STRING
      }
      final table = newTable(
        _glib.lookup<Void>('g_str_hash'),
        _glib.lookup<Void>('g_str_equal'),
      );
      try {
        // The table does not own its strings: the arena frees them.
        insert(
          table,
          arena.string(names[0]).cast(),
          arena.string(application).cast(),
        );
        insert(table, arena.string(names[1]).cast(), arena.string(key).cast());
        final error = arena<Pointer<_GError>>();
        return body(arena, schema, table, error);
      } finally {
        unref(table);
      }
    } finally {
      arena.releaseAll();
    }
  }

  /// Throws the `GError` in [error], if any, after freeing it.
  static void _check(Pointer<Pointer<_GError>> error, String operation) {
    final gError = error.value;
    if (gError == nullptr) {
      return;
    }
    final message = gError.ref.message == nullptr
        ? 'code ${gError.ref.code}'
        : readCString(gError.ref.message);
    _glib.lookupFunction<
      Void Function(Pointer<_GError>),
      void Function(Pointer<_GError>)
    >('g_error_free')(gError);
    error.value = nullptr;
    throw SecureTokenStoreException(
      'the Secret Service failed to $operation the value: $message '
      '(is a Secret Service such as GNOME Keyring or KWallet running?)',
      code: 'libsecret',
    );
  }
}
