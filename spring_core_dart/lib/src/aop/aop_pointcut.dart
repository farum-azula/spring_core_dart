import 'package:spring_core_dart/src/aop/join_point.dart';

/// Decides which members advice applies to, like Spring's `Pointcut`
/// (renamed because `@Pointcut` is the annotation).
///
/// Unlike Spring's `ClassFilter` + `MethodMatcher` pair, one static check
/// sees the member signature and the bean name.
///
/// ```dart
/// final class ReadOnlyPointcut implements AopPointcut {
///   const ReadOnlyPointcut();
///
///   @override
///   bool matches(MethodSignature signature, String beanName) =>
///       signature.name.startsWith('find') ||
///       signature.kind == MemberKind.getter;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class ReadOnlyPointcut extends StaticMethodMatcherPointcut {
///   public boolean matches(Method method, Class<?> targetClass) {
///     return method.getName().startsWith("find");
///   }
/// }
/// ```
abstract interface class AopPointcut {
  /// Whether advice applies to the member described by [signature] of
  /// the bean named [beanName].
  bool matches(MethodSignature signature, String beanName);
}

/// Matches every member.
///
/// ```dart
/// DefaultPointcutAdvisor(const TruePointcut(), LoggingInterceptor());
/// ```
///
/// Spring (Java):
/// ```java
/// new DefaultPointcutAdvisor(Pointcut.TRUE, new LoggingInterceptor());
/// ```
final class TruePointcut implements AopPointcut {
  /// Creates the match-all pointcut.
  const TruePointcut();

  @override
  bool matches(MethodSignature signature, String beanName) => true;
}

/// Matches member names with `*` wildcards, like Spring's
/// `NameMatchMethodPointcut`.
///
/// ```dart
/// DefaultPointcutAdvisor(
///   const NameMatchMethodPointcut(['find*', 'count']),
///   CachingInterceptor(),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// NameMatchMethodPointcut pointcut = new NameMatchMethodPointcut();
/// pointcut.setMappedNames("find*", "count");
/// new DefaultPointcutAdvisor(pointcut, new CachingInterceptor());
/// ```
final class NameMatchMethodPointcut implements AopPointcut {
  /// Creates a pointcut matching any of the [names] patterns.
  const NameMatchMethodPointcut(this.names);

  /// Member name patterns; `*` matches any characters.
  final List<String> names;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      names.any((pattern) => wildcardMatch(pattern, signature.name));
}

/// Matches members (or classes) carrying an annotation of type [A], like
/// Spring's `AnnotationMatchingPointcut`.
///
/// ```dart
/// // Methods annotated with @Timed().
/// const AnnotationMatchingPointcut<Timed>();
/// // Every member of classes annotated with @Service().
/// const AnnotationMatchingPointcut<Service>(onClass: true);
/// ```
///
/// Spring (Java):
/// ```java
/// AnnotationMatchingPointcut.forMethodAnnotation(Timed.class);
/// AnnotationMatchingPointcut.forClassAnnotation(Service.class);
/// ```
final class AnnotationMatchingPointcut<A> implements AopPointcut {
  /// Creates a pointcut for annotations of type [A] on members (or on
  /// the class when [onClass] is `true`).
  const AnnotationMatchingPointcut({this.onClass = false});

  /// Match the class annotation instead of the member annotation.
  final bool onClass;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      (onClass ? signature.targetAnnotations : signature.annotations).any(
        (a) => a is A,
      );
}

/// `*` wildcard matching.
///
/// The whole [text] must match; every other character is literal.
///
/// ```dart
/// wildcardMatch('find*', 'findAll'); // true
/// wildcardMatch('*Service', 'UserRepository'); // false
/// ```
bool wildcardMatch(String pattern, String text) =>
    RegExp('^${pattern.split('*').map(RegExp.escape).join('.*')}\$')
        .hasMatch(text);

