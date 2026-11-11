import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart/spring_core_dart.dart'
    show
        EnumerablePropertySource,
        PropertiesPropertySourceLoader,
        PropertySourceLoader,
        YamlPropertySourceLoader;

// What the build knows of the stores of spring_boot_starter_data, and the
// check that a repository (or a `@Transactional` bean) uses only what its
// store can do.
//
// A store is described by its package, in a constant the generator finds
// in (or exported by) `lib/spring_auto_configuration.dart` of the
// application's dependencies, the library it reads their
// `@AutoConfigurationModule`s from:
//
// ```dart
// @DataStoreDeclaration()
// const documentStore = DataStoreDescriptor(
//   'documents',
//   capabilities: DataStoreCapabilities(changes: true),
//   defaultWhen: DataStoreDefault(whenProperty: ['documents.url']),
// );
// ```
//
// Nothing here names a store: the starter's own (`memory`, `jdbc`) are
// declared by the starter the same way. Matched by URL, so the generator
// does not depend on the starter.

const _descriptorLibrary =
    'package:spring_boot_starter_data/src/store/data_store_descriptor.dart';
const _declaration = TypeChecker.fromUrl(
  '$_descriptorLibrary#DataStoreDeclaration',
);
const _descriptor = TypeChecker.fromUrl(
  '$_descriptorLibrary#DataStoreDescriptor',
);
const _transactional = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/transaction/'
  'transaction_definition.dart#Transactional',
);
const _autoConfigurationLibrary = 'lib/spring_auto_configuration.dart';
const _dataStarter = 'spring_boot_starter_data';

/// What a store may be able to do, by the name of the constant of the
/// starter's `DataStoreCapability` (and of the field of
/// `DataStoreCapabilities`).
enum StoreCapability {
  /// `@Transactional`.
  transactions,

  /// `@Lock`.
  locks,

  /// `@Query`.
  queries,

  /// `@Procedure`.
  functions,

  /// `watch…By` and `changes…By` methods.
  changes,
}

/// What one method of a repository needs of its store (the interface
/// itself when [method] is null): written into the generated class as a
/// `StoreRequirement`, and checked by the build against the store when it
/// knows it.
final class StoreNeed {
  /// The method [method] needs [capability].
  const StoreNeed(this.method, this.capability);

  /// The name of the method; null for the interface itself.
  final String? method;

  /// What it needs.
  final StoreCapability capability;
}

/// A store as its package describes it to the build.
final class DescribedStore {
  /// The store called [name].
  const DescribedStore(
    this.name, {
    required this.capabilities,
    required this.whenProperty,
    required this.unlessProperty,
    required this.fixes,
    required this.source,
    this.collectionsNeedJson = false,
  });

  /// `DataStore.name`: what `@UseStore` and `spring.data.store` say.
  final String name;

  /// What the store can (or may) do.
  final Set<StoreCapability> capabilities;

  /// The properties that must all be set for the store to be the default;
  /// null when the store says no rule.
  final List<String>? whenProperty;

  /// The properties of which none may be set for it to be the default.
  final List<String> unlessProperty;

  /// The store's own fix for a capability it lacks.
  final Map<StoreCapability, String> fixes;

  /// Where it is declared: `package.variable`, the order of the stores.
  final String source;

  /// Whether a `Map`, `List` or `Set` property of an entity needs `@Json`
  /// (or `@MappedCollection`) on this store: the descriptor's
  /// `collectionsNeedJson`.
  final bool collectionsNeedJson;
}

/// The stores the build knows and the application's default store, read
/// once for a build step; `BeanScanner` asks it while it scans the
/// repositories and the `@Transactional` beans.
///
/// The store of a repository is its `@UseStore`; else the SQL store with
/// a `@UseDataSource`; else `spring.data.store` of the configuration the
/// build reads (`application.yml` or `application.properties` without a
/// profile); else the first described store whose `defaultWhen` holds;
/// else unknown. A store that is not described is unknown too: the check
/// of the run time (`RepositoryFactory`) is then the only one.
final class DataStoreBuild {
  /// The stores [stores] with the default store [defaultStore] (a name,
  /// described or not; null when the build cannot tell) and the words of
  /// each capability ([texts]).
  const DataStoreBuild(this.stores, this.defaultStore, this.texts);

