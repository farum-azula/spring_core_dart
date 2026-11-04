import 'package:analyzer/dart/ast/ast.dart' hide Argument;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/metadata_locations.dart';

/// The beans of `spring_metadata.json`: what the scan registers
/// ([fromModel]) and the `BeanDefinition`s a package writes by hand, as
/// the starters do in their auto-configurations ([BeanDefinitionReader]).
abstract final class MetadataBeans {
  /// The entry of [bean] (see `roadmap/spring_metadata.md`) and the
  /// profiles it names.
  static Map<String, Object?> fromModel(BeanModel bean, Set<String> profiles) {
    final own = _profilesOf(bean.conditions);
    profiles.addAll(own.expand(profileNames));
    final element = bean.element;
    final owner = element.enclosingElement;
    return {
      'name': bean.name,
      'type': bean.type.getDisplayString(),
      'types': _typeNames(bean.type, bean.exposedTypes),
      'scope': bean.scope,
      'primary': bean.primary,
      'qualifiers': bean.qualifiers.toList()..sort(),
      'profiles': own,
      'conditions': [
        // A `@Bean` method has its class's conditions first.
        if (element is MethodElement && owner != null)
          ..._conditionSources(owner, bean),
        ..._conditionSources(element, bean),
      ],
      'source': sourceOf(element),
      'line': lineOf(element),
      'injects': _injects(bean),
      'members': members(bean.type),
    };
  }

  /// The plain profile names in a `@Profile` [expression] (`!test`,
  /// `(dev | local) & !ci`).
  static Iterable<String> profileNames(String expression) => RegExp(
    r'[A-Za-z0-9_.\-]+',
  ).allMatches(expression).map((m) => m[0]!);

  static List<String> _profilesOf(List<ConditionModel> conditions) => [
    for (final condition in conditions)
      ...switch (condition) {
        ProfileConditionModel(:final profiles) => profiles,
        GroupConditionModel(:final conditions) => _profilesOf(conditions),
        _ => const <String>[],
      },
  ];

  // The types a bean can be injected by, its own first.
  static List<String> _typeNames(
    InterfaceType type,
    List<InterfaceType> exposed,
  ) => {
    type.getDisplayString(),
    for (final t in exposed) t.getDisplayString(),
  }.toList();

  // The conditions of [element] as written (profiles are listed apart).
  static List<String> _conditionSources(Element element, BeanModel bean) {
    final custom = {
      for (final condition in bean.conditions)
        if (condition is AnnotationConditionModel)
          condition.value.type?.element?.name,
    };
    return [
      for (final annotation in element.metadata.annotations)
        if (annotation.computeConstantValue()?.type?.element?.name
            case final name?)
          if (name.startsWith('Conditional') || custom.contains(name))
            annotation.toSource(),
    ];
  }

  static List<Map<String, Object?>> _injects(BeanModel bean) {
    final arguments = [
      ...bean.creation.arguments,
      for (final property in bean.properties)
        Argument(property.point, namedAs: property.name),
      for (final method in bean.methods) ...method.arguments,
    ];
    return [
      for (final argument in arguments)
        if (argument.point.kind != PointKind.value)
          {
            'parameter': argument.namedAs ?? argument.point.name,
            'type': argument.point.type.getDisplayString(),
            'qualifier': argument.point.qualifier,
          },
    ];
  }

