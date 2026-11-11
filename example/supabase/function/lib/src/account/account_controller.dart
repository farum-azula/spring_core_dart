import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@RestController()
class AccountController {
  AccountController(this.runtime);

  final EdgeRuntime runtime;

  /// Open to everyone: where the function runs.
  @GetMapping('/health')
  Map<String, Object?> health() => {
    'status': 'UP',
    'runtime': runtime.platform ?? 'server',
  };

  /// Who calls, as the resource server read it from the project's token.
  @GetMapping('/me')
  Map<String, Object?> me(Authentication authentication) => {
    'id': authentication.name,
    'roles': [for (final a in authentication.authorities) a.authority],
  };

  @GetMapping('/admin')
  @PreAuthorize("hasRole('ADMIN')")
  String admin() => 'for admins';
}
