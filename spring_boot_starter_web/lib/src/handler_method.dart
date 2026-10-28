import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// One controller method that answers requests: which bean it belongs to
/// and how to call it.
///
/// The starter builds one per mapped method when the context starts, from
/// the description the generator wrote. Applications meet it in a
/// `HandlerInterceptor`, which receives the handler of the request and can
/// read its annotations, and in the `bestMatchingHandlerAttribute`
/// attribute of the request. The method is called on the bean as the
/// container holds it, so AOP advice on the controller (`@Cacheable`,
/// method validation) applies.
///
/// ```dart
/// // An interceptor that lets only admins call methods marked @AdminOnly.
/// @override
/// bool preHandle(request, response, HandlerMethod handler) {
///   if (handler.annotation<AdminOnly>() != null && !isAdmin(request)) {
///     throw ResponseStatusException(HttpStatus.forbidden);
///   }
///   return true;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public boolean preHandle(HttpServletRequest request,
///     HttpServletResponse response, Object handler) {
///   if (handler instanceof HandlerMethod method
///       && method.hasMethodAnnotation(AdminOnly.class) && !isAdmin(request)) {
///     throw new ResponseStatusException(HttpStatus.FORBIDDEN);
///   }
///   return true;
/// }
/// ```
final class HandlerMethod {
  /// The [method] of the bean [beanName], an instance of the class
  /// [beanTypeName]. Created by the starter.
  HandlerMethod({
    required this.beanName,
    required this.beanTypeName,
    required this.method,
    required this.classAnnotations,
    required this._beanFactory,
  });

  /// The name of the controller bean, such as `bookController`.
  final String beanName;

  /// The name of the controller class, used in messages and
  /// [description].
  final String beanTypeName;

  /// The method as the generator described it: its name, parameters,
  /// annotations and result type, and a way to invoke it.
  final BeanMethod<Object> method;

  /// The annotations on the controller class, such as its
  /// `@RequestMapping` or `@CrossOrigin`.
  final List<Object> classAnnotations;

  final BeanFactory _beanFactory;

  /// The class and method name, such as `BookController.find`, as logs
  /// and error messages show it.
  String get description => '$beanTypeName.${method.name}';

  /// The method's parameters, positional first, then named.
  late final List<MethodParameter> parameters = [
    for (final (index, parameter) in method.parameters.indexed)
      MethodParameter(this, index, parameter),
  ];

  /// The annotation of type [A] on the method or, when the method has
  /// none, on the controller class; `null` when neither has one.
  A? annotation<A>() =>
      method.annotations.whereType<A>().firstOrNull ??
      classAnnotations.whereType<A>().firstOrNull;

  /// The object the method is called on: the bean from the container
  /// (a proxy when advice applies), or its target when the proxy
  /// implements only the bean's interfaces and cannot take the call.
  Object resolveBean() {
    final bean = _beanFactory.getBeanByName(beanName);
    return method.appliesTo(bean) ? bean : AopUtils.getTarget(bean);
  }

  @override
  String toString() => description;
}

/// One parameter of a controller method: its name, type and annotations.
///
/// A [HandlerMethodArgumentResolver] receives it to decide whether it
/// fills the parameter and, per request, which value to give.
///
/// ```dart
/// // Fill every parameter marked @CurrentUser.
/// @override
/// bool supportsParameter(MethodParameter parameter) =>
///     parameter.has<CurrentUser>();
/// ```
///
/// Spring (Java):
/// ```java
/// public boolean supportsParameter(MethodParameter parameter) {
///   return parameter.hasParameterAnnotation(CurrentUser.class);
/// }
/// ```
final class MethodParameter {
  /// The parameter at [index] of [handler], described by [parameter].
  /// Created by the starter.
  MethodParameter(this.handler, this.index, this.parameter);

  /// The controller method the parameter belongs to.
  final HandlerMethod handler;

  /// The position among all parameters, positional first, then named
  /// (from 0).
  final int index;

  /// The generator's description of the parameter, with whether it is
  /// named and whether it is required.
  final BeanParameter parameter;

  /// The parameter's name in the source code.
  String get name => parameter.name;

  /// The declared type, with its type arguments and nullability:
  /// `type.type` is the Dart `Type`, `type.nullable` tells whether `null`
  /// is accepted.
  TypeInfo<Object?> get type => parameter.type;

  /// The annotations on the parameter.
  List<Object> get annotations => parameter.annotations;

  /// The first annotation of type [A] on the parameter, or `null`; use it
  /// to read the annotation's values.
  A? annotation<A>() => parameter.annotations.whereType<A>().firstOrNull;