/// An advice parameter that a pointcut expression binds, like the
/// parameter names Spring's `AspectJExpressionPointcut` binds
/// (`@annotation(timed)`, `args(id, ..)`, `this(service)`).
///
/// Written by the generator for every advice parameter that is neither a
/// `JoinPoint` nor the returned value / thrown error: [typeName] is the
/// simple name of the parameter type (release-safe) and [accepts] tests a
/// value against that type.
///
/// ```dart
/// // @Around('@annotation(timed)')
/// // Object? time(ProceedingJoinPoint call, Timed timed) => ...
/// AdviceBinding('Timed', (value) => value is Timed);
/// ```
///
/// Spring (Java):
/// ```java
/// @Around("@annotation(timed)")
/// Object time(ProceedingJoinPoint call, Timed timed) throws Throwable { ... }
/// ```
final class AdviceBinding {
  /// Binds a parameter of the type named [typeName]; `accepts` checks a
  /// value against that type.
  AdviceBinding(this.typeName, this._accepts);

  /// Simple name of the parameter type, e.g. `Timed`.
  final String typeName;

  final bool Function(Object? value) _accepts;

  /// Whether [value] has the parameter type.
  bool accepts(Object? value) => _accepts(value);

  @override
  String toString() => 'AdviceBinding($typeName)';
}

/// Pointcut expressions in Spring's syntax (`execution(...)`, `within(...)`,
/// `bean(...)`, ...).
///
/// Supported designators (names match simple type names; package parts of
/// patterns are ignored since Dart has libraries, not packages):
/// - `execution([modifiers] ret [Type.]method(params))` — `*` wildcards,
///   `..` for any parameters, `*` for one parameter, `Type+` for the type
///   and its subtypes;
/// - `within(TypePattern)` — the bean class (`Type+`: or a subtype);
/// - `target(Type)` / `this(Type)` — the bean class or any supertype;
/// - `args(...)` — the parameters (declared types; `..` for any number);
/// - `bean(namePattern)` — the bean name, an alias or a qualifier value;
/// - `@annotation(Name)` — an annotation on the member;
/// - `@within(Name)` / `@target(Name)` — an annotation on the bean class;
/// - named pointcuts `name()` (of the same aspect) / `Type.name()`;
/// - `&&` / `and`, `||` / `or`, `!` / `not`, parentheses.
///
/// With [bindings] (written by the generator for advice parameters), an
/// identifier naming an advice parameter in `@annotation(x)`,
/// `@within(x)`, `@target(x)`, `this(x)`, `target(x)` or `args(...)` binds
/// that parameter: the advice receives the annotation, the proxy, the
/// target or the argument ([bind]).
///
/// The expression is parsed eagerly; invalid expressions throw a
/// [FormatException].
///
/// ```dart
/// final pointcut = ExpressionPointcut(
///   'service() && !execution(* *.slow*(..))',
///   namedPointcuts: {'service': 'within(*Service) || @within(Service)'},
/// );
/// DefaultPointcutAdvisor(pointcut, LoggingInterceptor());
///
/// ExpressionPointcut('execution(Future<int> Calculator.slowAdd(int, *))');
/// ExpressionPointcut('bean(echoShouter) or @annotation(Timed)');
/// ExpressionPointcut('within(Repository+)');
/// ```
///
/// Spring (Java):
/// ```java
/// AspectJExpressionPointcut pointcut = new AspectJExpressionPointcut();
/// pointcut.setExpression(
///     "within(com.example..*Service) && !execution(* *.slow*(..))");
/// new DefaultPointcutAdvisor(pointcut, new LoggingInterceptor());
/// ```
final class ExpressionPointcut implements AopPointcut {
  /// Parses [expression].
  ///
  /// [namedPointcuts] resolve references: an unqualified `name()` is looked
  /// up as `'$owner.name'`, then as `'name'`; a qualified `Type.name()`
  /// only as `'Type.name'` (unqualified references inside it then refer to
  /// `Type`'s pointcuts). [bindings] are the advice parameters the
  /// expression may bind, by name.
  ExpressionPointcut(
    this.expression, {
    Map<String, String> namedPointcuts = const {},
    Map<String, AdviceBinding> bindings = const {},
    this.owner,
  }) : bindings = Map.unmodifiable(bindings),
       _root = _PointcutParser(
         expression,
         namedPointcuts,
         {},
         owner,
         bindings,
       ).parse();

