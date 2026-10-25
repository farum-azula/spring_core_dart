import 'package:flutter_counter/main.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Logs the app's lifecycle, which arrives as application events.
///
/// `@Log` generates the `log` getter (in `main.spring.dart`), like Lombok's
/// `@Slf4j`; without `topic` the logger would be `flutter_counter.LifecycleLog`.
@Component()
@Log(topic: 'counter.lifecycle')
class LifecycleLog {
  @EventListener()
  void onState(AppLifecycleStateEvent event) =>
      log.info('App ${event.state.name}');
}
