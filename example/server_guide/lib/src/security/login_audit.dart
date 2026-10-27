// Authentication events (chapter 4): the security packages publish them,
// the application decides what to do (here: log, and count failures).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@Component()
@Log(topic: 'neon.security')
class LoginAudit {
  /// Failed logins per user name since the start.
  final failures = <String, int>{};

  @EventListener()
  void onSuccess(AuthenticationSuccessEvent event) =>
      log.info('${event.authentication.name} logged in');

  @EventListener()
  void onBadCredentials(AuthenticationFailureBadCredentialsEvent event) {
    final name = event.authentication.name;
    final count = failures[name] = (failures[name] ?? 0) + 1;
    log.warning('failed login for "$name" ($count so far)');
  }

  @EventListener()
  void onLogout(LogoutSuccessEvent event) =>
      log.info('${event.authentication.name} logged out');
}
