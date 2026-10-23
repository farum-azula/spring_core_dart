import 'dart:math' as math;

import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// Mutable state of one evaluation, like Spring's `ExpressionState`.
///
/// Created by `SpelExpression` for each `getValue` / `setValue` call and
/// passed down the tree. It tracks the *active context object* (what a
/// bare `name` or `method()` applies to, and what `#this` is) and the
/// *scope root* (the active object at the start of the current compound
/// expression, against which arguments and indexes are evaluated). You
/// only meet it when writing your own [SpelNode]s.
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
  /// as `#root`, `#this` and the initial active object.
  ExpressionState(this.context, this.root, this.expressionString)
    : _active = [root],
      _scopeRoots = [root];

  /// The evaluation context (accessors, variables, types, ...).
  final EvaluationContext context;

  /// The root object (`#root`) of this evaluation.
  final Object? root;

  /// The expression text, used in error messages.
  final String expressionString;

  // Two stacks: _active changes at every step of `a.b.c`; _scopeRoots
  // only when a compound expression or `#this`-scope (selection,
  // projection, arguments) starts. pushScope pushes onto both.
  final List<Object?> _active;
  final List<Object?> _scopeRoots;

  /// The object property and method references apply to.
  Object? get activeContextObject => _active.last;

  /// `#this` at the start of the current compound expression; method and
  /// indexer arguments are evaluated against it.
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

  /// A [SpelEvaluationException] for this expression at [position].
  SpelEvaluationException error(
    SpelMessage code,
    String message,
    int position, [
    Object? cause,
  ]) => SpelEvaluationException(
    code,
    message,
    expressionString: expressionString,
    position: position,
    cause: cause,
  );

  /// [value] as a `bool`, converting with the context's type converter
  /// (e.g. `'true'`); `null` and non-convertible values throw
  /// [SpelMessage.notBoolean].
  bool asBool(Object? value, int position) {
    if (value is bool) {
      return value;
    }
    if (value != null && context.typeConverter.canConvert(value, bool)) {
      final converted = context.typeConverter.convertValue(value, bool);
      if (converted is bool) {
        return converted;
      }
    }
    throw error(
      SpelMessage.notBoolean,
      'Value $value of type ${value.runtimeType} cannot be used as a boolean',
      position,
    );
  }
}

/// A reference that can be read and written (assignment targets), like
/// Spring's `ValueRef`.
///
/// Returned by [SpelNode.getValueRef] for properties, variables and
/// indexed elements; `=`, `++`/`--` and `Expression.setValue` write
/// through it.
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

  /// Evaluates this node in [state].
  Object? getValue(ExpressionState state);

  /// Whether this node can be the target of an assignment.
  bool get isAssignable => false;

  /// Whether this node uses safe navigation (`?.`).
  bool get isNullSafe => false;

  /// A reference for assigning to this node; throws
  /// [SpelMessage.notAssignable] unless [isAssignable].
  ValueRef getValueRef(ExpressionState state) => throw state.error(
    SpelMessage.notAssignable,
    'Cannot assign to ${toString()}',
    start,
  );
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
  /// A literal [value] at [start].
  Literal(super.start, this.value);

  /// The constant value.
  final Object? value;

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
  Object? getValue(ExpressionState state) => [
    for (final item in items) item.getValue(state),
  ];

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
  Object? getValue(ExpressionState state) => {
    for (final (key, value) in entries)
      // An unquoted key is its own name, like Spring.
      (key is PropertyOrFieldReference ? key.name : key.getValue(state)): value
          .getValue(state),
  };

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
      throw state.error(
        SpelMessage.propertyOnNull,
        "Property or field '$name' cannot be found on null",
        start,
      );
    }
    return _read(state, target);
  }

  // Static fields of a T(...) type win; then the first accessor whose
  // canRead says yes. Non-SpEL errors from accessors are wrapped.
  Object? _read(ExpressionState state, Object target) {
    if (target is SpelType) {
      final field = target.staticFields[name];
      if (field != null) {
        return field();
      }
    }
    final context = state.context;
    for (final accessor in context.propertyAccessors) {
      if (accessor.canRead(context, target, name)) {
        try {
          return accessor.read(context, target, name);
        } on SpelEvaluationException {
          rethrow;
        } catch (error) {
          throw state.error(
            SpelMessage.exceptionDuringPropertyRead,
            "Property '$name' of ${target.runtimeType} cannot be read",
            start,
            error,
          );
        }
      }
    }
    throw state.error(
      SpelMessage.propertyNotReadable,
      "Property or field '$name' cannot be found on object of type "
      "'${target.runtimeType}'",
      start,
    );
  }

  @override
  ValueRef getValueRef(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      throw state.error(
        SpelMessage.propertyOnNull,
        "Property or field '$name' cannot be set on null",
        start,
      );
    }
    final context = state.context;
    return _FunctionRef(
      () => _read(state, target),
      (value) {
        for (final accessor in context.propertyAccessors) {
          if (accessor.canWrite(context, target, name)) {
            try {
              accessor.write(context, target, name, value);
            } on SpelEvaluationException {
              rethrow;
            } catch (error) {
              // E.g. a TypeError writing a String into a Map<String, int>.
              throw state.error(
                SpelMessage.exceptionDuringPropertyWrite,
                "Property '$name' of ${target.runtimeType} cannot be set to "
                '$value',
                start,
                error,
              );
            }
            return;
          }
        }
        throw state.error(
          SpelMessage.propertyNotWritable,
          "Property or field '$name' cannot be set on object of type "
          "'${target.runtimeType}'",
          start,
        );
      },
      isWritable: context.propertyAccessors.any(
        (a) => a.canWrite(context, target, name),
      ),
    );
  }

  @override
  String toString() => name;
}

