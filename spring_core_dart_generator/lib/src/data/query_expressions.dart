// The `:#{...}` expressions of a `@Query` method, compiled to Dart.
//
// The starter evaluates the SpEL of a `:#{...}` marker at each call, from the
// method's arguments (its variables `#name`, `#p0`, `#a0`, `#root` the list of
// the arguments, `#entityName`, `#methodName`, `@bean` the beans); the build
// knows the method's types, so `compileSpel` writes what the interpreter would
// do as a function of the arguments and of the starter's
// `QueryExpressionContext`:
//
// ```dart
// // @Query('select * from books where title = :#{#book.title}')
// // Future<List<Book>> sameTitle(Book book);
// expressions: [(arguments, context) => (arguments[0] as Book).title],
// ```
//
// The scanner compiles each expression to learn whether it compiles (and to
// report its problems), with plain reads of the arguments; the emitter
// compiles it again with casts that name the types, which only it can write.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart'
    show Expression, literalNum, literalString, refer;
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/spel_compiler.dart';

/// Compiles [text], an expression of the `@Query` method [member] of a
/// repository in [repository].
///
/// [beans] are the application's beans by name (the others are known to
/// the run time only, so a member of one is left to the interpreter).
/// [cast] gives the code that reads an argument or a bean as its type: the
/// scanner passes the value itself, the emitter a cast to the type.
///
/// ```dart
/// compileQueryExpression(
///   '#book.title',
///   repository: library,
///   member: member,
///   beans: const {},
///   cast: (value, type) => value,
/// ); // SpelCompiled: arguments[0].title
/// ```
SpelCompilation compileQueryExpression(
  String text, {
  required LibraryElement repository,
  required ProxyMember member,
  required Map<String, InterfaceType> beans,
  required Expression Function(Expression value, DartType type) cast,
}) {
  // The generated code is not a part of the repository's library: it sees
  // the public members of its classes, as `dart:core` does.
  final library = repository.typeProvider.objectType.element.library;
  final provider = library.typeProvider;
  final unknown = library.typeSystem.leastUpperBound(
    provider.objectType,
    provider.nullType,
  );
  final arguments = refer('arguments');
  final context = refer('context');

  // An argument as its type, when the type can be written in a field.
  SpelBinding argument(int index, DartType type) {
    final value = arguments.index(literalNum(index));
    return type is InterfaceType &&
            !type.isDartCoreObject &&
            !_hasTypeParameter(type)
        ? SpelBinding(type, cast(value, type))
        : SpelBinding(unknown, value);
  }

  // The interpreter sets `#p0`, `#a0` and `#name` for each argument, then
  // `#entityName` and `#methodName`: a later name replaces an earlier one.
  final variables = <String, SpelBinding>{};
  for (final (index, parameter) in member.parameters.indexed) {
    final binding = argument(index, parameter.type);
    variables['p$index'] = binding;
    variables['a$index'] = binding;
    variables[parameter.name] = binding;
  }
  variables['entityName'] = SpelBinding(
    provider.stringType,
    context.property('entityName'),
  );
  variables['methodName'] = SpelBinding(
    provider.stringType,
    context.property('methodName'),
  );

  return compileSpel(
    text,
    SpelScope(
      library: library,
      variables: variables,
      root: SpelBinding(provider.listType(unknown), arguments),
      beans: (name) {
        // `@environment` is the context's, unless the application has a
        // bean of that name.
        if (name == 'environment' && !beans.containsKey(name)) {
          return null;
        }
        final read = context.property('bean').call([
          literalString(name, raw: true),
        ]);
        final type = beans[name];
        return type == null
            ? SpelBinding(provider.objectType, read)
            : SpelBinding(type, cast(read, type));
      },
      environment: context.property('environment').nullChecked,
    ),
  );
}

// Whether [type] is, or has among its type arguments, a type parameter (of
// a generic method): it cannot be written in the field of the class.
bool _hasTypeParameter(DartType type) =>
    type is TypeParameterType ||
    (type is InterfaceType && type.typeArguments.any(_hasTypeParameter));
