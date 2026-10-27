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

/// A pointcut that matches only members or classes carrying annotations
/// from outside `package:spring_core_dart` (`@Cacheable`, `@Validated`),
/// like Spring's annotation-driven advisors.
///
/// The build skips the proxy classes of beans no pointcut can match
/// (`aop_prune`), keeping every bean that carries such an annotation. An
/// advisor bean of a starter's auto-configuration whose pointcut is an
/// `AnnotationPointcut` (declared so in the advisor's static type) keeps
/// that saving; any other advisor bean of a starter turns it off, since
/// the build cannot tell which beans it matches.
///
/// Read [MethodSignature.mergedAnnotations] to also see the annotations of
/// the superclass, mixin and interface declarations the member overrides
/// (Spring's `AnnotatedElementUtils` find semantics), as the cache and
/// method validation advisors do; [MethodSignature.annotations] is what
/// `@annotation(...)` matches.
///
/// ```dart
/// final class CacheAnnotationPointcut implements AnnotationPointcut {
///   const CacheAnnotationPointcut();
///
///   @override
///   bool matches(MethodSignature signature, String beanName) =>
///       signature.mergedAnnotations.any((a) => a is Cacheable);
/// }
///
/// DefaultPointcutAdvisor(const CacheAnnotationPointcut(), interceptor);
/// ```
///
/// Spring (Java):
/// ```java
/// new DefaultPointcutAdvisor(
///     new AnnotationMatchingPointcut(null, Cacheable.class), interceptor);
/// ```
abstract interface class AnnotationPointcut implements AopPointcut {}

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
final class AnnotationMatchingPointcut<A> implements AnnotationPointcut {
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

/// Combines pointcuts with [union] and [intersection], like Spring's
/// `ComposablePointcut` (a mutable builder: both return the pointcut
/// itself).
///
/// The match is static: an [ExpressionPointcut] part that depends on the
/// call (`args(id)`, bindings) counts as matching here; use it on its own
/// in an advisor to have it decided per call.
///
/// ```dart
/// final pointcut = ComposablePointcut(
///   const NameMatchMethodPointcut(['find*']),
/// ).union(const AnnotationMatchingPointcut<Timed>())
///  .intersection(ExpressionPointcut('within(*Service)'));
/// DefaultPointcutAdvisor(pointcut, LoggingInterceptor());
/// ```
///
/// Spring (Java):
/// ```java
/// ComposablePointcut pointcut = new ComposablePointcut(findMethods)
///     .union(AnnotationMatchingPointcut.forMethodAnnotation(Timed.class))
///     .intersection(servicePointcut);
/// ```
final class ComposablePointcut implements AopPointcut {
  /// Starts from [pointcut] (every member by default).
  ComposablePointcut([AopPointcut pointcut = const TruePointcut()])
    : _matches = ((s, name, aliases, introduced) => pointcutMatchesBean(
        pointcut,
        s,
        name,
        aliases,
        introducedTypes: introduced,
      ));

  bool Function(
    MethodSignature s,
    String beanName,
    List<String> aliases,
    List<String> introducedTypes,
  )
  _matches;

  /// Matches what this pointcut or [other] matches.
  ComposablePointcut union(AopPointcut other) {
    final current = _matches;
    _matches = (s, name, aliases, introduced) =>
        current(s, name, aliases, introduced) ||
        pointcutMatchesBean(
          other,
          s,
          name,
          aliases,
          introducedTypes: introduced,
        );
    return this;
  }

  /// Matches what both this pointcut and [other] match.
  ComposablePointcut intersection(AopPointcut other) {
    final current = _matches;
    _matches = (s, name, aliases, introduced) =>
        current(s, name, aliases, introduced) &&
        pointcutMatchesBean(
          other,
          s,
          name,
          aliases,
          introducedTypes: introduced,
        );
    return this;
  }

  @override
  bool matches(MethodSignature signature, String beanName) =>
      _matches(signature, beanName, const [], const []);