  /// The source expression.
  final String expression;

  /// The type (aspect or pointcut holder) whose pointcuts unqualified
  /// references refer to.
  final String? owner;

  /// Advice parameters this expression may bind, by name.
  final Map<String, AdviceBinding> bindings;

  // The expression compiled into a tree, evaluated per member.
  final _Node _root;

  /// Whether the expression binds advice parameters or tests arguments,
  /// so it must also be evaluated for every call ([bind]).
  bool get isRuntime => _root.isRuntime;

  /// Static match: `false` only when no call of the member can match
  /// (parts that depend on the arguments are assumed to match).
  @override
  bool matches(MethodSignature signature, String beanName) =>
      matchesBean(signature, beanName, const []);

  /// Like [matches], with the bean's aliases and qualifier values for
  /// `bean(...)` (Spring's `BeanFactoryAnnotationUtils.isQualifierMatch`).
  bool matchesBean(
    MethodSignature signature,
    String beanName,
    List<String> beanAliases,
  ) => _root.check(_Static(signature, [beanName, ...beanAliases])) != false;

  /// Evaluates the expression for one call: the bound advice parameters
  /// (empty when nothing is bound), or `null` when the call does not
  /// match (e.g. `args(id)` with an argument of another type).
  Map<String, Object?>? bind(
    MethodInvocation invocation, {
    String beanName = '',
    List<String> beanAliases = const [],
  }) {
    final bound = <String, Object?>{};
    final context = _Dynamic(invocation, [beanName, ...beanAliases]);
    return _root.run(context, bound) ? Map.unmodifiable(bound) : null;
  }

  @override
  String toString() => 'ExpressionPointcut: $expression';
}

// What a static check sees: the member and the bean's names.
class _Static {
  _Static(this.signature, this.beanNames);

  final MethodSignature signature;
  final List<String> beanNames;
}

// What a call-time check sees: the static information plus the call.
final class _Dynamic extends _Static {
  _Dynamic(this.invocation, List<String> beanNames)
    : super(invocation.signature, beanNames);

  final MethodInvocation invocation;
}

// A compiled expression. [check] decides from the signature alone: `true`,
// `false`, or `null` when only the call can tell; [run] decides for one
// call and adds bound values to `bound`.
sealed class _Node {
  bool? check(_Static context);
  bool run(_Dynamic context, Map<String, Object?> bound);
  bool get isRuntime;
}

final class _And extends _Node {
  _And(this.left, this.right);
  final _Node left;
  final _Node right;

  @override
  bool? check(_Static context) {
    final l = left.check(context);
    if (l == false) {
      return false;
    }
    final r = right.check(context);
    if (r == false) {
      return false;
    }
    return l == true && r == true ? true : null;
  }

  @override
  bool run(_Dynamic context, Map<String, Object?> bound) =>
      left.run(context, bound) && right.run(context, bound);

  @override
  bool get isRuntime => left.isRuntime || right.isRuntime;
}

final class _Or extends _Node {
  _Or(this.left, this.right);
  final _Node left;
  final _Node right;

  @override
  bool? check(_Static context) {
    final l = left.check(context);
    if (l == true) {
      return true;
    }
    final r = right.check(context);
    if (r == true) {
      return true;
    }
    return l == false && r == false ? false : null;
  }

  // The first matching branch binds.
  @override
  bool run(_Dynamic context, Map<String, Object?> bound) {
    final first = <String, Object?>{};
    if (left.run(context, first)) {
      bound.addAll(first);
      return true;
    }
    final second = <String, Object?>{};
    if (right.run(context, second)) {
      bound.addAll(second);
      return true;
    }
    return false;
  }

  @override
  bool get isRuntime => left.isRuntime || right.isRuntime;
}

final class _Not extends _Node {
  _Not(this.inner);
  final _Node inner;

