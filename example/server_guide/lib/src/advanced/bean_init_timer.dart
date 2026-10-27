// A BeanPostProcessor of our own: it sees every bean created after it,
// before and after the bean's init callbacks, and here measures them.
import 'package:neon_books_server/src/advanced/advanced_tour.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

@Component()
@AdvancedTour()
class BeanInitTimer extends BeanPostProcessor {
  final _started = <String, Stopwatch>{};

  /// How long each bean's initialization took (`@PostConstruct`,
  /// `afterPropertiesSet`, the init method), by bean name.
  final timings = <String, Duration>{};

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    _started[beanName] = Stopwatch()..start();
    return bean;
  }

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (_started.remove(beanName) case final watch?) {
      timings[beanName] = watch.elapsed;
    }
    return bean;
  }

  /// The [count] slowest initializations.
  List<MapEntry<String, Duration>> slowest(int count) =>
      (timings.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(count)
          .toList();
}