  /// Like [matches], with the bean's aliases and qualifier values for the
  /// `bean(...)` parts and the interfaces `@DeclareParents` adds to its
  /// proxy ([introducedTypes]) for `this(...)`.
  bool matchesBean(
    MethodSignature signature,
    String beanName,
    List<String> beanAliases, {
    List<String> introducedTypes = const [],
  }) => _matches(signature, beanName, beanAliases, introducedTypes);
}

/// Whether [pointcut] matches [signature] of the bean [beanName], with its
/// aliases and qualifier values ([beanAliases]) for pointcuts that test
/// bean names and the interfaces `@DeclareParents` adds to the bean's proxy
/// ([introducedTypes]) for `this(...)` ([ExpressionPointcut],
/// [ComposablePointcut]).
///
/// ```dart
/// pointcutMatchesBean(pointcut, signature, 'orders', ['primaryOrders']);
/// ```
bool pointcutMatchesBean(
  AopPointcut pointcut,
  MethodSignature signature,
  String beanName,
  List<String> beanAliases, {
  List<String> introducedTypes = const [],
}) => switch (pointcut) {
  final ExpressionPointcut p => p.matchesBean(
    signature,
    beanName,
    beanAliases,
    introducedTypes: introducedTypes,
  ),
  final ComposablePointcut p => p.matchesBean(
    signature,
    beanName,
    beanAliases,
    introducedTypes: introducedTypes,
  ),
  _ => pointcut.matches(signature, beanName),
};

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
///   and its subtypes; modifiers `public`, `protected` (`@protected`
///   members), `private` (never), optionally negated with `!`; a `throws`
///   clause is rejected (Dart methods declare no exceptions);
/// - `within(TypePattern)` — the class whose body runs for the member (the
///   bean class, or the superclass or mixin it inherits the member from;
///   `Type+`: or a subtype of it);
/// - `target(Type)` / `this(Type)` — the bean class or any supertype;
/// - `args(...)` — the parameters (`..` for any number): the declared
///   type, or the runtime argument when `typeTests` has the type;
/// - `@args(...)` — arguments whose runtime class carries the annotation
///   (`argumentAnnotations`);
/// - `bean(namePattern)` — the bean name, an alias or a qualifier value;
/// - `@annotation(Name)` — an annotation on the member;
/// - `@within(Name)` — an annotation on the class whose body runs;
/// - `@target(Name)` — an annotation on the bean class;
/// - named pointcuts `name()` (of the same aspect) / `Type.name()`;
/// - `&&` / `and`, `||` / `or`, `!` / `not`, parentheses.
///
/// With [bindings] (written by the generator for advice parameters), an
/// identifier naming an advice parameter in `@annotation(x)`,
/// `@within(x)`, `@target(x)`, `this(x)`, `target(x)`, `args(...)` or
/// `@args(...)` binds that parameter: the advice receives the annotation,
/// the proxy, the target or the argument ([bind]).
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
  ///
  /// [typeTests] test a value against a type by its simple name
  /// (`'String': (v) => v is String`): `args(String)` then also matches a
  /// parameter of another declared type whose argument is a `String` at
  /// runtime (AspectJ's `instanceof` test). [argumentAnnotations] return
  /// the annotation of the given type that the runtime class of a value
  /// carries, or `null` (`'Audited': (v) => v is Order ? const Audited() :
  /// null`), for `@args(Audited)`. The generator writes both for aspects.
  ExpressionPointcut(
    this.expression, {
    Map<String, String> namedPointcuts = const {},
    Map<String, AdviceBinding> bindings = const {},
    Map<String, bool Function(Object? value)> typeTests = const {},
    Map<String, Object? Function(Object? value)> argumentAnnotations = const {},
    this.owner,
  }) : bindings = Map.unmodifiable(bindings),
       _root = _parse(
         expression,
         namedPointcuts,
         owner,
         bindings,
         typeTests,
         argumentAnnotations,
       );

  // Parses [expression]; every binding must be used by it (AspectJ's
  // "formal unbound in pointcut"), or the advice would receive `null`.
  static _Node _parse(
    String expression,
    Map<String, String> named,
    String? owner,
    Map<String, AdviceBinding> bindings,
    Map<String, bool Function(Object? value)> typeTests,
    Map<String, Object? Function(Object? value)> argumentAnnotations,
  ) {
    final used = <String>{};
    final root = _PointcutParser(
      expression,
      named,
      {},
      owner,
      bindings,
      used,
      typeTests,
      argumentAnnotations,
    ).parse();
    final unbound = bindings.keys.where((name) => !used.contains(name));
    if (unbound.isNotEmpty) {
      throw FormatException(
        'Invalid pointcut (advice parameter ${unbound.join(', ')} is not '
        'bound by the expression; bind it with @annotation(name), '
        '@within(name), @target(name), this(name), target(name), '
        'args(name, ..) or @args(name, ..), or remove the parameter)',
        expression,
      );
    }
    return root;
  }

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
  /// `bean(...)` (Spring's `BeanFactoryAnnotationUtils.isQualifierMatch`)
  /// and the interfaces `@DeclareParents` adds to the bean's proxy
  /// ([introducedTypes]) for `this(...)`.
  bool matchesBean(
    MethodSignature signature,
    String beanName,
    List<String> beanAliases, {
    List<String> introducedTypes = const [],
  }) =>
      _root.check(
        _Static(signature, [beanName, ...beanAliases], introducedTypes),
      ) !=
      false;