  @override
  bool? check(_Static context) {
    final value = inner.check(context);
    return value == null ? null : !value;
  }

  // Values bound under `!` are dropped (nothing matched to bind them).
  @override
  bool run(_Dynamic context, Map<String, Object?> bound) =>
      !inner.run(context, <String, Object?>{});

  @override
  bool get isRuntime => inner.isRuntime;
}

// A designator. [test] is the static check; [bind] (for bindings and
// argument checks) decides a call and binds values.
final class _Leaf extends _Node {
  _Leaf(this.test, {this.bind, this.dynamicCheck = false});

  final bool Function(_Static context) test;
  final bool Function(_Dynamic context, Map<String, Object?> bound)? bind;

  // Whether a passing static test still depends on the call.
  final bool dynamicCheck;

  @override
  bool? check(_Static context) =>
      test(context) ? (dynamicCheck ? null : true) : false;

  @override
  bool run(_Dynamic context, Map<String, Object?> bound) =>
      test(context) && (bind?.call(context, bound) ?? true);

  @override
  bool get isRuntime => bind != null;
}

// Recursive-descent parser compiling an expression into a [_Node] tree.
//
// Grammar (lowest precedence first):
//   or      := and (('||' | 'or') and)*
//   and     := not (('&&' | 'and') not)*
//   not     := ('!' | 'not') not | primary
//   primary := '(' or ')' | designator '(' raw text ')'
//
// Designator bodies (e.g. `* Calculator.*(..)`) are not tokenized further:
// [_parenthesized] slices the raw text between balanced parentheses and
// each designator parses it on its own. A designator name it does not
// know, followed by `()`, is a named pointcut reference.
final class _PointcutParser {
  _PointcutParser(
    this.expression,
    this.named,
    this.resolving,
    this.owner,
    this.bindings,
  )
    // Tokens: operators, parentheses, identifiers (optionally `@`-prefixed
    // and dotted, e.g. `@annotation`, `Aspect.name`) and any other run of
    // non-space characters (e.g. `*`, `..`). Matches keep their offsets so
    // designator bodies can be cut from the source text.
    : _matches = RegExp(r'&&|\|\||!|\(|\)|@?[A-Za-z_$][\w$.]*|[^\s()]+')
          .allMatches(expression)
          .toList();

  final String expression;
  final Map<String, String> named;
  // References being resolved up the stack, to detect cycles.
  final Set<String> resolving;
  // Whose pointcuts unqualified references refer to.
  final String? owner;
  final Map<String, AdviceBinding> bindings;
  final List<RegExpMatch> _matches;
  int _pos = 0;

  List<String> get _tokens => [for (final m in _matches) m[0]!];

  _Node parse() {
    if (_tokens.isEmpty) {
      throw _error('empty pointcut expression');
    }
    final node = _or();
    if (_pos != _tokens.length) {
      throw _error("unexpected '${_tokens[_pos]}'");
    }
    return node;
  }

  _Node _or() {
    var left = _and();
    while (_peekAny(const ['||', 'or'])) {
      _pos++;
      left = _Or(left, _and());
    }
    return left;
  }

  _Node _and() {
    var left = _not();
    while (_peekAny(const ['&&', 'and'])) {
      _pos++;
      left = _And(left, _not());
    }
    return left;
  }

  _Node _not() {
    if (_peekAny(const ['!', 'not'])) {
      _pos++;
      return _Not(_not());
    }
    return _primary();
  }

