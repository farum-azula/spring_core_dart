import 'dart:math' as math;

import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/introspection_access.dart';
import 'package:spring_core_dart/src/expression/spel_numbers.dart';
import 'package:spring_core_dart/src/expression/spel_parser_configuration.dart';
import 'package:spring_core_dart/src/expression/spel_patterns.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// Mutable state of one evaluation, like Spring's `ExpressionState`.
///
/// Created by `SpelExpression` for each `getValue` / `setValue` call and
/// passed down the tree. It tracks the *active context object* (what a
/// bare `name` or `method()` applies to, and what `#this` is), the *scope
/// root* (the active object at the start of the current compound
/// expression, against which method arguments are evaluated) and the
/// number of operations performed so far (see
/// `SpelParserConfiguration.maximumOperations`). You only meet it when
/// writing your own [SpelNode]s.
///
/// ```dart
/// final state = ExpressionState(
///   StandardEvaluationContext(),
///   {'n': 2},
///   'n + 1',
/// );
/// state.activeContextObject; // {'n': 2}
/// state.withThis(5, node); // evaluates node with #this == 5
/// ```
///
/// Spring (Java):
/// ```java
/// ExpressionState state = new ExpressionState(context, new TypedValue(root));
/// state.pushActiveContextObject(new TypedValue(element));
/// try {
///   value = node.getValue(state);
/// } finally {
///   state.popActiveContextObject();
/// }
/// ```
final class ExpressionState {
  /// Starts an evaluation of [expressionString] in [context] with [root]
  /// as `#root`, `#this` and the initial active object, under the limits
  /// of [configuration] (the defaults when omitted).
  ExpressionState(
    this.context,
    this.root,
    this.expressionString, [
    SpelParserConfiguration? configuration,
  ]) : configuration = configuration ?? SpelParserConfiguration.withDefaults(),
       _active = [root],
       _scopeRoots = [root];

  /// The evaluation context (accessors, variables, types, ...).
  final EvaluationContext context;

  /// The root object (`#root`) of this evaluation.
  final Object? root;

  /// The expression text, used in error messages.
  final String expressionString;

  /// The parser configuration (limits, auto-grow).
  final SpelParserConfiguration configuration;

  // Two stacks: _active changes at every step of `a.b.c`; _scopeRoots
  // only when a compound expression or `#this`-scope (selection,
  // projection, arguments) starts. pushScope pushes onto both.
  final List<Object?> _active;
  final List<Object?> _scopeRoots;
  int _operations = 0;

  /// The object property and method references apply to.
  Object? get activeContextObject => _active.last;

  /// `#this` at the start of the current compound expression; method
  /// arguments are evaluated against it.
  Object? get scopeRoot => _scopeRoots.last;

  /// Makes [value] the active context object until [popActive].
  void pushActive(Object? value) => _active.add(value);

  /// Restores the previous active context object.
  void popActive() => _active.removeLast();

  /// Starts a new scope with [value] as scope root and active object;
  /// end it with [popScope].
  void pushScope(Object? value) {
    _scopeRoots.add(value);
    _active.add(value);
  }

  /// Ends the scope started by [pushScope].
  void popScope() {
    _scopeRoots.removeLast();
    _active.removeLast();
  }

  /// Evaluates [node] with [value] as `#this`.
  Object? withThis(Object? value, SpelNode node) {
    pushScope(value);
    try {
      return node.getValue(this);
    } finally {
      popScope();
    }
  }

  /// Counts one operation (Spring's `trackOperation`); throws
  /// [SpelMessage.maxOperationsExceeded] when the configured maximum is
  /// exceeded.
  void trackOperation() {
    final maximum = configuration.maximumOperations;
    if (++_operations > maximum) {
      throw SpelEvaluationException(
        SpelMessage.maxOperationsExceeded,
        inserts: [maximum],
        expressionString: expressionString,
      );
    }
  }

  /// The value of variable `#name` (counted as an operation).
  Object? lookupVariable(String name) {
    trackOperation();
    return context.lookupVariable(name);
  }

  /// Assigns `#name` through `EvaluationContext.assignVariable` (counted
  /// as an operation).
  Object? assignVariable(String name, Object? Function() valueSupplier) {
    trackOperation();
    return context.assignVariable(name, valueSupplier);
  }

  /// [operation] on [left] and [right] by the context's
  /// [OperatorOverloader]; throws
  /// [SpelMessage.operatorNotSupportedBetweenTypes] when it does not
  /// handle them.
  Object? operate(
    Operation operation,
    Object? left,
    Object? right,
    int position,
  ) {
    final overloader = context.operatorOverloader;
    if (overloader.overridesOperation(operation, left, right)) {
      trackOperation();
      return overloader.operate(operation, left, right);
    }
    throw error(SpelMessage.operatorNotSupportedBetweenTypes, position, [
      operation.name,
      typeName(left),
      typeName(right),
    ]);
  }

  /// A [SpelEvaluationException] for this expression at [position].
  SpelEvaluationException error(
    SpelMessage code,
    int position, [
    List<Object?> inserts = const [],
    Object? cause,
  ]) => SpelEvaluationException(
    code,
    inserts: inserts,
    cause: cause,
    expressionString: expressionString,
    position: position,
  );

  /// [exception] with this expression and [position] filled in when it
  /// has none (errors from type locators, converters, comparators...).
  SpelEvaluationException locate(
    SpelEvaluationException exception,
    int position,
  ) => exception.expressionString != null && exception.position >= 0
      ? exception
      : SpelEvaluationException(
          exception.messageCode,
          inserts: exception.inserts,
          cause: exception.cause,
          expressionString: exception.expressionString ?? expressionString,
          position: exception.position >= 0 ? exception.position : position,
        );

  /// Runs [body], adding this expression and [position] to a
  /// [SpelEvaluationException] that has none.
  T located<T>(int position, T Function() body) {
    try {
      return body();
    } on SpelEvaluationException catch (error, stackTrace) {
      final located = locate(error, position);
      if (identical(located, error)) {
        rethrow;
      }
      Error.throwWithStackTrace(located, stackTrace);
    }
  }

  /// [value] as a `bool`, converting with the context's type converter
  /// (e.g. `'true'`); `null` and non-convertible values throw
  /// [SpelMessage.typeConversionError], like Spring.
  bool asBool(Object? value, int position) {
    if (value is bool) {
      return value;
    }
    if (value != null && context.typeConverter.canConvert(value, bool)) {
      final converted = located(
        position,
        () => context.typeConverter.convertValue(value, bool),
      );
      if (converted is bool) {
        return converted;
      }
    }
    throw error(SpelMessage.typeConversionError, position, [
      typeName(value),
      'bool',
    ]);
  }

  /// The type name of [value] for messages (`null` for `null`).
  static String typeName(Object? value) =>
      value == null ? 'null' : '${value.runtimeType}';
}

/// A reference that can be read and written (assignment targets), like
/// Spring's `ValueRef`.
///
/// Returned by [SpelNode.getValueRef] for properties, variables and
/// indexed elements; `++`/`--` write through it.
///
/// ```dart
/// final ref = node.getValueRef(state);
/// if (ref.isWritable) {
///   ref.setValue((ref.getValue()! as int) + 1);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// ValueRef ref = node.getValueRef(state);
/// if (ref.isWritable()) {
///   ref.setValue(newValue);
/// }
/// ```
abstract interface class ValueRef {
  /// The current value.
  Object? getValue();

  /// Replaces the value with [value].
  void setValue(Object? value);

  /// Whether [setValue] is supported.
  bool get isWritable;
}

// ValueRef from a getter/setter pair; the closures capture the target that
// was active when the reference was created.
final class _FunctionRef implements ValueRef {
  _FunctionRef(this._get, this._set, {this.isWritable = true});

  final Object? Function() _get;
  final void Function(Object? value) _set;

  @override
  final bool isWritable;

  @override
  Object? getValue() => _get();

  @override
  void setValue(Object? value) => _set(value);
}

// Spring's NullValueRef: what a null-safe step on null refers to. Reads
// give null, writes are ignored.
final class _NullRef implements ValueRef {
  const _NullRef();

  @override
  Object? getValue() => null;

  @override
  void setValue(Object? value) {}

  @override
  bool get isWritable => false;
}

/// A node of the expression tree, like Spring's `SpelNode` /
/// `SpelNodeImpl`.
///
/// `SpelExpressionParser` builds the tree; `SpelExpression.ast` exposes the
/// root. Nodes are immutable and evaluate against an [ExpressionState].
///
/// ```dart
/// final expression =
///     SpelExpressionParser().parseExpression('a + 1') as SpelExpression;
/// final SpelNode ast = expression.ast; // BinaryOperator(add)
/// ast.toString(); // (a add 1)
/// ```
///
/// Spring (Java):
/// ```java
/// SpelExpression expression =
///     (SpelExpression) parser.parseExpression("a + 1");
/// SpelNode ast = expression.getAST(); // OpPlus
/// String text = ast.toStringAST();
/// ```
abstract class SpelNode {
  /// Creates a node starting at [start] in the expression text.
  SpelNode(this.start);

  /// Start position in the expression text.
  final int start;

