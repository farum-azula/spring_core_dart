import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';

/// The methods of the starter's own repository interfaces: the starter
/// implements them, so they are not derived queries.
const crudMethods = {
  'count',
  'delete',
  'deleteAll',
  'deleteAllById',
  'deleteById',
  'existsById',
  'findAll',
  'findAllById',
  'findById',
  'save',
  'saveAll',
};

/// The text of a string literal of a `@Query`, which may be several adjacent
/// literals: the contents joined, and where each piece sits in the file, so
/// an offset of the text maps back to the file.
final class QueryString {
  /// A query text read from [node].
  QueryString(this.node, this.text, this.segments, {required this.isCount});

  /// The string expression (one literal or adjacent literals).
  final Expression node;

  /// The contents of the literals, joined.
  final String text;

  /// Where each literal's contents are: `(offset in text, offset in the
  /// file, length)`.
  final List<(int, int, int)> segments;

  /// Whether this is the `countQuery:` of the annotation.
  final bool isCount;

  /// The offset in the file of the start of the contents.
  int get fileStart => segments.first.$2;

  /// The offset in the file where the contents end.
  int get fileEnd => segments.last.$2 + segments.last.$3;

  /// The offset in [text] of the file offset [fileOffset]; `null` outside
  /// the contents. The end of a literal's contents counts as inside it.
  int? textOffset(int fileOffset) {
    for (final (textStart, fileStart, length) in segments) {
      if (fileOffset >= fileStart && fileOffset <= fileStart + length) {
        return textStart + fileOffset - fileStart;
      }
    }
    return null;
  }

  /// The spans of the file that hold `[start, end)` of [text], one for each
  /// literal it touches.
  List<(int, int)> pieces(int start, int end) {
    final result = <(int, int)>[];
    for (final (textStart, fileStart, length) in segments) {
      final from = start > textStart ? start : textStart;
      final to = end < textStart + length ? end : textStart + length;
      if (to > from) {
        result.add((fileStart + from - textStart, fileStart + to - textStart));
      }
    }
    return result;
  }

  /// The file span of `[start, end)` of [text] as one range from its first
  /// character to its last (it may cover several literals); `null` when
  /// empty.
  (int, int)? span(int start, int end) {
    final parts = pieces(start, end);
    return parts.isEmpty ? null : (parts.first.$1, parts.last.$2);
  }
}

/// A parameter of a repository method.
final class ParameterInfo {
  /// A parameter [name] of [type] declared at [offset].
  const ParameterInfo(this.name, this.type, this.offset, this.index);

  /// The name.
  final String name;

  /// The type as written, with `?` and type arguments.
  final String type;

  /// Where the name is in the file.
  final int offset;

  /// The position among the method's parameters.
  final int index;

  /// Whether the starter binds it as the paging or the sorting of the
  /// query instead of a value: such a parameter is never used by name.
  bool get isSpecial {
    final base = type.replaceAll('?', '').replaceAll(RegExp('<.*'), '').trim();
    return base == 'Pageable' || base == 'PageRequest' || base == 'Sort';
  }
}

/// A repository method with `@Query`: its texts and parameters.
final class QueryMethod {
  /// A `@Query` method.
  QueryMethod(this.method, this.annotation, this.texts, this.parameters);

  /// The method.
  final MethodDeclaration method;

  /// The `@Query` annotation.
  final Annotation annotation;

  /// The SQL, then the count query when there is one; a text the editor
  /// cannot read (an interpolation, an escape) is left out.
  final List<QueryString> texts;

  /// The parameters, in order.
  final List<ParameterInfo> parameters;
}

/// A repository interface of a file: its `@Query` methods and the methods
/// whose names are derived queries.
final class RepositoryClass {
  /// A repository.
  RepositoryClass(this.declaration, this.queries, this.derived);

  /// The class.
  final ClassDeclaration declaration;

  /// The methods with `@Query`.
  final List<QueryMethod> queries;

  /// The abstract methods without `@Query` that are not the starter's own:
  /// derived queries, each with its parameters.
  final List<(MethodDeclaration, List<ParameterInfo>)> derived;
}

