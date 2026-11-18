// Compiles a SpEL expression to Dart.
//
// The runtime evaluates SpEL by walking a syntax tree and finding properties
// and methods through `BeanIntrospection`s. The build knows every type, so
// it can write the code the walk would end up running: `#book.title` becomes
// `a[0].title`, a typo becomes a build error with a suggestion, and nothing
// has to be introspected. The syntax is the runtime's (`SpelExpressionParser`
// of spring_core_dart); what an operator does is too: where Dart's operator
// differs (`/` on ints, `==` on numbers and collections, `<` on null, `+` on
// text) the code calls `SpelOperations`, which the interpreter runs as well.
//
// ```dart
// final result = compileSpel(
//   '#book.title + "!"',
//   SpelScope(
//     library: library,
//     variables: {'book': SpelBinding(bookType, refer('book'))},
//   ),
// );
// // SpelCompiled: SpelOperations.concat(book.title, '!'), a String
// ```
//
// Three outcomes: code and its static type; `unsupported` when the
// expression needs the interpreter (the caller keeps it for run time); or
// problems, which are build errors. What compiles: literals, `#variables`,
// `#root`, `#this`, `@beans`, properties and methods of the static types
// (`a.b`, `a?.b`, `a.m(x)`), indexing of lists, maps and strings, the
// arithmetic, comparison and logical operators, `? :` and `?:`.
//
// Compiled code is the interpreter's under a default context, apart from:
//
//  * a member on a nullable value without `?.` is a build error (the
//    interpreter fails on null at run time), and so is an unknown `#name`
//    (the interpreter reads null);
//  * an error thrown by a getter reaches the caller as it is (the
//    interpreter wraps it in EL1021E);
//  * errors of operators have no `Expression [...] @n` prefix;
//  * arguments and operands are not converted: what the static types do not
//    fit stays with the interpreter;
//  * properties and methods are Dart's: any public member, not only the
//    introspected ones. Java-style names of the interpreter (`size()`,
//    `equals`) stay with the interpreter;
//  * a converter, comparator or operator overloader set on an evaluation
//    context is not seen: the code has no context, it does what a default
//    one does;
//  * a real number is told from an int by its static type (`double`), as
//    Java does: for a `double` variable or property `'n=' + #whole` is
//    `n=7.0`, on the web too. The interpreter knows the real literals and
//    the arithmetic of reals, but not that a variable is one, and on the web
//    an integral double is an `int` at run time, so it says `n=7` there (on
//    the VM both say `n=7.0`). A deliberate difference: the static type is
//    the truth. A conditional or Elvis whose sides are a double and another
//    number stays with the interpreter, which tracks the number that came
//    out.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:code_builder/code_builder.dart'
    show
        Block,
        Code,
        CodeExpression,
        DartEmitter,
        Expression,
        literalBool,
        literalNull,
        literalNum,
        literalString,
        refer;
import 'package:spring_core_dart/expression.dart' as spel;
// The syntax tree is the runtime's internal; the build reads it.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/ast.dart' as ast;
import 'package:spring_core_dart_generator/src/did_you_mean.dart';

/// A value an expression reads: [type] is what the build knows of it and
/// [read] the code that reads it in the generated code.
///
/// ```dart
/// // `#book` is the first argument, a Book.
/// SpelBinding(
///   bookType,
///   refer('a').index(literalNum(0)).asA(refer('Book')),
/// );
/// ```
final class SpelBinding {
  /// A value of [type] read by [read].
  const SpelBinding(this.type, this.read);

  /// The static type of the value.
  final DartType type;

  /// The code that reads the value.
  final Expression read;
}

/// What an expression can see: its `#variables`, `#root`, beans and the
/// library whose members it may use.
///
/// ```dart
/// SpelScope(
///   library: library,
///   variables: {'book': SpelBinding(bookType, refer('book'))},
///   beans: (name) => name == 'clock' ? clockBinding : null,
///   beanNames: ['clock'],
/// );
/// ```
final class SpelScope {
  /// A scope of [library]; the rest is what the expression may read.
  const SpelScope({
    required this.library,
    this.variables = const {},
    this.root,
    this.beans,
    this.beanNames = const [],
    this.environment,
  });

  /// The library the generated code lives in: it decides which members are
  /// visible, and its type system and type provider type the expression.
  final LibraryElement library;

  /// The `#name` variables.
  final Map<String, SpelBinding> variables;

  /// `#root`, `#this` of the expression and the object a bare `name` or
  /// `method()` applies to; none when the expression has no root.
  final SpelBinding? root;

  /// The bean `@name` stands for, or `null` when there is none. Without it
  /// a bean reference is left to the interpreter.
  final SpelBinding? Function(String name)? beans;

  /// The names [beans] knows, for the suggestion of an unknown name.
  final Iterable<String> beanNames;

  /// The code of the `Environment` (a `PropertyResolver`) that
  /// `@environment` is, when [beans] has no bean of that name. Its methods
  /// are the ones the interpreter gives it: `getProperty(key)`,
  /// `getProperty(key, default)`, `getRequiredProperty`, `containsProperty`,
  /// `resolvePlaceholders` and `resolveRequiredPlaceholders`; any other
  /// member (the interpreter reads `@environment.name` as a property of the
  /// configuration) is left to the interpreter.
  final Expression? environment;
}

/// Something wrong with an expression, which the build reports.
final class SpelProblem {
  /// A problem at offset [position] of the expression (`-1` when unknown).
  const SpelProblem(this.message, this.position);

  /// What is wrong, with a suggestion when there is one.
  final String message;

  /// The offset in the expression text, or `-1`.
  final int position;

  @override
  String toString() => position < 0 ? message : '$message (at $position)';
}

/// The outcome of [compileSpel].
sealed class SpelCompilation {
  /// An outcome.
  const SpelCompilation();

  /// What is wrong with the expression; empty unless it is a
  /// [SpelInvalid].
  List<SpelProblem> get problems => const [];
}