  // Whether the last value of this node is a real number (a Java double)
  // even when integral. On the web `7.0` is an `int` at run time, so the
  // nodes that know better (real literals and arithmetic, `T(Math)`
  // functions, the branches they pass through) record it here for the
  // operators using the value; see _realValue.
  bool _real = false;

  /// Evaluates this node in [state].
  Object? getValue(ExpressionState state);

  /// Whether this node can be the target of an assignment.
  bool get isAssignable => false;

  /// Whether this node uses safe navigation (`?.`).
  bool get isNullSafe => false;

  /// A reference for `++`/`--` on this node; throws
  /// [SpelMessage.notAssignable] unless [isAssignable].
  ValueRef getValueRef(ExpressionState state) =>
      throw state.error(SpelMessage.notAssignable, start, [toString()]);

  /// Assigns the value from [valueSupplier] to this node and returns it
  /// (Spring's `setValueInternal`): `=` and `Expression.setValue`.
  ///
  /// The target is resolved before the value is computed; nodes that
  /// cannot be assigned throw [SpelMessage.setvalueNotSupported].
  Object? assign(ExpressionState state, Object? Function() valueSupplier) {
    if (!isAssignable) {
      throw state.error(SpelMessage.setvalueNotSupported, start, [runtimeType]);
    }
    final ref = getValueRef(state);
    final value = valueSupplier();
    ref.setValue(value);
    return value;
  }
}

// Whether [value], just computed by [node], is a real number: a `double`
// on the VM; on the web (where an integral double is an `int`) a
// non-integral number, or one [node] knows to be real.
bool _realValue(SpelNode node, Object? value) =>
    value is double && (value is! int || node._real);

// The elements of a list, map or array built by SpEL that hold real
// numbers: on the web an integral double is an `int` at run time, so
// without this `{1.0, 2.0}[0] / 2` would divide as ints there. Holds the
// keys (list indexes, map keys) or [_allElements] (a `double[]`). Only
// integral values need it, so on the VM (where a double is never an
// `int`) nothing is recorded.
final _realElements = Expando<Object>('realElements');
const _allElements = Object();

void _markRealElement(Object collection, Object? key) {
  final marks = _realElements[collection];
  if (marks is Set<Object?>) {
    marks.add(key);
  } else if (marks == null) {
    _realElements[collection] = <Object?>{key};
  }
}

// Whether [value], read from [collection] at [key], is a real number.
bool _isRealElement(Object collection, Object? key, Object? value) {
  if (value is! int) {
    return false;
  }
  final marks = _realElements[collection];
  return identical(marks, _allElements) ||
      (marks is Set<Object?> && marks.contains(key));
}

// Methods of `T(Math)` that return a double in Java whatever the
// arguments; `abs`, `max` and `min` do when an argument is real.
const _realMathMethods = {
  'sqrt', 'cbrt', 'pow', 'exp', 'log', 'log10', 'sin', 'cos', 'tan', //
  'asin', 'acos', 'atan', 'atan2', 'hypot', 'toRadians', 'toDegrees',
  'floor', 'ceil', 'rint', 'signum', 'random',
};

// Whether `target.name(arguments)` returns a Java double.
bool _realResult(
  Object target,
  String name,
  List<SpelNode> arguments,
  List<Object?> values,
) {
  if (name == 'doubleValue' || name == 'floatValue' || name == 'toDouble') {
    return true;
  }
  if (target is! SpelType) {
    return false;
  }
  switch (target.name) {
    case 'Math':
      if (_realMathMethods.contains(name)) {
        return true;
      }
      if (!const {'abs', 'max', 'min'}.contains(name)) {
        return false;
      }
      for (var i = 0; i < arguments.length; i++) {
        if (_realValue(arguments[i], values[i])) {
          return true;
        }
      }
      return false;
    case 'Double' || 'Float' || 'double' || 'float':
      return const {
        'valueOf', 'parseDouble', 'parseFloat', 'parse', 'tryParse', //
        'max', 'min', 'sum',
      }.contains(name);
  }
  return false;
}

// ---------------------------------------------------------------------------
// Literals and inline collections
// ---------------------------------------------------------------------------

/// A literal value: number, string, boolean or `null`.
///
/// Integer literals (`42`, `42L`, `0x7F`) become `int`, real literals
/// (`3.14`, `1e3`, `1.5f`, `2d`) `double`; `true`, `false` and `null` are
/// case-insensitive.
///
/// ```dart
/// SpelExpressionParser().parseExpression("'It''s'").getValue(); // It's
/// SpelExpressionParser().parseExpression('0x7F').getValue(); // 127
/// ```
///
/// Spring (Java):
/// ```java
/// // IntLiteral, LongLiteral, RealLiteral, FloatLiteral, StringLiteral,
/// // BooleanLiteral, NullLiteral
/// parser.parseExpression("'It''s'").getValue(); // It's
/// ```
final class Literal extends SpelNode {
  /// A literal [value] at [start]; [real] for real number literals.
  Literal(super.start, this.value, {this.real = false}) {
    _real = real;
  }

  /// The constant value.
  final Object? value;

  /// Whether this is a real number literal (`7.0`, `2d`, `1.5f`). On the
  /// web an integral real is an `int` at run time; this keeps `7.0 / 2`
  /// a real division there.
  final bool real;

  @override
  Object? getValue(ExpressionState state) => value;

  @override
  String toString() => value is String ? "'$value'" : '$value';
}

/// An inline list, `{1, 2, 3}` (`{}` is an empty list).
///
/// A new mutable `List` is created on each evaluation.
///
/// ```dart
/// SpelExpressionParser().parseExpression('{1, 2, 3}').getValue();
/// // [1, 2, 3]
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.InlineList
/// List<?> numbers = (List<?>) parser.parseExpression("{1, 2, 3}")
///     .getValue(); // unmodifiable when all items are literals
/// ```
final class InlineList extends SpelNode {
  /// A list of [items] at [start].
  InlineList(super.start, this.items);

  /// The item expressions, in order.
  final List<SpelNode> items;

  @override
  Object? getValue(ExpressionState state) {
    final list = <Object?>[];
    for (final item in items) {
      final value = item.getValue(state);
      if (item._real && value is int) {
        _markRealElement(list, list.length);
      }
      list.add(value);
    }
    return list;
  }

  @override
  String toString() => '{${items.join(',')}}';
}

/// An inline map, `{name: 'Ada', 'year': 1815}` (`{:}` is an empty map).
///
/// An unquoted key is taken as its name (not evaluated), like Spring.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("{name: 'Ada', 'year': 1815}")
///     .getValue(); // {name: Ada, year: 1815}
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.InlineMap
/// Map<?, ?> map = (Map<?, ?>) parser
///     .parseExpression("{name: 'Ada', 'year': 1815}").getValue();
/// ```
final class InlineMap extends SpelNode {
  /// A map of key/value [entries] at [start].
  InlineMap(super.start, this.entries);

  /// The key and value expressions, in order.
  final List<(SpelNode, SpelNode)> entries;

  @override
  Object? getValue(ExpressionState state) {
    final map = <Object?, Object?>{};
    for (final (key, value) in entries) {
      // An unquoted key is its own name, like Spring.
      final k = key is PropertyOrFieldReference
          ? key.name
          : key.getValue(state);
      final v = value.getValue(state);
      if (value._real && v is int) {
        _markRealElement(map, k);
      }
      map[k] = v;
    }
    return map;
  }

  @override
  String toString() => '{${entries.map((e) => '${e.$1}:${e.$2}').join(',')}}';
}

// ---------------------------------------------------------------------------
// References
// ---------------------------------------------------------------------------

/// A property read or written on the active object: `name`, `a.name`,
/// `a?.name`.
///
/// Properties of `SpelType`s are static fields (`T(Math).PI`); otherwise
/// the context's property accessors are asked in order. Without
/// reflection, user classes need an accessor such as
/// `FunctionPropertyAccessor` or `IntrospectionPropertyAccessor`.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression('user.name')
///     .getValue(null, {'user': {'name': 'Ada'}}); // Ada
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.PropertyOrFieldReference
/// parser.parseExpression("user.name").getValue(context);
/// ```
final class PropertyOrFieldReference extends SpelNode {
  /// A reference to property [name]; [nullSafe] for `?.name`.
  PropertyOrFieldReference(super.start, this.name, {this.nullSafe = false});

  /// The property name.
  final String name;

  /// Whether this is `?.name` (yields `null` on a `null` target).
  final bool nullSafe;

  @override
  bool get isNullSafe => nullSafe;

  @override
  bool get isAssignable => true;

