import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/context/security_context.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/method/annotations.dart';
import 'package:spring_security_core/src/method/expression_handler.dart';

/// Whether [annotation] is one of the five method security annotations:
/// [PreAuthorize], [PostAuthorize], [Secured], [PreFilter] or
/// [PostFilter].
bool isMethodSecurityAnnotation(Object annotation) =>
    annotation is PreAuthorize ||
    annotation is PostAuthorize ||
    annotation is Secured ||
    annotation is PreFilter ||
    annotation is PostFilter;

/// The security annotations that apply to one bean member, found the way
/// Spring finds them.
///
/// A member's own annotations win. A method without any takes those of
/// its class and the classes and interfaces above it; getters and setters
/// never inherit them. Used internally by [MethodSecurityInterceptor].
final class MethodSecurityAttributes {
  MethodSecurityAttributes._(this.annotations);

  /// The annotations that apply to [signature].
  ///
  /// Throws a [StateError] when the same annotation applies twice, which
  /// would make the rule ambiguous.
  factory MethodSecurityAttributes.of(MethodSignature signature) {
    var found = signature.mergedAnnotations
        .where(isMethodSecurityAnnotation)
        .toList();
    if (found.isEmpty && signature.kind == MemberKind.method) {
      found = signature.implementingTypeHierarchyAnnotations
          .where(isMethodSecurityAnnotation)
          .toList();
    }
    final attributes = MethodSecurityAttributes._(found);
    for (final type in [
      PreAuthorize,
      PostAuthorize,
      Secured,
      PreFilter,
      PostFilter,
    ]) {
      if (found.where((a) => a.runtimeType == type).length > 1) {
        throw StateError(
          'Found more than one @$type on ${signature.toShortString()}',
        );
      }
    }
    return attributes;
  }

  /// The security annotations found, in declaration order.
  final List<Object> annotations;

  /// Whether no security annotation applies, so the member is not
  /// checked.
  bool get isEmpty => annotations.isEmpty;

  /// The `@PreAuthorize` that applies, or `null`.
  PreAuthorize? get preAuthorize =>
      annotations.whereType<PreAuthorize>().firstOrNull;

  /// The `@PostAuthorize` that applies, or `null`.
  PostAuthorize? get postAuthorize =>
      annotations.whereType<PostAuthorize>().firstOrNull;

  /// The `@Secured` that applies, or `null`.
  Secured? get secured => annotations.whereType<Secured>().firstOrNull;

  /// The `@PreFilter` that applies, or `null`.
  PreFilter? get preFilter => annotations.whereType<PreFilter>().firstOrNull;

  /// The `@PostFilter` that applies, or `null`.
  PostFilter? get postFilter => annotations.whereType<PostFilter>().firstOrNull;
}

/// Selects the bean members that method security must wrap: those with a
/// security annotation of their own or from their class.
///
/// The auto-configured advisor pairs it with the
/// [MethodSecurityInterceptor]; applications do not use it directly.
final class MethodSecurityPointcut implements AnnotationPointcut {
  /// The stateless pointcut.
  const MethodSecurityPointcut();

  @override
  bool matches(MethodSignature signature, String beanName) =>
      !MethodSecurityAttributes.of(signature).isEmpty;

  @override
  String toString() => 'MethodSecurityPointcut';
}

/// The code that runs around every call of a secured bean method and
/// enforces its security annotations.
///
/// The auto-configuration installs it in the proxies of beans with
/// security annotations; applications only write the annotations. For each
/// call, in this order:
///
/// 1. It reads the current user from the security context. With none at
///    all, the call fails with an
///    `AuthenticationCredentialsNotFoundException` (401 on the web).
/// 2. `@PreFilter` filters the collection argument.
/// 3. `@PreAuthorize`, then `@Secured`: when one says no, the call fails
///    with an [AuthorizationDeniedException] (403 on the web) and the
///    method does not run.
/// 4. The method runs.
/// 5. `@PostFilter` filters the result, then `@PostAuthorize` checks it;
///    a denial replaces the result by an [AuthorizationDeniedException].
///
/// A synchronous method throws; an `async` method returns a failed
/// `Future`. Members without security annotations run unchanged.
///
/// Spring (Java): `AuthorizationManagerBeforeMethodInterceptor` and
/// `AuthorizationManagerAfterMethodInterceptor` together.
final class MethodSecurityInterceptor implements MethodInterceptor {
  /// An interceptor evaluating expressions with [expressionHandler] and
  /// reading the user from [holderStrategy].
  MethodSecurityInterceptor(this.expressionHandler, {this.holderStrategy});

