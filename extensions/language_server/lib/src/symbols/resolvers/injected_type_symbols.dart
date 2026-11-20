import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/index/bean_index.dart';
import 'package:dart_spring_language_server/src/symbols/injection_points.dart';
import 'package:dart_spring_language_server/src/symbols/symbol_resolver.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Methods whose type argument is a bean type: go to definition on `Clock`
/// in `context.getBean<Clock>()` lists the `Clock` beans.
const _beanLookupMethods = {
  'getBean',
  // spring_boot_starter_flutter: `context.bean<T>()`, `SpringScope.beanOf<T>`.
  'bean',
  'beanOf',
  'getBeansOfType',
  'getBeanProvider',
  'getSortedBeans',
  'findBean',
  'dependency',
  'optionalDependency',
  'provider',
};

/// The beans of a type at an injection point: a constructor or `@Bean`
/// parameter, a field of a bean, a `getBean<T>()` type argument, a field
/// of a Spring widget's bean record. Only the beans the file's package can
/// see are listed.
final class InjectedTypeSymbols implements SymbolResolver {
  /// Injection points of [points], whose beans [beans] finds.
  const InjectedTypeSymbols(this.beans, this.points);

  /// The beans of the workspace.
  final BeanIndex beans;

  /// How the syntax shows an injection point.
  final InjectionPoints points;

  @override
  Handled<Target>? resolve(DartFile file, AstNode node, int offset) {
    final type = node is NamedType
        ? node
        : node.thisOrAncestorOfType<NamedType>();
    return type == null ? null : Handled(_target(file.path, type));
  }

  Target? _target(String from, NamedType type) {
    final beanType = InjectionPoints.beanType(type);
    if (beanType == null) {
      return null;
    }
    final typeArguments = type.parent;
    if (typeArguments is TypeArgumentList &&
        typeArguments.parent is MethodInvocation &&
        _beanLookupMethods.contains(
          (typeArguments.parent! as MethodInvocation).methodName.name,
        )) {
      return beansOf(beanType, null, from);
    }
    if (InjectionPoints.widgetRecordField(type) case (
      final owner,
      final fieldName,
    )) {
      final candidates = beans.beansOfType(beanType, from: from);
      // A named field picks among several beans by its name.
      final named = [
        if (fieldName != null && candidates.length > 1)
          for (final bean in candidates)
            if (bean.matches(fieldName)) bean,
      ];
      return BeanTarget(
        named.isNotEmpty ? named : candidates,
        'Beans of type $beanType (record of $owner)',
      );
    }
    final parameter = type.thisOrAncestorOfType<FormalParameter>();
    if (parameter != null) {
      if (InjectionPoints.hasAnnotation(parameter.metadata, 'Value') ||
          !points.isInjectedParameter(parameter)) {
        return null;
      }
      return beansOf(
        beanType,
        InjectionPoints.qualifierOf(parameter.metadata),
        from,
      );
    }
    final field = type.thisOrAncestorOfType<FieldDeclaration>();
    if (field != null && !field.isStatic) {
      if (InjectionPoints.hasAnnotation(field.metadata, 'Value') ||
          !points.classes.isBeanClass(
            field.thisOrAncestorOfType<ClassDeclaration>(),
          )) {
        return null;
      }
      return beansOf(
        beanType,
        InjectionPoints.qualifierOf(field.metadata),
        from,
      );
    }
    return null;
  }

  /// The beans of [type] with [qualifier] that [from] can see.
  BeanTarget beansOf(String type, String? qualifier, String from) => BeanTarget(
    beans.beansOfType(type, qualifier: qualifier, from: from),
    qualifier == null
        ? 'Beans of type $type'
        : "Beans of type $type qualified '$qualifier'",
  );
}