final _scanned = Expando<List<RepositoryClass>>('repositories');

/// The repository interfaces of [file]: classes that extend or implement
/// something named `...Repository`, or any abstract class of a file that
/// imports the data starter and uses `@Query`.
List<RepositoryClass> repositoriesIn(DartFile file) {
  final cached = _scanned[file];
  if (cached != null) {
    return cached;
  }
  final importsData = file.unit.directives.any(
    (d) =>
        d is ImportDirective &&
        '${d.uri.stringValue}'.contains('spring_boot_starter_data'),
  );
  final result = <RepositoryClass>[];
  for (final declaration in file.unit.declarations) {
    if (declaration is! ClassDeclaration ||
        declaration.abstractKeyword == null) {
      continue;
    }
    final supertypes = [
      ...?declaration.implementsClause?.interfaces,
      ?declaration.extendsClause?.superclass,
    ];
    final isRepository =
        supertypes.any((t) => t.name.lexeme.endsWith('Repository')) ||
        importsData;
    if (!isRepository) {
      continue;
    }
    final queries = <QueryMethod>[];
    final derived = <(MethodDeclaration, List<ParameterInfo>)>[];
    for (final member in declaration.body.members) {
      if (member is! MethodDeclaration ||
          member.isStatic ||
          member.isGetter ||
          member.isSetter ||
          member.body is! EmptyFunctionBody) {
        continue;
      }
      final parameters = parametersOf(member);
      final annotation = member.metadata
          .where((a) => annotationName(a) == 'Query')
          .firstOrNull;
      if (annotation != null) {
        queries.add(
          QueryMethod(member, annotation, _texts(file, annotation), parameters),
        );
      } else if (!crudMethods.contains(member.name.lexeme) &&
          !member.metadata.any((a) => annotationName(a) == 'override')) {
        derived.add((member, parameters));
      }
    }
    if (queries.isNotEmpty || derived.isNotEmpty) {
      result.add(RepositoryClass(declaration, queries, derived));
    }
  }
  return _scanned[file] = result;
}

/// The parameters of [method], in order.
List<ParameterInfo> parametersOf(MethodDeclaration method) {
  final result = <ParameterInfo>[];
  for (final (index, parameter)
      in (method.parameters?.parameters ?? const <FormalParameter>[]).indexed) {
    final name = parameter.name;
    if (name == null) {
      continue;
    }
    final type = parameter.type?.toSource() ?? 'dynamic';
    result.add(ParameterInfo(name.lexeme, type, name.offset, index));
  }
  return result;
}

// The SQL and the count query of a `@Query`, each when it is a plain string.
List<QueryString> _texts(DartFile file, Annotation annotation) {
  final result = <QueryString>[];
  for (final (expression, isCount) in [
    (
      positionalArgument(annotation) ?? namedArgument(annotation, 'value'),
      false,
    ),
    (namedArgument(annotation, 'countQuery'), true),
  ]) {
    final query = _read(file, expression, isCount: isCount);
    if (query != null) {
      result.add(query);
    }
  }
  return result;
}

QueryString? _read(
  DartFile file,
  Expression? expression, {
  required bool isCount,
}) {
  final literals = switch (expression) {
    final SimpleStringLiteral literal => [literal],
    AdjacentStrings(:final strings) => [
      for (final s in strings)
        if (s is SimpleStringLiteral) s else null,
    ],
    _ => null,
  };
  if (literals == null || literals.contains(null)) {
    return null;
  }
  final text = StringBuffer();
  final segments = <(int, int, int)>[];
  for (final literal in literals.cast<SimpleStringLiteral>()) {
    final contents = file.text.substring(
      literal.contentsOffset,
      literal.contentsEnd,
    );
    // An escape (`\n`, `\'`) is not the character it stands for in the
    // source: the offsets would not map, so the text is not read.
    if (!literal.isRaw && contents.contains(r'\')) {
      return null;
    }
    segments.add((text.length, literal.contentsOffset, contents.length));
    text.write(contents);
  }
  return QueryString(
    expression!,
    text.toString(),
    segments,
    isCount: isCount,
  );
}
