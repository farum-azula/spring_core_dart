// A registry post-processor: registers a bean definition written by hand
// (no annotations, no generated code), before any bean is created.
import 'package:neon_books_server/src/advanced/advanced_tour.dart';
import 'package:neon_books_server/src/stock/stock_service.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Tells which books run low.
class LowStockAlarm {
  LowStockAlarm(this._stock);

  final StockService _stock;

  List<String> ringing() => [for (final book in _stock.lowStock()) book.title];
}

@Component()
@AdvancedTour()
class AlarmRegistrar implements BeanDefinitionRegistryPostProcessor {
  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<LowStockAlarm>(
          name: 'lowStockAlarm',
          dependencies: const [Dependency(StockService)],
          create: (r) => LowStockAlarm(r.dependency<StockService>()),
        ),
      );

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}
