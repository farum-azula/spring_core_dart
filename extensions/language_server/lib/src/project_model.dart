import 'package:dart_spring_language_server/src/config/config_editor.dart';
import 'package:dart_spring_language_server/src/data_model.dart';
import 'package:dart_spring_language_server/src/derived_queries.dart';
import 'package:dart_spring_language_server/src/diagnostics/dart_problems.dart';
import 'package:dart_spring_language_server/src/index/bean_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';
import 'package:dart_spring_language_server/src/index/code_key_index.dart';
import 'package:dart_spring_language_server/src/index/dart_types.dart';
import 'package:dart_spring_language_server/src/index/key_resolution.dart';
import 'package:dart_spring_language_server/src/index/message_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/pointcut_index.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/index/property_index.dart';
import 'package:dart_spring_language_server/src/index/pubspec_assets.dart';
import 'package:dart_spring_language_server/src/index/schema_index.dart';
import 'package:dart_spring_language_server/src/index/screen_index.dart';
import 'package:dart_spring_language_server/src/index/source_beans.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';
import 'package:dart_spring_language_server/src/spel_editor.dart';
import 'package:dart_spring_language_server/src/strings/spel_paths.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';
import 'package:dart_spring_language_server/src/symbols/dart_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/source_locations.dart';
import 'package:dart_spring_language_server/src/tokens/dart_tokens.dart';

/// What the language server knows about the open project, as the parts
/// that know it: the files, the indexes built from them, and the editors
/// of SpEL, queries and config files. One per workspace; each part is made
/// on first use and finds the others here.
///
/// It reads syntax only, with no type resolution, so it is fast and works
/// without `pub get` and on code that does not compile. The price: types
/// are matched by their simple name, and supertypes are followed only
/// through classes of the workspace; beans of dependencies are known from
/// their Spring metadata only.
final class ProjectModel {
  /// The model of the directories [roots]. Nothing is read until
  /// [refresh] or a query.
  ProjectModel(this.roots);

  /// The workspace folders the editor opened, scanned recursively.
  final List<String> roots;

  /// The Spring metadata of the packages, read from
  /// `lib/spring_gen/spring_metadata.json` and found through
  /// `.dart_tool/package_config.json`; re-read when a file changes.
  final metadata = MetadataStore();

  /// The Dart and config files, with the open documents' unsaved text.
  late final files = ProjectFiles(roots);

  /// Which package each file is in.
  late final packages = PackageLayout(roots);

  /// Turns offsets into ranges and shortens paths.
  late final locations = SourceLocations(files, packages);

  /// The classes of the workspace.
  late final classes = ClassIndex(files, packages);

  /// The beans of the workspace and of the metadata.
  late final beans = BeanIndex(
    files,
    packages,
    classes,
    metadata,
    SourceBeans(data),
  );

  /// The named pointcuts of the `@Aspect` classes.
  late final pointcuts = PointcutIndex(files, classes);

  /// The message bundles and the codes registered in code.
  late final messages = MessageIndex(files, packages);

  /// The properties of the config files.
  late final properties = PropertyIndex(files, packages, messages, metadata);

  /// The property keys the code reads.
  late final codeKeys = CodeKeyIndex(files, packages, roles);

  /// The known keys of each package.
  late final schemas = SchemaIndex(metadata, packages, codeKeys, properties);

  /// Whether a placeholder's key resolves where it is read.
  late final keys = KeyResolution(properties, schemas);

  /// The screens of the navigation.
  late final screens = ScreenIndex(classes, packages, metadata);

  /// The asset entries of the pubspecs.
  late final assets = PubspecAssets();

  /// The entities and repositories of the data layer.
  late final data = DataModel(this);

  /// Beans and members in SpEL.
  late final spel = SpelEditor(this);

  /// The Dart types of what SpEL reads, resolved from the syntax.
  late final dartTypes = DartTypes(this);

  /// The member paths of SpEL expressions, on those types.
  late final spelPaths = SpelPaths(this);

  /// The SQL of `@Query` methods.
  late final query = QueryEditor(this);

  /// The names of derived query methods.
  late final derived = DerivedQueryEditor(this);

  /// What the strings of Dart files mean.
  late final roles = StringRoles(stringRoles(this));

  /// Definitions and hovers in Dart files.
  late final symbols = DartSymbols(this);

  /// Semantic tokens of Dart files.
  late final tokens = DartTokens(this);

  /// The checks of Dart files.
  late final problems = DartProblems(this);

  /// Completion, hovers, definitions, tokens and checks of config files.
  late final config = ConfigEditor(this);

  /// The Spring metadata that applies to the file [path]: its package's and
  /// those of all the dependencies.
  MetadataView metadataFor(String path) =>
      metadata.viewFor(packages.packageRootOf(path));

  /// Scans the workspace folders again (at most once per [interval]
  /// unless [force] is set): re-reads changed files, forgets removed ones,
  /// and the metadata and package roots that may have changed.
  void refresh({
    bool force = false,
    Duration interval = const Duration(seconds: 2),
  }) {
    if (files.refresh(force: force, interval: interval)) {
      metadata.refresh();
      packages.forgetRoots();
    }
  }
}
