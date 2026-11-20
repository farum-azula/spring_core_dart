import 'package:dart_spring_language_server/src/config/config_document.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/theme_keys.dart';
import 'package:dart_spring_language_server/src/config/theme_references.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// A key of the checked document with what the schema says of it.
final class ResolvedKey {
  /// [key], resolved to [resolution].
  ResolvedKey(this.key, this.resolution) : isTheme = isThemeKey(key.segments);

  /// The key.
  final ConfigKey key;

  /// Where the schema puts it.
  final Resolution resolution;

  /// Whether it is a theme key.
  final bool isTheme;

  /// Whether its value is a plain scalar that can be checked.
  bool get hasPlainValue => key.value != null && !key.complex;
}

/// One pass of the checks over a config document: what they share.
final class ConfigCheckPass {
  /// A pass over [document] with what [model] knows.
  ConfigCheckPass(this.model, this.document)
    : schema = model.schemas.schemaFor(document.path),
      complete = model.metadataFor(document.path).complete;

  /// What the workspace knows.
  final ProjectModel model;

  /// The document checked.
  final ConfigDocument document;

  /// The known keys of the document's package.
  final Schema schema;

  /// Whether the metadata of every package of the closure is there: a
  /// dependency without metadata may define any key, so then only the
  /// theme, which the editor knows by itself, is checked for unknown keys.
  final bool complete;

  /// The key prefixes reported unknown: the keys below them are not
  /// checked again.
  final reported = <List<String>>[];

  /// The keys checked one by one (those below a reported prefix left
  /// out), in the order of the document.
  final checked = <ResolvedKey>[];

  /// The declarations of the themes the document sees, for `$` references.
  late final references = ThemeReferences(model.properties, document.path);

  /// The path of the document.
  String get path => document.path;
}

/// A check of each key of a config document (not those below a key
/// already reported unknown).
abstract interface class ConfigKeyCheck {
  /// Adds the problems of [key] to [problems].
  void check(ConfigCheckPass pass, ResolvedKey key, List<Problem> problems);
}

/// A check of a whole config document, after the checks of its keys.
abstract interface class ConfigDocumentCheck {
  /// Adds the problems of the document of [pass] to [problems].
  void check(ConfigCheckPass pass, List<Problem> problems);
}