  _Node _primary() {
    if (_pos >= _tokens.length) {
      throw _error('unexpected end of expression');
    }
    final token = _tokens[_pos++];
    if (token == '(') {
      final inner = _or();
      _expect(')');
      return inner;
    }
    // Every designator and named reference is followed by `( ... )`.
    final body = _parenthesized();
    switch (token) {
      case 'execution':
        return _execution(body);
      case 'within':
        final (pattern, subtypes) = _typePattern(body);
        return _Leaf((c) => _typeMatches(pattern, subtypes, c.signature));
      // Proxies implement the bean's types, so `this` and `target` check
      // the same types; bound, `this` is the proxy and `target` the bean.
      case 'target' || 'this':
        return _targetOrThis(body, isThis: token == 'this');
      case 'args':
        return _args(body);
      case 'bean':
        final pattern = body.trim();
        return _Leaf((c) => c.beanNames.any((n) => wildcardMatch(pattern, n)));
      case '@annotation':
        return _annotation(
          body,
          (s) => _names(s.annotationTypes, s.annotations),
          (s) => s.annotations,
        );
      case '@within' || '@target':
        return _annotation(
          body,
          (s) => _names(s.targetAnnotationTypes, s.targetAnnotations),
          (s) => s.targetAnnotations,
        );
      default:
        if (body.trim().isNotEmpty) {
          throw _error("unknown designator '$token'");
        }
        return _named(token);
    }
  }

  _Node _targetOrThis(String body, {required bool isThis}) {
    final binding = _binding(body);
    final type = binding?.typeName ?? _simple(body);
    bool test(_Static c) =>
        c.signature.targetTypes.contains(type) ||
        c.signature.targetType == type;
    if (binding == null) {
      return _Leaf(test);
    }
    final name = body.trim();
    return _Leaf(
      test,
      bind: (c, bound) {
        final value = isThis ? c.invocation.proxy : c.invocation.target;
        if (!binding.accepts(value)) {
          return false;
        }
        bound[name] = value;
        return true;
      },
    );
  }

  // `@annotation(Name)` / `@annotation(name)` (a binding), likewise
  // `@within` and `@target`.
  _Node _annotation(
    String body,
    List<String> Function(MethodSignature s) names,
    List<Object> Function(MethodSignature s) values,
  ) {
    final binding = _binding(body);
    if (binding == null) {
      final name = _annotationName(body);
      return _Leaf((c) => names(c.signature).contains(name));
    }
    final parameter = body.trim();
    return _Leaf(
      (c) => names(c.signature).contains(binding.typeName),
      bind: (c, bound) {
        for (final annotation in values(c.signature)) {
          if (binding.accepts(annotation)) {
            bound[parameter] = annotation;
            return true;
          }
        }
        return false;
      },
    );
  }

  // `args(String, ..)`, `args(id, ..)`: declared parameter types are
  // checked statically; bound arguments are checked (and bound) per call.
  _Node _args(String body) {
    // `null`: `..`; `(name, binding)`: a binding; a `String`: a type name
    // pattern.
    final items = <Object?>[
      for (final p in _splitParameters(body))
        if (p.trim() case final trimmed when trimmed.isNotEmpty)
          if (trimmed == '..')
            null
          else if (_binding(trimmed) case final binding?)
            (trimmed, binding)
          else
            _stripGenerics(trimmed),
    ];
    List<String> types(_Static c) => c.signature.parameterTypes;
    bool test(_Static c) =>
        _matchArgs(items, types(c).length, 0, 0, (item, index) {
          if (item case final String pattern) {
            return wildcardMatch(pattern, types(c)[index]);
          }
          return true;
        });
    if (!items.any((item) => item is (String, AdviceBinding))) {
      return _Leaf(test);
    }
    return _Leaf(
      test,
      dynamicCheck: true,
      bind: (c, bound) {
        final args = c.invocation.args;
        final declared = types(c);
        final values = <String, Object?>{};
        final matched = _matchArgs(items, args.length, 0, 0, (item, index) {
          switch (item) {
            case final String pattern:
              return index >= declared.length ||
                  wildcardMatch(pattern, declared[index]);
            case (final String name, final AdviceBinding binding):
              if (!binding.accepts(args[index])) {
                return false;
              }
              values[name] = args[index];
              return true;
          }
          return true;
        });
        if (matched) {
          bound.addAll(values);
        }
        return matched;
      },
    );
  }