  /// The members of [type] a SpEL expression can reach: the public
  /// getters, fields and methods of the class and its supertypes (not
  /// `Object`'s), by name. A method lists its parameters as `Type name`,
  /// named ones in braces, optional ones in brackets.
  static List<Map<String, Object?>> members(InterfaceType type) {
    final result = <String, Map<String, Object?>>{};
    for (final t in [type, ...type.allSupertypes]) {
      if (t.isDartCoreObject) {
        continue;
      }
      for (final field in t.element.fields) {
        if (_reachable(field.name, field.isStatic) &&
            field.isOriginDeclaration) {
          result.putIfAbsent(
            field.name!,
            () => {
              'name': field.name,
              'kind': 'field',
              'type': field.type.getDisplayString(),
            },
          );
        }
      }
      for (final getter in t.getters) {
        if (_reachable(getter.name, getter.isStatic) &&
            getter.isOriginDeclaration) {
          result.putIfAbsent(
            getter.name!,
            () => {
              'name': getter.name,
              'kind': 'getter',
              'type': getter.returnType.getDisplayString(),
            },
          );
        }
      }
      for (final method in t.methods) {
        if (_reachable(method.name, method.isStatic) &&
            method.name != 'noSuchMethod') {
          result.putIfAbsent(
            method.name!,
            () => {
              'name': method.name,
              'kind': 'method',
              'type': method.returnType.getDisplayString(),
              'parameters': [
                for (final parameter in method.formalParameters)
                  parameterSource(parameter),
              ],
            },
          );
        }
      }
    }
    return result.values.toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  }

  static bool _reachable(String? name, bool isStatic) =>
      name != null && !name.startsWith('_') && !isStatic && name != 'hashCode';

  /// `Type name`, `{Type name}` for a named parameter and `[Type name]` for
  /// an optional positional one.
  static String parameterSource(FormalParameterElement parameter) {
    final text = '${parameter.type.getDisplayString()} ${parameter.name}';
    if (parameter.isNamed) {
      return '{$text}';
    }
    return parameter.isOptionalPositional ? '[$text]' : text;
  }
}

/// The beans a library defines with `BeanDefinition<T>(...)` expressions in
/// plain Dart (the starters' auto-configurations), read from the resolved
/// syntax tree: name, type and its supertypes, scope, primary, qualifiers,
/// conditions and the `Dependency` list.
final class BeanDefinitionReader extends RecursiveAstVisitor<void> {
  /// Creates a reader that adds profiles it finds to [profiles].
  BeanDefinitionReader(this.profiles);

  /// The profiles named by the conditions read.
  final Set<String> profiles;

