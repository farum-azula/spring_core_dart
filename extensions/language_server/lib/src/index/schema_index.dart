import 'package:dart_spring_language_server/src/index/code_key_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/property_index.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// The known keys of each package ([Schema]): the properties, hints and
/// theme of its metadata and its dependencies', plus the keys its code
/// reads. Built again when the metadata or the keys the code reads
/// changed.
final class SchemaIndex {
  /// The schemas of the packages of [packages], from [metadata] and
  /// [codeKeys]; [properties] adds the keys in use to [knownKeys].
  SchemaIndex(this.metadata, this.packages, this.codeKeys, this.properties);

  /// The metadata of the packages.
  final MetadataStore metadata;

  /// The packages of the workspace.
  final PackageLayout packages;

  /// The keys the code of each package reads.
  final CodeKeyIndex codeKeys;

  /// The properties of the config files.
  final PropertyIndex properties;

  final _schemas = <String, (int, int, Schema)>{};

  /// The known keys for the package of [path]: the properties, hints and
  /// theme of the metadata, plus keys some code of the package reads.
  Schema schemaFor(String path) {
    final root = packages.packageRootOf(path);
    final view = metadata.viewFor(root);
    final keys = codeKeys.keysOf(root);
    final cached = _schemas[root];
    if (cached != null &&
        cached.$1 == view.version &&
        cached.$2 == codeKeys.generation) {
      return cached.$3;
    }
    final schema = Schema.build(view, codeKeys: keys);
    _schemas[root] = (view.version, codeKeys.generation, schema);
    return schema;
  }

  /// Whether the metadata of [path]'s package declares the property [key]
  /// (so it is no typo, and it has a value from the class's initial
  /// value).
  bool declaredByMetadata(String path, String key) {
    final prop = schemaFor(path).nodeAt(splitKey(key))?.prop;
    return prop != null && !prop.fromCode;
  }

  /// Every key a config file of [path]'s package may set, for `${}`
  /// completion: the properties of the metadata and the keys in use.
  List<String> knownKeys(String path) {
    final keys = <String>{};
    void walk(SchemaNode node, List<String> prefix) {
      for (final child in node.named) {
        final next = [...prefix, child.name];
        if (child.prop != null && !child.prop!.theme) {
          keys.add(next.join('.'));
        }
        walk(child, next);
      }
    }

    walk(schemaFor(path).root, const []);
    for (final entry in properties.configEntries(path)) {
      if (!entry.key.startsWith('spring.flutter.theme')) {
        keys.add(entry.key);
      }
    }
    return keys.toList()..sort();
  }
}
