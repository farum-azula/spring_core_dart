import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:spring_boot_starter_flutter_security/src/secret_store/native_memory.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/platform_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// The [PlatformSecretStore] of Linux: the Secret Service of the desktop
/// (GNOME Keyring, KWallet, KeePassXC) through `libsecret`.
///
/// Each value is a password item of the default collection (the login
/// keyring), found by two attributes: `application` ([application]) and
/// `key`. The Secret Service keeps it encrypted and unlocks it with the
/// user's login. It separates users, not apps: any program running as
/// the same user can read the items (the `application` attribute is a
/// name, not a lock).
///
/// [application] is `spring.flutter.security.application-id` when set
/// (a blank id counts as unset), else the application id of the running
/// app (the `APPLICATION_ID` of the runner's `linux/CMakeLists.txt`,
/// which Flutter's runner gives its GTK application), else the
/// executable's name. 0.4.x used the executable's name, so two apps of
/// that name shared items: with [legacyApplication] (the package's store
/// passes the executable's name), the items under it are moved to
/// [application] once, at the store's first call in the process that
/// finds no record of the move: a value already under [application]
/// wins, the old items are removed, and the move is recorded in the
/// keyring (an item of its own schema, which [keys] and [deleteAll] do
/// not see). From then on the old name is never read again, so another
/// app of that executable name (still on 0.4.x) no longer mixes its
/// values in; that app loses the values moved, its user logs in again.
///
/// While the keyring is locked, a call that needs a value throws a
/// [PlatformSecretStoreException] (`libsecret_locked`) rather than
/// answering "no value": a value may exist, and an app must not replace
/// it (a new DPoP key would make the stored tokens useless). For each
/// call:
///
/// - [read] of a key that has a value asks the Secret Service to unlock
///   the keyring; when the user dismisses the prompt, `libsecret_locked`.
///   A key that has no value reads as `null`: the Secret Service searches
///   a locked keyring too (the items' attributes are not encrypted), so
///   it knows the key is missing.
/// - [write] asks to unlock as well; dismissed, `libsecret_locked`.
/// - [delete] and [deleteAll] throw `libsecret_locked` when a value to
///   delete is in the locked keyring, without asking to unlock (libsecret
///   deletes unlocked items only); nothing to delete, they return.
/// - [keys] answers: it lists the keys, which are attributes, never the
///   values.
/// - With [legacyApplication], the first call in the process checks the
///   record of the 0.4.x move, which is in the keyring too: until the
///   keyring is unlocked, every call throws `libsecret_locked` (the check
///   runs again at the next call).
///
/// Only a locked item or collection counts: a read that runs while the
/// same key is written for the first time looks the value up again rather
/// than calling the keyring locked.
///
/// `libsecret-1.so.0` must be installed (the `libsecret-1-0` package on
/// Debian and Ubuntu, `libsecret` on Fedora and Arch) and a Secret
/// Service must run. Without them every call throws a
/// [PlatformSecretStoreException]; the values are never written to a plain
/// file instead. The calls block (the keyring may ask the user to unlock
/// it), so each runs in a short-lived isolate, not on the UI's.
final class LinuxSecretServiceStore implements SecretStore {
  /// The store of [application] (by default the running app's id, see
  /// above; a blank one is the default), moving the items of
  /// [legacyApplication] to it once, if given.
  LinuxSecretServiceStore({String? application, String? legacyApplication})
    : this._(
        _nonBlank(application) ?? defaultApplication(),
        _nonBlank(legacyApplication),
      );

  LinuxSecretServiceStore._(this.application, String? legacy)
    : legacyApplication = legacy == application ? null : legacy;

  /// The value of the `application` attribute of the items.
  final String application;

  /// The `application` of items written by 0.4.x, moved to [application]
  /// once; `null` for none.
  final String? legacyApplication;

  static String? _nonBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  /// The application id of the running GTK application, or the
  /// executable's name.
  static String defaultApplication() =>
      _runningApplicationId() ?? executableName();

  /// The executable's name: the `application` of 0.4.x.
  static String executableName() => Platform.resolvedExecutable.split('/').last;