  @override
  Object? getValue(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(SpelMessage.propertyOrFieldNotReadableOnNull, start, [
        name,
      ]);
    }
    return _read(state, target);
  }

  // Static fields of a T(...) type win; then the first accessor whose
  // canRead says yes. Non-SpEL errors from accessors are wrapped.
  Object? _read(ExpressionState state, Object target) {
    if (target is SpelType) {
      final field = target.staticFields[name];
      if (field != null) {
        state.trackOperation();
        return field();
      }
    }
    final context = state.context;
    for (final accessor in context.propertyAccessors) {
      if (accessor.canRead(context, target, name)) {
        state.trackOperation();
        try {
          return accessor.read(context, target, name);
        } on SpelEvaluationException catch (error) {
          throw state.locate(error, start);
        } catch (error) {
          throw state.error(SpelMessage.exceptionDuringPropertyRead, start, [
            name,
            _messageOf(error),
          ], error);
        }
      }
    }
    throw state.error(SpelMessage.propertyOrFieldNotReadable, start, [
      name,
      target is SpelType ? target : target.runtimeType,
    ]);
  }

  void _write(ExpressionState state, Object target, Object? value) {
    final context = state.context;
    for (final accessor in context.propertyAccessors) {
      if (accessor.canWrite(context, target, name)) {
        state.trackOperation();
        try {
          accessor.write(context, target, name, value);
        } on SpelEvaluationException catch (error) {
          throw state.locate(error, start);
        } catch (error) {
          // E.g. a TypeError writing a String into a Map<String, int>.
          throw state.error(SpelMessage.exceptionDuringPropertyWrite, start, [
            name,
            _messageOf(error),
          ], error);
        }
        return;
      }
    }
    throw state.error(SpelMessage.propertyOrFieldNotWritable, start, [
      name,
      target.runtimeType,
    ]);
  }

  @override
  ValueRef getValueRef(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return const _NullRef();
      }
      throw state.error(SpelMessage.propertyOrFieldNotWritableOnNull, start, [
        name,
      ]);
    }
    final context = state.context;
    return _FunctionRef(
      () => _read(state, target),
      (value) => _write(state, target, value),
      isWritable: context.propertyAccessors.any(
        (a) => a.canWrite(context, target, name),
      ),
    );
  }

  // Auto-grow (SpelParserConfiguration.autoGrowNullReferences): replaces
  // a null property followed by `.x` or `[i]` with a new object, when an
  // accessor knows the property type.
  Object? _autoGrow(ExpressionState state, Object? target) {
    if (target == null) {
      return null;
    }
    final context = state.context;
    for (final accessor in context.propertyAccessors) {
      if (accessor is IntrospectionPropertyAccessor &&
          accessor.canWrite(context, target, name)) {
        final created = accessor.newValue(target, name);
        if (created == null) {
          break;
        }
        state.trackOperation();
        _write(state, target, created);
        return _read(state, target);
      }
    }
    throw state.error(SpelMessage.unableToDynamicallyCreateObject, start, [
      name,
    ]);
  }

  @override
  String toString() => name;
}

/// A method call on the active object: `name(args)`, `a.name(args)`,
/// `a?.name(args)`.
///
/// Arguments are evaluated against the scope root (not the target);
/// static methods of `SpelType`s are tried first, then the context's
/// method resolvers in order. Exceptions thrown by the method propagate
/// unchanged, like Spring; an `AccessException` from an executor is
/// reported as [SpelMessage.exceptionDuringMethodInvocation].
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("'abc'.substring(1, 2)")
///     .getValue(); // b
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.MethodReference
/// parser.parseExpression("'abc'.substring(1, 2)").getValue(); // b
/// ```
final class MethodReference extends SpelNode {
  /// A call of method [name] with [arguments]; [nullSafe] for `?.`.
  MethodReference(
    super.start,
    this.name,
    this.arguments, {
    this.nullSafe = false,
  });

  /// The method name.
  final String name;

  /// The argument expressions.
  final List<SpelNode> arguments;

  /// Whether this is `?.name(...)` (yields `null` on a `null` target).
  final bool nullSafe;

  @override
  bool get isNullSafe => nullSafe;

  @override
  Object? getValue(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(SpelMessage.methodCallOnNullObjectNotAllowed, start, [
        '$name()',
      ]);
    }
    // Arguments see the scope root as #this: in `a.b(#this)` the argument
    // is the object `a` was read from, not `a` itself.
    final args = [
      for (final argument in arguments)
        state.withThis(state.scopeRoot, argument),
    ];
    final context = state.context;
    final resolvers = [
      if (target is SpelType) const SpelTypeMethodResolver(),
      ...context.methodResolvers,
    ];
    final targetType = target is SpelType ? target : target.runtimeType;
    for (final resolver in resolvers) {
      final MethodExecutor? executor;
      try {
        executor = resolver.resolve(context, target, name, args);
      } on SpelEvaluationException catch (error) {
        throw state.locate(error, start);
      } on AccessException catch (error) {
        throw state.error(SpelMessage.problemLocatingMethod, start, [
          _signature(args),
          targetType,
        ], error);
      }
      if (executor != null) {
        state.trackOperation();
        try {
          final result = executor(context, target, args);
          _real = _realResult(target, name, arguments, args);
          return result;
        } on SpelEvaluationException catch (error, stackTrace) {
          Error.throwWithStackTrace(state.locate(error, start), stackTrace);
        } on AccessException catch (error) {
          throw state.error(
            SpelMessage.exceptionDuringMethodInvocation,
            start,
            [name, targetType, error.message],
            error,
          );
        }
      }
    }
    throw state.error(SpelMessage.methodNotFound, start, [
      _signature(args),
      targetType,
    ]);
  }

  String _signature(List<Object?> args) =>
      '$name(${args.map(ExpressionState.typeName).join(',')})';

  @override
  String toString() => '$name(${arguments.join(',')})';
}

/// A variable: `#name`, plus the special `#this` (current element or
/// active object) and `#root` (the root object).
///
/// Unset variables evaluate to `null`. `#name = value` and `#name++`
/// assign through `EvaluationContext.assignVariable` (forbidden in a
/// `SimpleEvaluationContext`); `#this` and `#root` are read-only.
///
/// ```dart
/// final context = StandardEvaluationContext()..setVariable('n', 2);
/// SpelExpressionParser().parseExpression('#n * 10').getValue(context);
/// // 20
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.VariableReference
/// context.setVariable("n", 2);
/// parser.parseExpression("#n * 10").getValue(context); // 20
/// ```
final class VariableReference extends SpelNode {
  /// A reference to variable [name] (without `#`).
  VariableReference(super.start, this.name);

  /// The variable name, `this` or `root`.
  final String name;

  @override
  bool get isAssignable => name != 'this' && name != 'root';

  @override
  Object? getValue(ExpressionState state) => switch (name) {
    'this' => state.activeContextObject,
    'root' => state.root,
    _ => state.lookupVariable(name),
  };

  @override
  ValueRef getValueRef(ExpressionState state) {
    if (!isAssignable) {
      return super.getValueRef(state);
    }
    return _FunctionRef(
      () => getValue(state),
      (value) =>
          state.located(start, () => state.assignVariable(name, () => value)),
    );
  }

  @override
  Object? assign(ExpressionState state, Object? Function() valueSupplier) {
    if (!isAssignable) {
      throw state.error(SpelMessage.notAssignable, start, [toString()]);
    }
    return state.located(
      start,
      () => state.assignVariable(name, valueSupplier),
    );
  }

  @override
  String toString() => '#$name';
}

/// A call of a registered function: `#name(args)`.
///
/// The variable `#name` must hold a Dart `Function` or a
/// `VarargsFunction` (see `StandardEvaluationContext.registerFunction`).
/// Anything the function throws is reported as
/// [SpelMessage.exceptionDuringFunctionCall] with the error as `cause`,
/// like Spring.
///
/// ```dart
/// final context = StandardEvaluationContext()
///   ..registerFunction('twice', (int n) => n * 2);
/// SpelExpressionParser().parseExpression('#twice(21)').getValue(context);
/// // 42
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.FunctionReference
/// context.registerFunction("twice",
///     MathUtils.class.getDeclaredMethod("twice", int.class));
/// parser.parseExpression("#twice(21)").getValue(context); // 42
/// ```
final class FunctionReference extends SpelNode {
  /// A call of function [name] with [arguments].
  FunctionReference(super.start, this.name, this.arguments);

  /// The function's variable name (without `#`).
  final String name;

  /// The argument expressions.
  final List<SpelNode> arguments;

  @override
  Object? getValue(ExpressionState state) {
    final function = state.lookupVariable(name);
    if (function == null) {
      throw state.error(SpelMessage.functionNotDefined, start, [name]);
    }
    if (function is! Function && function is! VarargsFunction) {
      throw state.error(SpelMessage.functionReferenceCannotBeInvoked, start, [
        name,
        function.runtimeType,
      ]);
    }
    final args = [
      for (final argument in arguments)
        state.withThis(state.scopeRoot, argument),
    ];
    if (!VarargsFunction.accepts(function, args.length)) {
      throw state.error(
        SpelMessage.incorrectNumberOfArgumentsToFunction,
        start,
        [name, args.length, VarargsFunction.minimumArity(function) ?? '?'],
      );
    }
    state.trackOperation();
    final converted = VarargsFunction.convertArguments(
      function,
      args,
      state.context.typeConverter,
    );
    try {
      return VarargsFunction.apply(function, converted);
    } on SpelEvaluationException catch (error) {
      throw state.locate(error, start);
    } catch (error) {
      throw state.error(SpelMessage.exceptionDuringFunctionCall, start, [
        name,
        _messageOf(error),
      ], error);
    }
  }

  @override
  String toString() => '#$name(${arguments.join(',')})';
}

