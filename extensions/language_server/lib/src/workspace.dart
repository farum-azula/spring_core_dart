import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/metadata_notes.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/documents/document_kind.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/key_rename.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/properties/property_occurrences.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/properties/property_values.dart';
import 'package:dart_spring_language_server/src/properties/reference_finder.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

export 'package:dart_spring_language_server/src/completion.dart'
    show Completion, CompletionResult;
export 'package:dart_spring_language_server/src/diagnostics/problem.dart'
    show Problem;
export 'package:dart_spring_language_server/src/symbols/source_range.dart'
    show SourceRange;
export 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart'
    show
        SemanticToken,
        TokenModifier,
        TokenType,
        semanticTokenModifiers,
        semanticTokenTypes;

/// What the language server knows about the open project, as the features
/// ask it: the answers to the editor's questions ([definition], [hover],
/// [completion], [semanticTokens], [problems]) and the open documents'
/// text ([setOverlay]).
///
/// A facade: the work is done by the parts of a [ProjectModel] (the files
/// and indexes, the string roles, the checks, the editors of config files,
/// SpEL and queries), and each kind of document ([documentKinds]) answers
/// for its files.
///
/// ```dart
/// final workspace = SpringWorkspace(['/home/ada/shop'])
///   ..refresh(force: true);
/// // A click at offset 120 of the checkout: where are its beans?
/// final targets = workspace.definition(
///   '/home/ada/shop/lib/checkout.dart',
///   120,
/// );
/// ```
final class SpringWorkspace {
  /// A workspace over the directories [roots]. Nothing is read until
  /// [refresh] or a query.
  SpringWorkspace(List<String> roots) : this._(ProjectModel(roots));

  SpringWorkspace._(this._model)
    : _documents = documentKinds(_model),
      _notes = MetadataNotes(_model),
      _references = PropertyReferenceFinder(_model),
      _occurrences = PropertyOccurrences(_model);

  final ProjectModel _model;
  final List<DocumentKind> _documents;
  final MetadataNotes _notes;
  final PropertyReferenceFinder _references;
  final PropertyOccurrences _occurrences;

  /// The workspace folders the editor opened, scanned recursively.
  List<String> get roots => _model.roots;

  /// Whether [path] is a config file of the application, whose keys are
  /// indexed and whose values are highlighted: any `.properties` file, and
  /// YAML named `application*` or under a `resources/` directory.
  static bool isConfigFile(String path) => ConfigFormat.isConfigFile(path);

  /// Sets the unsaved [text] of the document open at [path]; with `null`
  /// (the document was closed), the file on disk counts again.
  void setOverlay(String path, String? text) =>
      _model.files.setOverlay(path, text);

  /// Scans the workspace folders again, at most once per [interval] (by
  /// default [scanInterval]) unless [force] is set.
  void refresh({bool force = false, Duration? interval}) =>
      _model.refresh(force: force, interval: interval ?? scanInterval);

  /// How often a query scans the folders for files changed on disk: every
  /// 2 seconds, unless the editor reports the changes itself
  /// ([SpringWorkspace.editorReportsChanges]).
  Duration scanInterval = const Duration(seconds: 2);

  /// The editor tells of every change of a file on disk (it watches the
  /// files for the server, which then scans only on its reports, and once
  /// a minute in case one was missed).
  void editorReportsChanges() => scanInterval = const Duration(minutes: 1);

  /// The parsed Dart file at [path]: the open document's text if there is
  /// one, else the file on disk. `null` when [path] is not a Dart file or
  /// does not exist.
  DartFile? file(String path) => _model.files.dartFile(path);

  /// The text of the file at [path]: the open document's, else the file on
  /// disk; `null` when it cannot be read.
  String? textOf(String path) => _model.files.textOf(path);

  /// Every bean of the workspace and of the metadata.
  List<BeanInfo> get beans => _model.beans.beans;

  /// The beans that answer to [name], by bean name, by
  /// `@Bean(aliases: ...)` or by `@Qualifier`.
  List<BeanInfo> beansNamed(String name) => _model.beans.beansNamed(name);

  /// The definitions of the property [key] for a value read in [from]
  /// (the config files of its package, and a test's own properties); of
  /// every config file without [from].
  List<PropertyEntry> property(String key, {String? from}) =>
      _model.properties.property(key, from: from);

  /// The entries of [key] a value read in [path] can come from.
  List<PropertyEntry> propertyEntriesIn(String path, String key) =>
      _model.properties.propertyEntriesIn(path, key);

  /// The profiles values are read under in [path].
  ActiveProfiles activeProfilesOf(String path, List<String> configured) =>
      _model.properties.activeProfilesOf(path, configured);

  /// The places of the Dart file [path] that read a property.
  List<PropertyReference> propertyReferences(String path) =>
      _references.referencesIn(path);

  /// The property key named at [line] and [column] of [path], with the
  /// range of the text that names it; `null` where none is.
  ({String key, SourceRange range})? keyAt(
    String path,
    int line,
    int column,
  ) => _occurrences.keyAt(path, line, column);

  /// The places of [path]'s package that name the property [key].
  List<KeyOccurrence> keyOccurrences(String path, String key) =>
      _occurrences.of(path, key);

  /// What renaming the property [key], named in [path], to [newKey]
  /// changes, or why it cannot.
  KeyRenamePlan renameKey(String path, String key, String newKey) =>
      KeyRename(_occurrences).plan(path, key, newKey);

  /// The definitions of the message [code] in the message bundles; with
  /// [from], only those of that file's package.
  List<PropertyEntry> messages(String code, {String? from}) =>
      _model.messages.messages(code, from: from);

  /// The targets of go to definition at [offset] (in UTF-16 units) of the
  /// file [path].
  List<SourceRange> definition(String path, int offset) =>
      _documentOf(path)?.definition(path, offset) ?? const [];

  /// Markdown for a hover at [offset] of the file [path]; `null` when
  /// there is nothing Spring-specific there.
  String? hover(String path, int offset) =>
      _documentOf(path)?.hover(path, offset);

  /// Completion proposals at [offset] of the file [path]; `null` when there
  /// is nothing to propose.
  CompletionResult? completion(String path, int offset) =>
      _documentOf(path)?.completion(path, offset);

  /// The semantic tokens of [path], sorted by position; empty for a file
  /// that is neither Dart nor config.
  List<SemanticToken> semanticTokens(String path) =>
      _documentOf(path)?.tokens(path) ?? const [];

  /// The problems of [path], for the editor to underline.
  List<Problem> problems(String path) =>
      _documentOf(path)?.problems(path) ?? const [];

  /// Notes about Spring metadata that is missing for the package of
  /// [path].
  List<Problem> metadataNotes(String path) => _notes.of(path);

  /// How many times what is built from the declarations of the workspace
  /// was built: the generation of the declarations, the builds of the
  /// beans, the generation of the keys the code reads. Tests read it to
  /// see that typing inside a method body builds none of them again.
  ({int declarations, int beans, int codeKeys}) get indexGenerations => (
    declarations: _model.classes.generation,
    beans: _model.beans.builds,
    codeKeys: _model.codeKeys.generation,
  );

  DocumentKind? _documentOf(String path) {
    for (final kind in _documents) {
      if (kind.accepts(path)) {
        return kind;
      }
    }
    return null;
  }
}