  /// Parses and evaluates the expressions of the annotations.
  final MethodSecurityExpressionHandler expressionHandler;

  /// Where the current user is read; `null` uses the strategy of
  /// [SecurityContextHolder] at the time of each call.
  final SecurityContextHolderStrategy? holderStrategy;

  SecurityContextHolderStrategy get _holder =>
      holderStrategy ?? SecurityContextHolder.getContextHolderStrategy();

  final _attributes = Expando<MethodSecurityAttributes>();

  /// The security annotations of [signature], looked up once and then
  /// cached.
  MethodSecurityAttributes attributesOf(MethodSignature signature) =>
      _attributes[signature] ??= MethodSecurityAttributes.of(signature);

  /// Parses every expression of [signature]'s annotations, so a broken one
  /// fails at startup rather than at the first call.
  ///
  /// Throws what the parser throws for an invalid expression.
  void validate(MethodSignature signature) {
    final attributes = attributesOf(signature);
    for (final text in [
      attributes.preAuthorize?.value,
      attributes.postAuthorize?.value,
      attributes.preFilter?.value,
      attributes.postFilter?.value,
    ]) {
      if (text != null) {
        expressionHandler.parse(text);
      }
    }
  }

  @override
  Object? invoke(MethodInvocation invocation) {
    final attributes = attributesOf(invocation.signature);
    if (attributes.isEmpty) {
      return invocation.proceed();
    }
    if (invocation is AsyncMethodInvocation) {
      try {
        return _invoke(invocation, attributes);
      } on Object catch (error, stackTrace) {
        return Future<Object?>.error(error, stackTrace);
      }
    }
    return _invoke(invocation, attributes);
  }

  Object? _invoke(
    MethodInvocation invocation,
    MethodSecurityAttributes attributes,
  ) {
    final authentication = _authentication;
    // Like Spring: no authentication fails every secured call with a 401
    // before any expression runs.
    authentication();
    final root = expressionHandler.createRoot(
      authentication,
      target: invocation.target,
    );
    final signature = invocation.signature;
    var args = invocation.args;

    if (attributes.preFilter case final filter?) {
      args = _preFilter(filter, root, signature, args);
    }
    if (attributes.preAuthorize case final pre?) {
      final context = expressionHandler.createEvaluationContext(
        root,
        signature,
        args,
      );
      _require(expressionHandler.evaluate(pre.value, context), signature);
    }
    if (attributes.secured case final secured?) {
      final result =
          AuthorityAuthorizationManager<MethodInvocation>.hasAnyAuthority(
            secured.value,
            roleHierarchy: expressionHandler.roleHierarchy,
          ).authorize(authentication, invocation);
      _require(result.isGranted, signature);
    }

    final result = identical(args, invocation.args)
        ? invocation.proceed()
        : invocation.proceed(args);

    final post = attributes.postAuthorize;
    final postFilter = attributes.postFilter;
    if (post == null && postFilter == null) {
      return result;
    }
    Object? after(Object? value) {
      var current = value;
      if (postFilter != null) {
        current = _filter(postFilter.value, current, root, signature, args);
      }
      if (post != null) {
        root.returnObject = current;
        final context = expressionHandler.createEvaluationContext(
          root,
          signature,
          args,
        );
        _require(expressionHandler.evaluate(post.value, context), signature);
      }
      return current;
    }

    if (invocation is AsyncMethodInvocation && result is Future) {
      // A new future with the checked (and filtered) value.
      return (result as Future<Object?>).then(after);
    }
    return after(result);
  }

  // The authentication, read once per call; none fails the call.
  Authentication? Function() get _authentication {
    Authentication? cached;
    var read = false;
    return () {
      if (!read) {
        read = true;
        cached = _holder.getContext().authentication;
        if (cached == null) {
          throw AuthenticationCredentialsNotFoundException();
        }
      }
      return cached;
    };
  }

  void _require(bool granted, MethodSignature signature) {
    if (!granted) {
      throw AuthorizationDeniedException(
        'Access Denied',
        AuthorizationDecision.denied,
      );
    }
  }