  /// The beans read, in source order.
  final beans = <Map<String, Object?>>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    if (type is InterfaceType &&
        type.element.name == 'BeanDefinition' &&
        (type.element.library.uri.path.startsWith('spring_core_dart/'))) {
      _read(node, type);
    }
    super.visitInstanceCreationExpression(node);
  }

  void _read(InstanceCreationExpression node, InterfaceType definition) {
    final named = <String, Expression>{};
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedArgument) {
        named[argument.name.lexeme] = argument.argumentExpression;
      }
    }
    final bean = definition.typeArguments.firstOrNull;
    final name = _string(named['name']);
    if (bean is! InterfaceType || name == null) {
      return;
    }
    final conditions = <String>[];
    final conditionProfiles = <String>[];
    if (named['conditions'] case final expression?) {
      _conditions(expression, conditions, conditionProfiles);
    }
    profiles.addAll(conditionProfiles.expand(MetadataBeans.profileNames));
    final types = <InterfaceType>[
      bean,
      for (final t in bean.allSupertypes)
        if (!t.isDartCoreObject) t,
    ];
    if (named['types'] case ListLiteral(:final elements)) {
      for (final item in elements) {
        if (item is Identifier) {
          if (item.element case final ClassElement c) {
            types.add(c.thisType);
          }
        }
      }
    }
    final scope = named['scope'];
    beans.add({
      'name': name,
      'type': bean.getDisplayString(),
      'types': {for (final t in types) t.getDisplayString()}.toList(),
      'scope': switch (scope) {
        null => 'singleton',
        PrefixedIdentifier(:final identifier) => identifier.name,
        _ => scope.toSource(),
      },
      'primary':
          named['primary'] is BooleanLiteral &&
          (named['primary']! as BooleanLiteral).value,
      'qualifiers': switch (named['qualifiers']) {
        SetOrMapLiteral(:final elements) => [
          for (final e in elements) ?_string(e),
        ]..sort(),
        _ => <String>[],
      },
      'profiles': conditionProfiles,
      'conditions': conditions,
      'source': _sourceOf(node),
      'line': _lineOf(node),
      'injects': _dependencies(named['dependencies']),
      'members': MetadataBeans.members(bean),
    });
  }

  // Each `Foo(...)` of a condition list or of a variable it names is a
  // condition; a `Profile`-like one is told by its class name.
  void _conditions(
    Expression expression,
    List<String> conditions,
    List<String> conditionProfiles,
  ) {
    switch (expression) {
      case ListLiteral(:final elements):
        for (final element in elements) {
          if (element is Expression) {
            _conditions(element, conditions, conditionProfiles);
          }
        }
      case InstanceCreationExpression(:final argumentList)
          when expression.staticType?.element?.name == 'ConditionGroup':
        for (final argument in argumentList.arguments) {
          _conditions(
            argument.argumentExpression,
            conditions,
            conditionProfiles,
          );
        }
      case InstanceCreationExpression():
        final name = expression.staticType?.element?.name ?? '';
        if (name == 'ProfileCondition') {
          final list = expression.argumentList.arguments.firstOrNull;
          if (list is ListLiteral) {
            for (final item in list.elements) {
              if (item is Expression && _string(item) != null) {
                conditionProfiles.add(_string(item)!);
              }
            }
          }
        } else {
          conditions.add('@${_withoutConst(expression.toSource())}');
        }
      case SimpleIdentifier(:final element):
        final variable = element is GetterElement ? element.variable : element;
        if (variable is TopLevelVariableElement) {
          final unit = _unitOf(expression);
          final declaration = _declarationOf(unit, variable.name);
          if (declaration != null) {
            _conditions(declaration, conditions, conditionProfiles);
          }
        }
      default:
        break;
    }
  }

  static String _withoutConst(String source) =>
      source.startsWith('const ') ? source.substring(6) : source;

  // The variable a condition list is kept in is in the same file.
  static CompilationUnit? _unitOf(AstNode node) =>
      node.thisOrAncestorOfType<CompilationUnit>();

  static Expression? _declarationOf(CompilationUnit? unit, String? name) {
    for (final declaration in unit?.declarations ?? const <Declaration>[]) {
      if (declaration is TopLevelVariableDeclaration) {
        for (final variable in declaration.variables.variables) {
          if (variable.name.lexeme == name) {
            return variable.initializer;
          }
        }
      }
    }
    return null;
  }

  static List<Map<String, Object?>> _dependencies(Expression? expression) {
    if (expression is! ListLiteral) {
      return const [];
    }
    return [
      for (final element in expression.elements)
        if (element is InstanceCreationExpression &&
            element.staticType?.element?.name == 'Dependency')
          {
            'parameter': null,
            'type': _dependencyType(element),
            'qualifier': _string(
              element.argumentList.arguments
                  .whereType<NamedArgument>()
                  .where((a) => a.name.lexeme == 'qualifier')
                  .map((a) => a.argumentExpression)
                  .firstOrNull,
            ),
          },
    ];
  }

  static String? _dependencyType(InstanceCreationExpression dependency) {
    final first = dependency.argumentList.arguments.firstOrNull;
    final expression = first?.argumentExpression;
    return expression is Identifier ? expression.name : expression?.toSource();
  }

  static String? _string(AstNode? node) =>
      node is StringLiteral ? node.stringValue : null;

  static String? _sourceOf(AstNode node) {
    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    final uri = unit?.declaredFragment?.source.uri;
    return uri == null ? null : sourceOfUri(uri);
  }

  static int? _lineOf(AstNode node) {
    final unit = node.thisOrAncestorOfType<CompilationUnit>();
    return unit?.lineInfo.getLocation(node.offset).lineNumber;
  }
}
