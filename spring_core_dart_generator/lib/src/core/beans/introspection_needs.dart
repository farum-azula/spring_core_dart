part of 'bean_scanner.dart';

// What the application does with the classes of its methods, as far as the
// build can see: the generator describes a class only for those uses (see
// `IntrospectionNeed`). What a package's annotation implies is the
// package's part's to say (`PackageGeneration.methodNeeds` and
// `expressionUse`), so the core knows no starter.
//
// ```dart
// @GetMapping('/books')
// Future<Page<BookDto>> books(@RequestBody SearchForm form) => ...
// // BookDto and Page: written out (getters) and read back (constructor
// // and setters, for a test that reads the answer); SearchForm: read in
// // (constructor and setters).
// ```
//
// A method with an annotation of a user's `@BeanMethodAnnotation()` that no
// part knows is something the build knows nothing of: its types are
// described entirely.

/// What the types of one annotated method need: the return type (a
/// `Future`'s value, the elements of a `Stream`, ...) and each parameter,
/// in declaration order.
typedef AnnotatedMethodNeeds = ({
  IntrospectionNeed result,
  List<IntrospectionNeed> parameters,
});

/// Where an expression of a method's annotations looks: at the arguments,
/// at the result, at the bean the method is called on.
typedef SpelUse = ({bool arguments, bool result, bool target});

extension _IntrospectionNeeds on BeanScanner {
  // What each annotation of the method [method] (the `@BeanMethodAnnotation`
  // ones, [marked]) does with its parameters and its result, as the first
  // part that knows the annotation says; the union over the annotations.
  AnnotatedMethodNeeds _annotatedMethodNeeds(
    MethodElement method,
    List<InterfaceType> marked,
  ) {
    var result = IntrospectionNeed.none;
    final need = List.filled(
      method.formalParameters.length,
      IntrospectionNeed.none,
    );
    for (final type in marked) {
      AnnotatedMethodNeeds? known;
      for (final generation in generations) {
        known = generation.methodNeeds(type, method, _packageScan);
        if (known != null) {
          break;
        }
      }
      if (known == null) {
        // An annotation the build does not know: whatever its framework
        // does with the values, it can.
        result |= IntrospectionNeed.all;
        for (var i = 0; i < need.length; i++) {
          need[i] |= IntrospectionNeed.all;
        }
        continue;
      }
      result |= known.result;
      for (final (i, parameter) in known.parameters.take(need.length).indexed) {
        need[i] |= parameter;
      }
    }
    return (result: result, parameters: need);
  }

  // The expressions in [annotations] (of one method): cache keys and
  // conditions, security expressions. Which values they may reach, as the
  // first part that knows each annotation says:
  //
  // - `#name`, `#p0`, `#a0`, `args`: the arguments;
  // - `#result` (cache), `returnObject` and `filterObject` (security): the
  //   result;
  // - `target`: the bean.
  SpelUse _spelUse(Iterable<DartObject> annotations) {
    var arguments = false;
    var result = false;
    var target = false;
    for (final annotation in annotations) {
      if (annotation.type == null) {
        continue;
      }
      for (final generation in generations) {
        if (generation.expressionUse(annotation, _packageScan)
            case final use?) {
          arguments |= use.arguments;
          result |= use.result;
          target |= use.target;
          break;
        }
      }
    }
    return (arguments: arguments, result: result, target: target);
  }

  // The classes an expression on a method of [model]'s bean reaches (cache
  // keys, security conditions) are read, and their methods called: the
  // arguments, the result when the expression looks at it, and the bean.
  void _introspectSpelTypes(ProxyModel? model) {
    if (model == null || model.targetType.element is! ClassElement) {
      return;
    }
    final owner = model.targetType.element as ClassElement;
    for (final member in model.members) {
      if (member.kind != ProxyMemberKind.method) {
        continue;
      }
      final use = _spelUse(member.mergedAnnotations);
      if (use.arguments) {
        for (final parameter in member.parameters) {
          introspection.need(parameter.type, owner, IntrospectionNeed.spel);
        }
      }
      if (use.result) {
        introspection.need(
          _valueTypeOf(member.returnType),
          owner,
          IntrospectionNeed.spel,
        );
      }
      if (use.target) {
        introspection.needClass(owner, IntrospectionNeed.spel);
      }
    }
  }

  // The type of the value of a `Future`, else the type itself.
  static DartType _valueTypeOf(DartType type) =>
      type is InterfaceType &&
          type.isDartAsyncFuture &&
          type.typeArguments.length == 1
      ? type.typeArguments.single
      : type;
}
