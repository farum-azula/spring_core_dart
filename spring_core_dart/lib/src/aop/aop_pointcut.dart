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

/// Pointcut expressions in Spring's syntax (`execution(...)`, `within(...)`,
/// `bean(...)`, ...).
///
/// Supported designators (names match simple type names; package parts of
/// patterns are ignored since Dart has libraries, not packages):
/// - `execution([modifiers] ret [Type.]method(params))` — `*` wildcards,
///   `..` for any parameters, `*` for one parameter;
/// - `within(TypePattern)` — the bean class;
/// - `target(Type)` — the bean class or any supertype;
/// - `bean(namePattern)` — the bean name;
/// - `@annotation(Name)` — an annotation on the member;
/// - `@within(Name)` — an annotation on the bean class;
/// - named pointcuts `name()` / `Aspect.name()`;
/// - `&&` / `and`, `||` / `or`, `!` / `not`, parentheses.
///
/// The expression is parsed eagerly; invalid expressions throw a
/// [FormatException]. Argument binding (`args(x)`, `@annotation(timed)`
/// with a parameter name) is not supported.
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
  /// Parses [expression]; [namedPointcuts] (method name or
  /// `Aspect.method` → expression) resolve references like `service()`.
  ExpressionPointcut(
    this.expression, {
    Map<String, String> namedPointcuts = const {},
  }) : _matcher = _PointcutParser(expression, namedPointcuts, {}).parse();

  /// The source expression.
  final String expression;

  // The expression compiled into a closure tree, evaluated per member.
  final _Matcher _matcher;

  @override
  bool matches(MethodSignature signature, String beanName) =>
      _matcher(signature, beanName);

  @override
  String toString() => 'ExpressionPointcut: $expression';
}

typedef _Matcher = bool Function(MethodSignature signature, String beanName);

// Recursive-descent parser compiling an expression into a [_Matcher].
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
  _PointcutParser(this.expression, this.named, this.resolving)
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
  final List<RegExpMatch> _matches;
  int _pos = 0;

  List<String> get _tokens => [for (final m in _matches) m[0]!];

  _Matcher parse() {
    if (_tokens.isEmpty) {
      throw _error('empty pointcut expression');
    }
    final matcher = _or();
    if (_pos != _tokens.length) {
      throw _error("unexpected '${_tokens[_pos]}'");
    }
    return matcher;
  }

  _Matcher _or() {
    var left = _and();
    while (_peekAny(const ['||', 'or'])) {
      _pos++;
      final l = left;
      final r = _and();
      left = (s, b) => l(s, b) || r(s, b);
    }
    return left;
  }

  _Matcher _and() {
    var left = _not();
    while (_peekAny(const ['&&', 'and'])) {
      _pos++;
      final l = left;
      final r = _not();
      left = (s, b) => l(s, b) && r(s, b);
    }
    return left;
  }

  _Matcher _not() {
    if (_peekAny(const ['!', 'not'])) {
      _pos++;
      final inner = _not();
      return (s, b) => !inner(s, b);
    }
    return _primary();
  }

  _Matcher _primary() {
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
        final pattern = _simple(body);
        return (s, _) => wildcardMatch(pattern, s.targetType);
      // Proxies implement the bean's types, so `this` and `target` are
      // the same check here.
      case 'target' || 'this':
        final type = _simple(body);
        return (s, _) => s.targetTypes.contains(type) || s.targetType == type;
      case 'bean':
        final pattern = body.trim();
        return (_, beanName) => wildcardMatch(pattern, beanName);
      case '@annotation':
        final name = _annotationName(body);
        return (s, _) =>
            _names(s.annotationTypes, s.annotations).contains(name);
      case '@within':
        final name = _annotationName(body);
        return (s, _) =>
            _names(s.targetAnnotationTypes, s.targetAnnotations).contains(name);
      default:
        if (body.trim().isNotEmpty) {
          throw _error("unknown designator '$token'");
        }
        return _named(token);
    }
  }

  // Resolves `name()` / `Aspect.name()`: the qualified key first, then
  // the simple method name; the referenced expression is parsed with the
  // same table.
  _Matcher _named(String reference) {
    final simple = reference.contains('.')
        ? reference.substring(reference.lastIndexOf('.') + 1)
        : reference;
    final target = named[reference] ?? named[simple];
    if (target == null) {
      throw _error("unknown pointcut '$reference'");
    }
    if (!resolving.add(reference)) {
      throw _error("circular pointcut reference '$reference'");
    }
    try {
      return _PointcutParser(target, named, resolving).parse();
    } finally {
      resolving.remove(reference);
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
  // declaring type, the bean class or any type declaring the member.
  _Matcher _execution(String body) {
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
    final typePattern = dot < 0 ? null : _simple(qualified.substring(0, dot));
    final params = [
      for (final p in match[3]!.split(','))
        if (p.trim().isNotEmpty) _stripGenerics(p.trim()),
    ];
    return (s, _) =>
        s.kind == MemberKind.method &&
        wildcardMatch(returnPattern, s.returnType) &&
        wildcardMatch(methodPattern, s.name) &&
        (typePattern == null ||
            wildcardMatch(typePattern, s.declaringType) ||
            wildcardMatch(typePattern, s.targetType) ||
            s.declaringTypes.any((t) => wildcardMatch(typePattern, t))) &&
        _matchParams(params, s.parameterTypes);
  }

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
  // name is Spring's argument binding (`@annotation(timed)`), which is not
  // supported: rejected instead of silently matching nothing.
  String _annotationName(String body) {
    final name = _simple(body);
    if (name.isNotEmpty && name[0] != name[0].toUpperCase()) {
      throw _error(
        "argument binding '$name' is not supported; use the annotation "
        'type name, e.g. @annotation(Timed), and read it from '
        'joinPoint.signature.annotations',
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