  /// Whether the parameter has an annotation of type [A].
  bool has<A>() => parameter.annotations.whereType<A>().isNotEmpty;

  @override
  String toString() => '${handler.description}($name)';
}

/// Supplies the value of controller parameters that the starter does
/// not know how to fill.
///
/// The starter fills path variables, query parameters, headers, cookies,
/// bodies and a few types (the request, the response, the `Principal`).
/// When a controller wants something else, computed from the request,
/// such as the current tenant or user, a resolver provides it, so each
/// controller method just declares a parameter instead of repeating the
/// lookup. Register it in `WebMvcConfigurer.addArgumentResolvers`.
///
/// At startup, [supportsParameter] is asked once for every parameter of
/// every controller method; the first resolver that says yes fills it on
/// each request. Custom resolvers are asked before the built-in ones
/// (Spring asks them after), so they can take over any parameter, which
/// the security starter needs for `@AuthenticationPrincipal`.
///
/// ```dart
/// // Controllers declare a `Tenant tenant` parameter; it comes from the
/// // X-Tenant header.
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
///
/// Spring (Java):
/// ```java
/// class TenantResolver implements HandlerMethodArgumentResolver {
///   public boolean supportsParameter(MethodParameter parameter) {
///     return parameter.getParameterType() == Tenant.class;
///   }
///
///   public Object resolveArgument(MethodParameter parameter,
///       ModelAndViewContainer mav, NativeWebRequest request,
///       WebDataBinderFactory binders) {
///     return new Tenant(request.getHeader("X-Tenant"));
///   }
/// }
/// ```
abstract interface class HandlerMethodArgumentResolver {
  /// Whether this resolver fills [parameter]. Asked once per parameter
  /// when the context starts, not per request.
  bool supportsParameter(MethodParameter parameter);

  /// The value of [parameter] for this [request]; may return a `Future`.
  /// An exception becomes the error answer of the request, so throw a
  /// `ResponseStatusException` for a 400 or 401.
  FutureOr<Object?> resolveArgument(
    MethodParameter parameter,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// Code that runs before and after the controller methods, with the
/// method at hand.
///
/// Use an interceptor for work around the controllers that depends on
/// which method answers: timing per endpoint, checks driven by a method's
/// annotation, adding to the result's headers. Unlike a `WebFilter`, it
/// runs only for requests mapped to a controller method, after the method
/// is chosen, and it receives that [HandlerMethod]. Mix it in and
/// override only the steps you need; the defaults do nothing.
///
/// An interceptor runs only when a `WebMvcConfigurer` registers it in
/// `addInterceptors`, optionally for some paths; a `HandlerInterceptor`
/// bean alone is not picked up. Interceptors run in registration order
/// before the method, and in reverse order after it.
///
/// ```dart
/// // Logs how long each controller method takes.
/// final class TimingInterceptor with HandlerInterceptor {
///   @override
///   bool preHandle(request, response, handler) {
///     request.attributes['start'] = DateTime.now();
///     return true;
///   }
///
///   @override
///   void afterCompletion(request, response, handler, error) {
///     final start = request.attributes['start'] as DateTime;
///     print('${handler.description}: ${DateTime.now().difference(start)}');
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class TimingInterceptor implements HandlerInterceptor {
///   public boolean preHandle(HttpServletRequest request,
///       HttpServletResponse response, Object handler) {
///     request.setAttribute("start", System.nanoTime());
///     return true;
///   }
/// }
/// ```
abstract mixin class HandlerInterceptor {
  /// Runs before the controller method. Return `true` to go on; return
  /// `false` when the interceptor has answered the request itself (the
  /// method is not called, and the interceptors before it get
  /// [afterCompletion]). Throwing makes the exception the request's
  /// answer, through the `@ExceptionHandler` methods. May return a
  /// `Future`.
  FutureOr<bool> preHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
  ) => true;

  /// Runs after the controller method returned [result] (the value of
  /// its `Future`), before the result is written. The response is not
  /// sent yet, so headers can still be added. Not called when the method
  /// threw.
  FutureOr<void> postHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
    Object? result,
  ) {}

  /// Runs when the request is done: after the result was written, or
  /// after an exception was answered. [error] is that exception (even
  /// when an `@ExceptionHandler` answered it), `null` on success. Called
  /// only for interceptors whose [preHandle] returned `true`; an exception
  /// thrown here is logged and ignored. Use it for clean-up and timing.
  FutureOr<void> afterCompletion(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
    Object? error,
  ) {}
}

/// The list of [HandlerInterceptor]s a `WebMvcConfigurer` fills in its
/// `addInterceptors` method, each with the paths it applies to.
///
/// The starter creates the registry, hands it to every
/// `WebMvcConfigurer` bean, and runs the interceptors in the order they
/// were added.
///
/// ```dart
/// @Configuration()
/// class WebConfig with WebMvcConfigurer {
///   // Time the API calls, but not the health checks.
///   @override
///   void addInterceptors(InterceptorRegistry registry) => registry
///       .addInterceptor(TimingInterceptor())
///       .addPathPatterns(['/api/**'])
///       .excludePathPatterns(['/api/health']);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class WebConfig implements WebMvcConfigurer {
///   @Override
///   public void addInterceptors(InterceptorRegistry registry) {
///     registry.addInterceptor(new TimingInterceptor())
///         .addPathPatterns("/api/**")
///         .excludePathPatterns("/api/health");
///   }
/// }
/// ```
final class InterceptorRegistry {
  final _registrations = <InterceptorRegistration>[];

