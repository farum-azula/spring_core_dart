import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';

final _signatures = Expando<String>('declaration signatures');

/// What the class and bean indexes read from [file], as text without
/// positions: each top-level class with its annotations, type parameters
/// and supertypes (type arguments included: a repository's entity is one),
/// and the annotated methods of its body with their return types.
///
/// Two parses with the same signature give the same classes and beans,
/// only perhaps at other offsets; typing inside a method body or a comment
/// does not change it. Computed once per parse.
String declarationSignature(DartFile file) =>
    _signatures[file] ??= _signatureOf(file.unit);

String _signatureOf(CompilationUnit unit) {
  final buffer = StringBuffer();
  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }
    for (final annotation in declaration.metadata) {
      buffer.writeln(annotation.toSource());
    }
    buffer
      ..write('class ${declaration.namePart.toSource()} ')
      ..write(declaration.extendsClause?.toSource() ?? '')
      ..write(declaration.withClause?.toSource() ?? '')
      ..writeln(declaration.implementsClause?.toSource() ?? '');
    for (final member in declaration.body.members) {
      if (member is MethodDeclaration && member.metadata.isNotEmpty) {
        for (final annotation in member.metadata) {
          buffer.writeln('  ${annotation.toSource()}');
        }
        buffer.writeln(
          '  ${member.returnType?.toSource() ?? ''} ${member.name.lexeme}',
        );
      }
    }
  }
  return buffer.toString();
}
