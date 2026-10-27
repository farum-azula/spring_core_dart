// Advice without an aspect (chapter 6): a PointcutAdvisor bean, a
// pointcut expression with a MethodInterceptor written by hand. It counts
// the calls of every controller method (the handlers are called through
// the controllers' proxies, so advice applies to them).
import 'package:spring_core_dart/spring_core_dart.dart';

/// Calls per handler, `BookController.search` → 12.
@Component()
class HandlerMetrics {
  final calls = <String, int>{};
}

final class CountingInterceptor implements MethodInterceptor {
  CountingInterceptor(this.metrics);

  final HandlerMetrics metrics;

  @override
  Object? invoke(MethodInvocation invocation) {
    final name =
        '${invocation.signature.declaringType}.${invocation.signature.name}';
    metrics.calls[name] = (metrics.calls[name] ?? 0) + 1;
    return invocation.proceed();
  }
}

@Configuration()
class MetricsConfig {
  @Bean()
  PointcutAdvisor handlerMetricsAdvisor(HandlerMetrics metrics) =>
      DefaultPointcutAdvisor(
        ExpressionPointcut('within(*Controller)'),
        CountingInterceptor(metrics),
      );
}
