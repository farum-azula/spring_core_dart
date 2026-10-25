// Container extension points: your own BeanPostProcessor,
// DestructionAwareBeanPostProcessor, BeanFactoryPostProcessor,
// BeanDefinitionRegistryPostProcessor and a custom scope.
//
// Spring (Java): the same interfaces; ConfigurableBeanFactory.registerScope.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

/// Marker for beans the BPP below should audit.
abstract interface class Audited {
  List<String> get auditTrail;
}

/// A custom BeanPostProcessor: stamps every [Audited] bean after its
/// initialization and counts the beans it saw.
@Component()
class AuditingPostProcessor extends BeanPostProcessor {
  final seen = <String>[];

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    seen.add(beanName);
    if (bean is Audited) {
      bean.auditTrail.add('audited by AuditingPostProcessor');
      tourLog.add('bpp: audited $beanName');
    }
    return bean;
  }
}

/// Runs before each singleton's destroy callbacks.
@Component()
class ShutdownWatcher extends DestructionAwareBeanPostProcessor {
  @override
  bool requiresDestruction(Object bean) => bean is Audited;

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      tourLog.add('destruction-aware bpp: $beanName');
}

@Service()
class InvoiceService implements Audited {
  @override
  final auditTrail = <String>[];
}

/// Changes another bean's definition before any bean is created.
@Component()
class ReportsLazyPostProcessor implements BeanFactoryPostProcessor {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    beanFactory.getBeanDefinition('salesReport').lazy = true;
    tourLog.add('bfpp: made salesReport lazy');
  }
}

class SalesReport {
  SalesReport() {
    tourLog.add('salesReport: created on first use');
  }
}

@Configuration()
class ReportConfig {
  @Bean()
  SalesReport salesReport() => SalesReport();
}

class Banner {
  Banner(this.text);
  final String text;
}

/// Registers a bean definition written by hand.
@Component()
class BannerRegistrar implements BeanDefinitionRegistryPostProcessor {
  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    registry.registerBeanDefinition(
      BeanDefinition<Banner>(
        name: 'banner',
        create: (r) => Banner('Sale! ${r.value<String>(r'${app.name}')}'),
      ),
    );
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}

/// A bean in the custom `basket` scope (registered by the tour with
/// `registerScope('basket', SimpleMapScope())`).
@Component()
@Scope('basket')
class Basket {
  final items = <String>[];
}

/// A singleton reads the scoped bean through a provider, so it always sees
/// the current basket.
@Service()
class BasketService {
  BasketService(this.basket);

  final ObjectProvider<Basket> basket;

  void add(String title) => basket.getObject().items.add(title);

  List<String> get items => basket.getObject().items;
}

/// A prototype: the container creates a new one for each lookup.
@Component()
@Scope(ScopeType.prototype)
class Receipt {
  final lines = <String>[];
}

/// Lookup method injection: an abstract singleton whose `@Lookup` methods
/// the generated subclass implements, returning beans of the container on
/// every call.
///
/// Spring (Java): the same `@Lookup` on abstract methods, implemented by a
/// CGLIB subclass.
@Service()
abstract class Cashier {
  /// A new [Receipt] per call (by return type).
  @Lookup()
  Receipt newReceipt();

  /// The bean named `banner` (a singleton: the same each time).
  @Lookup('banner')
  Banner banner();

  /// Rings up [titles] on a fresh receipt.
  Receipt ring(List<String> titles) => newReceipt()..lines.addAll(titles);
}