/// Indexing: `list[0]`, `map['key']`, `map[key]`, `'text'[0]`,
/// `obj['property']`, `a?.[0]`.
///
/// The index is evaluated against the root object, like Spring. Lists and
/// maps are readable and writable; strings are read-only; other targets
/// go to the context's `IndexAccessor`s, then iterables (read-only), then
/// a string index on any other object reads that property. An unquoted
/// name indexing a map is the key itself. With
/// `SpelParserConfiguration.autoGrowCollections`, lists grow (with
/// `null`s) when indexed past their end.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("items[1] + scores['ada']")
///     .getValue(null, {
///       'items': [1, 2],
///       'scores': {'ada': 10},
///     }); // 12
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Indexer
/// parser.parseExpression("items[1] + scores['ada']").getValue(context);
/// ```
final class Indexer extends SpelNode {
  /// An index access with [index]; [nullSafe] for `?.[...]`.
  Indexer(super.start, this.index, {this.nullSafe = false});

  /// The index expression.
  final SpelNode index;

  /// Whether this is `?.[...]` (yields `null` on a `null` target).
  final bool nullSafe;

  @override
  bool get isNullSafe => nullSafe;

  @override
  bool get isAssignable => true;

  @override
  Object? getValue(ExpressionState state) {
    _real = false;
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(SpelMessage.cannotIndexIntoNullValue, start);
    }
    return _ref(state, target).getValue();
  }

  @override
  ValueRef getValueRef(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return const _NullRef();
      }
      throw state.error(SpelMessage.cannotIndexIntoNullValue, start);
    }
    return _ref(state, target);
  }

  // Runs a write into [target], turning Dart errors into SpEL ones: a
  // TypeError (wrong element type for a typed List or Map) is a type
  // conversion error, an UnsupportedError (unmodifiable collection) means
  // the element is not assignable.
  void _store(
    ExpressionState state,
    Object target,
    Object? value,
    void Function() write,
  ) {
    state.trackOperation();
    try {
      write();
    } on TypeError catch (error) {
      throw state.error(SpelMessage.typeConversionError, start, [
        ExpressionState.typeName(value),
        target.runtimeType,
      ], error);
    } on UnsupportedError catch (error) {
      throw state.error(SpelMessage.notAssignable, start, [toString()], error);
    }
  }

  Object? _key(ExpressionState state, Object target) {
    // Like Spring, an unquoted name indexing a map is the key itself.
    if (target is Map && index is PropertyOrFieldReference) {
      return (index as PropertyOrFieldReference).name;
    }
    // Like Spring, the index is evaluated against the root object.
    state.pushActive(state.root);
    try {
      return index.getValue(state);
    } finally {
      state.popActive();
    }
  }

  ValueRef _ref(ExpressionState state, Object target) {
    final key = _key(state, target);
    final context = state.context;
    switch (target) {
      case Map<Object?, Object?>():
        return _FunctionRef(() {
          state.trackOperation();
          final value = target[key];
          _real = _isRealElement(target, key, value);
          return value;
        }, (value) => _store(state, target, value, () => target[key] = value));
      case List<Object?>():
        final i = _intIndex(state, key);
        return _FunctionRef(
          () {
            _grow(state, target, i, reading: true);
            state.trackOperation();
            final value = target[i];
            _real = _isRealElement(target, i, value);
            return value;
          },
          (value) {
            if (i >= target.length && state.configuration.autoGrowCollections) {
              _grow(state, target, i, reading: false);
              _store(state, target, value, () => target.add(value));
              return;
            }
            _grow(state, target, i, reading: false);
            _store(state, target, value, () => target[i] = value);
          },
        );
      case String():
        final i = _intIndex(state, key);
        return _FunctionRef(
          () {
            if (i >= target.length) {
              throw state.error(SpelMessage.stringIndexOutOfBounds, start, [
                target.length,
                i,
              ]);
            }
            state.trackOperation();
            return target[i];
          },
          (_) => throw state.error(
            SpelMessage.indexingNotSupportedForType,
            start,
            ['String'],
          ),
          isWritable: false,
        );
    }
    for (final accessor in context.indexAccessors) {
      final readable = accessor.canRead(context, target, key);
      final writable = accessor.canWrite(context, target, key);
      if (readable || writable) {
        return _FunctionRef(
          () {
            if (!readable) {
              throw state.error(
                SpelMessage.indexingNotSupportedForType,
                start,
                [target.runtimeType],
              );
            }
            state.trackOperation();
            try {
              return accessor.read(context, target, key);
            } on SpelEvaluationException catch (error) {
              throw state.locate(error, start);
            } catch (error) {
              throw state.error(SpelMessage.exceptionDuringIndexRead, start, [
                key,
                target.runtimeType,
              ], error);
            }
          },
          (value) {
            if (!writable) {
              throw state.error(
                SpelMessage.indexingNotSupportedForType,
                start,
                [target.runtimeType],
              );
            }
            state.trackOperation();
            try {
              accessor.write(context, target, key, value);
            } on SpelEvaluationException catch (error) {
              throw state.locate(error, start);
            } catch (error) {
              throw state.error(SpelMessage.exceptionDuringIndexWrite, start, [
                key,
                target.runtimeType,
              ], error);
            }
          },
          isWritable: writable,
        );
      }
    }
    if (target is Iterable<Object?>) {
      final i = _intIndex(state, key);
      return _FunctionRef(
        () {
          if (i >= target.length) {
            throw _outOfBounds(state, i, target.length);
          }
          state.trackOperation();
          return target.elementAt(i);
        },
        (_) => throw state.error(
          SpelMessage.indexingNotSupportedForType,
          start,
          [target.runtimeType],
        ),
        isWritable: false,
      );
    }
    if (key is String) {
      // obj['name'] is property access.
      state.pushActive(target);
      try {
        return PropertyOrFieldReference(start, key).getValueRef(state);
      } finally {
        state.popActive();
      }
    }
    throw state.error(SpelMessage.indexingNotSupportedForType, start, [
      target.runtimeType,
    ]);
  }

  // Index past the end of a list: out of bounds, or (auto-grow) the list
  // is filled with nulls up to [i] for a read, or up to [i] - 1 before a
  // write appends the value.
  void _grow(
    ExpressionState state,
    List<Object?> target,
    int i, {
    required bool reading,
  }) {
    if (i < target.length) {
      return;
    }
    final configuration = state.configuration;
    if (!configuration.autoGrowCollections) {
      throw _outOfBounds(state, i, target.length);
    }
    if (i >= configuration.maximumAutoGrowSize) {
      throw state.error(SpelMessage.unableToGrowCollection, start);
    }
    try {
      while (target.length < (reading ? i + 1 : i)) {
        state.trackOperation();
        target.add(null);
      }
    } on TypeError catch (error) {
      throw state.error(
        SpelMessage.unableToGrowCollectionUnknownElementType,
        start,
        const [],
        error,
      );
    } on UnsupportedError catch (error) {
      throw state.error(
        SpelMessage.unableToGrowCollection,
        start,
        const [],
        error,
      );
    }
  }

  // Ints, integral doubles and anything the type converter turns into an
  // int ('2'); negative indexes are out of bounds.
  int _intIndex(ExpressionState state, Object? key) {
    final int converted;
    if (key is int) {
      converted = key;
    } else if (key is num && key == key.truncate()) {
      converted = key.toInt();
    } else {
      final value = key == null
          ? null
          : state.located(
              start,
              () => state.context.typeConverter.convertValue(key, int),
            );
      if (value is! int) {
        throw state.error(SpelMessage.typeConversionError, start, [
          ExpressionState.typeName(key),
          'int',
        ]);
      }
      converted = value;
    }
    if (converted < 0) {
      throw state.error(SpelMessage.collectionIndexOutOfBounds, start, [
        '?',
        converted,
      ]);
    }
    return converted;
  }

  SpelEvaluationException _outOfBounds(
    ExpressionState state,
    int i,
    int length,
  ) => state.error(SpelMessage.collectionIndexOutOfBounds, start, [length, i]);

  @override
  String toString() => '${nullSafe ? '?.' : ''}[$index]';
}

/// Which matches a [Selection] returns.
///
/// ```dart
/// // '.?[...]' -> all, '.^[...]' -> first, '.$[...]' -> last
/// SpelExpressionParser().parseExpression(r'{1, 2, 3}.$[#this < 3]')
///     .getValue(); // 2
/// ```
///
/// Spring (Java):
/// ```java
/// // Selection.ALL, Selection.FIRST, Selection.LAST
/// parser.parseExpression("{1, 2, 3}.$[#this < 3]").getValue(); // 2
/// ```
enum SelectionKind {
  /// `.?[...]`: every match, as a list or map.
  all,

  /// `.^[...]`: the first match, or `null`.
  first,

  /// `.$[...]`: the last match, or `null`.
  last,
}

/// Collection selection: `list.?[cond]`, `list.^[cond]`, `list.$[cond]`,
/// `a?.?[cond]`.
///
/// [condition] is evaluated with each element as `#this` (a `MapEntry`
/// for maps, with `key` and `value` properties) and must yield a `bool`
/// (no conversion, like Spring). Selecting all gives a list for any
/// iterable (also a set) and a map for a map; the first or last match of
/// a map is a one-entry map, and `null` when nothing matches.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression('list.?[#this > 2]')
///     .getValue(null, {'list': [1, 2, 3, 4]}); // [3, 4]
/// SpelExpressionParser()
///     .parseExpression('{a: 1, b: 5}.?[value > 2]')
///     .getValue(); // {b: 5}
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Selection
/// parser.parseExpression("list.?[#this > 2]").getValue(context);
/// ```
final class Selection extends SpelNode {
  /// A selection of [kind] filtering by [condition]; [nullSafe] for
  /// `?.?[...]`.
  Selection(super.start, this.kind, this.condition, {this.nullSafe = false});