  /// A build that knows no store: nothing is checked.
  static const none = DataStoreBuild([], null, {});

  /// The described stores, by package and constant.
  final List<DescribedStore> stores;

  /// The name of the store of a repository without `@UseStore`; null when
  /// the build cannot tell.
  final String? defaultStore;

  /// What an error says of each capability: what uses it, what that
  /// needs, and the general fix, as the starter's `DataStoreCapability`
  /// has them (read from the enum, so the build and the run time say the
  /// same).
  final Map<StoreCapability, ({String usedBy, String need, String fix})> texts;

  /// Reads the declarations of the packages the application depends on
  /// (what [reachablePackages] gives; null for every package of the
  /// package config) and of the package itself, and decides the default
  /// store by the [configuration] (the texts of `lib/resources/`, by
  /// path).
  ///
  /// [none] without the Data starter among the packages.
  static Future<DataStoreBuild> read(
    BuildStep buildStep, {
    required Future<Set<String>?> Function() reachablePackages,
    Map<String, String> configuration = const {},
  }) async {
    final config = await buildStep.packageConfig;
    if (!config.packages.any((package) => package.name == _dataStarter)) {
      return none;
    }
    final root = buildStep.inputId.package;
    final reachable = await reachablePackages();
    // In a pub workspace the config lists every member: the starter is
    // there without being a dependency.
    if (root != _dataStarter &&
        reachable != null &&
        !reachable.contains(_dataStarter)) {
      return none;
    }
    final found = <String, (DartObject, String)>{};
    for (final package in config.packages) {
      if (package.name != root &&
          reachable != null &&
          !reachable.contains(package.name)) {
        continue;
      }
      final id = AssetId(package.name, _autoConfigurationLibrary);
      if (!await buildStep.canRead(id) ||
          !await buildStep.resolver.isLibrary(id)) {
        continue;
      }
      final library = await buildStep.resolver.libraryFor(id);
      // What the library declares and what it exports: a declaration is
      // counted once, where it is written.
      for (final element in library.exportNamespace.definedNames2.values) {
        final variable = switch (element) {
          final TopLevelVariableElement variable => variable,
          GetterElement(:final TopLevelVariableElement variable) => variable,
          _ => null,
        };
        if (variable == null || !_declaration.hasAnnotationOf(variable)) {
          continue;
        }
        final value = variable.computeConstantValue();
        final type = value?.type;
        if (value == null || type == null || !_descriptor.isExactlyType(type)) {
          throw InvalidGenerationSourceError(
            '@DataStoreDeclaration is for a constant DataStoreDescriptor: '
            '${variable.name} of ${variable.library.uri} is none.',
            element: variable,
          );
        }
        found.putIfAbsent(
          '${variable.library.uri}#${variable.name}',
          () => (
            value,
            '${variable.library.uri.pathSegments.first}.${variable.name}',
          ),
        );
      }
    }
    if (found.isEmpty) {
      return none;
    }
    final declared = found.values.toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final stores = [
      for (final (value, source) in declared) _store(value, source),
    ];
    return DataStoreBuild(
      stores,
      _defaultStore(stores, _Configuration.read(configuration)),
      _texts(declared.first.$1),
    );
  }