/// The expression as Dart code.
final class SpelCompiled extends SpelCompilation {
  /// The [code] of an expression of static type [type].
  const SpelCompiled(this.code, this.type);

  /// The code computing the value, in the order and with the semantics of
  /// the interpreter.
  final Expression code;

  /// The static type of [code].
  final DartType type;
}

/// An expression the compiler leaves to the interpreter.
final class SpelUnsupported extends SpelCompilation {
  /// An expression that needs the interpreter for [construct], found at
  /// offset [position].
  const SpelUnsupported(this.construct, this.position);

  /// What is not compiled, such as `T(Math)` or `a.size()`.
  final String construct;

  /// The offset of [construct] in the expression.
  final int position;

  @override
  String toString() => 'unsupported: $construct (at $position)';
}

/// An expression with problems: a build error.
final class SpelInvalid extends SpelCompilation {
  /// An expression with [problems].
  const SpelInvalid(this.problems);

  @override
  final List<SpelProblem> problems;
}

/// Compiles [expression], plain SpEL without `#{...}`, to Dart code for
/// [scope].
///
/// Returns [SpelCompiled] with the code and its static type,
/// [SpelUnsupported] when the interpreter has to run it, or [SpelInvalid]
/// with every problem found (also when another part is unsupported: a typo
/// is an error whatever else the expression does).
///
/// ```dart
/// final result = compileSpel('#book.titel', scope);
/// // SpelInvalid: No property 'titel' on type 'Book'; did you mean
/// // 'title'? Available properties: author, title, year.
/// ```
SpelCompilation compileSpel(String expression, SpelScope scope) {
  final ast.SpelNode node;
  try {
    node = spel.SpelExpressionParser().parseRaw(expression).ast;
  } on spel.ExpressionException catch (error) {
    return SpelInvalid([
      SpelProblem('Invalid expression: ${error.simpleMessage}', error.position),
    ]);
  }
  final compiler = _Compiler(scope);
  final value = compiler.compileRoot(node);
  if (compiler.problems.isNotEmpty) {
    return SpelInvalid(compiler.problems);
  }
  final unsupported = compiler.unsupported;
  if (unsupported != null || value == null) {
    return unsupported ?? const SpelUnsupported('the expression', 0);
  }
  return SpelCompiled(value.code, value.type);
}

// Precedence of the code a value is, to parenthesize only where needed
// (Dart's, as numbers that grow with binding strength).
const _pPostfix = 17;
const _pUnary = 16;
const _pMultiplicative = 15;
const _pAdditive = 14;
const _pRelational = 9;
const _pEquality = 8;
const _pLogicalAnd = 6;
const _pLogicalOr = 5;
const _pIfNull = 4;
const _pConditional = 3;

// The code of a value and its static type.
final class _Value {
  const _Value(
    this.code,
    this.type, [
    this.precedence = _pPostfix,
    this.isEnvironment = false,
  ]);

  final Expression code;
  final DartType type;
  final int precedence;

  // Whether this is `@environment` of the scope: its members are not Dart's.
  final bool isEnvironment;
}

// The state of a position in the tree, as in the interpreter's
// ExpressionState: the object names apply to (`#this`), the object the
// current compound expression started from (what arguments see as `#this`)
// and `#root`. Null where the expression has no root.
final class _Context {
  const _Context(this.root, this.active, this.scopeRoot);

  final _Value? root;
  final _Value? active;
  final _Value? scopeRoot;

  _Context withActive(_Value? value) => _Context(root, value, scopeRoot);
}

// A receiver of a member: the value, its class and whether `?.` is needed.
final class _Receiver {
  const _Receiver(this.value, this.type, {required this.safe});

  final _Value value;
  final InterfaceType type;
  final bool safe;
}

// The numeric kinds of static types.
enum _Num { int, double, num }

final Expression _ops = refer(
  'SpelOperations',
  'package:spring_core_dart/spring_core_dart.dart',
);

// Methods the interpreter's builtins define under a Dart name with another
// result or effect (`List.add` returns true there, `Iterable.take` a list).
const _divergentBuiltins = <String, Set<String>>{
  'List': {'add', 'addAll'},
  'Set': {'addAll'},
  'Iterable': {'take', 'skip'},
  'Map': {'putIfAbsent'},
};

final class _Compiler {
  _Compiler(this.scope)
    : library = scope.library,
      types = scope.library.typeSystem,
      provider = scope.library.typeProvider;

  final SpelScope scope;
  final LibraryElement library;
  final TypeSystem types;
  final TypeProvider provider;

  final problems = <SpelProblem>[];
  SpelUnsupported? unsupported;

  // The interpreter's own tables, asked whether it knows a member that Dart
  // does not have (a Java-style name such as `size`).
  static final _builtinContext = spel.StandardEvaluationContext();

  _Value? compileRoot(ast.SpelNode node) {
    final binding = scope.root;
    final root = binding == null ? null : _bound(binding);
    return _compile(node, _Context(root, root, root));
  }

  _Value? _problem(int position, String message) {
    problems.add(SpelProblem(message, position));
    return null;
  }

  _Value? _unsupported(int position, String construct) {
    unsupported ??= SpelUnsupported(construct, position);
    return null;
  }

  // -------------------------------------------------------------------------
  // The tree
  // -------------------------------------------------------------------------

  _Value? _compile(ast.SpelNode node, _Context context) => switch (node) {
    ast.Literal() => _literal(node),
    ast.VariableReference() => _variable(node, context),
    ast.PropertyOrFieldReference() => _property(node, context),
    ast.MethodReference() => _method(node, context),
    ast.Indexer() => _index(node, context),
    ast.CompoundExpression() => _compound(node, context),
    ast.BeanReference() => _bean(node),
    ast.BinaryOperator() => _binary(node, context),
    ast.UnaryOperator() => _unaryOperator(node, context),
    ast.Ternary() => _ternary(node, context),
    ast.Elvis() => _elvis(node, context),
    ast.TypeReference() => _unsupported(node.start, 'T(${node.typeName})'),
    ast.ConstructorReference() => _unsupported(
      node.start,
      'new ${node.typeName}',
    ),
    ast.FunctionReference() => _unsupported(
      node.start,
      'function call #${node.name}(...)',
    ),
    ast.Selection() => _unsupported(node.start, 'selection .?[...]'),
    ast.Projection() => _unsupported(node.start, 'projection .![...]'),
    ast.InlineList() => _unsupported(node.start, 'inline list {...}'),
    ast.InlineMap() => _unsupported(node.start, 'inline map {...}'),
    ast.Assign() => _unsupported(node.start, 'assignment'),
    ast.IncDec() => _unsupported(node.start, '++ and --'),
    _ => _unsupported(node.start, '${node.runtimeType}'),
  };