  /// Whether all, the first or the last match is returned.
  final SelectionKind kind;

  /// The boolean filter, evaluated per element.
  final SpelNode condition;

  /// Whether this is null-safe (yields `null` on a `null` target).
  final bool nullSafe;

  @override
  bool get isNullSafe => nullSafe;

  @override
  Object? getValue(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(SpelMessage.invalidTypeForSelection, start, ['null']);
    }
    bool matches(Object? element) {
      final result = state.withThis(element, condition);
      if (result is! bool) {
        throw state.error(
          SpelMessage.resultOfSelectionCriteriaIsNotBoolean,
          condition.start,
        );
      }
      if (result) {
        state.trackOperation();
      }
      return result;
    }

    switch (target) {
      case Map<Object?, Object?>():
        state.trackOperation();
        final selected = <Object?, Object?>{};
        MapEntry<Object?, Object?>? last;
        for (final entry in target.entries) {
          if (matches(entry)) {
            if (kind == SelectionKind.first) {
              return {entry.key: entry.value};
            }
            selected[entry.key] = entry.value;
            last = entry;
          }
        }
        return switch (kind) {
          SelectionKind.all => selected,
          _ => last == null ? null : {last.key: last.value},
        };
      case Iterable<Object?>():
        state.trackOperation();
        final keep = <bool>[];
        Object? last;
        for (final element in target) {
          final selected = matches(element);
          if (selected) {
            if (kind == SelectionKind.first) {
              return element;
            }
            last = element;
          }
          keep.add(selected);
        }
        if (kind != SelectionKind.all) {
          return last; // The last match, or null (also for `^[` without).
        }
        // A new list (Spring's ArrayList) with the element type of the
        // source: selecting from a List<int> gives a List<int>.
        var i = 0;
        return target.where((_) => keep[i++]).toList();
      default:
        throw state.error(SpelMessage.invalidTypeForSelection, start, [
          target.runtimeType,
        ]);
    }
  }

  @override
  String toString() =>
      '${switch (kind) {
        SelectionKind.all => '?',
        SelectionKind.first => '^',
        SelectionKind.last => r'$',
      }}[$condition]';
}

/// Collection projection: `list.![expr]`, `a?.![expr]`.
///
/// [expression] is evaluated with each element as `#this` (a `MapEntry`
/// for maps); the results form a new list.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression('users.![name]')
///     .getValue(null, {
///       'users': [
///         {'name': 'Ada'},
///         {'name': 'Bob'},
///       ],
///     }); // [Ada, Bob]
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Projection
/// parser.parseExpression("users.![name]").getValue(context);
/// ```
final class Projection extends SpelNode {
  /// A projection mapping each element through [expression]; [nullSafe]
  /// for `?.![...]`.
  Projection(super.start, this.expression, {this.nullSafe = false});

  /// The expression applied to each element.
  final SpelNode expression;

  /// Whether this is null-safe (yields `null` on a `null` target).
  final bool nullSafe;

  @override
  bool get isNullSafe => nullSafe;

  @override
  Object? getValue(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(SpelMessage.projectionNotSupportedOnType, start, [
        'null',
      ]);
    }
    final Iterable<Object?> elements = switch (target) {
      Map<Object?, Object?>() => target.entries,
      Iterable<Object?>() => target,
      _ => throw state.error(SpelMessage.projectionNotSupportedOnType, start, [
        target.runtimeType,
      ]),
    };
    state.trackOperation();
    return [for (final element in elements) _project(state, element)];
  }

  Object? _project(ExpressionState state, Object? element) {
    state.trackOperation();
    return state.withThis(element, expression);
  }

  @override
  String toString() => '![$expression]';
}

/// `a.b.c`: each part is evaluated against the previous result.
///
/// Safe navigation applies per step, like Spring 6.2: in `a?.b.c` a `null`
/// `a` makes `a?.b` `null`, and `.c` then fails on `null`; write
/// `a?.b?.c` to be null-safe throughout.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// parser.parseExpression('user.address.city').getValue(null, {
///   'user': {
///     'address': {'city': 'London'},
///   },
/// }); // London
/// parser
///     .parseExpression('user?.address?.city')
///     .getValue(null, {'user': null}); // null
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.CompoundExpression
/// parser.parseExpression("user?.address?.city").getValue(context);
/// ```
final class CompoundExpression extends SpelNode {
  /// A chain of [children] (at least two), evaluated left to right.
  CompoundExpression(super.start, this.children);

  /// The parts of the chain.
  final List<SpelNode> children;

  @override
  bool get isAssignable => children.last.isAssignable;

  @override
  Object? getValue(ExpressionState state) {
    _real = false;
    return _inScope(state, () {
      final value = children.last.getValue(state);
      _real = children.last._real;
      return value;
    }, () => null);
  }

  @override
  ValueRef getValueRef(ExpressionState state) => _inScope(
    state,
    () => children.last.getValueRef(state),
    () => const _NullRef(),
  );

  /// Evaluates all children but the last, then [last] with the result as
  /// the active object; [shortCircuit] when a `null` meets a `?.` step.
  T _inScope<T>(
    ExpressionState state,
    T Function() last,
    T Function() shortCircuit,
  ) {
    // The object the chain starts from becomes the scope root, so
    // arguments inside the chain are evaluated against it.
    state.pushScope(state.activeContextObject);
    try {
      // The object the previous child was evaluated on, for auto-grow.
      var owner = state.activeContextObject;
      var value = children.first.getValue(state);
      for (var i = 1; i < children.length; i++) {
        final child = children[i];
        final previous = children[i - 1];
        if (value == null) {
          // Safe navigation (Spring 6.2): a null before a `?.` step ends
          // the whole chain; later steps are not evaluated, even without
          // `?.`.
          if (child.isNullSafe) {
            return shortCircuit();
          }
          if (previous is PropertyOrFieldReference &&
              state.configuration.autoGrowNullReferences &&
              (child is Indexer || child is PropertyOrFieldReference)) {
            value = previous._autoGrow(state, owner);
          }
        }
        owner = value;
        state.pushActive(value);
        try {
          if (i == children.length - 1) {
            return last();
          }
          value = child.getValue(state);
        } finally {
          state.popActive();
        }
      }
      throw StateError('A compound expression has at least two parts');
    } finally {
      state.popScope();
    }
  }

  @override
  String toString() => children.join('.');
}

/// A type reference, `T(Name)`, evaluating to a [SpelType].
///
/// Used for static fields and methods (`T(Math).PI`, `T(int).parse('1')`)
/// and `instanceof`. Types come from the context's [TypeLocator]; unlike
/// Spring they must be registered, as Dart cannot load classes by name.
///
/// ```dart
/// SpelExpressionParser().parseExpression('T(Math).max(1, 2)').getValue();
/// // 2
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.TypeReference
/// parser.parseExpression("T(java.lang.Math).max(1, 2)").getValue(); // 2
/// ```
final class TypeReference extends SpelNode {
  /// A reference to the type named [typeName].
  TypeReference(super.start, this.typeName);

  /// The registered type name (dotted names are kept as is).
  final String typeName;

  @override
  Object? getValue(ExpressionState state) =>
      state.located(start, () => state.context.typeLocator.findType(typeName));

  @override
  String toString() => 'T($typeName)';
}

/// A constructor call, `new Name(args)`, or an array construction,
/// `new int[3]`, `new int[2][3]`, `new String[]{'a', 'b'}`.
///
/// Constructors come from the context's [ConstructorResolver]s (by
/// default the constructors registered on a [SpelType]); a
/// `SimpleEvaluationContext` has none. Arrays are Dart lists of the
/// element type: `int`, `long`, `short`, `byte` arrays are filled with
/// `0`, `double`/`float` with `0.0`, `boolean`/`bool` with `false`, others
/// with `null`; multi-dimensional arrays are lists of lists.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression('new DateTime(2026, 10, 20).year')
///     .getValue(); // 2026
/// SpelExpressionParser().parseExpression('new int[3]').getValue();
/// // [0, 0, 0]
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.ConstructorReference
/// parser.parseExpression("new java.util.Date()").getValue();
/// parser.parseExpression("new int[3]").getValue(); // int[] {0, 0, 0}
/// ```
final class ConstructorReference extends SpelNode {
  /// A call of [typeName]'s constructor with [arguments], or an array
  /// construction when [dimensions] is given.
  ConstructorReference(
    super.start,
    this.typeName,
    this.arguments, {
    this.dimensions,
    this.initializer,
  });

  /// The registered type name.
  final String typeName;

  /// The argument expressions (empty for arrays).
  final List<SpelNode> arguments;

  /// Array dimensions (`null` entries for `[]`), or `null` for a
  /// constructor call.
  final List<SpelNode?>? dimensions;

  /// The `{...}` initializer of an array construction.
  final InlineList? initializer;

