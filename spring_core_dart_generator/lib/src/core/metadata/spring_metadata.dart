import 'dart:convert';

/// The version of the `spring_metadata.json` format
/// (see `roadmap/spring_metadata.md`).
const springMetadataVersion = 1;

/// Puts the parts of a package's `spring_metadata.json` together: the
/// scanned properties, hints, beans and profiles, and the entries of the
/// packages' parts (the entities and repositories, the loader kinds, the
/// routes, the theme). Everything comes from the code. The result is
/// sorted and has a fixed key order, so the file only changes when the code
/// does (CI diffs it).
///
/// Spring Boot's annotation processor writes
/// `spring-configuration-metadata.json` from the code the same way.
abstract final class SpringMetadata {
  static const _propertyKeys = [
    'name',
    'type',
    'description',
    'default',
    'deprecated',
    'source',
    'line',
    'class',
  ];

  static const _hintKeys = ['name', 'values', 'provider', 'range', 'warn'];

  static const _beanKeys = [
    'name',
    'type',
    'types',
    'scope',
    'primary',
    'qualifiers',
    'profiles',
    'conditions',
    'source',
    'line',
    'injects',
    'members',
  ];

  /// The metadata of [package] as a JSON-ready map.
  ///
  /// [starters] are the entries of the packages' parts
  /// (`PackageGeneration.metadata`), written after the core's in their
  /// order, each already sorted by its part.
  static Map<String, Object?> assemble({
    required String package,
    required List<Map<String, Object?>> properties,
    required List<Map<String, Object?>> hints,
    required List<Map<String, Object?>> beans,
    required Iterable<String> profiles,
    Map<String, Object?> starters = const {},
  }) {
    // The first entry of a name wins (a class beats a read key).
    final sortedProperties = byName(_firstByName(properties), 'name');
    final sortedHints = byName(
      [for (final hint in _firstByName(hints)) _normalizeHint(hint)],
      'name',
    );
    return {
      'version': springMetadataVersion,
      'package': package,
      'properties': [
        for (final property in sortedProperties)
          ordered(property, _propertyKeys, nullable: true),
      ],
      'hints': [
        for (final hint in sortedHints)
          ordered(hint, _hintKeys, nullable: false),
      ],
      'beans': [
        for (final bean in _sortBeans(beans))
          ordered(bean, _beanKeys, nullable: true),
      ],
      'profiles': profiles.toSet().toList()..sort(),
      ...starters,
    };
  }

  /// The pretty-printed JSON of [metadata], with a final newline.
  static String encode(Map<String, Object?> metadata) =>
      '${const JsonEncoder.withIndent('  ').convert(metadata)}\n';

  static List<Map<String, Object?>> _firstByName(
    List<Map<String, Object?>> entries,
  ) {
    final byName = <String, Map<String, Object?>>{};
    for (final entry in entries) {
      byName.putIfAbsent('${entry['name']}', () => entry);
    }
    return byName.values.toList();
  }

  /// [entries] sorted by their value of [key], for a list whose order
  /// must not depend on the scan's.
  static List<Map<String, Object?>> byName(
    List<Map<String, Object?>> entries,
    String key,
  ) => entries.toList()..sort((a, b) => '${a[key]}'.compareTo('${b[key]}'));

  // Beans keep their name order, then source and line (two profiles may
  // declare the same name).
  static List<Map<String, Object?>> _sortBeans(
    List<Map<String, Object?>> beans,
  ) => beans.toList()
    ..sort((a, b) {
      final byName = '${a['name']}'.compareTo('${b['name']}');
      if (byName != 0) {
        return byName;
      }
      final bySource = '${a['source']}'.compareTo('${b['source']}');
      return bySource != 0
          ? bySource
          : ((a['line'] as int?) ?? 0).compareTo((b['line'] as int?) ?? 0);
    });

  // A value written as a bare string is `{value: ...}`.
  static Map<String, Object?> _normalizeHint(Map<String, Object?> hint) {
    final values = hint['values'];
    if (values is! List) {
      return hint;
    }
    return {
      ...hint,
      'values': [
        for (final value in values)
          if (value is Map)
            {
              'value': value['value'],
              'description': value['description'],
            }
          else
            {'value': value, 'description': null},
      ],
    };
  }

  /// [entry] with the known [keys] first, in their order, then the others
  /// sorted; a `null` stays when [nullable] (the format lists `default`,
  /// `deprecated`... as `null`), else it is left out.
  static Map<String, Object?> ordered(
    Map<String, Object?> entry,
    List<String> keys, {
    required bool nullable,
  }) => {
    for (final key in keys)
      if (entry.containsKey(key) || nullable) key: entry[key],
    for (final key in entry.keys.toList()..sort())
      if (!keys.contains(key)) key: entry[key],
  };
}
