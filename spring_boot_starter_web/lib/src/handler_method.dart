import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A controller method found at startup, like Spring's `HandlerMethod`:
/// the bean (looked up as other beans see it, so AOP advice applies) and
/// the method described by the generator.
final class HandlerMethod {
  /// The [method] of bean [beanName] (of class [beanTypeName]).
  HandlerMethod({
    required this.beanName,
    required this.beanTypeName,
    required this.method,
    required this.classAnnotations,
    required this._beanFactory,
  });

  /// The bean's name.
  final String beanName;

  /// The controller class name (for messages).
  final String beanTypeName;

  /// The method.
  final BeanMethod<Object> method;

  /// The annotations of the controller class.
  final List<Object> classAnnotations;

  final BeanFactory _beanFactory;

  /// `BookController.find`.
  String get description => '$beanTypeName.${method.name}';

  /// The parameters.
  late final List<MethodParameter> parameters = [
    for (final (index, parameter) in method.parameters.indexed)
      MethodParameter(this, index, parameter),
  ];

  /// The annotation [A] of the method, else of the class.
  A? annotation<A>() =>
      method.annotations.whereType<A>().firstOrNull ??
      classAnnotations.whereType<A>().firstOrNull;

  /// The bean the method is called on.
  Object resolveBean() {
    final bean = _beanFactory.getBeanByName(beanName);
    return method.appliesTo(bean) ? bean : AopUtils.getTarget(bean);
  }

  @override
  String toString() => description;
}

/// A parameter of a [HandlerMethod], like Spring's `MethodParameter`.
final class MethodParameter {
  /// Parameter [index] of [handler], described by [parameter].
  MethodParameter(this.handler, this.index, this.parameter);

  /// The method.
  final HandlerMethod handler;

  /// Its position among all parameters.
  final int index;

  /// The generator's description.
  final BeanParameter parameter;

  /// The parameter name.
  String get name => parameter.name;

  /// The declared type.
  TypeInfo<Object?> get type => parameter.type;

  /// Its annotations.
  List<Object> get annotations => parameter.annotations;

  /// The first annotation of type [A], or `null`.
  A? annotation<A>() => parameter.annotations.whereType<A>().firstOrNull;

  /// Whether it has an annotation of type [A].
  bool has<A>() => parameter.annotations.whereType<A>().isNotEmpty;

  @override
  String toString() => '${handler.description}($name)';
}

/// Resolves arguments of handler methods the starter does not know, like
/// Spring's `HandlerMethodArgumentResolver`. Register it with
/// `WebMvcConfigurer.addArgumentResolvers`; it is asked before the
/// built-in resolvers (Spring asks custom ones after; here they can take
/// over any parameter, which a security starter needs).
///
/// ```dart
/// final class TenantResolver implements HandlerMethodArgumentResolver {
///   @override
///   bool supportsParameter(MethodParameter parameter) =>
///       parameter.type.type == Tenant;
///
///   @override
///   Object? resolveArgument(MethodParameter parameter,
///           ServerHttpRequest request, ServerHttpResponse response) =>
///       Tenant(request.headers['X-Tenant'] ?? 'default');
/// }
/// ```
abstract interface class HandlerMethodArgumentResolver {
  /// Whether this resolver provides [parameter]'s value (checked once at
  /// startup).
  bool supportsParameter(MethodParameter parameter);

  /// The value of [parameter] for [request].
  FutureOr<Object?> resolveArgument(
    MethodParameter parameter,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// Code around handler methods, like Spring's `HandlerInterceptor`;
/// registered with `WebMvcConfigurer.addInterceptors`.
///
/// ```dart
/// final class TimingInterceptor with HandlerInterceptor {
///   @override
///   bool preHandle(request, response, handler) {
///     request.attributes['start'] = DateTime.now();
///     return true;
///   }
/// }
/// ```
abstract mixin class HandlerInterceptor {
  /// Before the handler; `false` stops the request (the interceptor
  /// answered it).
  FutureOr<bool> preHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
  ) => true;

  /// After the handler returned [result], before it is written.
  FutureOr<void> postHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
    Object? result,
  ) {}

  /// After the request (also after an [error]).
  FutureOr<void> afterCompletion(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
    Object? error,
  ) {}
}

/// Interceptors with the paths they apply to, like Spring's
/// `InterceptorRegistry`.
final class InterceptorRegistry {
  final _registrations = <InterceptorRegistration>[];

  /// Adds [interceptor] (every path unless restricted).
  InterceptorRegistration addInterceptor(HandlerInterceptor interceptor) {
    final registration = InterceptorRegistration._(interceptor);
    _registrations.add(registration);
    return registration;
  }

  /// The registrations, in order.
  List<InterceptorRegistration> get registrations =>
      List.unmodifiable(_registrations);
}

/// One interceptor of an [InterceptorRegistry].
final class InterceptorRegistration {
  InterceptorRegistration._(this.interceptor);

  /// The interceptor.
  final HandlerInterceptor interceptor;

  final _include = <PathPattern>[];
  final _exclude = <PathPattern>[];

  /// Applies only to [patterns].
  InterceptorRegistration addPathPatterns(List<String> patterns) {
    _include.addAll(patterns.map(PathPattern.parse));
    return this;
  }

  /// Does not apply to [patterns].
  InterceptorRegistration excludePathPatterns(List<String> patterns) {
    _exclude.addAll(patterns.map(PathPattern.parse));
    return this;
  }

  /// Whether it applies to [path].
  bool appliesTo(String path) =>
      (_include.isEmpty || _include.any((p) => p.matches(path))) &&
      !_exclude.any((p) => p.matches(path));
}

/// Customizes Spring MVC, like Spring's `WebMvcConfigurer`: declare beans
/// implementing it.
///
/// ```dart
/// @Configuration()
/// class WebConfig with WebMvcConfigurer {
///   @override
///   void addCorsMappings(CorsRegistry registry) =>
///       registry.addMapping('/api/**').allowedOrigins(['https://shop.example']);
/// }
/// ```
abstract mixin class WebMvcConfigurer {
  /// Adds handler interceptors.
  void addInterceptors(InterceptorRegistry registry) {}

  /// Adds global CORS mappings.
  void addCorsMappings(CorsRegistry registry) {}

  /// Adds argument resolvers.
  void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {}
}