/// A method call on the active object: `name(args)`, `a.name(args)`,
/// `a?.name(args)`.
///
/// Arguments are evaluated against the scope root (not the target);
/// static methods of `SpelType`s are tried first, then the context's
/// method resolvers in order.
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
      throw state.error(
        SpelMessage.methodOnNull,
        "Method call: Attempted to call method $name() on null",
        start,
      );
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
    for (final resolver in resolvers) {
      final executor = resolver.resolve(context, target, name, args);
      if (executor != null) {
        try {
          return executor(context, target, args);
        } on SpelEvaluationException {
          rethrow;
        } catch (error) {
          throw state.error(
            SpelMessage.exceptionDuringMethodInvocation,
            'Method $name(${args.map((a) => a.runtimeType).join(', ')}) '
            'failed on ${target.runtimeType}',
            start,
            error,
          );
        }
      }
    }
    throw state.error(
      SpelMessage.methodNotFound,
      'Method $name(${args.map((a) => a.runtimeType).join(', ')}) cannot be '
      "found on type '${target is SpelType ? target : target.runtimeType}'",
      start,
    );
  }

  @override
  String toString() => '$name(${arguments.join(',')})';
}

/// A variable: `#name`, plus the special `#this` (current element or
/// active object) and `#root` (the root object).
///
/// Unset variables evaluate to `null`. `#name = value` assigns through
/// `EvaluationContext.assignVariable` (which `SimpleEvaluationContext`
/// rejects); `#this` and `#root` are read-only.
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
    _ => state.context.lookupVariable(name),
  };

  @override
  ValueRef getValueRef(ExpressionState state) {
    if (!isAssignable) {
      return super.getValueRef(state);
    }
    return _FunctionRef(
      () => getValue(state),
      (value) => state.context.assignVariable(name, () => value),
    );
  }

  @override
  String toString() => '#$name';
}

/// A call of a registered function: `#name(args)`.
///
/// The variable `#name` must hold a Dart `Function` (see
/// `StandardEvaluationContext.registerFunction`); it is invoked with
/// `Function.apply`.
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
    final function = state.context.lookupVariable(name);
    if (function == null) {
      throw state.error(
        SpelMessage.functionNotFound,
        "Function '$name' is not registered",
        start,
      );
    }
    if (function is! Function) {
      throw state.error(
        SpelMessage.variableNotFunction,
        "Variable '$name' is not a function",
        start,
      );
    }
    final args = [
      for (final argument in arguments)
        state.withThis(state.scopeRoot, argument),
    ];
    try {
      return Function.apply(function, args);
    } on SpelEvaluationException {
      rethrow;
    } catch (error) {
      // Wrong number, names or types of arguments. A TypeError thrown
      // inside the body is reported the same way: Dart cannot tell them
      // apart without reflection.
      if (error is NoSuchMethodError || error is TypeError) {
        throw state.error(
          SpelMessage.functionNotFound,
          "Function '$name' cannot be called with $args",
          start,
          error,
        );
      }
      throw state.error(
        SpelMessage.exceptionDuringFunctionCall,
        "Function '$name' threw an exception",
        start,
        error,
      );
    }
  }

  @override
  String toString() => '#$name(${arguments.join(',')})';
}

