import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';

/// Types that wrap the bean type at an injection point: for
/// `List<Mailer>`, `ObjectProvider<Mailer>` or `Map<String, Mailer>`, the
/// beans of `Mailer` (the last type argument) are meant.
const beanContainers = {'List', 'Set', 'Iterable', 'ObjectProvider', 'Map'};

/// The widget types of spring_boot_starter_flutter that take their beans
/// as a record type argument.
const springWidgetTypes = {
  'SpringStatelessWidget',
  'SpringStatefulWidget',
  'SpringState',
};

/// How the syntax shows an injection point: the parameters and fields the
/// container fills, the bean type they ask for and their qualifier.
final class InjectionPoints {
  /// Injection points of the classes of [classes].
  const InjectionPoints(this.classes);

  /// The classes of the workspace, for their stereotypes.
  final ClassIndex classes;

  /// The bean type for an injection point type: `T` for `T`, `List<T>`,
  /// `Set<T>`, `ObjectProvider<T>`, `Map<String, T>`.
  static String? beanType(NamedType type) {
    final name = type.name.lexeme;
    final arguments = type.typeArguments?.arguments ?? const [];
    if (beanContainers.contains(name) && arguments.isNotEmpty) {
      final inner = arguments.last;
      return inner is NamedType ? inner.name.lexeme : null;
    }
    // Clicked on `T` inside `List<T>`: still T.
    return name;
  }

  /// Whether the container fills [parameter]: a constructor parameter of a
  /// bean class, or a parameter of a `@Bean` or `@Autowired` method.
  bool isInjectedParameter(FormalParameter parameter) {
    final list = parameter.thisOrAncestorOfType<FormalParameterList>();
    final owner = list?.parent;
    final classNode = parameter.thisOrAncestorOfType<ClassDeclaration>();
    if (owner is ConstructorDeclaration ||
        owner is PrimaryConstructorDeclaration) {
      return classes.isBeanClass(classNode);
    }
    if (owner is MethodDeclaration) {
      // `@Bean` method parameters, `@Autowired` methods and setters.
      return hasAnnotation(owner.metadata, 'Bean') ||
          hasAnnotation(owner.metadata, 'Autowired');
    }
    return false;
  }

  /// The declared type of the field `this.name` refers to.
  static NamedType? fieldType(FieldFormalParameter parameter) {
    final explicit = parameter.type;
    if (explicit is NamedType) {
      return explicit;
    }
    final classNode = parameter.thisOrAncestorOfType<ClassDeclaration>();
    for (final member in classNode?.body.members ?? <ClassMember>[]) {
      if (member is FieldDeclaration) {
        for (final variable in member.fields.variables) {
          if (variable.name.lexeme == parameter.name.lexeme) {
            final type = member.fields.type;
            return type is NamedType ? type : null;
          }
        }
      }
    }
    return null;
  }

  /// Whether [annotations] hold one called [name].
  static bool hasAnnotation(List<Annotation> annotations, String name) =>
      annotations.any((a) => annotationName(a) == name);

  /// The value of the `@Qualifier('...')` among [annotations].
  static String? qualifierOf(List<Annotation> annotations) {
    for (final annotation in annotations) {
      if (annotationName(annotation) == 'Qualifier') {
        return stringValue(positionalArgument(annotation));
      }
    }
    return null;
  }

  /// A field of the bean record of a spring_boot_starter_flutter widget:
  /// `SpringStatelessWidget<(Basket, {Clock utc})>`,
  /// `SpringStatefulWidget<...>`, `SpringState<W, (...)>`. The owner type
  /// and the field's name (named fields), or `null` for any other type.
  static (String, String?)? widgetRecordField(NamedType type) {
    final field = type.parent;
    final String? fieldName;
    if (field is RecordTypeAnnotationPositionalField) {
      fieldName = null;
    } else if (field is RecordTypeAnnotationNamedField) {
      fieldName = field.name.lexeme;
    } else {
      return null;
    }
    final record = type.thisOrAncestorOfType<RecordTypeAnnotation>();
    final arguments = record?.parent;
    // `typedef BasketPageBeans = (Basket, Clock);` used as
    // `SpringStatefulWidget<BasketPageBeans>` in the same file.
    if (arguments is GenericTypeAlias) {
      final widget = _widgetUsing(arguments.name.lexeme, arguments.root);
      return widget == null ? null : (widget, fieldName);
    }
    final owner = arguments?.parent;
    if (arguments is! TypeArgumentList ||
        owner is! NamedType ||
        !springWidgetTypes.contains(owner.name.lexeme)) {
      return null;
    }
    return (owner.name.lexeme, fieldName);
  }

  // The Spring widget type that takes the record type [alias] as its beans
  // somewhere in [unit], or null.
  static String? _widgetUsing(String alias, AstNode unit) {
    final finder = _AliasUse(alias);
    unit.accept(finder);
    return finder.widget;
  }
}

// Finds a Spring widget type with a given record type alias among its type
// arguments (`SpringState<W, BasketPageBeans>`).
final class _AliasUse extends RecursiveAstVisitor<void> {
  _AliasUse(this.alias);

  final String alias;
  String? widget;

  @override
  void visitNamedType(NamedType node) {
    final arguments = node.typeArguments?.arguments ?? const <TypeAnnotation>[];
    if (widget == null &&
        springWidgetTypes.contains(node.name.lexeme) &&
        arguments.any((a) => a is NamedType && a.name.lexeme == alias)) {
      widget = node.name.lexeme;
    }
    super.visitNamedType(node);
  }
}
