import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../../app/supabase_app.dart';

@RestController()
@RequestMapping('/api')
class AccountController {
  AccountController(this.reports, this.todos);

  final AdminReports reports;
  final Todos todos;

  @GetMapping('/me')
  Map<String, Object?> me(Authentication authentication) => {
    'name': authentication.name,
    'authorities': [for (final a in authentication.authorities) a.authority],
  };

  @GetMapping('/admin')
  String admin() => reports.all();

  /// The titles of the caller's rows, read from the project.
  @GetMapping('/todos')
  Future<List<String>> titles() async => [
    for (final todo in await todos.findAll()) todo.title,
  ];
}

@Service()
class AdminReports {
  @PreAuthorize("hasRole('ADMIN')")
  String all() => 'every report';
}
