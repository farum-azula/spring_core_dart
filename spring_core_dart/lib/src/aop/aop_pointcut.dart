import 'package:spring_core_dart/src/aop/join_point.dart';

/// A rule that decides which members of which beans an advisor's advice
/// applies to.
///
/// Each `PointcutAdvisor` pairs one with its advice. Most code never
/// implements it: aspects write pointcut expressions, and in code an
/// [ExpressionPointcut] takes the same syntax. Implement it when the rule
/// is easier to write in Dart, such as a test on the member's
/// annotations. [matches] runs once per member of each proxied bean, at
/// startup, not on every call. It is named `AopPointcut` because
/// `@Pointcut` is the annotation.
///
/// Unlike Spring's `ClassFilter` + `MethodMatcher` pair, one check sees
/// both the member signature and the bean name.
///
/// ```dart
/// // Advises the read-only members: find* methods and getters.
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
  /// Whether the advice applies to the member described by [signature] of
  /// the bean named [beanName].
  bool matches(MethodSignature signature, String beanName);
}

/// A marker for pointcuts that match only members or classes carrying
/// annotations from outside `package:spring_core_dart`, such as
/// `@Cacheable` or `@Validated`.
///
/// It exists for the build's proxy pruning (`aop_prune`): the build skips
/// the proxy classes of beans no pointcut can match, but always keeps the
/// beans that carry such an annotation. A starter's auto-configuration
/// that declares an advisor bean whose pointcut is an `AnnotationPointcut`
/// (in the advisor's static type, as the build sees it) keeps that saving;
/// any other advisor bean of a starter turns pruning off, since the build
/// cannot tell which beans it matches. Implement it in a library that
/// offers annotation-driven advice; applications do not need it.
///
/// Read [MethodSignature.mergedAnnotations] to also see the annotations of
/// the superclass, mixin and interface declarations the member overrides
/// (Spring's `AnnotatedElementUtils` find semantics), as the cache and
/// method validation advisors do; [MethodSignature.annotations] is what
/// `@annotation(...)` matches.
///
/// ```dart
/// // The cache starter's pointcut: members with @Cacheable.
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

/// A pointcut that matches every member of every bean.
///
/// Use it for advice that applies everywhere it is attached, such as
/// logging all calls of one proxy made with `ProxyFactory`. Adding advice
/// with `addAdvice` uses it.
///
/// ```dart
/// // Logs every call of every proxied bean.
/// DefaultPointcutAdvisor(const TruePointcut(), LoggingInterceptor());
/// ```
///
/// Spring (Java):
/// ```java
/// new DefaultPointcutAdvisor(Pointcut.TRUE, new LoggingInterceptor());
/// ```
final class TruePointcut implements AopPointcut {
  /// The pointcut that matches everything.
  const TruePointcut();

  @override
  bool matches(MethodSignature signature, String beanName) => true;
}

/// A pointcut that matches members by name, with `*` wildcards.
///
/// Use it in an advisor when the advised members follow a naming
/// convention, like `find*`. It matches the name only, in every bean and
/// for getters and setters too; combine it with other pointcuts in a
/// [ComposablePointcut] to narrow it.
///
/// ```dart
/// // Caches the find* methods and count.
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
  /// Matches members whose name matches any of the [names] patterns.
  const NameMatchMethodPointcut(this.names);

  /// The name patterns; `*` matches any characters, everything else
  /// literally, and the whole name must match.
  final List<String> names;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      names.any((pattern) => wildcardMatch(pattern, signature.name));
}

/// A pointcut that matches members carrying an annotation of type [A], or
/// every member of beans whose class carries it.
///
/// Use it in an advisor for annotation-driven advice: a `@Timed()` marker
/// on the methods to time. It tests the runtime type of the const
/// annotation objects, so [A] must be the annotation class. On members it
/// reads [MethodSignature.annotations] (like `@annotation(...)`, not the
/// overridden declarations'); with `onClass`, the bean class's
/// annotations.
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
  /// Matches members annotated with [A], or with [onClass] every member of
  /// a bean whose class is.
  const AnnotationMatchingPointcut({this.onClass = false});

  /// Whether to test the bean class's annotations instead of the
  /// member's; `false` by default.
  final bool onClass;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      (onClass ? signature.targetAnnotations : signature.annotations).any(
        (a) => a is A,
      );
}

/// A pointcut built from other pointcuts with "or" ([union]) and "and"
/// ([intersection]).
///
/// Use it to combine pointcuts written in code, such as a name pattern and
/// an annotation, when one expression cannot say it. It is a mutable
/// builder: both methods change this pointcut and return it, so calls
/// chain.
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
  /// Starts from [pointcut]; by default every member matches.
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

  /// From now on, also matches what [other] matches; returns this
  /// pointcut.
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

  /// From now on, matches only what [other] matches too; returns this
  /// pointcut.
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

/// Whether [pointcut] matches the member [signature] of the bean
/// [beanName], with everything the bean is known by.
///
/// [AopPointcut.matches] sees only the bean name. The pointcuts that test
/// names or types ([ExpressionPointcut], [ComposablePointcut]) also get the
/// bean's aliases and qualifier values ([beanAliases]), for `bean(...)`,
/// and the interfaces `@DeclareParents` adds to its proxy
/// ([introducedTypes]), for `this(...)`. The proxy machinery calls this;
/// call it too when matching pointcuts yourself, for example in a test.
///
/// ```dart
/// // Does the advisor apply to `find` of the bean also known as
/// // primaryOrders?
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

