import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';

/// Finds the places of a Dart file that read a property, whose values are
/// shown inline: the placeholders the string roles find, and the fields
/// of its `@ConfigurationProperties` classes.
final class PropertyReferenceFinder {
  /// A finder over [model].
  const PropertyReferenceFinder(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The references of the Dart file [path]; empty for other files.
  List<PropertyReference> referencesIn(String path) {
    final file = model.files.dartFile(path);
    return file == null ? const [] : referencesOf(file);
  }

  /// The references of [file]. What is read from it is kept for the
  /// parse unless [keep] is false (a search over every file of a package).
  List<PropertyReference> referencesOf(DartFile file, {bool keep = true}) => [
    ...model.roles.references(DartFileFacts.read(file, keep: keep).strings),
    ...configurationPropertiesFields(file.unit),
  ];
}