  // Aligns [items] (`null` = `..`) with [count] values by backtracking;
  // [accept] checks one item at one index.
  static bool _matchArgs(
    List<Object?> items,
    int count,
    int item,
    int index,
    bool Function(Object item, int index) accept,
  ) {
    if (item == items.length) {
      return index == count;
    }
    final current = items[item];
    if (current == null) {
      for (var skip = index; skip <= count; skip++) {
        if (_matchArgs(items, count, item + 1, skip, accept)) {
          return true;
        }
      }
      return false;
    }
    return index < count &&
        accept(current, index) &&
        _matchArgs(items, count, item + 1, index + 1, accept);
  }

  // The binding named by [body] (an advice parameter), if any.
  AdviceBinding? _binding(String body) => bindings[body.trim()];

  // Resolves `name()` / `Type.name()`: an unqualified name in the owner's
  // pointcuts first, then among the unqualified entries; a qualified one
  // only as `Type.name` (whose own references then refer to `Type`).
  _Node _named(String reference) {
    final String key;
    final String? nestedOwner;
    if (!reference.contains('.')) {
      final scoped = owner == null ? null : '$owner.$reference';
      if (scoped != null && named.containsKey(scoped)) {
        key = scoped;
      } else if (named.containsKey(reference)) {
        key = reference;
      } else {
        throw _error("unknown pointcut '$reference'");
      }
      nestedOwner = owner;
    } else {
      // `com.x.CommonPointcuts.web` → `CommonPointcuts.web`.
      final segments = reference.split('.');
      final type = segments[segments.length - 2];
      key = '$type.${segments.last}';
      if (!named.containsKey(key)) {
        throw _error("unknown pointcut '$reference'");
      }
      nestedOwner = type;
    }
    if (!resolving.add(key)) {
      throw _error("circular pointcut reference '$reference'");
    }
    try {
      return _PointcutParser(
        named[key]!,
        named,
        resolving,
        nestedOwner,
        bindings,
      ).parse();
    } finally {
      resolving.remove(key);
    }
  }

  /// The raw text between the next '(' and its matching ')'.
  String _parenthesized() {
    _expect('(');
    final start = _matches[_pos - 1].end;
    var depth = 1;
    while (_pos < _matches.length) {
      final token = _matches[_pos][0];
      if (token == '(') {
        depth++;
      } else if (token == ')') {
        depth--;
        if (depth == 0) {
          final body = expression.substring(start, _matches[_pos].start);
          _pos++;
          return body;
        }
      }
      _pos++;
    }
    throw _error("missing ')'");
  }

  // `execution([modifiers] returnType [Type.]name(params))`; Java
  // modifiers are accepted and ignored. The type pattern may match the
  // declaring type, the bean class or any type declaring the member;
  // `Type+` also any supertype of the bean class.
  _Node _execution(String body) {
    final match = RegExp(
      r'^\s*(?:(?:public|static|final)\s+)*(\S+)\s+([^\s(]+)\s*\((.*)\)\s*$',
    ).firstMatch(body);
    if (match == null) {
      throw _error("malformed execution pattern '$body'");
    }
    final returnPattern = _stripGenerics(match[1]!);
    final qualified = match[2]!;
    final dot = qualified.lastIndexOf('.');
    final methodPattern = dot < 0 ? qualified : qualified.substring(dot + 1);
    final typePattern = dot < 0
        ? null
        : _typePattern(qualified.substring(0, dot));
    final params = [
      for (final p in _splitParameters(match[3]!))
        if (p.trim().isNotEmpty) _stripGenerics(p.trim()),
    ];
    return _Leaf(
      (c) =>
          c.signature.kind == MemberKind.method &&
          wildcardMatch(returnPattern, c.signature.returnType) &&
          wildcardMatch(methodPattern, c.signature.name) &&
          (typePattern == null ||
              _declaringMatches(typePattern.$1, typePattern.$2, c.signature)) &&
          _matchParams(params, c.signature.parameterTypes),
    );
  }

  static bool _declaringMatches(
    String pattern,
    bool subtypes,
    MethodSignature s,
  ) =>
      wildcardMatch(pattern, s.declaringType) ||
      wildcardMatch(pattern, s.targetType) ||
      s.declaringTypes.any((t) => wildcardMatch(pattern, t)) ||
      (subtypes && s.targetTypes.any((t) => wildcardMatch(pattern, t)));