  // g_application_get_default() of GIO: the GtkApplication of Flutter's
  // runner (its id is the runner's APPLICATION_ID); none in a test.
  static String? _runningApplicationId() {
    try {
      final gio = DynamicLibrary.open('libgio-2.0.so.0');
      final current = gio
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'g_application_get_default',
          );
      final idOf = gio
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>),
            Pointer<Uint8> Function(Pointer<Void>)
          >('g_application_get_application_id');
      final app = current();
      if (app == nullptr) {
        return null;
      }
      final id = idOf(app);
      if (id == nullptr) {
        return null;
      }
      final text = readCString(id);
      return text.isEmpty ? null : text;
    } on Object {
      // No GIO (not Linux): the executable's name.
      return null;
    }
  }

  // The moves of 0.4.x items done or running in this process, by
  // (application, legacy): one per pair, whatever the number of stores.
  static final Map<(String, String), Future<void>> _migrations = {};

  /// Forgets the moves done in this process, as a new start does: the
  /// next call looks for the record again; for tests.
  @visibleForTesting
  static void debugForgetMigrations() => _migrations.clear();

  /// Removes the keyring's record that this store's 0.4.x items were
  /// moved (the keyring outlives a test run), and forgets the move in
  /// this process; for tests.
  @visibleForTesting
  Future<void> debugForgetMigration() async {
    final legacy = legacyApplication;
    if (legacy == null) {
      return;
    }
    final application = this.application;
    unawaited(_migrations.remove((application, legacy)));
    await Isolate.run(() => _LibSecret.forgetMigration(application, legacy));
  }

  /// Moves the items of [legacyApplication] to [application], once per
  /// keyring (recorded there) and once per process; a move that failed
  /// (a locked keyring) is tried again at the next call.
  Future<void> _migrated() {
    final legacy = legacyApplication;
    if (legacy == null) {
      return Future.value();
    }
    final application = this.application;
    final pair = (application, legacy);
    return _migrations[pair] ??= () async {
      try {
        await Isolate.run(() => _LibSecret.migrate(application, legacy));
      } on Object {
        // This very future: removed so the next call tries again.
        unawaited(_migrations.remove(pair));
        rethrow;
      }
    }();
  }

  @override
  Future<String?> read(String key) async {
    await _migrated();
    final application = this.application;
    return Isolate.run(() => _LibSecret.lookup(application, key));
  }

  @override
  Future<void> write(String key, String value) async {
    await _migrated();
    final application = this.application;
    return Isolate.run(() => _LibSecret.store(application, key, value));
  }

  @override
  Future<void> delete(String key) async {
    await _migrated();
    final application = this.application;
    await Isolate.run(() => _LibSecret.clear(application, key));
  }

  @override
  Future<Set<String>> keys() async {
    await _migrated();
    final application = this.application;
    return Isolate.run(() => _LibSecret.keys(application));
  }

  @override
  Future<void> deleteAll() async {
    await _migrated();
    final application = this.application;
    // Without a key, every item of the application matches (not the
    // record of the move: another schema).
    await Isolate.run(() => _LibSecret.clear(application, null));
  }
}

