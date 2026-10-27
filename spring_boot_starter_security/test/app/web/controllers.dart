import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@RestController()
class PublicController {
  @GetMapping('/public/hello')
  String hello() => 'hello';

  @GetMapping('/')
  String home() => 'home';
}

@RestController()
@RequestMapping('/api')
class ApiController {
  ApiController(this.reports);

  final Reports reports;

  @GetMapping('/me')
  Map<String, Object?> me(Authentication authentication) => {
    'name': authentication.name,
    'authorities': [for (final a in authentication.authorities) a.authority],
  };

  @GetMapping('/principal')
  String principal(Principal? principal) => principal?.name ?? 'none';

  @GetMapping('/user')
  String user(@AuthenticationPrincipal() UserDetails? user) =>
      user?.username ?? 'none';

  @GetMapping('/context')
  String context(@CurrentSecurityContext() SecurityContext context) =>
      context.authentication?.name ?? 'none';

  @GetMapping('/admin')
  String admin() => 'admin';

  @PostMapping('/data')
  String data(@RequestBody() String body) => 'got $body';

  @GetMapping('/users/{id}')
  String userById(@PathVariable() String id) => 'user $id';

  @GetMapping('/reports/{id}')
  String report(@PathVariable() String id) => reports.report(id);

  @GetMapping('/cors')
  @CrossOrigin(origins: ['https://app.example'])
  String cors() => 'cors';

  @GetMapping('/cached')
  String cached(ServerHttpResponse response) {
    response.headers.set('Cache-Control', 'max-age=60');
    return 'cached';
  }
}

@Service()
class Reports {
  @PreAuthorize("hasRole('ADMIN')")
  String report(String id) => 'report $id';
}

/// A form a page posts, with its CSRF token.
@RestController()
class FormController {
  @GetMapping('/form')
  String form(ServerHttpRequest request) {
    final token = csrfTokenOf(request)!;
    return '${token.parameterName}=${token.token}';
  }

  @PostMapping('/form')
  String submit(@RequestParam() String text) => 'submitted $text';
}
