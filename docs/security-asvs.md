# OWASP ASVS 4.0.3, level 2: the security packages

The checklist of [roadmap/security_verification.md](../roadmap/security_verification.md),
section 6: the level 2 requirements of chapters V2 (authentication), V3
(sessions), V4 (access control), V13 (API) and V14 (configuration) that a
framework can meet, each with its status and the test that shows it.

Status: **done** (by default, with a test), **option** (available, the
application turns it on), **app** (the application's part: the framework
cannot decide it), **open** (not yet).

Tests: `core` = `spring_security_core/test/`, `starter` =
`spring_boot_starter_security/test/`, `web` = `spring_boot_starter_web/test/`.

## V2 Authentication

| Requirement | Status | Shown by |
|---|---|---|
| 2.1.1 passwords of 12+ characters | app | a password policy is the registration's |
| 2.1.2 passwords of 64+ characters allowed | done | Argon2/PBKDF2/scrypt have no length limit (BCrypt's 72 bytes do not apply); `core/password_encoder_test.dart` ("long passwords are hashed whole") |
| 2.1.3 no truncation | done | the whole UTF-8 password is hashed; `core/password_encoder_test.dart` ("long passwords are hashed whole": a changed last character and a prefix fail) |
| 2.1.4 any printable Unicode | done | `core/password_encoder_test.dart` ("hashes written by Spring Security": `pässwörd ✓`, both ways), `starter/web_attacks_test.dart` (`a:b:ü✓` over Basic) |
| 2.2.1 anti-automation | app | failures are published as `AbstractAuthenticationFailureEvent`s to count; lockout and rate limits are the application's or its proxy's ([security.md](security.md)) |
| 2.4.1 salted, approved key derivation | done | Argon2id by default, PBKDF2, scrypt (Bouncy Castle); `core/password_encoder_test.dart` |
| 2.4.2 salts of 32+ bits, unique | done | 16 random bytes (`Random.secure`) per hash; `core/password_encoder_test.dart` ("a new salt every time") |
| 2.4.3 PBKDF2 with 100 000+ iterations | done | 310 000 (`Pbkdf2PasswordEncoder.defaultsForSpringSecurity`) |
| 2.4.5 a secret salt (pepper) | option | `Pbkdf2PasswordEncoder(secret: ...)` |
| 2.5.4 no default accounts | done | the default `user` exists only without any configuration of users, with a random password logged at startup (development only, as Spring Boot) |
| 2.10.4 secrets not in source | app | `spring.security.user.password` and keys come from the environment |

## V3 Session management

| Requirement | Status | Shown by |
|---|---|---|
| 3.1.1 no session tokens in URLs | done | sessions only through the cookie; `web/http_session_test.dart` |
| 3.2.1 a new token on authentication | done | `starter/defaults_test.dart` ("the whole form login flow": the id changes, the old one is worthless), `starter/differential_test.dart` |
| 3.2.2 64+ bits of entropy | done | 256 random bits; `web/http_session_test.dart` |
| 3.2.3 tokens only in secure cookies | done | `starter/web_attacks_test.dart` (cookie flags) |
| 3.2.4 approved random generator | done | `Random.secure` for session ids, CSRF tokens and salts |
| 3.3.1 logout invalidates the session | done | `starter/defaults_test.dart` (the old session after logout is anonymous) |
| 3.3.2 re-authentication after idle | done | `server.servlet.session.timeout` (30 min); `web/http_session_test.dart` (expiry) |
| 3.3.3 / 3.3.4 end other sessions | open | no session registry yet |
| 3.4.1 `Secure` | done | when the request was secure, or `server.servlet.session.cookie.secure=true`; `starter/web_attacks_test.dart` |
| 3.4.2 `HttpOnly` | done | `starter/web_attacks_test.dart`; the CSRF cookie too unless `withHttpOnlyFalse()`: `starter/csrf_test.dart` |
| 3.4.3 `SameSite` | done | `Lax` by default (Spring Boot sends none); `starter/web_attacks_test.dart` |
| 3.4.4 `__Host-` prefix | option | `server.servlet.session.cookie.name=__Host-SESSION` with `secure=true` |
| 3.5.3 signed stateless tokens, no null cipher, key checks | done | `starter/jwt_test.dart`: RFC 7515 vectors, `alg: none`, algorithm confusion, embedded keys, tampering, expiry; `starter/jose_test.dart`: key sizes, curve points, key use and `alg` restrictions, strict base64url |

## V4 Access control

| Requirement | Status | Shown by |
|---|---|---|
| 4.1.1 enforced on the server | done | the filter chain and method security run on the server, WebSocket handshakes included (`starter/websocket_test.dart`); in a Flutter app `@PreAuthorize` is documented as UI-only |
| 4.1.2 attributes not changeable by users | done | authorities come from the user store or a verified token; request attributes cannot be set by clients |
| 4.1.3 least privilege, deny by default | done | a request no rule matches is denied; `starter/fuzz_test.dart` ("denied by the rules" implies "denied by the filter"), `starter/rules_test.dart` |
| 4.1.5 fail securely, also on exceptions | done | errors in filters, expressions and providers deny: `core/method_security_test.dart` (broken expression), `core/core_test.dart` (unproxied bean, failing user store, unknown hash), `starter/rules_test.dart` |
| 4.2.1 IDOR | app | the means: `access(...)` with path variables, `@PreAuthorize` with arguments and `hasPermission`; `starter/rules_test.dart` ("path variables in a rule") |
| 4.2.2 anti-CSRF | done | `starter/web_attacks_test.dart` (CSRF group), `starter/csrf_test.dart`, `starter/differential_test.dart` |
| 4.3.1 MFA for administrators | open | no multi-factor authentication yet |

## V13 API and web services

| Requirement | Status | Shown by |
|---|---|---|
| 13.1.1 one parser for URIs | done | the rules and the router use the same `PathPattern` on the same path; ambiguous paths are refused, also when a server hands them over unnormalized; `starter/web_attacks_test.dart`, `starter/firewall_test.dart`, `starter/server_test.dart`, `starter/differential_test.dart` |
| 13.1.3 no secrets in URLs | done | bearer tokens in query strings are off by default (`DefaultBearerTokenResolver`); `starter/bearer_test.dart` ("is ignored by default") |
| 13.1.4 decisions at the URI and the resource level | done | request rules and method security together; `starter/rules_test.dart` ("method security on a service") |
| 13.2.1 methods allowed per user and action | done | `requestMatchersFor(method, ...)`; the firewall refuses TRACE and unknown methods |
| 13.2.3 CSRF for cookie-based REST | done | as 4.2.2 |
| 13.2.6 headers and payload trustworthy | done | bearer tokens are verified; TLS is the deployment's (`server.ssl.*` or a proxy) |

## V14 Configuration

| Requirement | Status | Shown by |
|---|---|---|
| 14.2.1 / 14.2.4 maintained, trusted components | done | `tool/check_dependencies.dart`: only the Dart and Flutter teams, plus `pointycastle` (Bouncy Castle) as a reviewed exception |
| 14.3.3 no version information | done | no `Server` or `X-Powered-By` header; `starter/server_test.dart` ("security headers once each on the wire") |
| 14.4.1 `Content-Type` with a charset | done | the web starter's writers |
| 14.4.3 Content Security Policy | option | `headers((h) => h.contentSecurityPolicy(...))` (Spring does not set one either) |
| 14.4.4 `X-Content-Type-Options: nosniff` | done | `starter/web_attacks_test.dart` (headers), `starter/server_test.dart` |
| 14.4.5 HSTS | done | over HTTPS (`max-age=31536000 ; includeSubDomains`); `starter/web_attacks_test.dart` |
| 14.4.6 `Referrer-Policy` | option | `headers((h) => h.referrerPolicy('no-referrer'))` |
| 14.4.7 no framing by default | done | `X-Frame-Options: DENY`; `starter/web_attacks_test.dart`, `starter/server_test.dart` |
| 14.5.1 only the methods in use | done | the firewall (TRACE refused), 405 from the router |
| 14.5.2 `Origin` not used for access decisions | done | `Origin` only drives CORS headers |
| 14.5.3 CORS with a strict allow list | done | `starter/web_attacks_test.dart` (CORS group): unknown origins get no CORS headers |
