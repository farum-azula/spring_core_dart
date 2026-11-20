// The files of a generated module the tests read: its `.spring.dart` and
// the files beside it (its descriptions, the binding of its
// `@ConfigurationProperties` classes, its proxies), which were one file
// before. Content checks read them as one text ([moduleText]); compile
// checks resolve each file ([moduleSiblings], [moduleErrors]).
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';

/// The one generated module of [result] (its `.spring.dart`), where a
/// build wrote one.
AssetId moduleOutput(TestBuilderResult result) =>
    result.outputs.singleWhere((id) => id.path.endsWith('.spring.dart'));

/// The ids of the module [module] (by default [result]'s one) and of the
/// files beside it that [result] wrote, the module first.
List<AssetId> moduleFiles(TestBuilderResult result, [AssetId? module]) {
  final id = module ?? moduleOutput(result);
  return [
    for (final file in [
      id,
      for (final extension in moduleFileExtensions) moduleFileId(id, extension),
    ])
      if (result.outputs.contains(file)) file,
  ];
}

/// The generated code of the module [module] (by default [result]'s
/// one): its library, then the files beside it, one after the other.
/// [moduleSources] gives the files back for the text.
String moduleText(TestBuilderResult result, [AssetId? module]) {
  final files = {
    for (final file in moduleFiles(result, module))
      '$file': result.readerWriter.testing.readString(file),
  };
  final text = files.values.join('\n');
  _files[text] = files;
  return text;
}

// The files of each text [moduleText] returned.
final _files = <String, Map<String, String>>{};

/// The files of the module whose [moduleText] is [text], by id
/// (`pkg|...`), to resolve.
Map<String, String> moduleSources(String text) =>
    _files[text] ?? (throw StateError('Not the text of a generated module.'));

/// The files [result] wrote beside its modules, by id (`pkg|...`), to
/// resolve with them.
Map<String, String> moduleSiblings(TestBuilderResult result) => {
  for (final id in result.outputs)
    if (id.path.split('/').contains(generatedFolder) &&
        moduleFileExtensions.any(id.path.endsWith))
      '$id': result.readerWriter.testing.readString(id),
};

/// The diagnostics of the generated library [library] and of the files it
/// is made of: its parts (the proxies) and the libraries of its
/// descriptions it imports, as one result.
Future<SomeErrorsResult> moduleErrors(LibraryElement library) async {
  final session = library.session;
  final paths = {
    for (final fragment in library.fragments) fragment.source.fullName,
    for (final fragment in library.fragments)
      for (final imported in fragment.importedLibraries)
        if (imported.uri.pathSegments.contains(generatedFolder) &&
            moduleFileExtensions.any(imported.uri.path.endsWith))
          imported.firstFragment.source.fullName,
  };
  return _ModuleErrors([
    for (final path in paths)
      if (await session.getErrors(path) case ErrorsResult(:final diagnostics))
        ...diagnostics,
  ]);
}

final class _ModuleErrors implements ErrorsResult {
  _ModuleErrors(this.diagnostics);

  @override
  final List<Diagnostic> diagnostics;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