  static DescribedStore _store(DartObject value, String source) {
    final reader = ConstantReader(value);
    final capabilities = reader.read('capabilities');
    final when = reader.read('defaultWhen');
    List<String> names(ConstantReader list) => [
      for (final item in list.listValue) item.toStringValue() ?? '',
    ];
    return DescribedStore(
      reader.read('name').stringValue,
      capabilities: {
        for (final capability in StoreCapability.values)
          if (capabilities.read(capability.name).boolValue) capability,
      },
      whenProperty: when.isNull ? null : names(when.read('whenProperty')),
      unlessProperty: when.isNull
          ? const []
          : names(when.read('unlessProperty')),
      fixes: {
        for (final MapEntry(:key, value: fix)
            in reader.read('fixes').mapValue.entries)
          ?_capabilityOf(key): ?fix?.toStringValue(),
      },
      source: source,
      collectionsNeedJson:
          reader.peek('collectionsNeedJson')?.boolValue ?? false,
    );
  }

  static StoreCapability? _capabilityOf(DartObject? constant) {
    final name = constant?.variable?.name;
    return StoreCapability.values.where((c) => c.name == name).firstOrNull;
  }

  // `usedBy`, `need` and `fix` of each constant of `DataStoreCapability`,
  // the enum declared beside the `DataStoreCapabilities` a descriptor
  // holds.
  static Map<StoreCapability, ({String usedBy, String need, String fix})>
  _texts(DartObject descriptor) {
    final capabilities = descriptor.getField('capabilities')?.type;
    final declared = capabilities is InterfaceType
        ? capabilities.element.library.getEnum('DataStoreCapability')
        : null;
    final result =
        <StoreCapability, ({String usedBy, String need, String fix})>{};
    for (final field in declared?.fields ?? const <FieldElement>[]) {
      final capability = StoreCapability.values
          .where((c) => field.isEnumConstant && c.name == field.name)
          .firstOrNull;
      final value = field.isEnumConstant ? field.computeConstantValue() : null;
      if (capability == null || value == null) {
        continue;
      }
      String text(String name) => value.getField(name)?.toStringValue() ?? '';
      result[capability] = (
        usedBy: text('usedBy'),
        need: text('need'),
        fix: text('fix'),
      );
    }
    return result;
  }

  // `spring.data.store` when the build can read it; else the first store
  // whose rule holds.
  static String? _defaultStore(
    List<DescribedStore> stores,
    _Configuration configuration,
  ) {
    const key = 'spring.data.store';
    if (configuration.isSet(key)) {
      return configuration.valueOf(key);
    }
    for (final store in stores) {
      final when = store.whenProperty;
      if (when != null &&
          when.every(configuration.isSet) &&
          !store.unlessProperty.any(configuration.isSet)) {
        return store.name;
      }
    }
    return null;
  }

  /// The described store called [name], or null (no name, or a store the
  /// build does not know).
  DescribedStore? described(String? name) =>
      stores.where((store) => store.name == name).firstOrNull;

  /// The described store of a repository with `@UseStore(useStore)` (null
  /// without one) and, when [usesDataSource], a `@UseDataSource`; null
  /// when the build cannot tell or does not know the store.
  DescribedStore? storeOf({String? useStore, bool usesDataSource = false}) =>
      described(useStore ?? (usesDataSource ? 'jdbc' : defaultStore));

  /// The problem of the repository [typeName] whose store is [store] and
  /// lacks what [need] asks, in the words of the run time's
  /// `StoreRequirement.problemWith` with the store's own fix first; null
  /// when the store has it.
  String? problem(String typeName, StoreNeed need, DescribedStore store) {
    if (store.capabilities.contains(need.capability)) {
      return null;
    }
    final text = texts[need.capability];
    final where = need.method == null ? typeName : '$typeName.${need.method}';
    return '$where: ${text?.usedBy ?? need.capability.name} needs '
        '${text?.need ?? 'a store with ${need.capability.name}'}, and the '
        '${store.name} store is none: ${_fix(store, need.capability)}';
  }