/// Whether [text] matches [pattern], where `*` stands for any characters.
///
/// The whole [text] must match; every other character is literal. Name
/// patterns of pointcuts (`find*`, `bean(order*)`) use it.
///
/// ```dart
/// wildcardMatch('find*', 'findAll'); // true
/// wildcardMatch('*Service', 'UserRepository'); // false
/// ```
bool wildcardMatch(String pattern, String text) =>
    RegExp('^${pattern.split('*').map(RegExp.escape).join('.*')}\$')
        .hasMatch(text);

/// The type of an advice parameter that the pointcut fills in, such as
/// `timed` in `@annotation(timed)` or `id` in `args(id, ..)`.
///
/// When a pointcut names a parameter instead of a type, the advice method
/// receives the matched value (the annotation, the argument, the bean).
/// The pointcut must know the parameter's type to match only calls where
/// the value fits, and Dart cannot read it at runtime, so the generator
/// writes one `AdviceBinding` per such parameter. [typeName] is the simple
/// name of the type, written at build time so it survives minified
/// builds; [accepts] tests a value. Applications do not write it.
///
/// ```dart
/// // Generated for the `timed` parameter of:
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
  /// Describes a parameter of the type named [typeName]; `accepts` tests
  /// whether a value has that type.
  AdviceBinding(this.typeName, this._accepts);

  /// The simple name of the parameter type, such as `Timed`. The pointcut
  /// matches it against the member's names at startup: `@annotation(timed)`
  /// selects the members annotated with `Timed`.
  final String typeName;

  final bool Function(Object? value) _accepts;

  /// Whether [value] has the parameter type, so it can be passed.
  bool accepts(Object? value) => _accepts(value);

  @override
  String toString() => 'AdviceBinding($typeName)';
}

/// A pointcut written as an AspectJ-style expression, the syntax of the
/// `@Before` / `@Around` / ... annotations.
///
/// Aspects use it behind the scenes: each advice annotation's string
/// becomes one. Create one yourself for a `DefaultPointcutAdvisor` bean,
/// to select members by name, type, annotation or bean name without
/// writing an [AopPointcut] class. The expression is parsed at once; an
/// invalid one throws a [FormatException] with the reason.
///
/// Type and name patterns use simple names: Dart has libraries, not Java
/// packages, so `com.x.Service` means `Service`, and a package wildcard
/// such as `com.x..*` is rejected rather than matching everything. `*`
/// matches any characters in a name, `Type+` means the type and its
/// subtypes, and type arguments and `?` are ignored (`Future<int>` matches
/// `Future`). The designators:
///
/// - `execution([modifiers] ret [Type.]name(params))` selects methods (not
///   getters or setters) by return type, declaring type, name and
///   parameters. In the parameters, `..` stands for any number and `*` for
///   exactly one. The modifiers are `public`, `protected` (members marked
///   `@protected`) and `private` (never matches), each optionally negated
///   with `!`. A `throws` clause is rejected, since Dart methods declare no
///   exceptions.
/// - `within(TypePattern)` selects every member whose body is in a
///   matching class: the bean class, or the superclass or mixin it
///   inherits the member from.
/// - `target(Type)` and `this(Type)` select every member of beans whose
///   class is that type or a subtype.
/// - `args(types)` selects members by their parameters (`..` for any
///   number): the declared type, or the runtime type of the argument when
///   `typeTests` knows the type.
/// - `@args(Annotation, ..)` selects calls whose arguments' runtime classes
///   carry the annotations (through `argumentAnnotations`).
/// - `bean(namePattern)` selects every member of beans with that name, an
///   alias or a qualifier value.
/// - `@annotation(Name)` selects members carrying the annotation;
///   `@within(Name)` members whose body is in a class carrying it;
///   `@target(Name)` members of beans whose class carries it.
/// - `name()` refers to a named pointcut of the same aspect (or of
///   [owner]), `Type.name()` to one of another class.
///
/// Designators combine with `&&` / `and`, `||` / `or`, `!` / `not` and
/// parentheses.
///
/// With [bindings] (written by the generator for advice parameters), a
/// lowercase identifier in `@annotation(x)`, `@within(x)`, `@target(x)`,
/// `this(x)`, `target(x)`, `args(...)` or `@args(...)` names an advice
/// parameter, which receives the annotation, the proxy, the target or the
/// argument ([bind]). Such an expression is also checked on every call.
///
/// ```dart
/// // Logs the calls of the services, except their slow* methods.
/// final pointcut = ExpressionPointcut(
///   'service() && !execution(* *.slow*(..))',
///   namedPointcuts: {'service': 'within(*Service) || @within(Service)'},
/// );
/// DefaultPointcutAdvisor(pointcut, LoggingInterceptor());
///
/// // Other expressions.
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
  /// Parses [expression]; throws a [FormatException] when it is invalid,
  /// or when a binding is not used by it.
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

  /// The expression as written.
  final String expression;

  /// The class (aspect or pointcut holder) whose named pointcuts an
  /// unqualified `name()` refers to; `null` outside an aspect.
  final String? owner;

  /// The advice parameters this expression binds, by name; empty for an
  /// expression written in code.
  final Map<String, AdviceBinding> bindings;

  // The expression compiled into a tree, evaluated per member.
  final _Node _root;

  /// Whether the expression binds advice parameters or tests arguments,
  /// so the startup match is not enough and every call is checked too
  /// ([bind]).
  bool get isRuntime => _root.isRuntime;

  /// Whether the member can match, decided once at startup; `false` only
  /// when no call of the member can match. Parts that depend on the
  /// arguments are assumed to match.
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

  /// Checks one call against the expression and returns the values of the
  /// bound advice parameters (empty when nothing is bound), or `null` when
  /// the call does not match, such as `args(id)` with an argument of
  /// another type. [beanName], [beanAliases] and [introducedTypes] are as
  /// in [matchesBean].
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
