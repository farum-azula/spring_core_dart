import 'package:neon_books_app/main.spring.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Logs the app's lifecycle, which arrives as application events: the
/// Flutter states (`AppLifecycleStateEvent`), and the context being
/// paused in the background (`@Scheduled` tasks and the chat's socket
/// stop) and restarted in the foreground.
///
/// `@Log` generates the `log` getter (in `main.spring.dart`), like
/// Lombok's `@Slf4j`; without `topic` the logger would be
/// `neon_books_app.LifecycleLog`.
@Component()
@Log(topic: 'neon.lifecycle')
class LifecycleLog {
  @EventListener()
  void onState(AppLifecycleStateEvent event) =>
      log.info('App ${event.state.name}');

  @EventListener()
  void onPaused(ContextPausedEvent event) =>
      log.info('In the background: scheduled tasks paused');

  @EventListener()
  void onRestarted(ContextRestartedEvent event) =>
      log.info('In the foreground again: scheduled tasks running');
}
