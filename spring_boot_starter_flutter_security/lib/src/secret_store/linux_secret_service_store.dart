import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_flutter_security/src/secret_store/native_memory.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/platform_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// The [PlatformSecretStore] of Linux: the Secret Service of the desktop
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
/// [PlatformSecretStoreException]; the values are never written to a plain
/// file instead. The calls block (the keyring may ask the user to unlock
/// it), so each runs in a short-lived isolate, not on the UI's.
final class LinuxSecretServiceStore implements SecretStore {
  /// The store of [application], by default the executable's name.
  LinuxSecretServiceStore({String? application})
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

  @override
  Future<Set<String>> keys() {
    final application = this.application;
    return Isolate.run(() => _LibSecret.keys(application));
  }

  @override
  Future<void> deleteAll() {
    final application = this.application;
    // Key by key: `secret_password_clearv_sync` with the application
    // alone does not remove every matching item with every Secret Service
    // (GNOME Keyring left some), so the keys are listed first and each
    // item is removed by its exact attributes, as on macOS.
    return Isolate.run(() {
      for (final key in _LibSecret.keys(application)) {
        _LibSecret.clear(application, key);
      }
    });
  }
}

// GList of glib/glist.h.
final class _GList extends Struct {
  external Pointer<Void> data;
  external Pointer<_GList> next;
  external Pointer<_GList> prev;
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
typedef _SearchNative = Pointer<_GList> Function(
  Pointer<_Schema>,
  Pointer<Void> attributes,
  Int32 flags,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _SearchDart = Pointer<_GList> Function(
  Pointer<_Schema>,
  Pointer<Void>,
  int,
  Pointer<Void>,
  Pointer<Pointer<_GError>>,
);

/// The calls, each made inside the isolate that runs it.
abstract final class _LibSecret {
  static const _schemaName =
      'dev.farumazula.SpringBootStarterFlutterSecurity.Secret';

  // SECRET_SEARCH_ALL: every matching item, not only the first.
  static const _searchAll = 1 << 1;

  static final DynamicLibrary _secret = _open('libsecret-1.so.0');
  static final DynamicLibrary _glib = _open('libglib-2.0.so.0');

  static DynamicLibrary _open(String name) {
    try {
      return DynamicLibrary.open(name);
    } on ArgumentError {
      throw PlatformSecretStoreException(
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
        final label = arena.string('Secret "$key" of $application');
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
            throw const PlatformSecretStoreException(
              'the Secret Service did not store the value',
              code: 'libsecret',
            );
          }
        } finally {
          // The C copy of the secret is wiped before it is freed.
          wipe(password, cStringLength(password));
        }
      });

  /// The `key` attributes of every item of [application]; the secrets
  /// themselves are not loaded.
  static Set<String> keys(String application) =>
      _withAttributes(application, null, (arena, schema, attributes, error) {
        final search = _secret.lookupFunction<_SearchNative, _SearchDart>(
          'secret_password_searchv_sync',
        );
        final attributesOf = _secret
            .lookupFunction<
              Pointer<Void> Function(Pointer<Void>),
              Pointer<Void> Function(Pointer<Void>)
            >('secret_retrievable_get_attributes');
        final lookupAttribute = _glib
            .lookupFunction<
              Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>),
              Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>)
            >('g_hash_table_lookup');
        final unref = _glib
            .lookupFunction<
              Void Function(Pointer<Void>),
              void Function(Pointer<Void>)
            >('g_hash_table_unref');
        final freeList = _glib
            .lookupFunction<
              Void Function(Pointer<_GList>, Pointer<Void>),
              void Function(Pointer<_GList>, Pointer<Void>)
            >('g_list_free_full');
        final list = search(schema, attributes, _searchAll, nullptr, error);
        _check(error, 'list');
        final keyName = arena.string('key').cast<Void>();
        final keys = <String>{};
        try {
          for (var node = list; node != nullptr; node = node.ref.next) {
            final table = attributesOf(node.ref.data);
            if (table == nullptr) {
              continue;
            }
            try {
              final key = lookupAttribute(table, keyName);
              if (key != nullptr) {
                keys.add(readCString(key));
              }
            } finally {
              unref(table);
            }
          }
        } finally {
          if (list != nullptr) {
            freeList(list, _glib.lookup<Void>('g_object_unref'));
          }
        }
        return keys;
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
  /// attributes of [key] (a `GHashTable` of strings; only the application
  /// when [key] is `null`, which matches all its items) and an empty
  /// `GError*`, and frees them after.
  static T _withAttributes<T>(
    String application,
    String? key,
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
        if (key != null) {
          insert(
            table,
            arena.string(names[1]).cast(),
            arena.string(key).cast(),
          );
        }
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
    throw PlatformSecretStoreException(
      'the Secret Service failed to $operation the value: $message '
      '(is a Secret Service such as GNOME Keyring or KWallet running?)',
      code: 'libsecret',
    );
  }
}