  _Value _literal(ast.Literal node) {
    final value = node.value;
    return switch (value) {
      null => _Value(literalNull, provider.nullType),
      final String text => _Value(
        _string(text),
        provider.stringType,
      ),
      final bool flag => _Value(literalBool(flag), provider.boolType),
      final int number => _Value(literalNum(number), provider.intType),
      final double number => _Value(literalNum(number), provider.doubleType),
      _ => throw StateError('Unexpected literal $value'),
    };
  }

  _Value? _variable(ast.VariableReference node, _Context context) {
    switch (node.name) {
      case 'root':
        return context.root ??
            _problem(node.start, "'#root' needs a root object");
      case 'this':
        return context.active ??
            _problem(node.start, "'#this' needs a root object");
    }
    final binding = scope.variables[node.name];
    if (binding == null) {
      return _problem(
        node.start,
        _unknown(
          "Unknown variable '#${node.name}'",
          node.name,
          'variables',
          scope.variables.keys,
          prefix: '#',
        ),
      );
    }
    return _bound(binding);
  }

  _Value? _bean(ast.BeanReference node) {
    if (node.factory) {
      return _unsupported(node.start, 'factory bean reference &${node.name}');
    }
    final resolve = scope.beans;
    final environment = scope.environment;
    final binding = resolve?.call(node.name);
    if (binding == null && node.name == 'environment' && environment != null) {
      return _Value(
        environment,
        provider.objectType,
        _precedenceOf(environment),
        true,
      );
    }
    if (resolve == null) {
      return _unsupported(node.start, 'bean reference @${node.name}');
    }
    if (binding == null) {
      final known = [
        ...scope.beanNames,
        if (environment != null) 'environment',
      ];
      return _problem(
        node.start,
        _unknown(
          "No bean named '${node.name}'",
          node.name,
          'beans',
          known,
        ),
      );
    }
    return _bound(binding);
  }

  // `a.b.c`: each step applies to the value of the previous one, and the
  // arguments of the steps see the object the chain started from.
  _Value? _compound(ast.CompoundExpression node, _Context context) {
    final scoped = _Context(context.root, context.active, context.active);
    var value = _compile(node.children.first, scoped);
    for (final child in node.children.skip(1)) {
      if (value == null) {
        return null;
      }
      value = _compile(child, scoped.withActive(value));
    }
    return value;
  }

  // -------------------------------------------------------------------------
  // Members
  // -------------------------------------------------------------------------

  _Value? _property(ast.PropertyOrFieldReference node, _Context context) {
    final target = context.active;
    if (target == null) {
      return _problem(
        node.start,
        "Property '${node.name}' needs a root object, but the expression "
        'has none',
      );
    }
    if (target.isEnvironment) {
      // The interpreter reads it as a property of the configuration.
      return _unsupported(
        node.start,
        "property '${node.name}' of @environment",
      );
    }
    final receiver = _receiver(
      node.start,
      target,
      "read property '${node.name}'",
      nullSafe: node.nullSafe,
    );
    if (receiver == null) {
      return null;
    }
    final type = receiver.type;
    final name = node.name;
    // A map reads the entry of that name before anything else, so what
    // `m.name` is depends on its keys at run time.
    if (_supertype(type, (t) => t.isDartCoreMap) != null) {
      return _unsupported(node.start, "property '$name' of a Map");
    }
    final getter = type.lookUpGetter(name, library);
    if (getter != null && !getter.isStatic) {
      return _member(receiver, name, getter.returnType);
    }
    if (name == 'name' && _isEnum(type)) {
      return _member(receiver, name, provider.stringType);
    }
    final sample = _sample(type);
    if (const spel.BuiltinPropertyAccessor().canRead(
      _builtinContext,
      sample,
      name,
    )) {
      return _unsupported(
        node.start,
        "Java-style property '$name' of ${_show(type)}",
      );
    }
    if (type.lookUpMethod(name, library) != null) {
      return _problem(
        node.start,
        "'$name' is a method of ${_show(type)}, not a property; "
        'call it as $name(...)',
      );
    }
    return _problem(
      node.start,
      _unknown(
        "No property '$name' on type '${_show(type)}'",
        name,
        'properties',
        _memberNames(type, methods: false),
      ),
    );
  }

  _Value? _method(ast.MethodReference node, _Context context) {
    final target = context.active;
    if (target == null) {
      return _problem(
        node.start,
        "Method '${node.name}' needs a root object, but the expression "
        'has none',
      );
    }
    // The arguments see the object the chain started from.
    final inner = _Context(context.root, context.scopeRoot, context.scopeRoot);
    final arguments = [
      for (final argument in node.arguments) _compile(argument, inner),
    ];
    if (target.isEnvironment) {
      return arguments.contains(null)
          ? null
          : _environmentMethod(node, target, [...arguments.nonNulls]);
    }
    final receiver = _receiver(
      node.start,
      target,
      "call method '${node.name}'",
      nullSafe: node.nullSafe,
    );
    if (receiver == null || arguments.contains(null)) {
      return null;
    }
    final type = receiver.type;
    final name = node.name;
    final method = type.lookUpMethod(name, library);
    if (method != null && !method.isStatic) {
      return _invoke(node, receiver, method, [...arguments.nonNulls]);
    }
    final sample = _sample(type);
    if (const spel.BuiltinMethodResolver().resolve(
          _builtinContext,
          sample,
          name,
          List<Object?>.filled(arguments.length, null),
        ) !=
        null) {
      return _unsupported(
        node.start,
        "Java-style method '$name()' of ${_show(type)}",
      );
    }
    if (type.lookUpGetter(name, library) != null) {
      return _problem(
        node.start,
        "'$name' is a property of ${_show(type)}, not a method; "
        'read it without ()',
      );
    }
    return _problem(
      node.start,
      _unknown(
        "No method '$name' on type '${_show(type)}'",
        name,
        'methods',
        _memberNames(type, properties: false),
      ),
    );
  }