  /// The problem of the property [where] (`Entity.property`) declared as
  /// the collection [type] with no `@Json`, on a store that has no column
  /// for it: the words of the starter's `CollectionColumns.problem`, which
  /// the SQL store says when the repository is created.
  static String collectionProblem(String where, String type) =>
      '$where: a $type property without @Json has no column on a SQL '
      'store: add @Json() to keep it as JSON, or @MappedCollection for '
      'rows of a child table';

  String _fix(DescribedStore store, StoreCapability capability) => [
    ?store.fixes[capability],
    if (texts[capability]?.fix case final fix? when fix.isNotEmpty) fix,
  ].join(', or ');

  /// Why the `@Transactional` of [element] (a bean's class, with its
  /// methods) cannot work: the application's default store is known, is
  /// described and has no transactions, and the annotation names no
  /// transaction manager. Null when there is no such annotation, or
  /// nothing is wrong, or the build cannot tell.
  String? transactionalProblem(InterfaceElement element) {
    final store = described(defaultStore);
    if (store == null ||
        store.capabilities.contains(StoreCapability.transactions)) {
      return null;
    }
    final where = [
      if (_unmanaged(element)) '${element.name}',
      for (final method in element.methods)
        if (!method.isStatic && _unmanaged(method))
          '${element.name}.${method.name}',
    ];
    if (where.isEmpty) {
      return null;
    }
    const select =
        'select a store with transactions (spring.data.store, or the '
        'property of its starter)';
    const manager =
        'name the transaction manager of another store '
        "(@Transactional(transactionManager: 'x'))";
    const function = 'do the atomic work in one database function (@Procedure)';
    final fixes = [
      ?store.fixes[StoreCapability.transactions],
      select,
      manager,
      function,
    ];
    return '${where.join(', ')}: @Transactional needs a store with '
        'transactions, and the default store of the application, '
        '${store.name}, has none: ${fixes.join(', or ')}';
  }

  // Whether [element] has a `@Transactional` that names no manager.
  static bool _unmanaged(Element element) {
    for (final annotation in _transactional.annotationsOf(element)) {
      final manager = annotation.getField('transactionManager');
      if (manager == null ||
          manager.isNull ||
          (manager.toStringValue() ?? '').isEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Whether [element] (a repository interface or one of its methods) has
  /// a `@Transactional`.
  static bool isTransactional(Element element) =>
      _transactional.hasAnnotationOf(element);
}

// The properties of the configuration the build reads: the files
// `application.properties`, `application.yml` and `application.yaml` at
// the root of `lib/resources/`, without a profile, as they are written (a
// `${PLACEHOLDER}` is a value: the key is set).
final class _Configuration {
  _Configuration(this._values);

  factory _Configuration.read(Map<String, String> texts) {
    const loaders = <PropertySourceLoader>[
      PropertiesPropertySourceLoader(),
      YamlPropertySourceLoader(),
    ];
    final values = <String, String>{};
    for (final path in texts.keys.toList()..sort()) {
      final match = RegExp(
        r'^application\.(properties|ya?ml)$',
      ).firstMatch(path);
      if (match == null) {
        continue;
      }
      final loader = loaders.firstWhere(
        (loader) => loader.fileExtensions.contains(match.group(1)),
      );
      try {
        for (final source in loader.load(path, texts[path]!)) {
          if (source is! EnumerablePropertySource<Object> ||
              source.containsProperty('spring.config.activate.on-profile')) {
            continue;
          }
          for (final name in source.propertyNames) {
            if (source.getProperty(name) case final value?) {
              values.putIfAbsent(name, () => '$value'.trim());
            }
          }
        }
      } on FormatException {
        // The reading of the configuration itself reports it.
      }
    }
    return _Configuration(values);
  }

  final Map<String, String> _values;

  // Whether the configuration gives [key] a value.
  bool isSet(String key) => _values[key]?.isNotEmpty ?? false;

  // The value of [key] when the build can read it: not a placeholder.
  String? valueOf(String key) {
    final value = _values[key];
    return value == null || value.isEmpty || value.contains(r'${')
        ? null
        : value;
  }
}