/// Indexing: `list[0]`, `map['key']`, `map[key]`, `'text'[0]`,
/// `obj['property']`, `a?.[0]`.
///
/// Lists and maps are readable and writable; strings and other iterables
/// are read-only. An unquoted name indexing a map is the key itself, and
/// a string index on any other object reads that property.
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
    final target = state.activeContextObject;
    if (target == null) {
      if (nullSafe) {
        return null;
      }
      throw state.error(
        SpelMessage.invalidIndex,
        'Cannot index into a null value',
        start,
      );
    }
    return _ref(state, target).getValue();
  }

  @override
  ValueRef getValueRef(ExpressionState state) {
    final target = state.activeContextObject;
    if (target == null) {
      throw state.error(
        SpelMessage.invalidIndex,
        'Cannot index into null',
        start,
      );
    }
    return _ref(state, target);
  }

  // Runs a write into [target], turning Dart errors into SpEL ones: a
  // TypeError (wrong element type for a typed List or Map) is a type
  // conversion error, an UnsupportedError (unmodifiable collection) means
  // the element is not assignable.
  void _store(ExpressionState state, Object target, void Function() write) {
    try {
      write();
    } on TypeError catch (error) {
      throw state.error(
        SpelMessage.typeConversionError,
        'Value does not fit the element type of ${target.runtimeType}',
        start,
        error,
      );
    } on UnsupportedError catch (error) {
      throw state.error(
        SpelMessage.notAssignable,
        'Cannot assign into ${target.runtimeType}',
        start,
        error,
      );
    }
  }

  // The index is evaluated against the scope root, so `list[#i]` and
  // `list[size - 1]` see the enclosing object, not the list.
  ValueRef _ref(ExpressionState state, Object target) {
    // Like Spring, an unquoted name indexing a map is the key itself.
    final key = target is Map && index is PropertyOrFieldReference
        ? (index as PropertyOrFieldReference).name
        : state.withThis(state.scopeRoot, index);
    switch (target) {
      case Map<Object?, Object?>():
        return _FunctionRef(
          () => target[key],
          (value) => _store(state, target, () => target[key] = value),
        );
      case List<Object?>():
        final i = _intIndex(state, key);
        return _FunctionRef(
          () => i < target.length
              ? target[i]
              : throw _outOfBounds(state, i, target.length),
          (value) {
            if (i >= target.length) {
              throw _outOfBounds(state, i, target.length);
            }
            _store(state, target, () => target[i] = value);
          },
        );
      case String():
        final i = _intIndex(state, key);
        return _FunctionRef(
          () => i < target.length
              ? target[i]
              : throw _outOfBounds(state, i, target.length),
          (_) => throw state.error(
            SpelMessage.notAssignable,
            'Strings are immutable',
            start,
          ),
          isWritable: false,
        );
      case Iterable<Object?>():
        final i = _intIndex(state, key);
        return _FunctionRef(
          () => i < target.length
              ? target.elementAt(i)
              : throw _outOfBounds(state, i, target.length),
          (_) => throw state.error(
            SpelMessage.notAssignable,
            'Cannot assign into ${target.runtimeType}',
            start,
          ),
          isWritable: false,
        );
      default:
        if (key is String) {
          // obj['name'] is property access.
          state.pushActive(target);
          try {
            return PropertyOrFieldReference(start, key).getValueRef(state);
          } finally {
            state.popActive();
          }
        }
        throw state.error(
          SpelMessage.invalidIndex,
          'Cannot index into ${target.runtimeType}',
          start,
        );
    }
  }

  // Accepts ints, integral doubles and numeric strings; negative indexes
  // are invalid (no Python-style indexing from the end).
  int _intIndex(ExpressionState state, Object? key) {
    final converted = key is int
        ? key
        : key is String
        ? int.tryParse(key)
        : key is num && key == key.truncate()
        ? key.toInt()
        : null;
    if (converted == null || converted < 0) {
      throw state.error(SpelMessage.invalidIndex, 'Invalid index $key', start);
    }
    return converted;
  }

  SpelEvaluationException _outOfBounds(
    ExpressionState state,
    int i,
    int length,
  ) => state.error(
    SpelMessage.indexOutOfBounds,
    'Index $i out of bounds for length $length',
    start,
  );

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
  /// `.?[...]`: every match, as a list, set or map.
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
/// for maps, with `key` and `value` properties) and must yield a boolean
/// (otherwise [SpelMessage.resultOfSelectionCriteriaIsNotBoolean]).
/// Selecting all keeps the collection kind: list, set or map; first/last
/// of a map is a one-entry map, or `null` when nothing matches.
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
      throw state.error(
        SpelMessage.selectionNotSupported,
        'Selection is not supported on null',
        start,
      );
    }
    // Like Spring, the criterion must be a boolean (no conversion).
    bool matches(Object? element) =>
        switch (state.withThis(element, condition)) {
          final bool result => result,
          _ => throw state.error(
            SpelMessage.resultOfSelectionCriteriaIsNotBoolean,
            'Result of selection criteria is not boolean',
            condition.start,
          ),
        };
    switch (target) {
      case Map<Object?, Object?>():
        final entries = target.entries.where(matches).toList();
        if (kind != SelectionKind.all && entries.isEmpty) {
          return null;
        }
        return Map<Object?, Object?>.fromEntries(switch (kind) {
          SelectionKind.all => entries,
          SelectionKind.first => [entries.first],
          SelectionKind.last => [entries.last],
        });
      case Iterable<Object?>():
        final selected = target.where(matches);
        return switch (kind) {
          SelectionKind.all =>
            target is Set ? selected.toSet() : selected.toList(),
          SelectionKind.first => selected.firstOrNull,
          SelectionKind.last => selected.lastOrNull,
        };
      default:
        throw state.error(
          SpelMessage.selectionNotSupported,
          'Selection is not supported on ${target.runtimeType}',
          start,
        );
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
      throw state.error(
        SpelMessage.projectionNotSupported,
        'Projection is not supported on null',
        start,
      );
    }
    final Iterable<Object?> elements = switch (target) {
      Map<Object?, Object?>() => target.entries,
      Iterable<Object?>() => target,
      _ => throw state.error(
        SpelMessage.projectionNotSupported,
        'Projection is not supported on ${target.runtimeType}',
        start,
      ),
    };
    return [
      for (final element in elements) state.withThis(element, expression),
    ];
  }

  @override
  String toString() => '![$expression]';
}