  // `@environment.getProperty(key)` and the other methods the interpreter
  // gives an environment. `getProperty(key, default)` has its default as a
  // named argument in Dart.
  _Value? _environmentMethod(
    ast.MethodReference node,
    _Value environment,
    List<_Value> arguments,
  ) {
    final name = node.name;
    final text = provider.stringType;
    final optionalText = _nullable(text);
    // (the types the arguments must have, the result)
    final (parameters, result, required) = switch (name) {
      'getProperty' => ([text, optionalText], optionalText, 1),
      'getRequiredProperty' => ([text], text, 1),
      'containsProperty' => ([text], provider.boolType, 1),
      'resolvePlaceholders' => ([text], text, 1),
      'resolveRequiredPlaceholders' => ([text], text, 1),
      'getActiveProfiles' ||
      'getDefaultProfiles' ||
      'matchesProfiles' => (<DartType>[], text, -1),
      _ => (<DartType>[], text, -2),
    };
    if (required == -1) {
      return _unsupported(node.start, '@environment.$name()');
    }
    if (required == -2) {
      // The interpreter answers the members every object has.
      if (const spel.BuiltinMethodResolver().resolve(
            _builtinContext,
            Object(),
            name,
            List<Object?>.filled(arguments.length, null),
          ) !=
          null) {
        return _unsupported(
          node.start,
          "Java-style method '$name()' of @environment",
        );
      }
      return _problem(
        node.start,
        _unknown(
          "No method '$name' on @environment",
          name,
          'methods',
          const [
            'getProperty',
            'getRequiredProperty',
            'containsProperty',
            'resolvePlaceholders',
            'resolveRequiredPlaceholders',
            'getActiveProfiles',
            'getDefaultProfiles',
            'matchesProfiles',
          ],
        ),
      );
    }
    if (arguments.length < required || arguments.length > parameters.length) {
      // Only getProperty has an optional argument.
      final wanted = parameters.length == required
          ? '$required argument'
          : 'one or two arguments';
      return _problem(
        node.start,
        "Method '@environment.$name' takes $wanted, but "
        '${arguments.length} ${arguments.length == 1 ? 'was' : 'were'} given',
      );
    }
    for (final (index, argument) in arguments.indexed) {
      if (!types.isAssignableTo(
        argument.type,
        parameters[index],
        strictCasts: true,
      )) {
        return _unsupported(
          node.start,
          "argument ${index + 1} of '@environment.$name': "
          '${_show(argument.type)} is not a ${_show(parameters[index])} (the '
          'interpreter converts arguments)',
        );
      }
    }
    final call = _operand(environment, _pPostfix)
        .property(name)
        .call(
          [for (final argument in arguments.take(1)) argument.code],
          {
            if (arguments.length > 1) 'defaultValue': arguments[1].code,
          },
        );
    return _Value(call, result);
  }

  _Value? _invoke(
    ast.MethodReference node,
    _Receiver receiver,
    MethodElement method,
    List<_Value> arguments,
  ) {
    final name = node.name;
    final type = receiver.type;
    if (_isDivergent(type, name)) {
      return _unsupported(
        node.start,
        "method '$name' of ${_show(type)}: the interpreter's differs from "
        "Dart's",
      );
    }
    if (method.typeParameters.isNotEmpty) {
      return _unsupported(node.start, "generic method '$name'");
    }
    final function = method.type;
    final parameters = function.formalParameters;
    final required = parameters.where((p) => p.isRequiredPositional).length;
    final positional = parameters
        .where((p) => p.isRequiredPositional || p.isOptionalPositional)
        .length;
    final needsNamed = parameters.any((p) => p.isRequiredNamed);
    if (arguments.length < required ||
        arguments.length > positional ||
        needsNamed) {
      final wanted = needsNamed
          ? 'a named argument it cannot be given'
          : required == positional
          ? '$required argument${required == 1 ? '' : 's'}'
          : 'between $required and $positional arguments';
      return _problem(
        node.start,
        "Method '${_show(type)}.$name' takes $wanted, but "
        '${arguments.length} ${arguments.length == 1 ? 'was' : 'were'} given',
      );
    }
    final code = <Expression>[];
    for (final (index, argument) in arguments.indexed) {
      final converted = _argument(argument, parameters[index].type);
      if (converted == null) {
        return _unsupported(
          node.start,
          "argument ${index + 1} of '$name': ${_show(argument.type)} is not "
          'a ${_show(parameters[index].type)} (the interpreter converts '
          'arguments)',
        );
      }
      code.add(converted);
    }
    final result = function.returnType;
    if (result is VoidType || result is NeverType) {
      return _problem(
        node.start,
        "Method '${_show(type)}.$name' returns ${_show(result)}: it has no "
        'value',
      );
    }
    // A double prints as Java's: `7.0` also on the web.
    if (name == 'toString' && arguments.isEmpty && type.isDartCoreDouble) {
      return receiver.safe
          ? _unsupported(node.start, 'toString() of a nullable double')
          : _Value(
              _ops.property('doubleToString').call([receiver.value.code]),
              provider.stringType,
            );
    }
    final target = _receiverCode(receiver.value);
    final call =
        (receiver.safe ? target.nullSafeProperty(name) : target.property(name))
            .call(code);
    return _Value(call, receiver.safe ? _nullable(result) : result);
  }