  // `within(Type)`: the bean class; `within(Type+)`: or any supertype of it
  // (the bean is a subtype of `Type`).
  static bool _typeMatches(String pattern, bool subtypes, MethodSignature s) =>
      wildcardMatch(pattern, s.targetType) ||
      (subtypes && s.targetTypes.any((t) => wildcardMatch(pattern, t)));

  // Matches parameter types against patterns; `..` matches zero or more
  // parameters (tried by backtracking over every possible skip).
  static bool _matchParams(List<String> patterns, List<String> types) {
    if (patterns.isEmpty) {
      return types.isEmpty;
    }
    final head = patterns.first;
    if (head == '..') {
      for (var skip = 0; skip <= types.length; skip++) {
        if (_matchParams(patterns.sublist(1), types.sublist(skip))) {
          return true;
        }
      }
      return false;
    }
    return types.isNotEmpty &&
        wildcardMatch(head, types.first) &&
        _matchParams(patterns.sublist(1), types.sublist(1));
  }

  // Splits a parameter list at top-level commas (`Map<String, int>, ..`).
  static List<String> _splitParameters(String text) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
        case ',' when depth == 0:
          parts.add(text.substring(start, i));
          start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }

  // A type pattern with an optional trailing `+` (the type and its
  // subtypes): the simple pattern and whether `+` was given.
  (String, bool) _typePattern(String raw) {
    final cleaned = _stripGenerics(raw.trim());
    final subtypes = cleaned.endsWith('+');
    return (
      _simple(subtypes ? cleaned.substring(0, cleaned.length - 1) : cleaned),
      subtypes,
    );
  }

  /// Last segment of a dotted type pattern, without generics.
  ///
  /// Dart has no Java packages: `com.x.Service` is reduced to `Service`,
  /// but a qualified wildcard such as `com.x.service..*` is rejected —
  /// reducing it to `*` would silently match every bean.
  String _simple(String pattern) {
    final cleaned = _stripGenerics(pattern.trim()).replaceAll(' ', '');
    final parts = cleaned.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return cleaned;
    }
    if (parts.length > 1 && parts.last.contains('*')) {
      throw _error(
        "package-qualified type pattern '$cleaned' is not supported (Dart "
        'has no packages); use a simple type name pattern such as '
        "'*Service'",
      );
    }
    return parts.last;
  }

  // The annotation type of `@annotation(X)` / `@within(X)`. A lower-case
  // name that is not an advice parameter cannot be bound: rejected
  // instead of silently matching nothing.
  String _annotationName(String body) {
    final name = _simple(body);
    if (name.isNotEmpty && name[0] != name[0].toUpperCase()) {
      throw _error(
        "argument binding '$name' needs an advice parameter named '$name'; "
        'otherwise use the annotation type name, e.g. @annotation(Timed), '
        'and read it from joinPoint.signature.annotations',
      );
    }
    return name;
  }

  // Generated names when present (release-safe), else runtime type names.
  static List<String> _names(List<String> generated, List<Object> values) =>
      generated.isNotEmpty ? generated : [for (final a in values) _typeName(a)];

  // `Future<int>` → `Future`; `?` is dropped so `int?` matches `int`.
  static String _stripGenerics(String type) {
    final index = type.indexOf('<');
    return (index < 0 ? type : type.substring(0, index)).replaceAll('?', '');
  }

  // Annotations are matched by simple runtime type name.
  static String _typeName(Object annotation) =>
      _stripGenerics(annotation.runtimeType.toString());

  bool _peekAny(List<String> values) =>
      _pos < _tokens.length && values.contains(_tokens[_pos]);

  void _expect(String token) {
    if (_pos >= _tokens.length || _tokens[_pos] != token) {
      throw _error("expected '$token'");
    }
    _pos++;
  }

  FormatException _error(String message) =>
      FormatException('Invalid pointcut ($message)', expression);
}
