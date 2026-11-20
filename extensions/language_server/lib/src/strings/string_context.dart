import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';

/// A string literal of a Dart file, with what decides how it is read: the
/// annotation and the method call it is (most closely) inside.
///
/// The string roles read it: `'cash'` in `@Qualifier('cash')` is a bean
/// name, `'shop.name'` in `getProperty('shop.name')` a property key.
final class StringContext {
  /// [literal] of [file], inside [annotation] and [invocation] (the
  /// nearest of each, or `null`).
  StringContext(this.file, this.literal, this.annotation, this.invocation);

  /// [literal] of [file], with its nearest annotation and method call
  /// looked up among its ancestors.
  factory StringContext.of(DartFile file, SimpleStringLiteral literal) =>
      StringContext(
        file,
        literal,
        literal.thisOrAncestorOfType<Annotation>(),
        literal.thisOrAncestorOfType<MethodInvocation>(),
      );

  /// The file of the string.
  final DartFile file;

  /// The string literal.
  final SimpleStringLiteral literal;

  /// The nearest annotation the string is inside.
  final Annotation? annotation;

  /// The nearest method call the string is inside: as an argument, or as
  /// (part of) its target.
  final MethodInvocation? invocation;

  /// The name of [annotation]'s type ([annotationName]): `Value` for
  /// `@Value(...)`.
  late final String? annotationType = annotation == null
      ? null
      : annotationName(annotation!);

  /// The name of [invocation]'s method: `getProperty`.
  String? get method => invocation?.methodName.name;

  /// The string's value, escapes resolved.
  String get value => literal.value;

  /// The path of the file.
  String get path => file.path;

  /// The offset where the string's contents start (after the quote).
  int get contentStart => literal.contentsOffset;

  /// The offset just after the string's contents (before the quote).
  int get contentEnd => literal.contentsEnd;

  /// The contents as written in the file, escapes not resolved: offsets
  /// in it map to the file by adding [contentStart].
  String get contents => file.text.substring(contentStart, contentEnd);

  /// Whether the string is the first argument of [invocation].
  bool get isFirstArgument {
    final arguments = literal.parent;
    return arguments is ArgumentList &&
        arguments.arguments.isNotEmpty &&
        arguments.arguments.first == literal;
  }

  /// The name of the named argument whose value the string is (`branch`
  /// for `branch: '/more'`); `null` for any other string.
  String? get argumentName => switch (literal.parent) {
    final NamedArgument named => named.name.lexeme,
    _ => null,
  };
}