  /// Evaluates the expression for one call: the bound advice parameters
  /// (empty when nothing is bound), or `null` when the call does not
  /// match (e.g. `args(id)` with an argument of another type).
  Map<String, Object?>? bind(
    MethodInvocation invocation, {
    String beanName = '',
    List<String> beanAliases = const [],
    List<String> introducedTypes = const [],
  }) {
    final bound = <String, Object?>{};
    final context = _Dynamic(invocation, [
      beanName,
      ...beanAliases,
    ], introducedTypes);
    return _root.run(context, bound) ? Map.unmodifiable(bound) : null;
  }

  @override
  String toString() => 'ExpressionPointcut: $expression';
}

// What a static check sees: the member and the bean's names.
class _Static {
  _Static(this.signature, this.beanNames, [this.introducedTypes = const []]);

  final MethodSignature signature;
  final List<String> beanNames;

  /// Interfaces `@DeclareParents` adds to the proxy (for `this(...)`).
  final List<String> introducedTypes;
}

// What a call-time check sees: the static information plus the call.
final class _Dynamic extends _Static {
  _Dynamic(
    this.invocation,
    List<String> beanNames, [
    List<String> introducedTypes = const [],
  ]) : super(invocation.signature, beanNames, introducedTypes);

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

// A designator. [test] is the static check; [bind] (for bindings)
// binds values per call.
final class _Leaf extends _Node {
  _Leaf(this.test, {this.bind});

  final bool Function(_Static context) test;
  final bool Function(_Dynamic context, Map<String, Object?> bound)? bind;

  @override
  bool? check(_Static context) => test(context);

  @override
  bool run(_Dynamic context, Map<String, Object?> bound) =>
      test(context) && (bind?.call(context, bound) ?? true);

  @override
  bool get isRuntime => bind != null;
}

// A designator whose static check may be undecided (`null`) and whose
// call-time check [decide] may bind values.
final class _Runtime extends _Node {
  _Runtime(this.test, this.decide);

  final bool? Function(_Static context) test;
  final bool Function(_Dynamic context, Map<String, Object?> bound) decide;

  @override
  bool? check(_Static context) => test(context);

  @override
  bool run(_Dynamic context, Map<String, Object?> bound) =>
      test(context) != false && decide(context, bound);

  @override
  bool get isRuntime => true;
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
    this.used,
    this.typeTests,
    this.argumentAnnotations,
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
  // Names of [bindings] the expression (and its named pointcuts) binds.
  final Set<String> used;
  final Map<String, bool Function(Object? value)> typeTests;
  final Map<String, Object? Function(Object? value)> argumentAnnotations;
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
    // Every designator and named reference is followed by `( ... )`; errors
    // in it point at the designator.
    _designatorStart = _matches[_pos - 1].start;
    try {
      return _designator(token);
    } finally {
      _designatorStart = null;
    }
  }

