part of 'bean_scanner.dart';

// The constant initial value of the fields of introspected classes, for
// `BeanProperty.initialValue`.
//
// The analyzer evaluates the constants of `const` variables and of
// parameter defaults (`computeConstantValue`), but not the initializer of a
// plain field (`int version = 0;`), which is not a constant variable. So
// the resolved initializer is read here and evaluated for the shapes that
// matter for a default value; anything else leaves the field without an
// initial value.
//
// ```dart
// @Introspected()
// class Item {
//   int version = 0;                 // 0
//   bool inStock = true;             // true
//   String status = 'new';           // 'new'
//   Status state = Status.draft;     // the enum value
//   List<String> tags = const [];    // const []
//   DateTime added = DateTime.now(); // none: not a constant
//   List<String> notes = [];         // none: not const
// }
// ```
//
// A value is `null`, a `bool`, `int`, `double` or `String`; a
// `DartObject` of a referenced constant (an enum value, a `const`
// variable); or a `List`, `Set` or `Map` of such values (from a `const`
// literal). `({Object? value})?` tells "no value" (`null`) from the
// value `null`.

/// A field's evaluated initializer; see [BeanScanner].
typedef InitialValue = ({Object? value});

extension _FieldInitializers on BeanScanner {
  /// The key of a field in [BeanScanner._fieldInitializers]:
  /// `library#Class.field`.
  static String fieldKey(FieldElement field) =>
      '${field.library.uri}#${field.enclosingElement.name}.${field.name}';

