// A secured REST API in a Spring Boot application: a SecurityFilterChain
// bean decides who may call what, users come from a UserDetailsService
// bean, and @PreAuthorize guards a service method. The generator writes the
// controllers' handlers and the proxies (example.spring.dart, from
// `dart run build_runner build`).
//
//   dart run example/example.dart
//   curl -i localhost:8080/api/books                       # 200, public
//   curl -i localhost:8080/api/me                          # 401 + WWW-Authenticate
//   curl -i -u ada:ada-secret localhost:8080/api/me        # 200 "ada"
//   curl -i -u ada:ada-secret -X DELETE localhost:8080/api/books/1    # 403
//   curl -i -u root:root-secret -X DELETE localhost:8080/api/books/1  # 204
//   open http://localhost:8080/account                     # the login page
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'example.spring.dart';

@Service()
class BookService {
  final _books = {'1': 'Dune', '2': 'Emma'};

  List<String> all() => [..._books.values];

  /// Method security: checked wherever the call comes from.
  @PreAuthorize("hasRole('ADMIN')")
  Future<void> remove(String id) async => _books.remove(id);
}

@RestController()
@RequestMapping('/api')
class BookController {
  BookController(this.books);
  final BookService books;

  @GetMapping('/books')
  List<String> all() => books.all();

  @DeleteMapping('/books/{id}')
  @ResponseStatus(HttpStatus.noContent)
  Future<void> remove(@PathVariable() String id) => books.remove(id);

  /// The logged-in user.
  @GetMapping('/me')
  String me(Authentication authentication) => authentication.name;
}

@RestController()
class AccountController {
  /// A browser without a session is sent to the login page first.
  @GetMapping('/account')
  String account(@AuthenticationPrincipal() UserDetails user) =>
      'Hello, ${user.username}';
}

@Configuration()
class SecurityConfig {
  /// The REST API: HTTP Basic on every request, no session, so no CSRF
  /// token either (nothing a browser sends by itself authenticates).
  @Bean()
  @Order(1)
  SecurityFilterChain api(HttpSecurity http) => http
      .securityMatcher('/api/**')
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchersFor(HttpMethod.get, ['/api/books'])
            .permitAll()
            .anyRequest()
            .authenticated(),
      )
      .httpBasic()
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .build();

  /// Everything else: pages for browsers, form login with a session and
  /// CSRF protection. The first matching rule decides; a request no rule
  /// matches is denied.
  @Bean()
  @Order(2)
  SecurityFilterChain pages(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
      .formLogin()
      .build();

  /// Passwords are stored hashed (`{argon2}...`), never as they are.
  @Bean()
  UserDetailsService users() {
    final encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
    return InMemoryUserDetailsManager([
      User.withUsername('ada')
          .password(encoder.encode('ada-secret'))
          .roles(['USER'])
          .build(),
      User.withUsername('root')
          .password(encoder.encode('root-secret'))
          .roles(['ADMIN'])
          .build(),
    ]);
  }
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