/// `a.b.c`: each part is evaluated against the previous result.
///
/// Safe navigation short-circuits the whole chain: in `a?.b.c`, a `null`
/// `a` makes the result `null` without evaluating `b` or `c`.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// parser.parseExpression('user.address.city').getValue(null, {
///   'user': {
///     'address': {'city': 'London'},
///   },
/// }); // London
/// parser
///     .parseExpression('user?.address.city')
///     .getValue(null, {'user': null}); // null
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.CompoundExpression
/// parser.parseExpression("user?.address.city").getValue(context);
/// ```
final class CompoundExpression extends SpelNode {
  /// A chain of [children] (at least two), evaluated left to right.
  CompoundExpression(super.start, this.children);

  /// The parts of the chain.
  final List<SpelNode> children;

  @override
  bool get isAssignable => children.last.isAssignable;

  @override
  Object? getValue(ExpressionState state) =>
      _inScope(state, (target) => children.last.getValue(state), () => null);

  @override
  ValueRef getValueRef(ExpressionState state) => _inScope(
    state,
    (target) => children.last.getValueRef(state),
    () => _FunctionRef(() => null, (_) {}, isWritable: false),
  );

  /// Evaluates all children but the last, then [last] with the result as
  /// the active object; [shortCircuit] when a safe navigation hits null.
  T _inScope<T>(
    ExpressionState state,
    T Function(Object? target) last,
    T Function() shortCircuit,
  ) {
    // The object the chain starts from becomes the scope root, so
    // arguments and indexes inside the chain are evaluated against it.
    state.pushScope(state.activeContextObject);
    try {
      var value = children.first.getValue(state);
      for (var i = 1; i < children.length - 1; i++) {
        final child = children[i];
        // Safe navigation: a null before a `?.` part ends the whole chain
        // (later parts are not evaluated, even without `?.`).
        if (value == null && child.isNullSafe) {
          return shortCircuit();
        }
        state.pushActive(value);
        try {
          value = child.getValue(state);
        } finally {
          state.popActive();
        }
      }
      if (value == null && children.last.isNullSafe) {
        return shortCircuit();
      }
      state.pushActive(value);
      try {
        return last(value);
      } finally {
        state.popActive();
      }
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
  Object? getValue(ExpressionState state) {
    try {
      return state.context.typeLocator.findType(typeName);
    } on SpelEvaluationException catch (error) {
      throw state.error(error.code, error.message, start);
    }
  }

  @override
  String toString() => 'T($typeName)';
}

/// A constructor call, `new Name(args)`.
///
/// Calls the default constructor (key `''`) registered on the [SpelType]
/// with `Function.apply`. Disabled in a `SimpleEvaluationContext`.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression('new DateTime(2026, 10, 20).year')
///     .getValue(); // 2026
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.expression.spel.ast.ConstructorReference
/// parser.parseExpression("new java.util.Date()").getValue();
/// ```
final class ConstructorReference extends SpelNode {
  /// A call of [typeName]'s constructor with [arguments].
  ConstructorReference(super.start, this.typeName, this.arguments);

  /// The registered type name.
  final String typeName;

  /// The argument expressions.
  final List<SpelNode> arguments;

  @override
  Object? getValue(ExpressionState state) {
    if (!state.context.isConstructorEnabled) {
      throw state.error(
        SpelMessage.notSupportedInSimpleContext,
        'Constructor invocation is not supported in this context',
        start,
      );
    }
    final type = TypeReference(start, typeName).getValue(state)! as SpelType;
    final constructor = type.constructors[''];
    if (constructor == null) {
      throw state.error(
        SpelMessage.constructorNotFound,
        'No constructor registered for $typeName',
        start,
      );
    }
    final args = [
      for (final argument in arguments)
        state.withThis(state.scopeRoot, argument),
    ];
    try {
      return Function.apply(constructor, args);
    } on SpelEvaluationException {
      rethrow;
    } catch (error) {
      // Wrong number, names or types of arguments. A TypeError thrown
      // inside the body is reported the same way: Dart cannot tell them
      // apart without reflection.
      if (error is NoSuchMethodError || error is TypeError) {
        throw state.error(
          SpelMessage.constructorNotFound,
          'Constructor of $typeName cannot be called with $args',
          start,
          error,
        );
      }
      throw state.error(
        SpelMessage.constructorInvocationProblem,
        'Constructor of $typeName threw an exception',
        start,
        error,
      );
    }
  }

  @override
  String toString() => 'new $typeName(${arguments.join(',')})';
}

/// A bean reference, `@name`, `@'dotted.name'` or `&factoryBean`.
///
/// Resolved by the context's [BeanResolver] (e.g. `BeanFactoryResolver`).
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
    final resolver = state.context.beanResolver;
    if (resolver == null) {
      throw state.error(
        SpelMessage.beanResolverNotRegistered,
        'No bean resolver registered in the context to resolve access to '
        "bean '$name'",
        start,
      );
    }
    final beanName = factory ? '&$name' : name;
    try {
      return resolver.resolve(state.context, beanName);
    } catch (error) {
      throw state.error(
        SpelMessage.beanNotFound,
        "Bean '$beanName' cannot be resolved",
        start,
        error,
      );
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
/// Arithmetic follows Java: `int / int` truncates (`7 / 2` is `3`),
/// division or modulus of ints by zero fails, `%` keeps the sign of the
/// left operand, and `int ^ int` stays an `int` for non-negative
/// exponents. `+` concatenates when either side is a string. Numbers
/// compare by value across `int` and `double` (`2 == 2.0`). Other operand
/// types go to the context's [OperatorOverloader].
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
            SpelMessage.operatorNotSupported,
            'instanceof needs a type reference on the right',
            right.start,
          );
        }
        return type.isInstance(value);
      default:
        return _evaluate(state, left.getValue(state), right.getValue(state));
    }
  }

  Object? _evaluate(ExpressionState state, Object? l, Object? r) {
    final context = state.context;
    switch (kind) {
      case BinaryKind.eq:
        return equalityCheck(context, l, r);
      case BinaryKind.ne:
        return !equalityCheck(context, l, r);
      case BinaryKind.lt || BinaryKind.le || BinaryKind.gt || BinaryKind.ge:
        final comparator = context.typeComparator;
        if (!comparator.canCompare(l, r)) {
          throw state.error(
            SpelMessage.notComparable,
            'Cannot compare ${l.runtimeType} and ${r.runtimeType}',
            start,
          );
        }
        final result = comparator.compare(l, r);
        return switch (kind) {
          BinaryKind.lt => result < 0,
          BinaryKind.le => result <= 0,
          BinaryKind.gt => result > 0,
          _ => result >= 0,
        };
      case BinaryKind.matches:
        if (l is! String || r is! String) {
          throw state.error(
            SpelMessage.invalidRegex,
            'matches needs a string and a regular expression',
            start,
          );
        }
        if (r.length > SpelLimits.maxRegexLength) {
          throw state.error(
            SpelMessage.maxRegexLengthExceeded,
            'The regular expression is ${r.length} characters long; the '
            'maximum is ${SpelLimits.maxRegexLength}',
            right.start,
          );
        }
        // Anchored, so the whole string must match (Java's
        // String.matches semantics).
        try {
          return RegExp('^(?:$r)\$').hasMatch(l);
        } on FormatException catch (error) {
          throw state.error(
            SpelMessage.invalidRegex,
            "Invalid regular expression '$r'",
            right.start,
            error,
          );
        }
      case BinaryKind.between:
        if (r is! List || r.length != 2) {
          throw state.error(
            SpelMessage.betweenRightOperandMustBeTwoElementList,
            "Right operand of 'between' must be a two-element list",
            right.start,
          );
        }
        final comparator = context.typeComparator;
        if (!comparator.canCompare(r[0], l) ||
            !comparator.canCompare(l, r[1])) {
          throw state.error(
            SpelMessage.notComparable,
            'Cannot compare ${l.runtimeType} with '
            '${r[0].runtimeType} and ${r[1].runtimeType}',
            start,
          );
        }
        return comparator.compare(r[0], l) <= 0 &&
            comparator.compare(l, r[1]) <= 0;
      default:
        return arithmetic(state, l, r);
    }
  }

  // A `+` operand as text: strings as they are, `null` as `null`, other
  // values through the context's TypeConverter when it can convert them
  // (Spring's OpPlus.convertTypedValueToString).
  static String _concatPart(ExpressionState state, Object? value) {
    if (value is String) {
      return value;
    }
    final converter = state.context.typeConverter;
    if (value != null && converter.canConvert(value, String)) {
      return '${converter.convertValue(value, String)}';
    }
    return '$value';
  }

  /// Applies this arithmetic operator to the evaluated operands [l] and
  /// [r]: numbers natively, then string concatenation (`+`) and
  /// repetition (`string * int`), then the context's
  /// [OperatorOverloader].
  ///
  /// Throws [SpelMessage.operatorNotSupported] when nothing applies.
  Object? arithmetic(ExpressionState state, Object? l, Object? r) {
    final operation = switch (kind) {
      BinaryKind.add => Operation.add,
      BinaryKind.subtract => Operation.subtract,
      BinaryKind.multiply => Operation.multiply,
      BinaryKind.divide => Operation.divide,
      BinaryKind.modulus => Operation.modulus,
      _ => Operation.power,
    };
    if (l is num && r is num) {
      switch (operation) {
        case Operation.add:
          return l + r;
        case Operation.subtract:
          return l - r;
        case Operation.multiply:
          return l * r;
        case Operation.divide:
          // Java-like integer division: two ints truncate toward zero and
          // fail on zero; any double gives a double (1 / 0.0 = Infinity).
          if (l is int && r is int) {
            if (r == 0) {
              throw state.error(
                SpelMessage.divisionByZero,
                'Division by zero',
                start,
              );
            }
            return l ~/ r;
          }
          return l / r;
        case Operation.modulus:
          if (l is int && r is int && r == 0) {
            throw state.error(
              SpelMessage.divisionByZero,
              'Division by zero',
              start,
            );
          }
          // remainder (not Dart's %) keeps the sign of the dividend, like
          // Java: -7 % 3 == -1.
          return l.remainder(r);
        case Operation.power:
          // int ^ non-negative int stays an int (exponentiation by
          // squaring, so huge exponents finish quickly); otherwise a
          // double via math.pow.
          if (l is int && r is int && r >= 0) {
            var result = 1;
            var base = l;
            for (var exponent = r; exponent > 0; exponent >>= 1) {
              if (exponent & 1 == 1) {
                result *= base;
              }
              base *= base;
            }
            return result;
          }
          return math.pow(l, r).toDouble();
      }
    }
    if (operation == Operation.add && (l is String || r is String)) {
      // Spring's OpPlus converts the other operand with the TypeConverter.
      final text = '${_concatPart(state, l)}${_concatPart(state, r)}';
      if (text.length > SpelLimits.maxConcatenatedStringLength) {
        throw state.error(
          SpelMessage.maxConcatenatedStringLengthExceeded,
          'Concatenated string is ${text.length} characters long; the '
          'maximum is ${SpelLimits.maxConcatenatedStringLength}',
          start,
        );
      }
      return text;
    }
    if (operation == Operation.multiply && l is String && r is int) {
      if (r < 0) {
        throw state.error(
          SpelMessage.negativeRepeatedTextCount,
          'Repeat count $r must not be negative',
          start,
        );
      }
      if (l.length * r > SpelLimits.maxRepeatedTextSize) {
        throw state.error(
          SpelMessage.maxRepeatedTextSizeExceeded,
          'Repeated text would be ${l.length * r} characters long; the '
          'maximum is ${SpelLimits.maxRepeatedTextSize}',
          start,
        );
      }
      return l * r;
    }
    final overloader = state.context.operatorOverloader;
    if (overloader.overridesOperation(operation, l, r)) {
      return overloader.operate(operation, l, r);
    }
    throw state.error(
      SpelMessage.operatorNotSupported,
      "Operator '${operation.name}' is not supported for "
      '${l.runtimeType} and ${r.runtimeType}',
      start,
    );
  }

  /// Numbers are equal by value, otherwise `==` (or `compareTo == 0` for
  /// comparable values of the same type), like Spring.
  static bool equalityCheck(EvaluationContext context, Object? l, Object? r) {
    if (l is num && r is num) {
      return l.compareTo(r) == 0;
    }
    if (l == r) {
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
      case UnaryKind.minus || UnaryKind.plus:
        if (value is! num) {
          throw state.error(
            SpelMessage.operatorNotSupported,
            "Unary '${kind == UnaryKind.minus ? '-' : '+'}' is not supported "
            'for ${value.runtimeType}',
            start,
          );
        }
        return kind == UnaryKind.minus ? -value : value;
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
  Object? getValue(ExpressionState state) =>
      state.asBool(condition.getValue(state), condition.start)
      ? whenTrue.getValue(state)
      : whenFalse.getValue(state);

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
    return result == null || (result is String && result.isEmpty)
        ? fallback.getValue(state)
        : result;
  }

  @override
  String toString() => '($value ?: $fallback)';
}