  static const _primitiveDefaults = <String, Object>{
    'int': 0,
    'long': 0,
    'short': 0,
    'byte': 0,
    'double': 0.0,
    'float': 0.0,
    'num': 0,
    'boolean': false,
    'bool': false,
    'char': '\u0000',
  };

  @override
  Object? getValue(ExpressionState state) {
    if (dimensions != null) {
      return _array(state, dimensions!);
    }
    final args = [
      for (final argument in arguments)
        state.withThis(state.scopeRoot, argument),
    ];
    final context = state.context;
    final signature = '(${args.map(ExpressionState.typeName).join(',')})';
    for (final resolver in context.constructorResolvers) {
      final ConstructorExecutor? executor;
      try {
        executor = resolver.resolve(context, typeName, args);
      } on SpelEvaluationException catch (error) {
        throw state.locate(error, start);
      } on AccessException catch (error) {
        throw state.error(SpelMessage.constructorInvocationProblem, start, [
          typeName,
          signature,
        ], error);
      }
      if (executor != null) {
        state.trackOperation();
        try {
          return executor(context, args);
        } on SpelEvaluationException catch (error, stackTrace) {
          Error.throwWithStackTrace(state.locate(error, start), stackTrace);
        } on AccessException catch (error) {
          throw state.error(SpelMessage.constructorInvocationProblem, start, [
            typeName,
            signature,
          ], error);
        }
      }
    }
    throw state.error(SpelMessage.constructorNotFound, start, [
      typeName,
      signature,
    ]);
  }

  Object? _array(ExpressionState state, List<SpelNode?> dimensions) {
    final type = TypeReference(start, typeName).getValue(state)! as SpelType;
    final fill = _primitiveDefaults[typeName];
    final initializer = this.initializer;
    if (initializer == null) {
      final sizes = [
        for (final dimension in dimensions)
          dimension == null
              ? throw state.error(SpelMessage.missingArrayDimension, start)
              : _size(state, dimension),
      ];
      var total = 1;
      for (final size in sizes) {
        total *= size;
        if (total > SpelLimits.maxArrayElements) {
          throw state.error(
            SpelMessage.maxArrayElementsThresholdExceeded,
            start,
            [SpelLimits.maxArrayElements],
          );
        }
      }
      return _markReal(_filled(state, type, sizes, fill), null);
    }
    if (dimensions.length > 1) {
      throw state.error(
        SpelMessage.multidimArrayInitializerNotSupported,
        start,
      );
    }
    final values = initializer.getValue(state)! as List<Object?>;
    final dimension = dimensions.single;
    if (dimension != null && _size(state, dimension) != values.length) {
      throw state.error(SpelMessage.initializerLengthIncorrect, start);
    }
    final elements = [
      for (final value in values) _element(state, type, fill, value),
    ];
    state.trackOperation();
    return _markReal(type.arrayOf(elements), values);
  }

  // A one-dimensional `double[]` / `float[]` holds real numbers only; an
  // array of another type keeps the marks of its [initializer] values.
  Object? _markReal(Object? array, List<Object?>? initializer) {
    if (array is! List<Object?>) {
      return array;
    }
    if (const {'double', 'float', 'Double', 'Float'}.contains(typeName)) {
      if (dimensions!.length == 1) {
        _realElements[array] = _allElements;
      }
    } else if (initializer != null) {
      if (_realElements[initializer] case final marks?) {
        _realElements[array] = marks;
      }
    }
    return array;
  }

  List<Object?> _filled(
    ExpressionState state,
    SpelType type,
    List<int> sizes,
    Object? fill,
  ) {
    state.trackOperation();
    if (sizes.length == 1) {
      return type.newArray(sizes.single, fill);
    }
    return [
      for (var i = 0; i < sizes.first; i++)
        _filled(state, type, sizes.sublist(1), fill),
    ];
  }

  // An initializer element converted to the element type; primitives do
  // not take null.
  Object? _element(
    ExpressionState state,
    SpelType type,
    Object? fill,
    Object? value,
  ) {
    if (value == null) {
      if (fill != null) {
        throw state.error(SpelMessage.incorrectElementTypeForArray, start, [
          typeName,
          'null',
        ]);
      }
      return null;
    }
    if (type.isInstance(value) || type.type == null) {
      return value;
    }
    final converted = state.located(
      start,
      () => state.context.typeConverter.convertValue(value, type.type!),
    );
    if (!type.isInstance(converted)) {
      throw state.error(SpelMessage.incorrectElementTypeForArray, start, [
        typeName,
        value.runtimeType,
      ]);
    }
    return converted;
  }

  int _size(ExpressionState state, SpelNode dimension) {
    final value = dimension.getValue(state);
    final size = value is int
        ? value
        : state.located(
            start,
            () => state.context.typeConverter.convertValue(value, int),
          );
    if (size is! int || size < 0) {
      throw state.error(SpelMessage.typeConversionError, start, [
        ExpressionState.typeName(value),
        'int',
      ]);
    }
    return size;
  }

  @override
  String toString() {
    final dimensions = this.dimensions;
    if (dimensions == null) {
      return 'new $typeName(${arguments.join(',')})';
    }
    return 'new $typeName${dimensions.map((d) => '[${d ?? ''}]').join()}'
        '${initializer ?? ''}';
  }
}

/// A bean reference, `@name`, `@'dotted.name'` or `&factoryBean`.
///
/// Resolved by the context's [BeanResolver] (e.g. `BeanFactoryResolver`);
/// an `AccessException` from the resolver is reported as
/// [SpelMessage.exceptionDuringBeanResolution].
///
/// ```dart
/// final context = StandardEvaluationContext()
///   ..beanResolver = BeanFactoryResolver(beanFactory);
/// SpelExpressionParser().parseExpression('@mailer').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.BeanReference
/// context.setBeanResolver(new BeanFactoryResolver(beanFactory));
/// parser.parseExpression("@mailer").getValue(context);
/// ```
final class BeanReference extends SpelNode {
  /// A reference to bean [name]; [factory] for `&name`.
  BeanReference(super.start, this.name, {this.factory = false});

  /// The bean name (without `@` or `&`).
  final String name;

  /// Whether this is `&name`, the factory bean itself.
  final bool factory;

  @override
  Object? getValue(ExpressionState state) {
    final beanName = factory ? '&$name' : name;
    final resolver = state.context.beanResolver;
    if (resolver == null) {
      throw state.error(SpelMessage.noBeanResolverRegistered, start, [
        beanName,
      ]);
    }
    state.trackOperation();
    try {
      return resolver.resolve(state.context, beanName);
    } on SpelEvaluationException catch (error) {
      throw state.locate(error, start);
    } on AccessException catch (error) {
      throw state.error(SpelMessage.exceptionDuringBeanResolution, start, [
        beanName,
        error.message,
      ], error);
    }
  }

  @override
  String toString() => '${factory ? '&' : '@'}$name';
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

/// The operator of a [BinaryOperator].
///
/// ```dart
/// // '1 + 2' -> add, 'a and b' -> and, "s matches '[a-z]+'" -> matches
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring has one AST class per operator: OpPlus, OpAnd,
/// // OperatorMatches, ...
/// ```
enum BinaryKind {
  /// `+`: addition or string concatenation (Spring `OpPlus`).
  add,

  /// `-`: subtraction (Spring `OpMinus`).
  subtract,

  /// `*`: multiplication or string repetition (Spring `OpMultiply`).
  multiply,

  /// `/` or `div`: division, truncating for two ints (Spring `OpDivide`).
  divide,

  /// `%` or `mod`: remainder (Spring `OpModulus`).
  modulus,

  /// `^`: exponentiation (Spring `OpPower`).
  power,

  /// `==` or `eq` (Spring `OpEQ`).
  eq,

  /// `!=` or `ne` (Spring `OpNE`).
  ne,

  /// `<` or `lt` (Spring `OpLT`).
  lt,

  /// `<=` or `le` (Spring `OpLE`).
  le,

  /// `>` or `gt` (Spring `OpGT`).
  gt,

  /// `>=` or `ge` (Spring `OpGE`).
  ge,

  /// `&&` or `and`, short-circuiting (Spring `OpAnd`).
  and,

  /// `||` or `or`, short-circuiting (Spring `OpOr`).
  or,

  /// `instanceof T(Name)` (Spring `OperatorInstanceof`).
  instanceOf,

  /// `matches`: full regular expression match (Spring
  /// `OperatorMatches`).
  matches,

