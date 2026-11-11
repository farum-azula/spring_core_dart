import 'package:spring_boot_starter_data/src/store/data_store_capabilities.dart';

/// Marks a top-level constant [DataStoreDescriptor] as a store the build
/// knows: the generator finds the declarations in (or exported by)
/// `lib/spring_auto_configuration.dart` of the application's dependencies,
/// as it finds their `@AutoConfigurationModule`s.
///
/// ```dart
/// // lib/spring_auto_configuration.dart of the package of the store
/// @DataStoreDeclaration()
/// const documentStore = DataStoreDescriptor(
///   'documents',
///   capabilities: DataStoreCapabilities(changes: true),
/// );
/// ```
///
/// Spring (Java): none; a Spring Data module is chosen by the dependency
/// and its repository interfaces, and nothing is checked before the
/// application starts.
class DataStoreDeclaration {
  /// Marks a store's description.
  const DataStoreDeclaration();
}

/// What the build may know of a `DataStore` before the application runs:
/// its [name] (what `@UseStore` and `spring.data.store` say), its
/// [capabilities], and when it is the application's default store.
///
/// With it the build refuses what the run time would refuse when the
/// repository is created: a repository method that needs a capability its
/// store lacks (`@Lock`, `@Query`, `@Procedure`, a stream of changes,
/// `@Transactional`) is a build error naming the method, the store and
/// the fix; so is a `@Transactional` of any bean when the default store
/// has no transactions. A store without a description is checked when the
/// application starts, as before. With [collectionsNeedJson] it refuses a
/// collection property the store has no column for (see there).
///
/// The store of a repository is, for the build: its `@UseStore`; else
/// `spring.data.store`; else the first described store whose [defaultWhen]
/// holds (by package, then by the constant's name); else unknown.
///
/// A capability that depends on the configuration or on the database
/// (functions of the SQL store, which PostgreSQL has and SQLite has not)
/// is declared `true`: the build must not refuse what may work, and the
/// store's own `capabilities` decide when the application starts.
///
/// ```dart
/// @DataStoreDeclaration()
/// const documentStore = DataStoreDescriptor(
///   'documents',
///   capabilities: DataStoreCapabilities(changes: true),
///   defaultWhen: DataStoreDefault(
///     whenProperty: ['documents.url'],
///     unlessProperty: ['spring.datasource.url', 'spring.data.store'],
///   ),
///   fixes: {
///     DataStoreCapability.transactions:
///         'set documents.sql-url to run the repositories over SQL',
///   },
/// );
/// ```
///
/// Spring (Java): none (see [DataStoreDeclaration]).
final class DataStoreDescriptor {
  /// The store called [name] has [capabilities]; it is the default store
  /// when [defaultWhen] holds; [fixes] say, for a capability it lacks,
  /// what to do with this store (before the general advice).
  const DataStoreDescriptor(
    this.name, {
    this.capabilities = const DataStoreCapabilities(),
    this.defaultWhen,
    this.fixes = const {},
    this.collectionsNeedJson = false,
  });

  /// The store's name: `DataStore.name`.
  final String name;

  /// What the store can do; `true` for what it may do (see the class).
  final DataStoreCapabilities capabilities;

  /// When the store is the default of the repositories without
  /// `@UseStore`; null when the build cannot tell.
  final DataStoreDefault? defaultWhen;

  /// The store's own way to get a capability it lacks, by capability: a
  /// sentence without a full stop, as `DataStoreCapability.fix` is.
  final Map<DataStoreCapability, String> fixes;

  /// Whether a `Map`, `List` or `Set` property of an entity must be
  /// `@Json` (or a `@MappedCollection`) to be kept: the store has no
  /// column for a collection. The build then refuses, for a repository of
  /// this store, an entity with a `Map`, a `Set`, or a `List` of anything
  /// but simple values without it, naming the entity, the property and
  /// the fix. A list of simple values is left to the store (it may be an
  /// array column of its database, as in PostgreSQL), which refuses it
  /// when the repository is created, and bytes (`List<int>`, `Uint8List`)
  /// are a column everywhere. False (nothing is checked) unless said.
  final bool collectionsNeedJson;

  @override
  String toString() => 'DataStoreDescriptor($name, $capabilities)';
}

/// When a described store is the application's default, by the properties
/// of the configuration the build reads (`application.yml` or
/// `application.properties` without a profile, as `AutoConfigurationBuild`
/// reads it): every one of [whenProperty] is set, and none of
/// [unlessProperty] is.
///
/// A property is set when the file gives it a value, also one the build
/// cannot resolve (`${DATABASE_URL}`): the key is there.
///
/// ```dart
/// const DataStoreDefault(
///   whenProperty: ['spring.datasource.url'],
///   unlessProperty: ['spring.data.store'],
/// )
/// ```
///
/// Spring (Java): none (see [DataStoreDeclaration]).
final class DataStoreDefault {
  /// Holds when all of [whenProperty] are set and none of
  /// [unlessProperty].
  const DataStoreDefault({
    this.whenProperty = const [],
    this.unlessProperty = const [],
  });

  /// The properties that must all be set.
  final List<String> whenProperty;

  /// The properties of which none may be set.
  final List<String> unlessProperty;
}
