part of 'bean_scanner.dart';

// The type a `@Bean` method really returns, inferred from its body.
//
// Spring registers a `@Bean` definition without a class (`beanClassName`
// is `null`): until the bean is created only the declared return type is
// known, so `@ConditionalOnMissingBean(HikariDataSource.class)` misses
// `@Bean DataSource dataSource() { return new HikariDataSource(); }`.
// The generator sees the method body, so the definition is registered
// under the concrete class (with its full generic arguments) and all its
// supertypes from the start: lookups, conditions and AOP see it before the
// bean exists (a deliberate improvement over Spring).
//
// ```dart
// @Bean()
// DataSource dataSource() => HikariDataSource(url);   // HikariDataSource
//
// @Bean()
// Store<Object> store() => MemoryStore<User>();       // MemoryStore<User>
//
// @Bean()
// Shape shape() {                                     // the common
//   if (round) return Circle();                       // supertype of
//   return Square();                                  // Circle and Square
// }
// ```

extension _BeanTypeInference on BeanScanner {
  /// The key of [method] in [BeanScanner._beanMethodDeclarations]:
  /// `library#Class.method`.
  static String methodKey(ExecutableElement method) =>
      '${method.library.uri}#${method.enclosingElement?.name}.${method.name}';

  /// Resolves and stores the declarations (with typed bodies) of the
  /// `@Bean` methods of [library]'s classes, so [inferredBeanType] can read
  /// what they return.
  ///
  /// The classes they `@Import` and their superclasses and mixins are
  /// included, since those may live outside the scanned directory. SDK
  /// classes are skipped. Must run before the library is scanned.
  Future<void> resolveBeanMethodDeclarations(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) async {
    final pending = <InterfaceElement>[...library.classes];
    final seen = <InterfaceElement>{};
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (!seen.add(element) || element.library.isInSdk) {
        continue;
      }
      // Inherited `@Bean` methods (superclasses and mixins may live in
      // libraries outside the scan).
      pending.addAll([
        for (final supertype in [?element.supertype, ...element.mixins])
          supertype.element,
      ]);
      for (final annotation in _import.annotationsOf(element)) {
        for (final value
            in ConstantReader(annotation).peek('value')?.listValue ??
                const <DartObject>[]) {
          if (value.toTypeValue()?.element case final ClassElement imported) {
            pending.add(imported);
          }
        }
      }
      for (final method in element.methods) {
        if (!_bean.hasAnnotationOf(method)) {
          continue;
        }
        final key = methodKey(method);
        if (_beanMethodDeclarations.containsKey(key)) {
          continue;
        }
        if (await astNodeFor(method.firstFragment)
            case final MethodDeclaration node) {
          _beanMethodDeclarations[key] = node;
        }
      }
    }
  }

  /// The type of the bean [method] creates: the static type of what its
  /// body returns, when that is more specific than [declared]; otherwise
  /// [declared].
  ///
  /// Several `return`s give their least upper bound, and `throw` is
  /// ignored. The inference gives up and returns [declared] when the body
  /// was not resolved, has a bare `return;`, returns a nullable or
  /// non-class type, or returns a type the generated code cannot name
  /// (private, internal to the SDK, or with type-parameter arguments).
  InterfaceType inferredBeanType(MethodElement method, InterfaceType declared) {
    final declaration = _beanMethodDeclarations[methodKey(method)];
    if (declaration == null) {
      return declared;
    }
    final returned = <DartType>[];
    switch (declaration.body) {
      case ExpressionFunctionBody(:final expression):
        if (expression.staticType case final type?) {
          returned.add(type);
        }
      case BlockFunctionBody(:final block):
        final collector = _ReturnCollector();
        block.accept(collector);
        if (collector.incomplete) {
          return declared;
        }
        returned.addAll(collector.types);
      default:
        return declared;
    }
    // `throw` (type `Never`) does not return a bean.
    final types = [
      for (final type in returned)
        if (type is! NeverType) type,
    ];
    if (types.isEmpty) {
      return declared;
    }
    final typeSystem = method.library.typeSystem;
    final result = types
        .skip(1)
        .fold(types.first, (a, b) => typeSystem.leastUpperBound(a, b));
    if (result is! InterfaceType ||
        result.nullabilitySuffix != NullabilitySuffix.none ||
        result == declared ||
        !typeSystem.isSubtypeOf(result, declared) ||
        !_isNameable(result)) {
      return declared;
    }
    return result;
  }

  /// The types a bean with an inferred type is registered under:
  /// [inferred] and its public supertypes, then [declared] and its
  /// supertypes not already listed.
  ///
  /// The declared type stays because callers inject what the method
  /// signature promises: `MemoryStore<String>` is also found as
  /// `Store<Object>` when that is the declared type.
  List<InterfaceType> exposedInferredTypes(
    InterfaceType inferred,
    InterfaceType declared,
  ) {
    final types = _exposedTypes(inferred);
    for (final type in _exposedTypes(declared)) {
      if (!types.contains(type)) {
        types.add(type);
      }
    }
    return types;
  }

  // A public class type, with concrete type arguments, that generated code
  // can import (see [isImportableType]).
  static bool _isNameable(DartType type) => switch (type) {
    InterfaceType() =>
      type.element.isPublic &&
          isImportableType(type) &&
          type.typeArguments.every(_isConcreteArgument),
    _ => false,
  };

  static bool _isConcreteArgument(DartType type) => switch (type) {
    TypeParameterType() => false,
    InterfaceType() => _isNameable(type),
    FunctionType() =>
      type.typeParameters.isEmpty &&
          _isConcreteArgument(type.returnType) &&
          type.formalParameters.every((p) => _isConcreteArgument(p.type)),
    RecordType() =>
      type.positionalFields.every((f) => _isConcreteArgument(f.type)) &&
          type.namedFields.every((f) => _isConcreteArgument(f.type)),
    VoidType() || DynamicType() || NeverType() => true,
    _ => false,
  };
}

// The static types of the `return` statements of a block body, without
// those of nested functions and closures. A `return;` makes the result
// incomplete (no inference).
class _ReturnCollector extends RecursiveAstVisitor<void> {
  final types = <DartType>[];
  bool incomplete = false;

  @override
  void visitReturnStatement(ReturnStatement node) {
    final type = node.expression?.staticType;
    if (type == null) {
      incomplete = true;
    } else {
      types.add(type);
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}
}