  /// `between {low, high}`, inclusive (Spring `OperatorBetween`).
  between,
}

/// A binary operator: arithmetic, comparison, logic, `instanceof`,
/// `matches` or `between`.
///
/// Arithmetic follows Java: `int / int` truncates (`7 / 2` is `3`; an
/// integer division by zero throws Dart's `IntegerDivisionByZeroException`
/// unchanged, like Java's `ArithmeticException`), `%` keeps the sign of
/// the left operand, `int ^ int` is computed as a double and truncated
/// with saturation (`2 ^ -1` is `0`, `2 ^ 100` is the largest `int`), and
/// `'d' - 3` is `'a'`. `+` concatenates when either side is a string,
/// converting the other side with the context's `TypeConverter` (`'a' +
/// {1, 2}` is `a1,2`). Numbers compare by value across `int` and `double`
/// (`2 == 2.0`), collections deeply (`{1, 2} == {1, 2}`), values of one
/// enum by index. Other operand types go to the context's
/// [OperatorOverloader]. `matches` uses Dart's `RegExp` (see
/// `SpelPatterns`).
///
/// ```dart
/// final parser = SpelExpressionParser();
/// parser.parseExpression('7 / 2 + 7 % 3').getValue(); // 4
/// parser.parseExpression("'n=' + 1").getValue(); // n=1
/// parser.parseExpression('3 between {1, 5}').getValue(); // true
/// parser.parseExpression("'5.00' matches '\\d+\\.\\d{2}'").getValue();
/// // true
/// ```
///
/// Spring (Java):
/// ```java
/// // OpPlus, OpDivide, OpModulus, OperatorBetween, OperatorMatches, ...
/// parser.parseExpression("7 / 2 + 7 % 3").getValue(); // 4
/// parser.parseExpression("3 between {1, 5}").getValue(); // true
/// ```
final class BinaryOperator extends SpelNode {
  /// The operation [kind] applied to [left] and [right].
  BinaryOperator(super.start, this.kind, this.left, this.right);

  /// Which operator this is.
  final BinaryKind kind;

  /// The left operand.
  final SpelNode left;

  /// The right operand.
  final SpelNode right;

  @override
  Object? getValue(ExpressionState state) {
    switch (kind) {
      // and/or short-circuit and instanceof needs the raw right value,
      // so these are handled before both operands are evaluated.
      case BinaryKind.and:
        return state.asBool(left.getValue(state), left.start) &&
            state.asBool(right.getValue(state), right.start);
      case BinaryKind.or:
        return state.asBool(left.getValue(state), left.start) ||
            state.asBool(right.getValue(state), right.start);
      case BinaryKind.instanceOf:
        final value = left.getValue(state);
        final type = right.getValue(state);
        if (type is! SpelType) {
          throw state.error(
            SpelMessage.instanceofOperatorNeedsClassOperand,
            right.start,
            [ExpressionState.typeName(type)],
          );
        }
        return value != null && type.isInstance(value);
      default:
        final l = left.getValue(state);
        final leftReal = _realValue(left, l);
        final r = right.getValue(state);
        final rightReal = _realValue(right, r);
        _real = false;
        return _evaluate(state, l, r, leftReal, rightReal);
    }
  }

  Object? _evaluate(
    ExpressionState state,
    Object? l,
    Object? r,
    bool leftReal,
    bool rightReal,
  ) {
    final context = state.context;
    switch (kind) {
      case BinaryKind.eq:
        return equalityCheck(context, l, r);
      case BinaryKind.ne:
        return !equalityCheck(context, l, r);
      case BinaryKind.lt || BinaryKind.le || BinaryKind.gt || BinaryKind.ge:
        final comparator = context.typeComparator;
        if (!comparator.canCompare(l, r)) {
          throw state.error(SpelMessage.notComparable, start, [
            ExpressionState.typeName(l),
            ExpressionState.typeName(r),
          ]);
        }
        final result = state.located(start, () => comparator.compare(l, r));
        return switch (kind) {
          BinaryKind.lt => result < 0,
          BinaryKind.le => result <= 0,
          BinaryKind.gt => result > 0,
          _ => result >= 0,
        };
      case BinaryKind.matches:
        if (l is! String) {
          throw state.error(
            SpelMessage.invalidFirstOperandForMatchesOperator,
            left.start,
            [l],
          );
        }
        if (r is! String) {
          throw state.error(
            SpelMessage.invalidSecondOperandForMatchesOperator,
            right.start,
            [r],
          );
        }
        // Anchored, so the whole string must match (Java's
        // String.matches semantics).
        final regex = state.located(right.start, () => SpelPatterns.compile(r));
        return regex.hasMatch(l);
      case BinaryKind.between:
        if (r is! List || r.length != 2) {
          throw state.error(
            SpelMessage.betweenRightOperandMustBeTwoElementList,
            right.start,
          );
        }
        final comparator = context.typeComparator;
        if (!comparator.canCompare(r[0], l) ||
            !comparator.canCompare(l, r[1])) {
          throw state.error(SpelMessage.notComparable, start, [
            ExpressionState.typeName(l),
            ExpressionState.typeName(r[0]),
          ]);
        }
        return state.located(
          start,
          () =>
              comparator.compare(r[0], l) <= 0 &&
              comparator.compare(l, r[1]) <= 0,
        );
      default:
        return arithmetic(
          state,
          l,
          r,
          leftReal: leftReal,
          rightReal: rightReal,
        );
    }
  }

  /// Applies this arithmetic operator to the evaluated operands [l] and
  /// [r]: numbers natively, then string concatenation (`+`), repetition
  /// (`string * int`) and character arithmetic (`'d' - 3`), then the
  /// context's [OperatorOverloader].
  ///
  /// [leftReal] / [rightReal] mark integral operands that are real
  /// numbers (on the web, where `7.0` is an `int` at run time).
  ///
  /// Throws [SpelMessage.operatorNotSupportedBetweenTypes] when nothing
  /// applies.
  Object? arithmetic(
    ExpressionState state,
    Object? l,
    Object? r, {
    bool leftReal = false,
    bool rightReal = false,
  }) {
    final operation = switch (kind) {
      BinaryKind.add => Operation.add,
      BinaryKind.subtract => Operation.subtract,
      BinaryKind.multiply => Operation.multiply,
      BinaryKind.divide => Operation.divide,
      BinaryKind.modulus => Operation.modulus,
      _ => Operation.power,
    };
    if (l is num && r is num) {
      final ints = l is int && !leftReal && r is int && !rightReal;
      _real = !ints;
      switch (operation) {
        case Operation.add:
          return l + r;
        case Operation.subtract:
          return l - r;
        case Operation.multiply:
          return l * r;
        case Operation.divide:
          // Java-like integer division: two ints truncate toward zero (and
          // throw on zero, like Java's ArithmeticException); any double
          // gives a double (1 / 0.0 = Infinity).
          if (ints) {
            return l.toInt() ~/ _nonZero(r.toInt());
          }
          return l.toDouble() / r.toDouble();
        case Operation.modulus:
          // remainder (not Dart's %) keeps the sign of the dividend, like
          // Java: -7 % 3 == -1.
          return ints
              ? l.toInt().remainder(_nonZero(r.toInt()))
              : l.toDouble().remainder(r.toDouble());
        case Operation.power:
          // Spring 7's OpPower: a double when an operand is real;
          // otherwise Math.pow cast to long when above Integer.MAX_VALUE
          // or an operand is a long (here: outside the int range), else
          // cast to int, which saturates at Integer.MIN_VALUE.
          final result = math.pow(l.toDouble(), r.toDouble()).toDouble();
          if (!ints) {
            return result;
          }
          return result > _maxInt || _isLong(l) || _isLong(r)
              ? toJavaLong(result)
              : _toJavaInt(result);
      }
    }
    switch (operation) {
      case Operation.add when l is String || r is String:
        final text = l is String && r is String
            ? (l, r)
            : l is String
            ? (l, _string(state, r, real: rightReal))
            : (_string(state, l, real: leftReal), r! as String);
        final length = text.$1.length + text.$2.length;
        if (length > SpelLimits.maxConcatenatedStringLength) {
          throw state.error(
            SpelMessage.maxConcatenatedStringLengthExceeded,
            start,
            [SpelLimits.maxConcatenatedStringLength],
          );
        }
        return '${text.$1}${text.$2}';
      case Operation.subtract when l is String && l.length == 1 && r is int:
        // Java char arithmetic: 'd' - 3 is 'a'.
        return String.fromCharCode((l.codeUnitAt(0) - r) & 0xFFFF);
      case Operation.multiply when l is String && r is int:
        return _repeat(state, l, r);
      default:
        return state.operate(operation, l, r, start);
    }
  }

  static const _maxInt = 2147483647;
  static const _minInt = -2147483648;

  static bool _isLong(int value) => value > _maxInt || value < _minInt;

  // Java's `(int)` cast of a double: NaN is 0, out-of-range values
  // saturate.
  static int _toJavaInt(double value) => value.isNaN
      ? 0
      : value >= _maxInt
      ? _maxInt
      : value <= _minInt
      ? _minInt
      : value.truncate();

  // Java's ArithmeticException for an integer division by zero, the same
  // on the VM and the web (where `~/ 0` fails differently).
  static int _nonZero(int divisor) =>
      divisor == 0 ? throw UnsupportedError('/ by zero') : divisor;

  // Repetition with Spring's limits, checked before the string is built
  // (`'x' * 2^62` must not overflow into a huge allocation).
  String _repeat(ExpressionState state, String text, int count) {
    if (count < 0) {
      throw state.error(SpelMessage.negativeRepeatedTextCount, start, [count]);
    }
    if (text.isEmpty || count == 0) {
      return '';
    }
    if (count > SpelLimits.maxRepeatedTextSize ~/ text.length) {
      throw state.error(SpelMessage.maxRepeatedTextSizeExceeded, start, [
        SpelLimits.maxRepeatedTextSize,
      ]);
    }
    return text * count;
  }

