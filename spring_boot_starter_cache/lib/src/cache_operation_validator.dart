import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache_interceptor.dart';
import 'package:spring_boot_starter_cache/src/cache_operation.dart';

/// Checks the cache annotations of each proxied bean when the bean is
/// created, so a wrong annotation fails the startup instead of the first
/// call of the method.
///
/// It is a bean post-processor: the container hands it every new bean,
/// and for the beans with a generated proxy it asks the [CacheInterceptor]
/// to read and check the annotations of every member
/// ([CacheInterceptor.cacheOperations]). Spring does the same when it
/// builds the proxy. The starter registers it; applications do not use
/// it.
///
/// ```dart
/// // In the auto-configuration: the interceptor is fetched at first use.
/// CacheOperationValidator.lazy(() => factory.getBean<CacheInterceptor>())
/// ```
final class CacheOperationValidator extends BeanPostProcessor
    implements BeanFactoryAware {
  /// A validator that checks with [interceptor].
  CacheOperationValidator(CacheInterceptor interceptor)
    : _interceptor = (() => interceptor);

  /// A validator that calls [interceptor] to get the interceptor only when
  /// the first bean with cache annotations comes.
  ///
  /// The auto-configuration uses this one. The dependencies of a
  /// post-processor are created before the other post-processors are
  /// registered, so they would miss them (the context then logs that they
  /// are "not eligible for getting processed by all BeanPostProcessors");
  /// fetching the interceptor late avoids that.
  CacheOperationValidator.lazy(CacheInterceptor Function() interceptor)
    : _interceptor = interceptor;

  final CacheInterceptor Function() _interceptor;

  /// The interceptor whose [CacheInterceptor.cacheOperations] checks the
  /// annotations; obtained on first use.
  late final CacheInterceptor interceptor = _interceptor();

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  // Before initialization, so it runs ahead of the auto proxy creator
  // (which proxies after initialization) whatever the order.
  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory! as BeanDefinitionRegistry).containsBeanDefinition(
          beanName,
        )) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    for (final signature
        in definition.aopProxy?.signatures ?? const <MethodSignature>[]) {
      if (AnnotationCacheOperationSource.cacheAnnotationsOf(signature)
          .isNotEmpty) {
        interceptor.cacheOperations(signature);
      }
    }
    return bean;
  }
}
