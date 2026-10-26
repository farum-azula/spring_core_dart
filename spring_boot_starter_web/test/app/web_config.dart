import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@Component()
@Order(1)
class TraceFilter implements WebFilter {
  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    response.headers.set('X-Trace', 'on');
    return chain.doFilter(request, response);
  }
}

final class CountingInterceptor with HandlerInterceptor {
  var count = 0;

  @override
  bool preHandle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    HandlerMethod handler,
  ) {
    count++;
    return true;
  }
}

@Configuration()
class WebConfig with WebMvcConfigurer {
  final interceptor = CountingInterceptor();

  @override
  void addCorsMappings(CorsRegistry registry) => registry
      .addMapping('/api/**')
      .allowedOrigins(['https://shop.example'])
      .allowedMethods(['GET', 'POST']);

  @override
  void addInterceptors(InterceptorRegistry registry) =>
      registry.addInterceptor(interceptor).addPathPatterns(['/api/**']);
}