/// Assignment, `target = value`, evaluating to the assigned value.
///
/// The target can be a property, a variable (`#x`) or an indexed element;
/// assignment must be enabled in the context.
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
      throw state.error(
        SpelMessage.notAssignable,
        'Assignment is disabled in this context',
        start,
      );
    }
    final target = this.target;
    if (target is VariableReference && target.isAssignable) {
      // Like Spring, the value is only evaluated when the context allows
      // the assignment.
      return state.context.assignVariable(
        target.name,
        () => value.getValue(state),
      );
    }
    final newValue = value.getValue(state);
    target.getValueRef(state).setValue(newValue);
    return newValue;
  }

  @override
  String toString() => '$target = $value';
}

/// `++x`, `x++`, `--x`, `x--` on assignable numeric targets.
///
/// Prefix forms evaluate to the new value, postfix forms to the old one.
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
      throw state.error(
        SpelMessage.notAssignable,
        'Assignment is disabled in this context',
        start,
      );
    }
    if (!target.isAssignable) {
      throw state.error(
        SpelMessage.notAssignable,
        'Cannot ${increment ? 'increment' : 'decrement'} $target',
        start,
      );
    }
    final ref = target.getValueRef(state);
    final current = ref.getValue();
    if (current is! num) {
      throw state.error(
        SpelMessage.operatorNotSupported,
        'Cannot ${increment ? 'increment' : 'decrement'} ${current.runtimeType}',
        start,
      );
    }
    final next = increment ? current + 1 : current - 1;
    ref.setValue(next);
    return prefix ? next : current;
  }

  @override
  String toString() => prefix
      ? '${increment ? '++' : '--'}$target'
      : '$target${increment ? '++' : '--'}';
}