  /// Resolves and stores the initializers of the fields of the
  /// `@Introspected` classes of [library] and of the classes introspected
  /// along with them, so that [scanLibrary] can read their initial values.
  ///
  /// The classes reached are the ones [BeanScanner._scanIntrospected] may
  /// describe: those in `@Introspected(classes: [...])`, the supertypes and
  /// mixins, the types of fields and constructor parameters from the same
  /// package, the classes of the `@JsonSubTypes` and `@JsonTypeInfo`
  /// annotations, and the return types of `@ConfigurationProperties` bean
  /// methods. Only fields that have an initializer are resolved.
  Future<void> resolveFieldInitializerDeclarations(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) async {
    final pending = <ClassElement>[];
    for (final element in library.classes) {
      if (_introspected.hasAnnotationOf(element)) {
        pending.add(element);
      }
      for (final method in element.methods) {
        final returned = method.returnType.element;
        if (returned is ClassElement &&
            _configurationProperties.hasAnnotationOf(method)) {
          pending.add(returned);
        }
      }
    }
    final seen = <ClassElement>{};
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (!seen.add(element) || element.library.isInSdk) {
        continue;
      }
      void reach(Object? type, {required bool samePackage}) {
        switch (type) {
          case final InterfaceType type:
            final reached = type.element;
            if (reached is ClassElement &&
                (!samePackage ||
                    BeanScanner._packageOf(reached) ==
                        BeanScanner._packageOf(element))) {
              pending.add(reached);
            }
            for (final argument in type.typeArguments) {
              reach(argument, samePackage: samePackage);
            }
          case final DartObject object:
            reach(object.toTypeValue(), samePackage: false);
            for (final item in object.toListValue() ?? const <DartObject>[]) {
              reach(item, samePackage: false);
            }
            reach(object.getField('value'), samePackage: false);
            reach(object.getField('defaultImpl'), samePackage: false);
        }
      }

      for (final supertype in [?element.supertype, ...element.mixins]) {
        reach(supertype, samePackage: false);
      }
      for (final annotation in element.metadata.annotations) {
        final value = annotation.computeConstantValue();
        if (value == null) {
          continue;
        }
        if (_introspected.isAssignableFromType(value.type!)) {
          for (final listed
              in value.getField('classes')?.toListValue() ??
                  const <DartObject>[]) {
            reach(listed, samePackage: false);
          }
        } else if (_jsonSubTypes.isExactlyType(value.type!)) {
          for (final subType
              in value.getField('value')?.toListValue() ??
                  const <DartObject>[]) {
            reach(subType, samePackage: false);
          }
        } else if (_jsonTypeInfo.isExactlyType(value.type!)) {
          reach(value.getField('defaultImpl'), samePackage: false);
        }
      }
      for (final field in element.fields) {
        reach(field.type, samePackage: true);
        if (field.isStatic ||
            field.isPrivate ||
            !field.hasInitializer ||
            field.name == null) {
          continue;
        }
        final key = fieldKey(field);
        if (_fieldInitializers.containsKey(key)) {
          continue;
        }
        if (await astNodeFor(field.firstFragment) case VariableDeclaration(
          :final initializer?,
        )) {
          _fieldInitializers[key] = initializer;
        }
      }
      for (final constructor in element.constructors) {
        for (final parameter in constructor.formalParameters) {
          reach(parameter.type, samePackage: true);
        }
      }
    }
  }

  /// The constant initial value of [field], or `null` when it has none, or
  /// when its initializer is not a constant the generated code can write.
  ///
  /// An `int` initializer of a `double` field (`double rate = 1`) is
  /// converted to `1.0`, as Dart does.
  InitialValue? initialValueOf(FieldElement field) {
    final initializer = _fieldInitializers[fieldKey(field)];
    if (initializer == null) {
      return null;
    }
    final result = _evaluate(initializer, inConst: false);
    if (result == null) {
      return null;
    }
    final value = result.value;
    final type = field.type;
    if (value is int && type.isDartCoreDouble) {
      return (value: value.toDouble());
    }
    return result;
  }

  // The value of [expression] when it is a constant expression of a shape
  // supported here; `inConst` is true inside a `const` literal, where the
  // inner collections need no `const` of their own.
  InitialValue? _evaluate(Expression expression, {required bool inConst}) {
    switch (expression) {
      case ParenthesizedExpression(:final expression):
        return _evaluate(expression, inConst: inConst);
      case NullLiteral():
        return (value: null);
      case BooleanLiteral(:final value):
        return (value: value);
      case IntegerLiteral(:final value?):
        return (value: value);
      case DoubleLiteral(:final value):
        return (value: value);
      case StringLiteral(:final stringValue?):
        return (value: stringValue);
      case PrefixExpression(
            :final operator,
            operand: IntegerLiteral(:final value?),
          )
          when operator.type == TokenType.MINUS:
        return (value: -value);
      case PrefixExpression(
            :final operator,
            operand: DoubleLiteral(:final value),
          )
          when operator.type == TokenType.MINUS:
        return (value: -value);
      case ListLiteral(:final constKeyword, :final elements)
          when constKeyword != null || inConst:
        final items = _evaluateAll(elements);
        return items == null ? null : (value: items);
      case SetOrMapLiteral(:final constKeyword, :final elements, :final isSet)
          when constKeyword != null || inConst:
        if (isSet) {
          final items = _evaluateAll(elements);
          return items == null ? null : (value: items.toSet());
        }
        final entries = <Object?, Object?>{};
        for (final element in elements) {
          if (element is! MapLiteralEntry) {
            return null;
          }
          final key = _evaluate(element.key, inConst: true);
          final value = _evaluate(element.value, inConst: true);
          if (key == null || value == null) {
            return null;
          }
          entries[key.value] = value.value;
        }
        return (value: entries);
      case Identifier() || PropertyAccess():
        final element = switch (expression) {
          final Identifier identifier => identifier.element,
          PropertyAccess(:final propertyName) => propertyName.element,
          _ => null,
        };
        final variable = switch (element) {
          final PropertyAccessorElement accessor => accessor.variable,
          final VariableElement variable => variable,
          _ => null,
        };
        if (variable == null || !variable.isConst) {
          return null;
        }
        final value = variable.computeConstantValue();
        return value != null && _isRecreatable(value) ? (value: value) : null;
      default:
        return null;
    }
  }

  List<Object?>? _evaluateAll(List<CollectionElement> elements) {
    final items = <Object?>[];
    for (final element in elements) {
      if (element is! Expression) {
        return null;
      }
      final item = _evaluate(element, inConst: true);
      if (item == null) {
        return null;
      }
      items.add(item.value);
    }
    return items;
  }
}
