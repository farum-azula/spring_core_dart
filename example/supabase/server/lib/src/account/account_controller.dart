import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:supabase_example_server/src/todos/todo.dart';

/// `GET /api/me`: who the token belongs to.
@Introspected()
class Me {
  const Me({required this.id, required this.roles, this.email});

  /// The user's id in the project (the token's `sub`).
  final String id;

  /// From `app_metadata.roles` of the user, without the `ROLE_` prefix.
  /// Only the project's admin API writes them (`SupabaseAuthAdmin`).
  final List<String> roles;

  final String? email;
}

/// `GET /api/admin/report`.
@Introspected()
class Report {
  const Report({required this.todos});

  /// The todos of every user.
  final int todos;
}

/// What only an admin may ask. The rule is on the bean, not on the path:
/// whoever calls [report], from whatever controller, needs the role.
@Service()
class AdminReports {
  AdminReports(this.todos, this.credentials);

  final Todos todos;
  final SupabaseCredentials credentials;

  /// Counts the todos of every user: inside `asServiceRole` the statement
  /// runs as the user of `spring.supabase.db.url`, past row-level
  /// security, instead of as the caller.
  @PreAuthorize("hasRole('ADMIN')")
  Future<Report> report() async =>
      Report(todos: await credentials.asServiceRole(todos.count));
}

@RestController()
@RequestMapping('/api')
class AccountController {
  AccountController(this.reports);

  final AdminReports reports;

  /// The caller, as Spring Security sees a token of the project: the
  /// name is the user's id, the authorities `ROLE_<role>`.
  @GetMapping('/me')
  Me me(Authentication authentication) => Me(
    id: authentication.name,
    email: switch (authentication) {
      JwtAuthenticationToken(:final jwt) => switch (jwt.claims['email']) {
        final String email => email,
        _ => null,
      },
      _ => null,
    },
    roles: [
      for (final authority in authentication.authorities)
        if (authority.authority case final String name
            when name.startsWith('ROLE_'))
          name.substring('ROLE_'.length),
    ]..sort(),
  );

  /// 403 for a user without the role `ADMIN`.
  @GetMapping('/admin/report')
  Future<Report> report() => reports.report();
}
