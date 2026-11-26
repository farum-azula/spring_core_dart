import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_event.dart';

/// The post-processor through which the [DebugBeanGraph] hears of the
/// beans created and destroyed. The graph adds it to the bean factory
/// when it starts and takes it away when it stops, so while the graph is
/// not used, and in a build without it, the container does no work for
/// it at all.
///
/// While it is in, every bean created asks for destruction callbacks, so
/// the destruction of a bean of a custom scope (a route's) reaches it
/// even when the bean has no destroy method of its own.
final class DebugBeanLifecycleRecorder
    extends DestructionAwareBeanPostProcessor {
  /// A recorder of the beans of [factory], telling [onEvent].
  DebugBeanLifecycleRecorder(this.factory, this.onEvent);

  /// The factory whose beans it watches.
  final ConfigurableListableBeanFactory factory;

  /// Told of each bean created and destroyed, while the container creates
  /// or destroys it: it must only take note.
  final void Function(DebugBeanEventKind kind, String beanName) onEvent;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    // A factory bean's product and an object of initializeBean pass here
    // too, outside the creation of a bean of that name: not a new bean.
    if (factory.isCurrentlyInCreation(beanName)) {
      onEvent(DebugBeanEventKind.created, beanName);
    }
    return bean;
  }

  @override
  void postProcessBeforeDestruction(Object bean, String beanName) =>
      onEvent(DebugBeanEventKind.destroyed, beanName);

  @override
  bool requiresDestruction(Object bean) => true;
}