  _Node _designator(String token) {
    final body = _parenthesized();
    switch (token) {
      case 'execution':
        return _execution(body);
      // AspectJ's `within` is lexical: the class whose body runs.
      case 'within':
        final (pattern, subtypes) = _typePattern(body);
        return _Leaf((c) => _withinMatches(pattern, subtypes, c.signature));
      // Proxies implement the bean's types, so `this` and `target` check
      // the same types; bound, `this` is the proxy and `target` the bean.
      case 'target' || 'this':
        return _targetOrThis(body, isThis: token == 'this');
      case 'args':
        return _args(body);
      case '@args':
        return _annotatedArgs(body);
      case 'bean':
        final pattern = body.trim();
        return _Leaf((c) => c.beanNames.any((n) => wildcardMatch(pattern, n)));
      case '@annotation':
        return _annotation(
          body,
          (s) => _names(s.annotationTypes, s.annotations),
          (s) => s.annotations,
        );
      // `@within`: the class whose body runs; `@target`: the bean class.
      case '@within':
        return _annotation(
          body,
          (s) => _names(
            s.implementingTypeAnnotationTypes ?? s.targetAnnotationTypes,
            s.implementingTypeAnnotations ?? s.targetAnnotations,
          ),
          (s) => s.implementingTypeAnnotations ?? s.targetAnnotations,
        );
      case '@target':
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

  // `target(Type)` / `this(Type)`; bound (`target(t)`), the parameter's
  // type check on the target or proxy decides each call, so a parameter of
  // type `Object` (or of a type the static names do not show, like an
  // introduced interface for `this`) matches too.
  _Node _targetOrThis(String body, {required bool isThis}) {
    final binding = _binding(body);
    final type = binding?.typeName ?? _simple(body);
    final any = type == 'Object' || type == 'dynamic';
    // `this`: the proxy, which also implements the introduced interfaces.
    bool named(_Static c) =>
        any ||
        c.signature.targetTypes.contains(type) ||
        c.signature.targetType == type ||
        (isThis && c.introducedTypes.contains(type));
    if (binding == null) {
      return _Leaf(named);
    }
    final name = body.trim();
    return _Runtime(
      // The proxy may implement more types than the bean class
      // (introductions): `this` is then decided per call.
      (c) => named(c) ? true : (isThis ? null : false),
      (c, bound) {
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
    // A type name with a runtime test may match an argument of another
    // declared type (AspectJ tests `instanceof` on the argument).
    bool testable(String pattern) =>
        !pattern.contains('*') && typeTests.containsKey(pattern);
    bool declaredMatch(_Static c, String pattern, int index) =>
        wildcardMatch(pattern, types(c)[index]);
    bool test(_Static c) =>
        _matchArgs(items, types(c).length, 0, 0, (item, index) {
          if (item case final String pattern) {
            return declaredMatch(c, pattern, index) || testable(pattern);
          }
          return true;
        });
    final bindsValues = items.any((item) => item is (String, AdviceBinding));
    final runtime =
        bindsValues || items.any((item) => item is String && testable(item));
    if (!runtime) {
      return _Leaf(test);
    }
    return _Runtime(
      (c) {
        if (!test(c)) {
          return false;
        }
        // Decided without the call when the declared types match and
        // nothing is bound.
        final declaredOnly = _matchArgs(
          items,
          types(c).length,
          0,
          0,
          (item, index) => item is! String || declaredMatch(c, item, index),
        );
        return declaredOnly && !bindsValues ? true : null;
      },
      (c, bound) {
        final args = c.invocation.args;
        final declared = types(c);
        final values = <String, Object?>{};
        final matched = _matchArgs(items, args.length, 0, 0, (item, index) {
          switch (item) {
            case final String pattern:
              if (index >= declared.length ||
                  wildcardMatch(pattern, declared[index])) {
                return true;
              }
              return testable(pattern) && typeTests[pattern]!(args[index]);
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

  // `@args(Audited, ..)` / `@args(audited)`: the runtime class of each
  // argument carries the annotation (AspectJ); decided per call with
  // [argumentAnnotations], which return the annotation of a value or null.
  _Node _annotatedArgs(String body) {
    // `null`: `..`; `'*'`: any one argument; `(name, binding)`: a binding;
    // another `String`: an annotation type name.
    final items = <Object?>[
      for (final p in _splitParameters(body))
        if (p.trim() case final trimmed when trimmed.isNotEmpty)
          if (trimmed == '..')
            null
          else if (trimmed == '*')
            '*'
          else if (_binding(trimmed) case final binding?)
            (trimmed, binding)
          else
            _annotationName(trimmed),
    ];
    final known = items.every(
      (item) => switch (item) {
        (String _, final AdviceBinding binding) =>
          argumentAnnotations.containsKey(binding.typeName),
        final String name when name != '*' => argumentAnnotations.containsKey(
          name,
        ),
        _ => true,
      },
    );
    return _Runtime(
      (c) =>
          known &&
              _matchArgs(
                items,
                c.signature.parameterTypes.length,
                0,
                0,
                (_, _) => true,
              )
          ? null
          : false,
      (c, bound) {
        final args = c.invocation.args;
        final values = <String, Object?>{};
        final matched = _matchArgs(items, args.length, 0, 0, (item, index) {
          switch (item) {
            case '*':
              return true;
            case final String name:
              return argumentAnnotations[name]!(args[index]) != null;
            case (final String name, final AdviceBinding binding):
              final annotation = argumentAnnotations[binding.typeName]!(
                args[index],
              );
              if (annotation == null || !binding.accepts(annotation)) {
                return false;
              }
              values[name] = annotation;
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
  AdviceBinding? _binding(String body) {
    final binding = bindings[body.trim()];
    if (binding != null) {
      used.add(body.trim());
    }
    return binding;
  }

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
        used,
        typeTests,
        argumentAnnotations,
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

  // `execution([modifiers] returnType [Type.]name(params))`. Modifiers:
  // `public` (not `@protected`), `protected` (`@protected`, Dart's closest),
  // `private` (never: private members are not proxied), each optionally
  // negated with `!`; `static` and `final` are accepted and ignored. The
  // type pattern may match the declaring type, the bean class or any type
  // declaring the member; `Type+` also any supertype of the bean class.
  _Node _execution(String body) {
    if (RegExp(r'\)\s*throws\b').hasMatch(body)) {
      throw _error(
        "'throws' in execution is not supported: Dart methods declare no "
        'exceptions; select errors with @AfterThrowing and a typed error '
        "parameter (or throwing: 'name') instead",
      );
    }
    final head = RegExp(
      r'^\s*((?:!?\s*(?:public|protected|private|static|final)\s+)*)',
    ).firstMatch(body)!;
    // The return type pattern: one word, where a parenthesized combination
    // (`(String || int)`, `!(String || int)`) and type arguments
    // (`Map<String, int>`) may contain spaces.
    var rest = body.substring(head.end);
    String? returnText;
    var depth = 0;
    var end = 0;
    while (end < rest.length &&
        (depth > 0 || !RegExp(r'\s').hasMatch(rest[end]))) {
      if (rest[end] == '<' || rest[end] == '(') {
        depth++;
      } else if (rest[end] == '>' || rest[end] == ')') {
        depth--;
      }
      end++;
    }
    if (end > 0) {
      returnText = rest.substring(0, end);
      rest = rest.substring(end);
    }
    final match = RegExp(r'^\s+([^\s(]+)\s*\((.*)\)\s*$').firstMatch(rest);
    if (returnText == null || match == null) {
      throw _error("malformed execution pattern '$body'");
    }
    final modifiers = [
      for (final m in RegExp(
        r'(!?)\s*(public|protected|private|static|final)',
      ).allMatches(head[1]!))
        (m[1] == '!', m[2]!),
    ];
    bool modifiersMatch(MethodSignature s) => modifiers.every((modifier) {
      final (negated, name) = modifier;
      final bool has;
      switch (name) {
        case 'public':
          has = !s.isProtected;
        case 'protected':
          has = s.isProtected;
        case 'private':
          has = false;
        default:
          return true;
      }
      return has != negated;
    });
    final returnMatches = _typeExpression(returnText);
    final qualified = match[1]!;
    final dot = qualified.lastIndexOf('.');
    final methodPattern = dot < 0 ? qualified : qualified.substring(dot + 1);
    final typePattern = dot < 0
        ? null
        : _typePattern(qualified.substring(0, dot));
    final params = [
      for (final p in _splitParameters(match[2]!))
        if (p.trim().isNotEmpty)
          if (p.trim() == '..') null else _typeExpression(p.trim()),
    ];
    return _Leaf(
      (c) =>
          c.signature.kind == MemberKind.method &&
          modifiersMatch(c.signature) &&
          returnMatches(c.signature.returnType) &&
          wildcardMatch(methodPattern, c.signature.name) &&
          (typePattern == null ||
              _declaringMatches(typePattern.$1, typePattern.$2, c.signature)) &&
          _matchParams(params, c.signature.parameterTypes),
    );
  }

  // Subtypes `Type+` knows among the types signatures name (simple names
  // of the declared types; the hierarchy of other types is not recorded).
  static const _knownSubtypes = {
    'num': {'num', 'int', 'double'},
    'Iterable': {'Iterable', 'List', 'Set'},
    'Pattern': {'Pattern', 'String', 'RegExp'},
  };

  // An AspectJ type pattern for an `execution` return or parameter type:
  // a (qualified) name with `*` wildcards and generics (ignored), `Type+`,
  // `!pattern`, and `&&` / `||` combinations in parentheses
  // (`(String || int)`; unparenthesized they are an error, as in AspectJ).
  bool Function(String type) _typeExpression(String raw) {
    // Type arguments are not matched (`Map<String, int>` → `Map`).
    var text = raw;
    for (var previous = ''; previous != text;) {
      previous = text;
      text = text.replaceAll(RegExp('<[^<>]*>'), '');
    }
    final tokens = [
      for (final m in RegExp(r'\|\||&&|!|\(|\)|[^\s()!|&]+').allMatches(text))
        m[0]!,
    ];
    var index = 0;
    String? peek() => index < tokens.length ? tokens[index] : null;

    late bool Function(String) Function() or;
    bool Function(String) unary() {
      final token = peek();
      if (token == null || token == ')' || token == '||' || token == '&&') {
        throw _error("malformed type pattern '$raw'");
      }
      index++;
      if (token == '!') {
        final inner = unary();
        return (type) => !inner(type);
      }
      if (token == '(') {
        final inner = or();
        if (peek() != ')') {
          throw _error("missing ')' in type pattern '$raw'");
        }
        index++;
        return inner;
      }
      return _simpleTypeMatcher(token);
    }

    bool Function(String) and() {
      var left = unary();
      while (peek() == '&&') {
        index++;
        final first = left;
        final second = unary();
        left = (type) => first(type) && second(type);
      }
      return left;
    }

    or = () {
      var left = and();
      while (peek() == '||') {
        index++;
        final first = left;
        final second = and();
        left = (type) => first(type) || second(type);
      }
      return left;
    };

    final matcher = unary();
    if (index < tokens.length) {
      throw _error(
        "type pattern '${raw.trim()}' combines types with "
        "'${tokens[index]}' outside parentheses; write "
        "'(${raw.trim()})', as AspectJ requires",
      );
    }
    return matcher;
  }

  // One type name pattern of [_typeExpression].
  bool Function(String) _simpleTypeMatcher(String raw) {
    final cleaned = _stripGenerics(raw);
    if (!cleaned.endsWith('+')) {
      final pattern = _simple(cleaned);
      return (type) => wildcardMatch(pattern, type);
    }
    final pattern = _simple(cleaned.substring(0, cleaned.length - 1));
    if (pattern == 'Object' || pattern == '*') {
      return (type) => type != 'void';
    }
    if (_knownSubtypes[pattern] case final subtypes?) {
      return subtypes.contains;
    }
    throw _error(
      "'$cleaned' in an execution return or parameter type: signatures "
      'carry the simple name of each declared type, not its supertypes, '
      'so the subtypes of $pattern are unknown; list them '
      "('($pattern || Sub1 || Sub2)'), or use 'Object+' or '*'",
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

  // `within(Type)`: the class whose body runs for the member (the bean
  // class, or the superclass / mixin it inherits the member from);
  // `within(Type+)`: or any supertype of that class.
  static bool _withinMatches(
    String pattern,
    bool subtypes,
    MethodSignature s,
  ) =>
      wildcardMatch(pattern, s.implementingType) ||
      (subtypes &&
          s.implementingTypeHierarchy.any((t) => wildcardMatch(pattern, t)));

  // Matches parameter types against patterns; `..` matches zero or more
  // parameters (tried by backtracking over every possible skip).
  static bool _matchParams(
    List<bool Function(String)?> patterns,
    List<String> types,
  ) {
    if (patterns.isEmpty) {
      return types.isEmpty;
    }
    final head = patterns.first;
    if (head == null) {
      for (var skip = 0; skip <= types.length; skip++) {
        if (_matchParams(patterns.sublist(1), types.sublist(skip))) {
          return true;
        }
      }
      return false;
    }
    return types.isNotEmpty &&
        head(types.first) &&
        _matchParams(patterns.sublist(1), types.sublist(1));
  }

  // Splits a parameter list at top-level commas (`Map<String, int>, ..`).
  static List<String> _splitParameters(String text) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '<' || '(':
          depth++;
        case '>' || ')':
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

  // Where the designator being parsed starts; null between designators.
  int? _designatorStart;

  /// An error pointing at the designator being parsed, else at the current
  /// token (the end of the expression when all were read).
  FormatException _error(String message) => FormatException(
    'Invalid pointcut ($message)',
    expression,
    _designatorStart ??
        (_pos < _matches.length ? _matches[_pos].start : expression.length),
  );
}
