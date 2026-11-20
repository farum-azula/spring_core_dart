import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';

final _facts = Expando<DartFileFacts>('file facts');

/// What the checks, the highlighting and the indexes read from a Dart
/// file, collected in one walk of its syntax tree and kept for that parse:
/// its string literals (each with the annotation and the method call it
/// is in), its string interpolations, the parameters of its parameter
/// lists and its field declarations.
final class DartFileFacts {
  DartFileFacts._(this.file);

  /// The facts of [file], collected on first use and kept for the parse:
  /// for the files the editor asks about.
  factory DartFileFacts.of(DartFile file) =>
      _facts[file] ??= DartFileFacts._(file).._collect();

  /// The facts of [file], kept only when [keep] is set or they were kept
  /// already: the indexes read every file of the workspace once and keep
  /// only what they take from it, but keep the facts of an open document,
  /// which the checks and the highlighting read next.
  factory DartFileFacts.read(DartFile file, {bool keep = false}) => keep
      ? DartFileFacts.of(file)
      : _facts[file] ?? (DartFileFacts._(file).._collect());

  /// The file.
  final DartFile file;

  /// The string literals, in the order of the source.
  final strings = <StringContext>[];

  /// The string interpolations (`'${key}'`), each with the annotation it
  /// is in, in the order of the source.
  final interpolations = <(StringInterpolation, Annotation?)>[];

  /// The parameters of every parameter list (methods, constructors,
  /// closures), in the order of the source.
  final parameters = <FormalParameter>[];

  /// The field declarations, in the order of the source.
  final fields = <FieldDeclaration>[];

  void _collect() => file.unit.accept(_Collector(this));
}

final class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.facts);

  final DartFileFacts facts;
  final _annotations = <Annotation>[];
  final _invocations = <MethodInvocation>[];

  @override
  void visitAnnotation(Annotation node) {
    _annotations.add(node);
    super.visitAnnotation(node);
    _annotations.removeLast();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _invocations.add(node);
    super.visitMethodInvocation(node);
    _invocations.removeLast();
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    facts.strings.add(
      StringContext(
        facts.file,
        node,
        _annotations.lastOrNull,
        _invocations.lastOrNull,
      ),
    );
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    facts.interpolations.add((node, _annotations.lastOrNull));
    super.visitStringInterpolation(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    facts.parameters.addAll(node.parameters);
    super.visitFormalParameterList(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    facts.fields.add(node);
    super.visitFieldDeclaration(node);
  }
}
