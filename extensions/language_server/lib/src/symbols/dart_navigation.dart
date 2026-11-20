import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/derived_queries.dart';
import 'package:dart_spring_language_server/src/query_editor.dart';
import 'package:dart_spring_language_server/src/symbols/source_locations.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Answers go to definition and hovers in a part of a Dart file it knows:
/// the SQL of a `@Query`, the name of a derived query, or anything the
/// [SymbolResolver]s find. Asked in order; the first that answers wins.
abstract interface class DartNavigation {
  /// The targets of go to definition at [offset] of [file]; `null` when
  /// [offset] is not in this navigation's part.
  List<SourceRange>? definition(DartFile file, int offset);

  /// The hover at [offset] of [file]; `null` when there is none here.
  String? hover(DartFile file, int offset);
}

/// The SQL of the `@Query` methods of repositories.
final class QueryNavigation implements DartNavigation {
  /// Navigation through [editor].
  const QueryNavigation(this.editor);

  /// The editor of `@Query` texts.
  final QueryEditor editor;

  @override
  List<SourceRange>? definition(DartFile file, int offset) =>
      editor.definition(file, file.path, offset);

  @override
  String? hover(DartFile file, int offset) =>
      editor.hover(file, file.path, offset);
}

/// The names of derived query methods (`findByTitle`).
final class DerivedQueryNavigation implements DartNavigation {
  /// Navigation through [editor].
  const DerivedQueryNavigation(this.editor);

  /// The editor of derived query names.
  final DerivedQueryEditor editor;

  @override
  List<SourceRange>? definition(DartFile file, int offset) {
    final found = editor.definition(file, file.path, offset);
    return found == null || found.isEmpty ? null : found;
  }

  @override
  String? hover(DartFile file, int offset) =>
      editor.hover(file, file.path, offset);
}

/// Whatever the [resolvers] find at the node under the cursor: strings,
/// injection points, getters of beans.
final class SymbolNavigation implements DartNavigation {
  /// Navigation through [resolvers], asked in order.
  const SymbolNavigation(this.locations, this.resolvers);

  /// Turns offsets into ranges.
  final SourceLocations locations;

  /// The resolvers.
  final List<SymbolResolver> resolvers;

  /// The target at [offset] of [file]; `null` when there is none.
  Target? targetAt(DartFile file, int offset) {
    final node = file.nodeAt(offset);
    if (node == null) {
      return null;
    }
    for (final resolver in resolvers) {
      if (resolver.resolve(file, node, offset) case final handled?) {
        return handled.value;
      }
    }
    return null;
  }

  @override
  List<SourceRange> definition(DartFile file, int offset) =>
      targetAt(file, offset)?.definitions(_context(file, offset)) ?? const [];

  @override
  String? hover(DartFile file, int offset) =>
      targetAt(file, offset)?.hover(_context(file, offset));

  TargetContext _context(DartFile file, int offset) =>
      TargetContext(locations, file.text, offset);
}