  // The other operand of a string concatenation, through the context's
  // TypeConverter like Spring (a list becomes `1,2`); null is 'null'.
  static String _string(
    ExpressionState state,
    Object? value, {
    bool real = false,
  }) {
    if (value == null) {
      return 'null';
    }
    // A real number that is an `int` at run time (the web): Java's `7.0`.
    if (real && value is int) {
      return '$value.0';
    }
    final converter = state.context.typeConverter;
    if (converter.canConvert(value, String)) {
      final converted = converter.convertValue(value, String);
      if (converted is String) {
        return converted;
      }
    }
    return '$value';
  }

  /// Numbers are equal by value, collections deeply (lists in order, sets
  /// and maps by content), otherwise `==` (or `compareTo == 0` for
  /// comparable values of the same type), like Spring.
  static bool equalityCheck(EvaluationContext context, Object? l, Object? r) {
    // Numbers compare by value like Spring's OpEQ (`1 == 1.0`), with
    // Java's double semantics: NaN equals nothing, `0.0 == -0.0`.
    if (l is num && r is num) {
      return l == r;
    }
    if (_deepEquals(l, r)) {
      return true;
    }
    if (l is Comparable &&
        r is Comparable &&
        l.runtimeType == r.runtimeType &&
        context.typeComparator.canCompare(l, r)) {
      return context.typeComparator.compare(l, r) == 0;
    }
    return false;
  }

  // Java's equals for collections: List.equals is ordered and
  // element-wise, Set.equals and Map.equals compare contents.
  static bool _deepEquals(Object? l, Object? r) {
    if (identical(l, r) || l == r) {
      return true;
    }
    if (l is List && r is List) {
      if (l.length != r.length) {
        return false;
      }
      for (var i = 0; i < l.length; i++) {
        if (!_deepEquals(l[i], r[i])) {
          return false;
        }
      }
      return true;
    }
    if (l is Set && r is Set) {
      return l.length == r.length &&
          l.every((a) => r.contains(a) || r.any((b) => _deepEquals(a, b)));
    }
    if (l is Map && r is Map) {
      if (l.length != r.length) {
        return false;
      }
      for (final entry in l.entries) {
        if (!r.containsKey(entry.key) ||
            !_deepEquals(entry.value, r[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override
  String toString() => '($left ${kind.name} $right)';
}

/// The operator of a [UnaryOperator].
///
/// ```dart
/// // '!flag' or 'not flag' -> not, '-x' -> minus, '+x' -> plus
/// ```
///
/// Spring (Java):
/// ```java
/// // OperatorNot, OpMinus (one operand), OpPlus (one operand)
/// ```
enum UnaryKind {
  /// `!` or `not`: boolean negation.
  not,

  /// `-`: numeric negation.
  minus,

  /// `+`: numeric identity.
  plus,
}

/// A unary operator: `!x`, `not x`, `-x`, `+x`.
///
/// ```dart
/// SpelExpressionParser().parseExpression('!(1 > 2)').getValue(); // true
/// SpelExpressionParser().parseExpression('-5 + +3').getValue(); // -2
/// ```
///
/// Spring (Java):
/// ```java
/// // OperatorNot, OpMinus, OpPlus
/// parser.parseExpression("!(1 > 2)").getValue(); // true
/// ```
final class UnaryOperator extends SpelNode {
  /// The operation [kind] applied to [operand].
  UnaryOperator(super.start, this.kind, this.operand);

  /// Which operator this is.
  final UnaryKind kind;

  /// The operand.
  final SpelNode operand;

  @override
  Object? getValue(ExpressionState state) {
    final value = operand.getValue(state);
    switch (kind) {
      case UnaryKind.not:
        return !state.asBool(value, operand.start);
      case UnaryKind.minus:
        _real = _realValue(operand, value);
        return value is num
            ? -value
            : state.operate(Operation.subtract, value, null, start);
      case UnaryKind.plus:
        _real = _realValue(operand, value);
        return value is num
            ? value
            : state.operate(Operation.add, value, null, start);
    }
  }

  @override
  String toString() => '${kind.name}($operand)';
}

/// The ternary operator, `cond ? a : b`; only the chosen branch is
/// evaluated.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("age >= 18 ? 'adult' : 'minor'")
///     .getValue(null, {'age': 20}); // adult
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Ternary
/// parser.parseExpression("age >= 18 ? 'adult' : 'minor'")
///     .getValue(context);
/// ```
final class Ternary extends SpelNode {
  /// Chooses [whenTrue] or [whenFalse] by [condition].
  Ternary(super.start, this.condition, this.whenTrue, this.whenFalse);

  /// The boolean condition.
  final SpelNode condition;

  /// Evaluated when [condition] is `true`.
  final SpelNode whenTrue;

  /// Evaluated when [condition] is `false`.
  final SpelNode whenFalse;

  @override
  Object? getValue(ExpressionState state) {
    final branch = state.asBool(condition.getValue(state), condition.start)
        ? whenTrue
        : whenFalse;
    final result = branch.getValue(state);
    _real = branch._real;
    return result;
  }

  @override
  String toString() => '($condition ? $whenTrue : $whenFalse)';
}

/// `a ?: b`: [fallback] when [value] is null or an empty string.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("name ?: 'Unknown'")
///     .getValue(null, {'name': ''}); // Unknown
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Elvis
/// parser.parseExpression("name ?: 'Unknown'").getValue(context);
/// ```
final class Elvis extends SpelNode {
  /// [value], or [fallback] when it is null or empty.
  Elvis(super.start, this.value, this.fallback);

  /// The preferred value.
  final SpelNode value;

  /// The value used when [value] is null or an empty string.
  final SpelNode fallback;

  @override
  Object? getValue(ExpressionState state) {
    final result = value.getValue(state);
    if (result == null || (result is String && result.isEmpty)) {
      final other = fallback.getValue(state);
      _real = fallback._real;
      return other;
    }
    _real = value._real;
    return result;
  }

  @override
  String toString() => '($value ?: $fallback)';
}

/// Assignment, `target = value`, evaluating to the assigned value.
///
/// The target can be a property, a variable (`#x`) or an indexed element;
/// assignment must be enabled in the context. Like Spring, the target is
/// resolved before the value is evaluated.
///
/// ```dart
/// final data = <String, Object?>{'n': 1};
/// SpelExpressionParser().parseExpression('n = n + 1').getValue(null, data);
/// // data['n'] == 2
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.Assign
/// parser.parseExpression("n = n + 1").getValue(context);
/// ```
final class Assign extends SpelNode {
  /// Assigns [value] to [target].
  Assign(super.start, this.target, this.value);

  /// The assignable target.
  final SpelNode target;

  /// The new value.
  final SpelNode value;

  @override
  Object? getValue(ExpressionState state) {
    if (!state.context.isAssignmentEnabled) {
      throw state.error(SpelMessage.notAssignable, start, [toString()]);
    }
    final result = target.assign(state, () => value.getValue(state));
    _real = value._real;
    return result;
  }

  @override
  String toString() => '$target = $value';
}

/// `++x`, `x++`, `--x`, `x--` on assignable numeric targets.
///
/// Prefix forms evaluate to the new value, postfix forms to the old one.
/// Non-numbers go to the context's [OperatorOverloader].
///
/// ```dart
/// final context = StandardEvaluationContext()..setVariable('n', 1);
/// final parser = SpelExpressionParser();
/// parser.parseExpression('#n++').getValue(context); // 1, n is now 2
/// parser.parseExpression('++#n').getValue(context); // 3
/// ```
///
/// Spring (Java):
/// ```java
/// // OpInc, OpDec
/// parser.parseExpression("counter++").getValue(context);
/// ```
final class IncDec extends SpelNode {
  /// Increments ([increment]) or decrements [target], as prefix or
  /// postfix operator ([prefix]).
  IncDec(
    super.start,
    this.target, {
    required this.increment,
    required this.prefix,
  });

  /// The assignable numeric target.
  final SpelNode target;

  /// `true` for `++`, `false` for `--`.
  final bool increment;

  /// `true` for `++x` / `--x`, `false` for `x++` / `x--`.
  final bool prefix;

  @override
  Object? getValue(ExpressionState state) {
    if (!state.context.isAssignmentEnabled) {
      throw state.error(SpelMessage.notAssignable, start, [toString()]);
    }
    final notSupported = increment
        ? SpelMessage.operandNotIncrementable
        : SpelMessage.operandNotDecrementable;
    // `1++` fails here with notAssignable, like Spring.
    final ref = target.getValueRef(state);
    final current = ref.getValue();
    final Object? next;
    if (current is num) {
      next = increment ? current + 1 : current - 1;
    } else {
      try {
        next = state.operate(
          increment ? Operation.add : Operation.subtract,
          current,
          1,
          start,
        );
      } on SpelEvaluationException catch (error) {
        if (error.messageCode == SpelMessage.operatorNotSupportedBetweenTypes) {
          throw state.error(notSupported, target.start, [target.toString()]);
        }
        rethrow;
      }
    }
    ref.setValue(next);
    return prefix ? next : current;
  }

  @override
  String toString() => prefix
      ? '${increment ? '++' : '--'}$target'
      : '$target${increment ? '++' : '--'}';
}

// The message of an error for EL inserts.
String _messageOf(Object error) =>
    error is AccessException ? error.message : '$error';