// What a search without unlocking found.
enum _Found { none, locked, unlocked, unknown }

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

  // The record that the items of 0.4.x were moved: an item of its own
  // schema (`application` the app, `key` the old name), so the app's
  // keys() and deleteAll() never see it.
  static const _migrationSchemaName =
      'dev.farumazula.SpringBootStarterFlutterSecurity.Migration';

  // SECRET_SEARCH_NONE: the first matching item, not unlocked.
  static const _searchNone = 0;

  // SECRET_SEARCH_ALL: every matching item, not only the first.
  static const _searchAll = 1 << 1;

  static final DynamicLibrary _secret = _open('libsecret-1.so.0');
  static final DynamicLibrary _glib = _open('libglib-2.0.so.0');
  // g_object_unref is GObject's, not GLib's.
  static final DynamicLibrary _gobject = _open('libgobject-2.0.so.0');

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

  /// The value of [key], `null` when there is none; throws
  /// `libsecret_locked` when the item is in a locked keyring whose unlock
  /// prompt was dismissed.
  static String? lookup(
    String application,
    String key, {
    String schemaName = _schemaName,
  }) => _withAttributes(application, key, schemaName: schemaName, (
    arena,
    schema,
    attributes,
    error,
  ) {
    final lookup = _secret.lookupFunction<_LookupNative, _LookupDart>(
      'secret_password_lookupv_sync',
    );
    final free = _secret
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('secret_password_free');
    for (var attempt = 1; ; attempt++) {
      final password = lookup(schema, attributes, nullptr, error);
      _check(error, 'read');
      if (password != nullptr) {
        try {
          return readCString(password);
        } finally {
          free(password); // wipes the copy before freeing it
        }
      }
      // No value, or a locked one whose unlock prompt was dismissed (a
      // search without unlocking still finds a locked item), or one
      // written right after the lookup by another call: only an item
      // still locked is "locked"; one that is not is looked up again.
      switch (_find(schema, attributes, error)) {
        case _Found.none:
          return null;
        case _Found.locked:
          throw const PlatformSecretStoreException(
            'the keyring holding the value is locked (the prompt to unlock '
            'it was dismissed): unlock it and try again',
            code: 'libsecret_locked',
          );
        case _Found.unlocked || _Found.unknown when attempt < 3:
          continue;
        case _Found.unlocked || _Found.unknown:
          // Never "no value" for a value that exists.
          throw const PlatformSecretStoreException(
            'the Secret Service has the value but did not return it',
            code: 'libsecret',
          );
      }
    }
  });

  /// Moves the items of [legacy] to [application], unless the keyring
  /// records that it was done: each value not under [application] yet is
  /// copied, every old item removed, then the move recorded.
  static void migrate(String application, String legacy) {
    if (lookup(application, legacy, schemaName: _migrationSchemaName) != null) {
      return;
    }
    for (final key in keys(legacy)) {
      final value = lookup(legacy, key);
      if (value != null && lookup(application, key) == null) {
        store(application, key, value);
      }
      clear(legacy, key);
    }
    store(
      application,
      legacy,
      'moved',
      schemaName: _migrationSchemaName,
      label: 'Secrets of "$legacy" moved to $application',
    );
  }

  static void store(
    String application,
    String key,
    String value, {
    String schemaName = _schemaName,
    String? label,
  }) => _withAttributes(application, key, schemaName: schemaName, (
    arena,
    schema,
    attributes,
    error,
  ) {
    final store = _secret.lookupFunction<_StoreNative, _StoreDart>(
      'secret_password_storev_sync',
    );
    final itemLabel = arena.string(label ?? 'Secret "$key" of $application');
    final password = arena.string(value);
    try {
      final ok = store(
        schema,
        attributes,
        nullptr, // the default collection
        itemLabel,
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
            freeList(list, _gobject.lookup<Void>('g_object_unref'));
          }
        }
        return keys;
      });

  // Whether an item matches [attributes] and whether the Secret Service
  // reports it locked; nothing is unlocked and no secret loaded. The
  // first item found, or with [all] every one: locked when any is (the
  // Secret Service searches locked keyrings too, their attributes being
  // stored in the clear).
  static _Found _find(
    Pointer<_Schema> schema,
    Pointer<Void> attributes,
    Pointer<Pointer<_GError>> error, {
    bool all = false,
  }) {
    final search = _secret.lookupFunction<_SearchNative, _SearchDart>(
      'secret_password_searchv_sync',
    );
    final freeList = _glib
        .lookupFunction<
          Void Function(Pointer<_GList>, Pointer<Void>),
          void Function(Pointer<_GList>, Pointer<Void>)
        >('g_list_free_full');
    final list = search(
      schema,
      attributes,
      all ? _searchAll : _searchNone,
      nullptr,
      error,
    );
    _check(error, 'read');
    if (list == nullptr) {
      return _Found.none;
    }
    try {
      // A SecretItem of the D-Bus Secret Service knows whether it is
      // locked; another kind of item (libsecret's local file backend) has
      // no lock.
      final itemType = _secret
          .lookupFunction<UintPtr Function(), int Function()>(
            'secret_item_get_type',
          )();
      final isA = _gobject
          .lookupFunction<
            Int32 Function(Pointer<Void>, UintPtr),
            int Function(Pointer<Void>, int)
          >('g_type_check_instance_is_a');
      final locked = _secret
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('secret_item_get_locked');
      var found = _Found.none;
      for (var node = list; node != nullptr; node = node.ref.next) {
        final item = node.ref.data;
        if (item == nullptr || isA(item, itemType) == 0) {
          found = _Found.unknown;
        } else if (locked(item) != 0) {
          return _Found.locked;
        } else if (found == _Found.none) {
          found = _Found.unlocked;
        }
      }
      return found;
    } finally {
      freeList(list, _gobject.lookup<Void>('g_object_unref'));
    }
  }

  /// Removes the record of the move of [legacy]'s items to
  /// [application].
  static void forgetMigration(String application, String legacy) =>
      _withAttributes(application, legacy, schemaName: _migrationSchemaName, (
        arena,
        schema,
        attributes,
        error,
      ) {
        final clear = _secret.lookupFunction<_ClearNative, _ClearDart>(
          'secret_password_clearv_sync',
        );
        clear(schema, attributes, nullptr, error);
        _check(error, 'delete');
      });

  /// Removes the item of [key], or every item of [application] when
  /// [key] is `null`; throws `libsecret_locked` when one is in a locked
  /// keyring.
  ///
  /// libsecret removes the unlocked items only: a locked one is left
  /// without an error (nor a prompt to unlock it), and its result says
  /// only whether anything was removed. So what is left is looked up:
  /// a locked item fails the call rather than staying silently, an
  /// unlocked one (written meanwhile by another call) is removed again.
  static void clear(String application, String? key) =>
      _withAttributes(application, key, (arena, schema, attributes, error) {
        final clear = _secret.lookupFunction<_ClearNative, _ClearDart>(
          'secret_password_clearv_sync',
        );
        for (var attempt = 1; ; attempt++) {
          clear(schema, attributes, nullptr, error);
          _check(error, 'delete');
          switch (_find(schema, attributes, error, all: true)) {
            case _Found.none:
              return;
            case _Found.locked:
              throw const PlatformSecretStoreException(
                'the keyring holding the value is locked: unlock it and try '
                'again (libsecret does not delete locked items)',
                code: 'libsecret_locked',
              );
            case _Found.unlocked || _Found.unknown when attempt < 3:
              continue;
            case _Found.unlocked || _Found.unknown:
              throw const PlatformSecretStoreException(
                'the Secret Service did not delete the value',
                code: 'libsecret',
              );
          }
        }
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
    body, {
    String schemaName = _schemaName,
  }) {
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
      schema.ref.name = arena.string(schemaName);
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
  // libsecret's error domain (`secret_error_get_quark()`).
  static int _secretErrorQuark() =>
      _secret.lookupFunction<Uint32 Function(), int Function()>(
        'secret_error_get_quark',
      )();

  static void _check(Pointer<Pointer<_GError>> error, String operation) {
    final gError = error.value;
    if (gError == nullptr) {
      return;
    }
    final message = gError.ref.message == nullptr
        ? 'code ${gError.ref.code}'
        : readCString(gError.ref.message);
    // SECRET_ERROR_IS_LOCKED (2) of libsecret's error domain: a locked
    // collection (the user dismissed the unlock prompt), reported as
    // `libsecret_locked` like a locked item, so callers see one code.
    final locked =
        gError.ref.domain == _secretErrorQuark() && gError.ref.code == 2;
    _glib.lookupFunction<
      Void Function(Pointer<_GError>),
      void Function(Pointer<_GError>)
    >('g_error_free')(gError);
    error.value = nullptr;
    if (locked) {
      throw PlatformSecretStoreException(
        'the Secret Service is locked: unlock the keyring to $operation '
        'the value ($message)',
        code: 'libsecret_locked',
      );
    }
    throw PlatformSecretStoreException(
      'the Secret Service failed to $operation the value: $message '
      '(is a Secret Service such as GNOME Keyring or KWallet running?)',
      code: 'libsecret',
    );
  }
}