  // [argument] as the code for a parameter of [parameter], or null when the
  // types do not fit.
  Expression? _argument(_Value argument, DartType parameter) {
    final type = argument.type;
    if (types.isAssignableTo(type, parameter, strictCasts: true)) {
      return argument.code;
    }
    // The interpreter converts an int to a double for a double parameter.
    if (_numeric(type) == _Num.int && parameter.isDartCoreDouble) {
      return _operand(argument, _pPostfix).property('toDouble').call([]);
    }
    return null;
  }

  // Reading [name] of [receiver] with a result of [type].
  _Value _member(_Receiver receiver, String name, DartType type) {
    final target = _receiverCode(receiver.value);
    return _Value(
      receiver.safe ? target.nullSafeProperty(name) : target.property(name),
      receiver.safe ? _nullable(type) : type,
    );
  }

  Expression _receiverCode(_Value value) => _operand(value, _pPostfix);

  // The class of [target] for a member, or null after reporting why not.
  _Receiver? _receiver(
    int position,
    _Value target,
    String action, {
    required bool nullSafe,
  }) {
    final type = target.type;
    final nullable = types.isNullable(type);
    if (type is DynamicType ||
        type is InvalidType ||
        type is NeverType ||
        type is VoidType ||
        type is TypeParameterType ||
        type is FunctionType ||
        type is RecordType ||
        (type is InterfaceType &&
            (type.isDartCoreObject || type.isDartCoreFunction))) {
      _unsupported(
        position,
        '$action of a value of type ${_show(type)}: only the interpreter '
        'knows its members',
      );
      return null;
    }
    if (type is! InterfaceType || type.isDartCoreNull) {
      _problem(position, 'Cannot $action on null');
      return null;
    }
    if (type.element.name == 'FutureOr') {
      _unsupported(position, '$action of a ${_show(type)}');
      return null;
    }
    if (nullable && !nullSafe) {
      _problem(
        position,
        'Cannot $action on ${_show(type)}, which can be null: use ?. '
        '(the interpreter fails on null)',
      );
      return null;
    }
    return _Receiver(
      target,
      types.promoteToNonNull(type) as InterfaceType,
      safe: nullable,
    );
  }

  // `target[key]` on lists, maps and strings.
  _Value? _index(ast.Indexer node, _Context context) {
    final target = context.active;
    if (target == null) {
      return _problem(
        node.start,
        'Indexing needs a root object, but the expression has none',
      );
    }
    if (target.isEnvironment) {
      return _unsupported(node.start, 'index into @environment');
    }
    final receiver = _receiver(
      node.start,
      target,
      'index',
      nullSafe: node.nullSafe,
    );
    final type = receiver?.type;
    final name = node.index;
    // Without the class of the receiver (a value of an unknown type, or one
    // that is reported) an unquoted name may be the key of a map, and it is
    // no property of the root: there is nothing to compile.
    if (receiver == null && name is ast.PropertyOrFieldReference) {
      return null;
    }
    // Like Spring, an unquoted name indexing a map is the key itself, and
    // any other index is evaluated against the root object.
    final isMap =
        type != null && _supertype(type, (t) => t.isDartCoreMap) != null;
    final key = isMap && name is ast.PropertyOrFieldReference
        ? _Value(_string(name.name), provider.stringType)
        : _compile(node.index, context.withActive(context.root));
    if (receiver == null || key == null) {
      return null;
    }
    // `a?.[i]` indexes the value `a` was tested to be.
    final subject = receiver.safe ? _guarded : _receiverCode(receiver.value);
    final inner = _operand(key, 0);
    final Expression code;
    final DartType elementType;
    final list = _supertype(receiver.type, (t) => t.isDartCoreList);
    final map = _supertype(receiver.type, (t) => t.isDartCoreMap);
    if (list != null && _numeric(key.type) == _Num.int) {
      code = _ops.property('listElement').call([subject, inner]);
      elementType = list.typeArguments.single;
    } else if (map != null) {
      code = subject.index(inner);
      elementType = _nullable(map.typeArguments.last);
    } else if (receiver.type.isDartCoreString &&
        _numeric(key.type) == _Num.int) {
      code = _ops.property('stringElement').call([subject, inner]);
      elementType = provider.stringType;
    } else {
      _unsupported(
        node.start,
        'index of type ${_show(key.type)} into ${_show(receiver.type)}',
      );
      return null;
    }
    if (!receiver.safe) {
      return _Value(code, elementType);
    }
    // Null for null, without evaluating the index.
    final guarded = CodeExpression(
      Block.of([
        const Code('(switch ('),
        receiver.value.code.code,
        const Code(r') { final spel$target? => '),
        code.code,
        const Code(', _ => null })'),
      ]),
    );
    return _Value(guarded, _nullable(elementType));
  }

  // The value `a?.[i]` tested to be non-null.
  static final Expression _guarded = refer(r'spel$target');

  // -------------------------------------------------------------------------
  // Operators
  // -------------------------------------------------------------------------

  _Value? _unaryOperator(ast.UnaryOperator node, _Context context) {
    final operand = _compile(node.operand, context);
    if (operand == null) {
      return null;
    }
    switch (node.kind) {
      case ast.UnaryKind.not:
        return _Value(
          _operand(_condition(operand), _pUnary, right: true).negate(),
          provider.boolType,
          _pUnary,
        );
      case ast.UnaryKind.minus:
        if (_numeric(operand.type) == null) {
          return _unsupported(
            node.start,
            'unary - on ${_show(operand.type)}',
          );
        }
        return _Value(
          CodeExpression(
            Block.of([
              const Code('-'),
              _operand(operand, _pUnary, right: true).code,
            ]),
          ),
          operand.type,
          _pUnary,
        );
      case ast.UnaryKind.plus:
        if (_numeric(operand.type) == null) {
          return _unsupported(
            node.start,
            'unary + on ${_show(operand.type)}',
          );
        }
        return operand;
    }
  }

