# spring_boot_starter_security (planned)

Spring Security for incoming requests, on the
[web starter](spring_boot_starter_web.md): a filter chain in front of the
controllers. The security context and `@PreAuthorize` come from
[spring_security_core](spring_security_core.md).

## Filter chain

A `SecurityFilterChain` bean with Spring's builder, so a Spring
configuration reads the same:

```dart
@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain api(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth
          .requestMatchers('/api/admin/**').hasRole('ADMIN')
          .requestMatchers(HttpMethod.get, '/api/books/**').permitAll()
          .anyRequest().authenticated())
      .oauth2ResourceServer((server) => server.jwt())
      .cors(Customizer.withDefaults())
      .build();
}
```

Without such a bean, like Spring Boot: everything needs a login, with one
user from `spring.security.user.name` / `password` (or a generated
password printed at startup).

## Authentication

- HTTP Basic, form login with sessions, API keys.
- `UserDetailsService` + `PasswordEncoder` for own users.
- JWT resource server: tokens checked against the issuer's keys
  (`spring.security.oauth2.resourceserver.jwt.issuer-uri` /
  `jwk-set-uri`), claims mapped to authorities. HS256 works on
  `package:crypto` (Dart team); RS256 / ES256 need RSA and ECDSA
  verification — in pure Dart, or a vetted package as an allowed exception
  (open question).

## Around it

- CORS, CSRF for session logins, security headers (HSTS, frame options,
  content type options).
- 401 / 403 as `ProblemDetail`, with `WWW-Authenticate`.
- Method security from the core on the controllers' and services' beans.
- Tests: a user per test, like `@WithMockUser`
  (`mockMvc.get('/api/admin', user: TestUser(roles: ['ADMIN']))`), and JWTs
  signed with a test key.
