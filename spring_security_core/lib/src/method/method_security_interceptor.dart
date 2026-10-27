import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/context/security_context.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/method/annotations.dart';
import 'package:spring_security_core/src/method/expression_handler.dart';

/// Whether [annotation] is one of the method security annotations.
bool isMethodSecurityAnnotation(Object annotation) =>
    annotation is PreAuthorize ||
    annotation is PostAuthorize ||
    annotation is Secured ||
    annotation is PreFilter ||
    annotation is PostFilter;

/// The security annotations that apply to a member: its own, else those of
/// its class (and superclasses), like Spring's lookup (method first).
final class MethodSecurityAttributes {
  MethodSecurityAttributes._(this.annotations);

  /// The attributes of [signature].
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

  /// The annotations.
  final List<Object> annotations;

  /// Whether nothing applies.
  bool get isEmpty => annotations.isEmpty;

  /// `@PreAuthorize`.
  PreAuthorize? get preAuthorize =>
      annotations.whereType<PreAuthorize>().firstOrNull;

  /// `@PostAuthorize`.
  PostAuthorize? get postAuthorize =>
      annotations.whereType<PostAuthorize>().firstOrNull;

  /// `@Secured`.
  Secured? get secured => annotations.whereType<Secured>().firstOrNull;

  /// `@PreFilter`.
  PreFilter? get preFilter => annotations.whereType<PreFilter>().firstOrNull;

  /// `@PostFilter`.
  PostFilter? get postFilter => annotations.whereType<PostFilter>().firstOrNull;
}

/// Matches members with method security annotations (for the advisor).
final class MethodSecurityPointcut implements AnnotationPointcut {
  /// The pointcut.
  const MethodSecurityPointcut();

  @override
  bool matches(MethodSignature signature, String beanName) =>
      !MethodSecurityAttributes.of(signature).isEmpty;

  @override
  String toString() => 'MethodSecurityPointcut';
}

/// Applies `@PreFilter`, `@PreAuthorize`, `@Secured`, `@PostAuthorize`
/// and `@PostFilter` around a call, like Spring's
/// `AuthorizationManagerBeforeMethodInterceptor` and
/// `AuthorizationManagerAfterMethodInterceptor` together.
///
/// The current user is the `SecurityContextHolder`'s; with none, a
/// secured call fails with `AuthenticationCredentialsNotFoundException`
/// (401), a denied one with `AuthorizationDeniedException` (403). An
/// `async` method fails through its `Future`.
final class MethodSecurityInterceptor implements MethodInterceptor {
  /// An interceptor evaluating with [expressionHandler].
  MethodSecurityInterceptor(this.expressionHandler, {this.holderStrategy});

  /// Evaluates the expressions.
  final MethodSecurityExpressionHandler expressionHandler;

  /// Where the current user is read; `SecurityContextHolder`'s when
  /// `null`.
  final SecurityContextHolderStrategy? holderStrategy;

  SecurityContextHolderStrategy get _holder =>
      holderStrategy ?? SecurityContextHolder.getContextHolderStrategy();

  final _attributes = Expando<MethodSecurityAttributes>();

  /// The attributes of [signature] (cached).
  MethodSecurityAttributes attributesOf(MethodSignature signature) =>
      _attributes[signature] ??= MethodSecurityAttributes.of(signature);

  /// Parses every expression of [signature], so a broken one fails at
  /// startup.
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

/// Checks the method security annotations of beans at startup, like
/// Spring when it builds the proxies: every expression parses, and every
/// bean with such annotations is proxied — otherwise the annotations
/// would be silently ignored, so the application fails to start
/// (docs/security.md: fail closed).
final class MethodSecurityValidator extends BeanPostProcessor
    implements BeanFactoryAware, Ordered {
  /// A validator for the rules of the interceptor [interceptor] returns,
  /// asked for it at the first secured bean: a post-processor's own
  /// dependencies are created before the other post-processors and would
  /// miss them.
  MethodSecurityValidator(this._interceptor);

  final MethodSecurityInterceptor Function() _interceptor;

  /// Parses the expressions.
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
