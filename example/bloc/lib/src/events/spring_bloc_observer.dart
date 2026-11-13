import 'package:bloc_showcase/src/events/bloc_application_events.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Publishes what every bloc of the app does as application events, so a
/// bean hears a bloc with `@EventListener` and knows nothing of streams
/// or subscriptions:
///
/// ```dart
/// @EventListener()
/// void onChange(BlocStateChanged change) { ... }
/// ```
///
/// Bloc has one observer for the whole app (`Bloc.observer`): this bean
/// takes its place when the application starts, before any bloc is made
/// (a `BeanFactoryPostProcessor` runs first), and gives it back when it
/// closes. The publisher is given by the container
/// (`ApplicationEventPublisherAware`), not through the constructor: a
/// post-processor is made too early for ordinary injection. Written by hand, in forty lines: the framework has no part in
/// it but the events.
@Component()
class SpringBlocObserver extends BlocObserver
    implements BeanFactoryPostProcessor, ApplicationEventPublisherAware {
  /// Where the events go: given by the container.
  late ApplicationEventPublisher events;

  @override
  void setApplicationEventPublisher(ApplicationEventPublisher publisher) =>
      events = publisher;

  BlocObserver? _previous;

  /// Becomes the app's observer before any other bean is made: a bloc
  /// keeps the observer there was when it was created, so one made
  /// earlier would not be heard.
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    _previous = Bloc.observer;
    Bloc.observer = this;
  }

  /// Gives the place back, unless something else took it since.
  @PreDestroy()
  void uninstall() {
    if (identical(Bloc.observer, this) && _previous != null) {
      Bloc.observer = _previous!;
    }
    _previous = null;
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.publishEvent(BlocEventAdded(bloc, event));
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    events.publishEvent(
      BlocStateChanged(
        bloc,
        current: change.currentState,
        next: change.nextState,
      ),
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    events.publishEvent(BlocFailed(bloc, error, stackTrace));
  }
}
