import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Removes the excluded auto-configurations and puts the rest in Spring
/// Boot's `AutoConfigurationSorter` order: alphabetically by module name,
/// then by `AutoConfigurationModule.order`, then by the `before` / `after`
/// constraints (a cycle is an error).
///
/// A name in [excludeTypes] / [excludeNames] / `before` / `after` matches a
/// module by its `BeanModule.name` or an `@AutoConfiguration` class by its
/// name (matched through the `source` of the bean definitions the class
/// produced, `package:x/src/y.dart#CacheAutoConfiguration`, or just
/// `CacheAutoConfiguration`). Excluding a class removes its definitions,
/// its `@Import`s (registrars and selectors) and its conditional
/// `@PropertySource`s only; excluding a module removes all of it.
///
/// An excluded [Type] that no auto-configuration matches is an error (like
/// Boot's "could not be excluded because it is not an auto-configuration
/// class"); an unknown name is ignored, like a class missing on the
/// classpath.
List<BeanModule> selectAutoConfigurations(
  List<BeanModule> modules, {
  Map<BeanModule, AutoConfigurationModule> metadata = const {},
  Iterable<Type> excludeTypes = const [],
  Iterable<String> excludeNames = const [],
}) {
  final typeNames = {for (final type in excludeTypes) '$type'};
  final names = {
    ...typeNames,
    for (final name in excludeNames)
      if (name.trim().isNotEmpty) name.trim(),
  };
  final matched = <String>{};
  final entries = <_Entry>[];
  for (final module in modules) {
    if (names.contains(module.name)) {
      matched.add(module.name);
      continue;
    }
    // Whether [source] belongs to an excluded class (recorded as matched).
    bool excluded(String? source) {
      final owner = _owner(source);
      final hit = owner == null
          ? const <String>{}
          : {owner.$1, owner.$2}.intersection(names);
      matched.addAll(hit);
      return hit.isNotEmpty;
    }

    final kept = [
      for (final definition in module.definitions)
        if (!excluded(definition.source)) definition,
    ];
    // The imports of the classes left (an import belongs to its importer,
    // else to the class of its condition group).
    final keptImports = [
      for (final declaration in module.registrars)
        if (!excluded(
          declaration.importer ??
              declaration.conditions
                  .whereType<ConditionGroup>()
                  .firstOrNull
                  ?.key,
        ))
          declaration,
    ];
    final keptSources = [
      for (final declaration in module.propertySources)
        if (!excluded(
          declaration.conditions.whereType<ConditionGroup>().firstOrNull?.key,
        ))
          declaration,
    ];
    final info = metadata[module];
    entries.add(
      _Entry(
        kept.length == module.definitions.length &&
                keptImports.length == module.registrars.length &&
                keptSources.length == module.propertySources.length
            ? module
            : _withDefinitions(module, kept, keptImports, keptSources),
        info?.order ?? 0,
        info?.before ?? const [],
        info?.after ?? const [],
        {
          for (final definition in module.definitions)
            ?_owner(definition.source)?.$1,
        },
      ),
    );
  }
  final missing = typeNames.difference(matched);
  if (missing.isNotEmpty) {
    throw StateError(
      'The following classes could not be excluded because they are not '
      'auto-configuration classes:\n'
      '${[for (final name in missing) '\t- $name'].join('\n')}',
    );
  }
  return _sort(entries);
}

// `(Class, package:x/src/y.dart#Class)` of a definition source such as
// `package:x/src/y.dart#Class` or `package:x/src/y.dart#Class.method`.
(String, String)? _owner(String? source) {
  final hash = source?.indexOf('#') ?? -1;
  if (source == null || hash < 0) {
    return null;
  }
  final rest = source.substring(hash + 1);
  final dot = rest.indexOf('.');
  final name = dot < 0 ? rest : rest.substring(0, dot);
  return (name, '${source.substring(0, hash + 1)}$name');
}

BeanModule _withDefinitions(
  BeanModule module,
  List<BeanDefinition<Object>> definitions,
  List<ImportDeclaration> registrars,
  List<PropertySourceDeclaration> propertySources,
) => BeanModule(
  module.name,
  definitions,
  propertySources: propertySources,
  imports: module.imports,
  registrars: registrars,
  configurers: module.configurers,
  configurablePostConstruct: module.configurablePostConstruct,
  configurablePreDestroy: module.configurablePreDestroy,
  introspections: module.introspections,
  resources: module.resources,
);

final class _Entry {
  _Entry(this.module, this.order, this.before, this.after, this.classes);

  final BeanModule module;
  final int order;
  final List<String> before;
  final List<String> after;
  final Set<String> classes;

  String get name => module.name;

  bool matches(String other) => other == name || classes.contains(other);
}

// Boot's AutoConfigurationSorter: names, then order, then constraints.
List<BeanModule> _sort(List<_Entry> entries) {
  // Alphabetical, then (stable) by order; the list position breaks ties.
  final indexed = [...entries]
    ..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) {
        return byOrder;
      }
      final byName = a.name.compareTo(b.name);
      return byName != 0
          ? byName
          : entries.indexOf(a).compareTo(entries.indexOf(b));
    });

  final toSort = [...indexed];
  final sorted = <_Entry>{};
  final processing = <_Entry>{};

  // [entry]'s own `after` plus the entries that want to come before it.
  Iterable<_Entry> requestedAfter(_Entry entry) => [
    for (final other in indexed)
      if (!identical(other, entry) &&
          (entry.after.any(other.matches) || other.before.any(entry.matches)))
        other,
  ];

  void visit(_Entry current) {
    toSort.remove(current);
    processing.add(current);
    for (final after in requestedAfter(current)) {
      if (processing.contains(after)) {
        throw StateError(
          'AutoConfigure cycle detected between ${current.name} and '
          '${after.name}',
        );
      }
      if (!sorted.contains(after) && toSort.contains(after)) {
        visit(after);
      }
    }
    processing.remove(current);
    sorted.add(current);
  }

  while (toSort.isNotEmpty) {
    visit(toSort.first);
  }
  return [for (final entry in sorted) entry.module];
}