  // [value] as a `bool`: `SpelOperations.toBool` unless it is one already
  // (it converts `'true'` and fails on null, like the interpreter).
  _Value _condition(_Value value) {
    final type = value.type;
    if (type.isDartCoreBool && !types.isNullable(type)) {
      return value;
    }
    return _Value(
      _ops.property('toBool').call([value.code]),
      provider.boolType,
    );
  }

  _Value? _ternary(ast.Ternary node, _Context context) {
    final condition = _compile(node.condition, context);
    final whenTrue = _compile(node.whenTrue, context);
    final whenFalse = _compile(node.whenFalse, context);
    if (condition == null || whenTrue == null || whenFalse == null) {
      return null;
    }
    if (_mixesReals(whenTrue.type, whenFalse.type)) {
      return _unsupported(
        node.start,
        'a conditional with a double and a non-double branch',
      );
    }
    // `?:` of Dart nests to the right, so a conditional that is the test
    // needs parentheses: `(a ? b : c) ? d : e`.
    final test = _operand(_condition(condition), _pConditional, right: true);
    return _Value(
      test.conditional(
        _operand(whenTrue, _pConditional),
        _operand(whenFalse, _pConditional, right: true),
      ),
      _same(whenTrue.type, whenFalse.type),
      _pConditional,
    );
  }

  // `a ?: b`: b when a is null or an empty string.
  _Value? _elvis(ast.Elvis node, _Context context) {
    final value = _compile(node.value, context);
    final fallback = _compile(node.fallback, context);
    if (value == null || fallback == null) {
      return null;
    }
    final present = _nonNull(value.type);
    if (_mixesReals(present, fallback.type)) {
      return _unsupported(
        node.start,
        'an elvis with a double and a non-double side',
      );
    }
    final result = _same(present, fallback.type);
    final nullable = types.isNullable(value.type);
    final mayBeText = types.isSubtypeOf(provider.stringType, present);
    if (!mayBeText) {
      // Cannot be an empty string: null is the only case.
      return nullable
          ? _Value(
              _operand(value, _pIfNull).ifNullThen(
                _operand(fallback, _pIfNull, right: true),
              ),
              result,
              _pIfNull,
            )
          : value;
    }
    final empty = nullable ? "null || ''" : "''";
    final keep = nullable ? 'final text? => text' : 'final text => text';
    final code = CodeExpression(
      Block.of([
        const Code('(switch ('),
        value.code.code,
        Code(') { $empty => '),
        fallback.code.code,
        Code(', $keep })'),
      ]),
    );
    return _Value(code, result);
  }

  _Value? _binary(ast.BinaryOperator node, _Context context) {
    // The operator is what the interpreter is needed for; the operands are
    // still compiled, for their problems.
    final interpreted = switch (node.kind) {
      ast.BinaryKind.instanceOf => 'instanceof',
      ast.BinaryKind.matches => 'matches',
      ast.BinaryKind.between => 'between',
      _ => null,
    };
    if (interpreted != null) {
      _unsupported(node.start, interpreted);
    }
    final left = _compile(node.left, context);
    final right = _compile(node.right, context);
    if (left == null || right == null) {
      return null;
    }
    switch (node.kind) {
      case ast.BinaryKind.and:
        return _logical(left, right, and: true);
      case ast.BinaryKind.or:
        return _logical(left, right, and: false);
      case ast.BinaryKind.eq:
        return _equality(left, right, negated: false);
      case ast.BinaryKind.ne:
        return _equality(left, right, negated: true);
      case ast.BinaryKind.lt ||
          ast.BinaryKind.le ||
          ast.BinaryKind.gt ||
          ast.BinaryKind.ge:
        return _relational(node.kind, left, right);
      case ast.BinaryKind.add:
        return _add(node, left, right);
      case ast.BinaryKind.subtract || ast.BinaryKind.multiply:
        return _plain(node, left, right);
      case ast.BinaryKind.divide:
        return _arithmetic(node, left, right, 'divide', 'divideInts', '/');
      case ast.BinaryKind.modulus:
        return _arithmetic(
          node,
          left,
          right,
          'modulus',
          'modulusInts',
          null,
          reals: 'modulusReals',
        );
      case ast.BinaryKind.power:
        return _arithmetic(
          node,
          left,
          right,
          'power',
          'powerInts',
          null,
          reals: 'powerReals',
        );
      case ast.BinaryKind.instanceOf ||
          ast.BinaryKind.matches ||
          ast.BinaryKind.between:
        return null;
    }
  }

  _Value _logical(_Value left, _Value right, {required bool and}) {
    final precedence = and ? _pLogicalAnd : _pLogicalOr;
    final l = _operand(_condition(left), precedence);
    final r = _operand(_condition(right), precedence, right: true);
    return _Value(and ? l.and(r) : l.or(r), provider.boolType, precedence);
  }

  _Value _equality(_Value left, _Value right, {required bool negated}) {
    final l = _equalityKind(left.type);
    final r = _equalityKind(right.type);
    // Dart's `==` is the interpreter's for numbers, texts and booleans
    // among themselves and for null; everything else compares by
    // SpelOperations.equals (collections, comparables).
    if (l == 'null' || r == 'null' || (l != null && l == r)) {
      final a = _operand(left, _pEquality);
      final b = _operand(right, _pEquality, right: true);
      return _Value(
        negated ? a.notEqualTo(b) : a.equalTo(b),
        provider.boolType,
        _pEquality,
      );
    }
    final call = _ops.property('equals').call([left.code, right.code]);
    return negated
        ? _Value(call.negate(), provider.boolType, _pUnary)
        : _Value(call, provider.boolType);
  }

  _Value _relational(ast.BinaryKind kind, _Value left, _Value right) {
    final bothNumbers =
        _numeric(left.type) != null && _numeric(right.type) != null;
    final bothStrings = _isText(left.type) && _isText(right.type);
    final Expression order;
    if (bothNumbers || bothStrings) {
      // The comparator's own `compareTo` for numbers and strings.
      order = _operand(
        left,
        _pPostfix,
      ).property('compareTo').call([right.code]);
    } else {
      order = _ops.property('compare').call([left.code, right.code]);
    }
    final zero = literalNum(0);
    final code = switch (kind) {
      ast.BinaryKind.lt => order.lessThan(zero),
      ast.BinaryKind.le => order.lessOrEqualTo(zero),
      ast.BinaryKind.gt => order.greaterThan(zero),
      _ => order.greaterOrEqualTo(zero),
    };
    return _Value(code, provider.boolType, _pRelational);
  }

