import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limiter.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The filter that applies the rules of `spring.web.rate-limit.rules`.
/// A request past a limit ends here with a 429 and `Retry-After`: its
/// body is not read, no later filter and no handler runs.
///
/// The starter registers two of them, with the rules sorted by what
/// their key needs:
///
/// - `rateLimitFilter` at [beforeAuthenticationOrder] (-5000): the rules
///   keyed by `ip` (and by a resolver that says it needs no user). It
///   runs after the forwarded headers are applied (-10000) and before the
///   sessions (-1000) and the security filter chain (-100): a flood is
///   refused before a session is looked up, a token checked or a
///   password hashed.
/// - `authenticatedRateLimitFilter` at [afterAuthenticationOrder] (-50):
///   the rules keyed by `user` or by an expression. It runs right after
///   the security filter chain, inside its scope, so `request.principal`
///   is the authenticated user. A request the chain answered itself (a
///   401, a 403, a login page) does not reach it: limit those by `ip`.
///
/// Without the security starter both run one after the other and `user`
/// counts by address.
///
/// ```dart
/// // Its own rules, in code, before authentication.
/// @Bean()
/// RateLimitFilter uploads(RequestRateLimiter limiter) => RateLimitFilter(
///   limiter,
///   [RateLimitRule(name: 'uploads', path: '/upload/**', key: 'ip',
///       limit: RateLimit.parse('10/1h'))],
///   order: RateLimitFilter.beforeAuthenticationOrder,
/// );
/// ```
///
/// Spring (Java): Spring Cloud Gateway's `RequestRateLimiter` gateway
/// filter; with Bucket4j, a servlet `Filter` before the security chain.
final class RateLimitFilter implements WebFilter, Ordered {
  /// A filter applying [rules] through [limiter], at [order] among the
  /// web filters.
  RateLimitFilter(
    this.limiter,
    List<RateLimitRule> rules, {
    required this.order,
  }) : rules = List.unmodifiable(rules);

  /// The order of the filter of the rules that need no user: after the
  /// forwarded headers, before the sessions and the security chain.
  static const beforeAuthenticationOrder = -5000;

  /// The order of the filter of the rules that read the user: right
  /// after the security filter chain (-100).
  static const afterAuthenticationOrder = -50;

  /// Applies the rules.
  final RequestRateLimiter limiter;

  /// The rules of this filter, in the order they are applied.
  final List<RateLimitRule> rules;

  @override
  final int order;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final matching = [
      for (final rule in rules)
        if (rule.matches(request)) rule,
    ];
    if (matching.isNotEmpty) {
      await limiter.acquire(request, response, matching);
    }
    await chain.doFilter(request, response);
  }
}

/// Applies the `@RateLimiter` annotations of the controllers: an
/// interceptor, as it needs the handler of the request. It runs before
/// the handler's arguments are bound, so a refused request's body is not
/// read; the filters of the rules have run before it.
///
/// The annotations are read when the application starts, and a limit or
/// a key that cannot be read stops the start.
final class RateLimiterInterceptor
    with HandlerInterceptor
    implements SmartInitializingSingleton {
  /// An interceptor applying the annotations of the controllers of
  /// [beanFactory] through [limiter]; [environment] resolves the
  /// placeholders of their limits.
  RateLimiterInterceptor(this.limiter, this.beanFactory, this.environment);

  /// Applies the rules.
  final RequestRateLimiter limiter;

  /// The container whose controllers are read.
  final ListableBeanFactory beanFactory;

  /// Resolves `${...}` in the limits.
  final Environment environment;

  final _byMethod = Map<BeanMethod<Object>, List<RateLimitRule>>.identity();

  @override
  void afterSingletonsInstantiated() {
    for (final (:type, :method, :annotations) in controllerRateLimiters(
      beanFactory,
    )) {
      _byMethod[method] = [
        for (final (annotation, onClass) in annotations)
          _rule(annotation, onClass ? type : '$type.${method.name}'),
      ];
    }
  }

  RateLimitRule _rule(RateLimiter annotation, String name) {
    final RateLimit limit;
    try {
      limit = RateLimit.parse(
        environment.resolveRequiredPlaceholders(annotation.limit),
        burst: annotation.burst,
      );
    } on FormatException catch (error) {
      throw StateError('@RateLimiter on $name: ${error.message}');
    }
    final rule = RateLimitRule(
      name: annotation.name ?? name,
      limit: limit,
      key: annotation.key ?? 'user',
      onStoreFailure: annotation.onStoreFailure,
    );
    limiter.validate(rule);
    return rule;
  }

  @override
  Future<bool> preHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
  ) async {
    final rules = _byMethod[handler.method];
    if (rules != null && rules.isNotEmpty) {
      await limiter.acquire(request, response, rules);
    }
    return true;
  }
}

/// The `@RateLimiter` annotations of the controllers of [beanFactory]:
/// for each annotated method, the controller's class name, the method and
/// its annotations (those of the class first, marked `true`).
Iterable<
  ({
    String type,
    BeanMethod<Object> method,
    List<(RateLimiter, bool)> annotations,
  })
>
controllerRateLimiters(ListableBeanFactory beanFactory) sync* {
  final registry = beanFactory as BeanDefinitionRegistry;
  for (final name in beanFactory.getBeanNamesForAnnotation<Controller>()) {
    if (!registry.containsBeanDefinition(name)) {
      continue;
    }
    final definition = registry.getBeanDefinition(name);
    final onClass = definition.annotations.whereType<RateLimiter>();
    for (final method in definition.annotatedMethods) {
      if (method.annotations.whereType<Mapping>().isEmpty) {
        continue;
      }
      final annotations = [
        for (final annotation in onClass) (annotation, true),
        for (final annotation in method.annotations.whereType<RateLimiter>())
          (annotation, false),
      ];
      if (annotations.isNotEmpty) {
        yield (
          type: '${definition.beanType}',
          method: method,
          annotations: annotations,
        );
      }
    }
  }
}

/// Stops the start of an application whose controllers have
/// `@RateLimiter` while rate limiting was never turned on
/// (`spring.web.rate-limit.enabled` not set and no rule): the annotations
/// would do nothing. With `enabled: false` they are off on purpose, and
/// nothing is checked.
final class RateLimiterAnnotationGuard implements SmartInitializingSingleton {
  /// A guard of the controllers of [beanFactory].
  const RateLimiterAnnotationGuard(this.beanFactory);

  /// The container whose controllers are read.
  final ListableBeanFactory beanFactory;

  @override
  void afterSingletonsInstantiated() {
    final first = controllerRateLimiters(beanFactory).firstOrNull;
    if (first != null) {
      throw StateError(
        '@RateLimiter on ${first.type}.${first.method.name}, but rate '
        'limiting is off: set spring.web.rate-limit.enabled to true (or to '
        'false, to turn the annotations off on purpose)',
      );
    }
  }
}