  /// Adds [interceptor] after those already added, for every path until
  /// the returned registration restricts it.
  InterceptorRegistration addInterceptor(HandlerInterceptor interceptor) {
    final registration = InterceptorRegistration._(interceptor);
    _registrations.add(registration);
    return registration;
  }

  /// The registrations in the order they were added (read-only).
  List<InterceptorRegistration> get registrations =>
      List.unmodifiable(_registrations);
}

/// One interceptor of an [InterceptorRegistry] with the paths it applies
/// to, set with chained calls.
///
/// Paths are path patterns (`/api/**`, `/books/{isbn}`) matched against
/// the request path without the context path. With no included pattern
/// the interceptor applies to every path; an excluded pattern wins over
/// an included one.
final class InterceptorRegistration {
  InterceptorRegistration._(this.interceptor);

  /// The interceptor this registration applies.
  final HandlerInterceptor interceptor;

  final _include = <PathPattern>[];
  final _exclude = <PathPattern>[];

  /// Restricts the interceptor to paths matching one of [patterns];
  /// repeated calls add patterns. Returns this registration.
  InterceptorRegistration addPathPatterns(List<String> patterns) {
    _include.addAll(patterns.map(PathPattern.parse));
    return this;
  }

  /// Keeps the interceptor away from paths matching one of [patterns],
  /// even when they are included. Returns this registration.
  InterceptorRegistration excludePathPatterns(List<String> patterns) {
    _exclude.addAll(patterns.map(PathPattern.parse));
    return this;
  }

  /// Whether the interceptor runs for a request to [path]: it matches an
  /// included pattern (or none is set) and no excluded one.
  bool appliesTo(String path) =>
      (_include.isEmpty || _include.any((p) => p.matches(path))) &&
      !_exclude.any((p) => p.matches(path));
}

/// A bean that adds interceptors, CORS rules or argument resolvers to
/// the controllers.
///
/// The starter sets up the controllers with no interceptors, no global
/// CORS rules and only its own argument resolvers. To add any of them,
/// declare a bean that mixes this in and override the methods you need;
/// the others do nothing. The starter calls every `WebMvcConfigurer` bean
/// once, while it creates the controllers' mapping at startup, in bean
/// order.
///
/// ```dart
/// @Configuration()
/// class WebConfig with WebMvcConfigurer {
///   // The shop's pages may call the API from the browser.
///   @override
///   void addCorsMappings(CorsRegistry registry) => registry
///       .addMapping('/api/**')
///       .allowedOrigins(['https://shop.example']);
///
///   // Controllers can declare a `Tenant` parameter.
///   @override
///   void addArgumentResolvers(
///     List<HandlerMethodArgumentResolver> resolvers,
///   ) => resolvers.add(TenantResolver());
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class WebConfig implements WebMvcConfigurer {
///   @Override
///   public void addCorsMappings(CorsRegistry registry) {
///     registry.addMapping("/api/**").allowedOrigins("https://shop.example");
///   }
///
///   @Override
///   public void addArgumentResolvers(
///       List<HandlerMethodArgumentResolver> resolvers) {
///     resolvers.add(new TenantResolver());
///   }
/// }
/// ```
abstract mixin class WebMvcConfigurer {
  /// Override to add [HandlerInterceptor]s, each for all paths or some.
  void addInterceptors(InterceptorRegistry registry) {}

  /// Override to add CORS rules by path pattern; they apply to every
  /// controller on those paths, combined with its `@CrossOrigin`.
  void addCorsMappings(CorsRegistry registry) {}

  /// Override to add [HandlerMethodArgumentResolver]s to [resolvers];
  /// they are asked in list order, before the built-in ones.
  void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {}
}
