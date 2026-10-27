// Spring MVC settings in code (chapter 3): a HandlerInterceptor
// registered by a WebMvcConfigurer for the API's paths.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@Configuration()
class WebConfig with WebMvcConfigurer {
  @override
  void addInterceptors(InterceptorRegistry registry) => registry
      .addInterceptor(ServerTimingInterceptor())
      .addPathPatterns(['/api/**'])
      .excludePathPatterns(['/api/stock/events']);
}

/// Tells clients how long the handler took (`Server-Timing: app;dur=1.2`,
/// shown by browsers' developer tools).
final class ServerTimingInterceptor with HandlerInterceptor {
  static const _start = 'neon.start';

  @override
  bool preHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
  ) {
    request.attributes[_start] = Stopwatch()..start();
    return true;
  }

  /// After the handler, before the result is written: headers can still
  /// be set.
  @override
  void postHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
    Object? result,
  ) {
    final watch = request.attributes[_start]! as Stopwatch;
    final millis = watch.elapsedMicroseconds / 1000;
    response.headers.set(
      'Server-Timing',
      'app;dur=${millis.toStringAsFixed(1)};desc="${handler.description}"',
    );
  }
}