  // `+`: numbers add, a text and anything else concatenate.
  _Value? _add(ast.BinaryOperator node, _Value left, _Value right) {
    final l = _numeric(left.type);
    final r = _numeric(right.type);
    if (l != null && r != null) {
      return _plain(node, left, right);
    }
    if (_isText(left.type) || _isText(right.type)) {
      final real = [
        if (left.type.isDartCoreDouble) 'leftReal',
        if (right.type.isDartCoreDouble) 'rightReal',
      ];
      return _Value(
        _ops
            .property('concat')
            .call(
              [left.code, right.code],
              {for (final name in real) name: literalBool(true)},
            ),
        provider.stringType,
      );
    }
    return _unsupported(
      node.start,
      '+ on ${_show(left.type)} and ${_show(right.type)}',
    );
  }

  // `+`, `-` and `*` of two numbers: Dart's, with Dart's result type.
  _Value? _plain(ast.BinaryOperator node, _Value left, _Value right) {
    final l = _numeric(left.type);
    final r = _numeric(right.type);
    if (l == null || r == null) {
      return _unsupported(
        node.start,
        '${_symbol(node.kind)} on ${_show(left.type)} and '
        '${_show(right.type)}',
      );
    }
    final add =
        node.kind == ast.BinaryKind.add || node.kind == ast.BinaryKind.subtract;
    final precedence = add ? _pAdditive : _pMultiplicative;
    final a = _operand(left, precedence);
    final b = _operand(right, precedence, right: true);
    final code = switch (node.kind) {
      ast.BinaryKind.add => a.operatorAdd(b),
      ast.BinaryKind.subtract => a.operatorSubtract(b),
      _ => a.operatorMultiply(b),
    };
    return _Value(code, _arithmeticType(l, r), precedence);
  }

  // `/`, `%` and `^` of two numbers: ints, reals or either.
  _Value? _arithmetic(
    ast.BinaryOperator node,
    _Value left,
    _Value right,
    String generic,
    String ints,
    String? operator, {
    String? reals,
  }) {
    final l = _numeric(left.type);
    final r = _numeric(right.type);
    if (l == null || r == null) {
      return _unsupported(
        node.start,
        '${_symbol(node.kind)} on ${_show(left.type)} and '
        '${_show(right.type)}',
      );
    }
    if (l == _Num.int && r == _Num.int) {
      return _Value(
        _ops.property(ints).call([left.code, right.code]),
        provider.intType,
      );
    }
    final real = l == _Num.double || r == _Num.double;
    if (real && operator != null) {
      // A double operand makes `/` a double division, Dart's `/`.
      return _Value(
        _operand(left, _pMultiplicative).operatorDivide(
          _operand(right, _pMultiplicative, right: true),
        ),
        provider.doubleType,
        _pMultiplicative,
      );
    }
    if (real && reals != null) {
      return _Value(
        _ops.property(reals).call([left.code, right.code]),
        provider.doubleType,
      );
    }
    return _Value(
      _ops.property(generic).call([left.code, right.code]),
      provider.numType,
    );
  }

  // -------------------------------------------------------------------------
  // Types
  // -------------------------------------------------------------------------

  // The kind of a non-nullable number type.
  _Num? _numeric(DartType type) {
    if (type is! InterfaceType || types.isNullable(type)) {
      return null;
    }
    return type.isDartCoreInt
        ? _Num.int
        : type.isDartCoreDouble
        ? _Num.double
        : type.isDartCoreNum
        ? _Num.num
        : null;
  }

  bool _isText(DartType type) =>
      type is InterfaceType && type.isDartCoreString && !types.isNullable(type);

  // Which kind of value `==` compares directly: numbers, texts, booleans,
  // null.
  String? _equalityKind(DartType type) => type.isDartCoreNull
      ? 'null'
      : type.isDartCoreInt || type.isDartCoreDouble || type.isDartCoreNum
      ? 'num'
      : type.isDartCoreString
      ? 'string'
      : type.isDartCoreBool
      ? 'bool'
      : null;

  // Dart's type of `a + b`, `a - b`, `a * b` for numbers.
  DartType _arithmeticType(_Num l, _Num r) => l == _Num.int && r == _Num.int
      ? provider.intType
      : l == _Num.double || (l == _Num.int && r == _Num.double)
      ? provider.doubleType
      : provider.numType;

  // Whether one of the types is a double and the other a number that is
  // not: the interpreter knows a real number that is integral on the web
  // from its static kind, which a common supertype would lose.
  bool _mixesReals(DartType a, DartType b) {
    bool number(DartType t) =>
        t.isDartCoreInt || t.isDartCoreDouble || t.isDartCoreNum;
    return number(a) && number(b) && a.isDartCoreDouble != b.isDartCoreDouble;
  }

  // The type of either of two branches.
  DartType _same(DartType a, DartType b) =>
      a == b ? a : types.leastUpperBound(a, b);

  DartType _nullable(DartType type) =>
      types.leastUpperBound(type, provider.nullType);

  DartType _nonNull(DartType type) => types.promoteToNonNull(type);

  bool _isEnum(InterfaceType type) =>
      type.element is EnumElement ||
      type.allSupertypes.any((t) => t.isDartCoreEnum);

