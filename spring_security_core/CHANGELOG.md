## Unreleased

- `GrantedAuthoritiesMapper` and `NullAuthoritiesMapper` (Spring's `org.springframework.security.core.authority.mapping`), for logins through other systems such as OAuth 2.0 (`spring_boot_starter_oauth2_client`).

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- Initial version: Spring Security's core for servers and Flutter apps. `SecurityContextHolder` kept per `Zone` (with one global context outside every scope), `Authentication` and its tokens, users (`UserDetails`, `User.withUsername`, `UserDetailsService`, `InMemoryUserDetailsManager`), `AuthenticationManager`, `ProviderManager` and `DaoAuthenticationProvider` (no user enumeration by message or timing, hashes upgraded at login, hashing on another isolate), authentication events. Password encoders on Bouncy Castle's Dart port (`pointycastle`): Argon2 (the default), PBKDF2, scrypt and the delegating encoder, in Spring Security's formats (hashes checked both ways against Spring Security 7.1). Method security: `@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@PreFilter` and `@PostFilter` on bean methods with SpEL (`hasRole`, `principal`, arguments, `returnObject`, `hasPermission`, beans), always on, every expression parsed at startup, run before `@Cacheable`; `RoleHierarchy`, `GrantedAuthorityDefaults`. Tests: `withMockUser`, `withAuthentication`, `withAnonymousUser`.
