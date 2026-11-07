## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- No changes of its own; released with the family version 0.7.1.

## 0.7.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.7.0.

## 0.6.3

### Changes

- The editor metadata of `spring.security.password-checks.*` is made from code and the package reads the same class: `PasswordChecksProperties` is bound by the Binder. The hand-written `spring_metadata_additional.json` is gone.

## 0.6.2

- No changes of its own; released with the family version 0.6.2.

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Changes

- The PBKDF2 derivation (HMAC-SHA-1, -256 and -512) is checked against Project Wycheproof's vectors (Apache-2.0, `test/fixtures/wycheproof/`): all match.
- Debug and trace lines in Spring Security's words: `Authenticating request with UsernamePasswordAuthenticationToken (1/1)` (trace), `Failed to find user 'ada'` and `Failed to authenticate since password does not match stored value` (debug; the user name goes through `LogFormatUtils`, the password is never logged), `Failed to authenticate since Bad credentials`, and a denied method call (`@PreAuthorize`, `@Secured`). The old debug text for a wrong password is now Spring's.

## 0.5.0

### Changes

- `PasswordCheckLimiter`: the password checks of `DaoAuthenticationProvider` run at most half the processors at once (`spring.security.password-checks.max-concurrent`) with eight times that waiting (`spring.security.password-checks.max-queued`); another one fails at once with `PasswordChecksBusyException`, without hashing. Each check had an isolate of its own without a bound, so a flood of logins with wrong passwords took every core of the machine and more memory with each request. The auto-configured manager uses the `passwordCheckLimiter` bean; providers made in code use `PasswordCheckLimiter.shared` unless given one. Not in Spring.

## 0.4.3

- `PreAuthenticatedAuthenticationToken` (Spring's, of `spring-security-web`): a login another system has checked, such as the server of a Flutter web app (`spring_boot_starter_flutter_security`).
- `GrantedAuthoritiesMapper` and `NullAuthoritiesMapper` (Spring's `org.springframework.security.core.authority.mapping`), for logins through other systems such as OAuth 2.0 (`spring_boot_starter_oauth2_client`).

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- Initial version: Spring Security's core for servers and Flutter apps. `SecurityContextHolder` kept per `Zone` (with one global context outside every scope), `Authentication` and its tokens, users (`UserDetails`, `User.withUsername`, `UserDetailsService`, `InMemoryUserDetailsManager`), `AuthenticationManager`, `ProviderManager` and `DaoAuthenticationProvider` (no user enumeration by message or timing, hashes upgraded at login, hashing on another isolate), authentication events. Password encoders on Bouncy Castle's Dart port (`pointycastle`): Argon2 (the default), PBKDF2, scrypt and the delegating encoder, in Spring Security's formats (hashes checked both ways against Spring Security 7.1). Method security: `@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@PreFilter` and `@PostFilter` on bean methods with SpEL (`hasRole`, `principal`, arguments, `returnObject`, `hasPermission`, beans), always on, every expression parsed at startup, run before `@Cacheable`; `RoleHierarchy`, `GrantedAuthorityDefaults`. Tests: `withMockUser`, `withAuthentication`, `withAnonymousUser`.