  // The supertype of [type] (or itself) that satisfies [test], with the
  // type arguments [type] gives it.
  InterfaceType? _supertype(
    InterfaceType type,
    bool Function(InterfaceType) test,
  ) {
    for (final candidate in [type, ...type.allSupertypes]) {
      if (test(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  String _show(DartType type) => type.getDisplayString();

  String _symbol(ast.BinaryKind kind) => switch (kind) {
    ast.BinaryKind.add => '+',
    ast.BinaryKind.subtract => '-',
    ast.BinaryKind.multiply => '*',
    ast.BinaryKind.divide => '/',
    ast.BinaryKind.modulus => '%',
    ast.BinaryKind.power => '^',
    _ => kind.name,
  };

  // -------------------------------------------------------------------------
  // The interpreter's builtins
  // -------------------------------------------------------------------------

  // A value of the kind of [type], to ask the interpreter's builtin
  // properties and methods whether they know a name.
  Object _sample(InterfaceType type) {
    if (type.isDartCoreString) {
      return '';
    }
    if (type.isDartCoreInt) {
      return 0;
    }
    if (type.isDartCoreDouble) {
      return 0.0;
    }
    if (type.isDartCoreNum) {
      return 0;
    }
    if (_supertype(type, (t) => t.isDartCoreMap) != null) {
      return <Object?, Object?>{};
    }
    if (_supertype(type, (t) => t.isDartCoreList) != null) {
      return <Object?>[0];
    }
    if (_supertype(type, (t) => t.isDartCoreSet) != null) {
      return <Object?>{0};
    }
    if (_supertype(type, (t) => t.isDartCoreIterable) != null) {
      return <Object?>[0];
    }
    if (type.element.library.isInSdk) {
      switch (type.element.name) {
        case 'DateTime':
          return DateTime(2020);
        case 'Duration':
          return Duration.zero;
        case 'StringBuffer':
          return StringBuffer();
      }
    }
    return Object();
  }

  // Whether the interpreter's builtin [method] of [type] works differently
  // from Dart's.
  bool _isDivergent(InterfaceType type, String method) {
    final kinds = <String>[
      if (_supertype(type, (t) => t.isDartCoreList) != null) 'List',
      if (_supertype(type, (t) => t.isDartCoreSet) != null) 'Set',
      if (_supertype(type, (t) => t.isDartCoreMap) != null) 'Map',
      if (_supertype(type, (t) => t.isDartCoreIterable) != null) 'Iterable',
    ];
    return kinds.any((kind) => _divergentBuiltins[kind]!.contains(method));
  }

  // -------------------------------------------------------------------------
  // Code
  // -------------------------------------------------------------------------

  // The code of a string literal: plain when nothing in it needs escaping,
  // raw otherwise (code_builder's plain form leaves `$` and `\` as they
  // are).
  Expression _string(String text) => _plainText.hasMatch(text)
      ? literalString(text)
      : literalString(text, raw: true);

  static final _plainText = RegExp(r'^[^\\$\x00-\x1f\x7f\u2028\u2029\u0027]*$');

  // The value of a binding the caller supplied.
  _Value _bound(SpelBinding binding) =>
      _Value(binding.read, binding.type, _precedenceOf(binding.read));

  // How tightly the code of the caller binds: names, member accesses, calls
  // and indexing are primaries, anything else (a cast, a conditional) is
  // parenthesized where it is used.
  int _precedenceOf(Expression code) {
    final text = code
        .accept(DartEmitter())
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r' (?=[\[(.])'), '');
    return _isPrimary(text) ? _pPostfix : 0;
  }

  // Whether [text] is one primary: outside brackets and strings only names,
  // dots, `?` and generic arguments.
  static bool _isPrimary(String text) {
    if (text.isEmpty || text.contains('..')) {
      return false;
    }
    var depth = 0;
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      switch (char) {
        case "'" || '"':
          quote = char;
        case '(' || '[' || '{':
          depth++;
        case ')' || ']' || '}':
          depth--;
          if (depth < 0) {
            return false;
          }
        default:
          // `!` is a primary's own only after it (`a!.b`).
          if (depth == 0 &&
              !_primaryChar.hasMatch(char) &&
              !(char == '!' && i > 0)) {
            return false;
          }
      }
    }
    return depth == 0 && quote == null;
  }

  static final _primaryChar = RegExp(r'[\w$.?<>,]');

  // The code of [value] as an operand of an operator of [precedence]:
  // parenthesized when it binds less tightly (or as tightly, on the right
  // of a left-associative operator).
  Expression _operand(_Value value, int precedence, {bool right = false}) =>
      _wrapped(value.code, value.precedence, precedence, right: right);

  Expression _wrapped(
    Expression code,
    int own,
    int precedence, {
    bool right = false,
  }) => own < precedence || (right && own == precedence)
      ? code.parenthesized
      : code;

  // -------------------------------------------------------------------------
  // Messages
  // -------------------------------------------------------------------------

  // The public instance properties and methods of [type] and its
  // supertypes.
  List<String> _memberNames(
    InterfaceType type, {
    bool properties = true,
    bool methods = true,
  }) {
    final names = <String>{};
    for (final candidate in [type, ...type.allSupertypes]) {
      if (candidate.isDartCoreObject) {
        continue;
      }
      if (properties) {
        for (final getter in candidate.getters) {
          if (getter.isPublic && !getter.isStatic) {
            names.add(getter.name ?? '');
          }
        }
      }
      if (methods) {
        for (final method in candidate.methods) {
          final name = method.name ?? '';
          if (method.isPublic &&
              !method.isStatic &&
              !method.isOperator &&
              name != 'noSuchMethod') {
            names.add(name);
          }
        }
      }
    }
    names.removeAll(const {'', 'hashCode', 'runtimeType'});
    return names.toList()..sort();
  }

  // [problem] about the unknown [name], with the closest of [names] as a
  // suggestion and all of them listed as [what] (shown with [prefix]).
  String _unknown(
    String problem,
    String name,
    String what,
    Iterable<String> names, {
    String prefix = '',
  }) {
    final best = closestName(name, names);
    final sorted = names.toList()..sort();
    final suggestion = best == null ? '.' : "; did you mean '$prefix$best'?";
    final available = sorted.isEmpty
        ? ' There are no $what.'
        : ' Available $what: ${sorted.map((n) => '$prefix$n').join(', ')}.';
    return '$problem$suggestion$available';
  }
}
