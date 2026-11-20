import 'package:dart_spring_language_server/src/index/property_index.dart';
import 'package:dart_spring_language_server/src/index/schema_index.dart';

final _environmentVariable = RegExp(r'^[A-Z][A-Z0-9_]*$');

/// Whether a placeholder's key resolves where it is read: the one rule
/// the checks and the highlighting of Dart and config files share.
final class KeyResolution {
  /// The rule over [properties] and the metadata of [schemas].
  KeyResolution(this.properties, this.schemas);

  /// The properties of the config files and tests.
  final PropertyIndex properties;

  /// The known keys of the metadata.
  final SchemaIndex schemas;

  /// Whether something defines the property [key] for a value read in
  /// [from]: an environment variable (by its look), the Spring metadata of
  /// the package, a property the test sets, or a config file of the
  /// package.
  bool resolves(String from, String key) =>
      _environmentVariable.hasMatch(key) ||
      schemas.declaredByMetadata(from, key) ||
      properties.property(key, from: from).isNotEmpty;
}