  List<Object?> _preFilter(
    PreFilter filter,
    MethodSecurityExpressionRoot root,
    MethodSignature signature,
    List<Object?> args,
  ) {
    int index;
    if (filter.filterTarget.isNotEmpty) {
      index = signature.parameterNames.indexOf(filter.filterTarget);
      if (index < 0) {
        throw ArgumentError(
          'No argument ${filter.filterTarget} on '
          '${signature.toShortString()} for @PreFilter',
        );
      }
    } else {
      final candidates = [
        for (var i = 0; i < args.length; i++)
          if (args[i] is Iterable || args[i] is Map) i,
      ];
      if (candidates.length != 1) {
        throw ArgumentError(
          '@PreFilter on ${signature.toShortString()} needs filterTarget: '
          '${candidates.isEmpty ? 'no' : 'more than one'} collection argument',
        );
      }
      index = candidates.single;
    }
    return [
      for (var i = 0; i < args.length; i++)
        if (i == index)
          _filter(filter.value, args[i], root, signature, args)
        else
          args[i],
    ];
  }

  static Map<Object?, Object?> _filterMap(
    Map<Object?, Object?> map,
    bool Function(Object?) keep,
  ) {
    try {
      map.removeWhere((key, value) => !keep(MapEntry(key, value)));
    } on UnsupportedError {
      throw ArgumentError('Cannot filter an unmodifiable Map');
    }
    return map;
  }

  // A filtered copy of a List or Set (with its element type), the Map
  // itself filtered; null stays null.
  Object? _filter(
    String expression,
    Object? collection,
    MethodSecurityExpressionRoot root,
    MethodSignature signature,
    List<Object?> args,
  ) {
    if (collection == null) {
      return null;
    }
    final context = expressionHandler.createEvaluationContext(
      root,
      signature,
      args,
    );
    bool keep(Object? element) {
      root.filterObject = element;
      return expressionHandler.evaluate(expression, context);
    }

    try {
      return switch (collection) {
        final List<Object?> list => list.where(keep).toList(),
        final Set<Object?> set => set.where(keep).toSet(),
        // In place, like Spring (a copy would lose the map's types).
        final Map<Object?, Object?> map => _filterMap(map, keep),
        _ => throw ArgumentError(
          'Can only filter a List, Set or Map, not ${collection.runtimeType}',
        ),
      };
    } finally {
      root.filterObject = null;
    }
  }
}

/// The startup check that makes sure no security annotation is silently
/// ignored.
///
/// For every bean whose class or methods carry security annotations, it
/// parses each expression and checks that the bean was proxied. A bean
/// that could not be proxied (a `final` class, for example) would run its
/// methods unchecked, so the application fails to start with a
/// [StateError] that says so. The auto-configuration registers it;
/// applications never use it directly.
///
/// Spring checks the expressions when it builds the proxies; this check
/// also stops the startup for a secured bean left without a proxy.
final class MethodSecurityValidator extends BeanPostProcessor
    implements BeanFactoryAware, Ordered {
  /// A validator that gets the interceptor from the given function at the
  /// first secured bean.
  ///
  /// The interceptor is not a constructor argument: a post-processor's own
  /// dependencies are created before the other post-processors exist and
  /// would miss them.
  MethodSecurityValidator(this._interceptor);

  final MethodSecurityInterceptor Function() _interceptor;

  /// The interceptor whose expression handler parses the expressions,
  /// obtained on first use.
  late final MethodSecurityInterceptor interceptor = _interceptor();

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  // After every other post-processor, so the proxy (if any) exists.
  @override
  int get order => Ordered.lowestPrecedence;

  BeanDefinition<Object>? _definition(String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry) {
      return null;
    }
    final registry = factory! as BeanDefinitionRegistry;
    return registry.containsBeanDefinition(beanName)
        ? registry.getBeanDefinition(beanName)
        : null;
  }

  // Whether the bean's class or methods carry method security annotations.
  static bool _secured(BeanDefinition<Object> definition) =>
      definition.annotations.any(isMethodSecurityAnnotation) ||
      definition.annotatedMethods.any(
        (method) => method.annotations.any(isMethodSecurityAnnotation),
      );

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final definition = _definition(beanName);
    // Only secured beans need the interceptor (and its dependencies, which
    // may be beans being created right now).
    if (definition == null || !_secured(definition)) {
      return bean;
    }
    for (final signature
        in definition.aopProxy?.signatures ?? const <MethodSignature>[]) {
      if (!interceptor.attributesOf(signature).isEmpty) {
        interceptor.validate(signature);
      }
    }
    return bean;
  }

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    final definition = _definition(beanName);
    if (definition == null || bean is Advised) {
      return bean;
    }
    if (_secured(definition)) {
      throw StateError(
        'Bean $beanName has method security annotations but no proxy: they '
        'would not be checked. Make the class proxyable (not final, public '
        'members) or move the annotations to a bean that is.',
      );
    }
    return bean;
  }
}
