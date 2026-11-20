import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/dart_navigation.dart';
import 'package:dart_spring_language_server/src/symbols/injection_points.dart';
import 'package:dart_spring_language_server/src/symbols/resolvers/context_getter_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/resolvers/field_parameter_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/resolvers/injected_type_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/resolvers/string_symbols.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';

/// What is found at a node of a Dart file, in the order the resolvers are
/// asked: a new kind of symbol is a new [SymbolResolver] and one entry
/// here.
List<SymbolResolver> symbolResolvers(ProjectModel model) {
  final types = InjectedTypeSymbols(
    model.beans,
    InjectionPoints(model.classes),
  );
  return [
    StringSymbols(model.roles),
    FieldParameterSymbols(types),
    types,
    ContextGetterSymbols(model.beans),
  ];
}

/// The parts of a Dart file with their own navigation, in the order they
/// are asked.
List<DartNavigation> dartNavigations(ProjectModel model) => [
  QueryNavigation(model.query),
  DerivedQueryNavigation(model.derived),
  SymbolNavigation(model.locations, symbolResolvers(model)),
];

/// Go to definition and hovers in Dart files: the beans of an injection
/// point or a bean name, the definitions of a property key or a message
/// code, the file of a `resources:` location, the class or method a
/// pointcut names, the entities and columns of a query. Empty when there
/// is nothing Spring-specific at the offset; the Dart analysis server
/// answers for the rest.
final class DartSymbols {
  /// Navigation over [model].
  DartSymbols(this.model) : _navigations = dartNavigations(model);

  /// What the workspace knows.
  final ProjectModel model;

  final List<DartNavigation> _navigations;

  /// The targets of go to definition at [offset] (in UTF-16 units) of the
  /// Dart file [path].
  List<SourceRange> definition(String path, int offset) {
    final file = model.files.dartFile(path);
    if (file == null) {
      return const [];
    }
    for (final navigation in _navigations) {
      if (navigation.definition(file, offset) case final found?) {
        return found;
      }
    }
    return const [];
  }

  /// Markdown for a hover at [offset] of the Dart file [path], about the
  /// same target as [definition]: the candidate beans with their files,
  /// the value of a property in each file, the files a location resolves
  /// to. When nothing is found it says so (and, for a location, where it
  /// looked). `null` when [offset] is not on such a target.
  String? hover(String path, int offset) {
    final file = model.files.dartFile(path);
    if (file == null) {
      return null;
    }
    for (final navigation in _navigations) {
      if (navigation.hover(file, offset) case final text?) {
        return text;
      }
    }
    return null;
  }
}
