import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/pointcuts.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';
import 'package:spring_core_dart/aop.dart' show ExpressionPointcut;

/// The colour of each part of a pointcut.
const Map<PointcutPartKind, TokenType> _colours = {
  PointcutPartKind.designator: TokenType.keyword,
  PointcutPartKind.operator: TokenType.operator,
  PointcutPartKind.wildcard: TokenType.operator,
  PointcutPartKind.type: TokenType.type,
  PointcutPartKind.declaringType: TokenType.type,
  PointcutPartKind.aspect: TokenType.type,
  PointcutPartKind.annotation: TokenType.classType,
  PointcutPartKind.bean: TokenType.variable,
  PointcutPartKind.member: TokenType.method,
  PointcutPartKind.reference: TokenType.method,
};

/// A pointcut expression: a string of an advice or `@Pointcut` annotation
/// ([pointcutAnnotations]).
///
/// It is highlighted part by part, and parsed by the runtime's
/// `ExpressionPointcut` with the `@Pointcut` methods of the project as
/// named pointcuts, so the editor rejects exactly what the application
/// would. Types and annotations go to their classes, `bean(...)` to the
/// beans, `pricing()` to the `@Pointcut` method, the method of
/// `execution(* Type.name(..))` to the matching methods.
final class PointcutRole extends StringRole {
  /// The role, over [model].
  const PointcutRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  static bool _claims(StringContext string) =>
      pointcutAnnotations.contains(string.annotationType);

  @override
  Handled<Target>? target(StringContext string, int offset) {
    if (!_claims(string)) {
      return null;
    }
    final source = string.contents;
    final relative = offset - string.contentStart;
    final parts = scanPointcut(source);
    final index = parts.indexWhere(
      (part) => relative >= part.start && relative <= part.end,
    );
    if (index < 0) {
      return const Handled(null);
    }
    final part = parts[index];
    // The part right before, joined by a dot: `Aspect.name`, `Type.method`.
    final qualifier =
        index > 0 &&
            parts[index - 1].end == part.start - 1 &&
            source[part.start - 1] == '.'
        ? parts[index - 1].text
        : null;
    return Handled(_targetOf(string, part, qualifier));
  }

  Target? _targetOf(
    StringContext string,
    PointcutPart part,
    String? qualifier,
  ) {
    final from = string.path;
    switch (part.kind) {
      case PointcutPartKind.type ||
          PointcutPartKind.declaringType ||
          PointcutPartKind.aspect:
        return _classes(from, part.text, 'Classes matching `${part.text}`');
      case PointcutPartKind.annotation:
        return _classes(from, part.text, 'Annotation `${part.text}`');
      case PointcutPartKind.bean:
        return BeanTarget([
          for (final bean in model.beans.beans)
            if (wildcardMatches(part.text, bean.name) ||
                bean.aliases.any((alias) => wildcardMatches(part.text, alias)))
              bean,
        ], "Beans matching '${part.text}'");
      case PointcutPartKind.reference:
        return _reference(string, part, qualifier);
      case PointcutPartKind.member:
        return _methods(from, part, qualifier);
      case PointcutPartKind.designator ||
          PointcutPartKind.operator ||
          PointcutPartKind.wildcard:
        return null;
    }
  }

  DeclarationTarget _classes(String from, String pattern, String description) =>
      DeclarationTarget(description, [
        for (final info in model.classes.classesMatching(from, pattern))
          DeclarationSite(
            info.path,
            info.nameOffset,
            info.name.length,
            'class `${info.name}`',
          ),
      ]);

  // `pricing()` or `AuditAspect.pricing()`: the `@Pointcut` method, the
  // one of the aspect the string is in first.
  DeclarationTarget _reference(
    StringContext string,
    PointcutPart part,
    String? qualifier,
  ) {
    final owner = string.literal
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.namePart
        .typeName
        .lexeme;
    final named = [
      for (final method in model.pointcuts.pointcutMethods)
        if (method.name == part.text &&
            (qualifier == null || method.className == qualifier))
          method,
    ];
    final own = [
      for (final method in named)
        if (method.className == owner) method,
    ];
    return DeclarationTarget('Pointcut `${part.text}()`', [
      for (final method in qualifier == null && own.isNotEmpty ? own : named)
        DeclarationSite(
          method.path,
          method.offset,
          method.name.length,
          '`${method.className}.${method.name}()`: `${method.expression}`',
        ),
    ]);
  }

  // The methods of `execution(* Type.name(..))`: of the classes matching
  // the type, or of every component when there is none.
  DeclarationTarget _methods(
    String from,
    PointcutPart part,
    String? qualifier,
  ) {
    final classes = qualifier == null
        ? model.classes.samePackageFirst(from, [
            for (final bean in model.beans.beans)
              if (bean.kind == BeanKind.component)
                ...model.classes.classesNamed(bean.typeName),
          ])
        : model.classes.classesMatching(from, qualifier);
    return DeclarationTarget('Methods matching `${part.text}`', [
      for (final info in classes)
        for (final member in info.declaration.body.members)
          if (member is MethodDeclaration &&
              wildcardMatches(part.text, member.name.lexeme))
            DeclarationSite(
              info.path,
              member.name.offset,
              member.name.length,
              '`${info.name}.${member.name.lexeme}`',
            ),
    ]);
  }

  @override
  void tokens(StringContext string, AddToken add) {
    if (!_claims(string)) {
      return;
    }
    final base = string.contentStart;
    for (final part in scanPointcut(string.contents)) {
      add(base + part.start, base + part.end, _colours[part.kind]!);
    }
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (!_claims(string)) {
      return;
    }
    try {
      ExpressionPointcut(
        string.value,
        namedPointcuts: model.pointcuts.namedPointcuts,
      );
    } on FormatException catch (error) {
      // Point at the quoted name of the message when it is in this string
      // (`unknown pointcut 'audit'`), else at the whole string.
      final quoted = RegExp("'([^']+)'").firstMatch(error.message)?[1];
      var start = string.contentStart;
      var end = string.contentEnd;
      for (final part in scanPointcut(string.contents)) {
        if (part.text == quoted) {
          start = string.contentStart + part.start;
          end = string.contentStart + part.end;
          break;
        }
      }
      problems.add(
        Problem(
          model.locations.rangeOf(string.file, start, end),
          error.message,
          error: true,
        ),
      );
    }
  }
}
