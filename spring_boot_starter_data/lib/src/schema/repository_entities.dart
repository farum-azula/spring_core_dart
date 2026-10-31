import 'dart:collection';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';

/// The entities (the aggregate roots) the repositories of one SQL data
/// source use: the tables the schema creation and the schema validation
/// work on.
///
/// It reads the bean definitions, not the repositories, so it is right
/// before any repository exists, and also for lazy ones:
///
/// - a repository is a bean whose types include `DataRepository<Book, int>`;
///   `Book` is its entity;
/// - it belongs to the data source `@UseDataSource('name')` names, else to
///   the primary one;
/// - a repository that asks for another store (`@UseStore('memory')`, or
///   any name but `jdbc`) is left out, and one with no `@UseStore` is on
///   the SQL data source only when [defaultStoreIsJdbc] is true (the
///   default store is `jdbc` once a primary data source exists).
///
/// Entities that no repository uses are not touched: an aggregate reached
/// only through a `JdbcTemplate` is the application's own table (its
/// migrations create it); the children of an aggregate come with their
/// root. An entity that cannot be mapped is left out here, and the
/// repository that uses it reports it, with the reasons, when it is
/// created.
///
/// Spring (Java): none; Hibernate scans the `@Entity` classes of the
/// persistence unit instead.
final class RepositoryEntities extends IterableBase<PersistentEntity<Object>> {
  /// The entities of the repositories among [beans] that use the data
  /// source [dataSource] (null: the primary one), mapped by
  /// [mappingContext].
  RepositoryEntities({
    required this.beans,
    required this.mappingContext,
    this.dataSource,
    this.defaultStoreIsJdbc = true,
  });

  /// Where the repositories' bean definitions are.
  final ConfigurableListableBeanFactory beans;

  /// Maps the classes.
  final RelationalMappingContext mappingContext;

  /// The data source name; null for the primary one.
  final String? dataSource;

  /// Whether a repository without `@UseStore` is on the SQL data source.
  final bool defaultStoreIsJdbc;

  List<PersistentEntity<Object>>? _found;

  /// The names of the entity classes the repositories name, sorted; they
  /// are what [iterator] maps.
  List<String> get entityNames {
    final names = <String>{};
    for (final name in beans.beanDefinitionNames) {
      final definition = beans.getBeanDefinition(name);
      final entity = _entityNameOf(definition);
      if (entity == null || !_isOnThisDataSource(definition)) {
        continue;
      }
      names.add(entity);
    }
    return names.toList()..sort();
  }

  bool _isOnThisDataSource(BeanDefinition<Object> definition) {
    final store = definition.annotations
        .whereType<UseStore>()
        .firstOrNull
        ?.value;
    final named = definition.annotations
        .whereType<UseDataSource>()
        .firstOrNull
        ?.value;
    if (named != dataSource) {
      return false;
    }
    return store == null
        ? defaultStoreIsJdbc || named != null
        : store == 'jdbc';
  }

  // `Book` for a bean of `DataRepository<Book, int>`; null for a bean that
  // is no repository.
  static String? _entityNameOf(BeanDefinition<Object> definition) {
    for (final type in definition.types) {
      final text = '$type';
      if (!text.startsWith('DataRepository<')) {
        continue;
      }
      final inner = text.substring('DataRepository<'.length, text.length - 1);
      final entity = _firstArgument(inner);
      if (entity != 'dynamic') {
        return entity;
      }
    }
    return null;
  }

  // The first top-level type argument of `Book, int` or `Page<X>, int`.
  static String _firstArgument(String arguments) {
    var depth = 0;
    for (var i = 0; i < arguments.length; i++) {
      switch (arguments[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
        case ',' when depth == 0:
          return arguments.substring(0, i).trim();
      }
    }
    return arguments.trim();
  }

  List<PersistentEntity<Object>> _resolve() {
    final wanted = entityNames.toSet();
    final byName = <String, List<BeanIntrospection<Object>>>{};
    for (final introspection in mappingContext.introspector.introspections) {
      if (!introspection.annotations.any((a) => a is Table)) {
        continue;
      }
      byName
          .putIfAbsent('${introspection.beanType}', () => [])
          .add(
            introspection,
          );
    }
    final entities = <PersistentEntity<Object>>[];
    for (final name in wanted) {
      final candidates = byName[name];
      // Two classes of one name cannot be told apart from the text of a
      // type: the repository reports a mapping problem itself.
      if (candidates == null || candidates.length != 1) {
        continue;
      }
      try {
        final entity = mappingContext.getPersistentEntity(
          candidates.single.beanType,
        );
        if (entity != null) {
          entities.add(entity);
        }
      } on MappingException {
        // Reported by the repository when it is created.
      }
    }
    return entities;
  }

  @override
  Iterator<PersistentEntity<Object>> get iterator =>
      (_found ??= _resolve()).iterator;
}
