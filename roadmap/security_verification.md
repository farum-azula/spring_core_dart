# Verifying the security packages (plan)

[spring_security_core](spring_security_core.md) and
[spring_boot_starter_security](spring_boot_starter_security.md) must be
**shown** to be safe: nobody should have to trust that the code looks
right. The owner has no time to review security code line by line, so the
work produces evidence that can be checked without reading it: a threat
model, a catalog of attacks that each have a test, reports, and
comparisons with Spring Security itself.

## Status

| Part | Status |
|---|---|
| 1. Threat model and rules | done: [docs/security.md](../docs/security.md) |
| 2. Attack catalog as tests | done, except denial of service beyond the size limits (rate limits are documented as the application's or the proxy's); `oauth2Login()` too (October 2026: `test/oauth2_login_test.dart`, against a fake OpenID Connect provider) |
| 3. Differential tests against Spring Security | done: `tool/security_reference` (Spring Boot 4.1, Spring Security 7.1), `spring_boot_starter_security/test/differential_test.dart`, CI job "Security compared with Spring Security"; password hashes both ways; `oauth2Login()` and the DPoP resource server (October 2026: profiles `oauth2` and `dpop` of the reference, a fake OpenID Connect provider both use, `test/differential_provider.dart`) |
| 4. Generated inputs | done: `spring_boot_starter_security/test/fuzz_test.dart` (seeded) |
| 5. Mutation testing and coverage | done: `tool/mutation_test.dart`; the scores are in [docs/security.md](../docs/security.md#how-it-is-shown). Coverage is measured, not yet reported by CI. The SSO and DPoP code (October 2026): `dpop.dart`, `lib/src/oauth2/`, the client's ID token validator, DPoP proof builder and authorization response ([docs/security-mutation.md](../docs/security-mutation.md)); **later:** the `oauth2Login()` parts of `http_security.dart`, the app login's checks (`flutter test`) |
| 6. Scanners and reviews | ASVS checklist done ([docs/security-asvs.md](../docs/security-asvs.md)); the ZAP baseline scan done (October 2026): CI job "OWASP ZAP baseline" on the server guide, logged in with the form login (dev) and through Keycloak's login (`sso`), rules in `.zap/`; an external review is open |

## 1. Threat model and rules (before any code)

- `docs/security.md`: what the packages protect (endpoints, sessions, tokens,
  method calls), against whom (anonymous clients, other users, a stolen
  token, a malicious browser page), and what is out of scope (the host, the
  TLS terminator, the app's own business logic).
- **Secure by default**, like Spring Boot: with the starter on the
  classpath every endpoint needs authentication; deny when no rule
  matches; errors never leak details; security headers on; CSRF on for
  session logins.
- **Fail closed:** an exception inside a security filter is a 401/403,
  never a pass-through.
- **One path model:** the security matchers and the router use the same
  `PathPattern` on the same normalized path, so a request cannot be
  matched differently by the two (the root cause of several Spring
  Security CVEs).

## 2. Attack catalog as tests

Each class of attack is a test file; each known Spring Security CVE class
gets a regression test, so its mistake cannot be made here.

| Area | Tests |
|---|---|
| Path matching | encoded slashes (`%2F`, `%252F`), `..` and `%2e%2e`, `;` path parameters, double slashes, trailing slash, case, Unicode normalization, `**` patterns (CVE-2023-34034), regex `.` (CVE-2022-22978), mismatches between router and matcher (CVE-2023-20860) |
| Authentication | missing, malformed and repeated `Authorization` headers, Basic with `:` in the password, wrong charset, user enumeration through timing or messages |
| Passwords | BCrypt / Argon2 known-answer vectors, upgrade of old hashes, constant-time comparison |
| JWT | the RFC 7515 / 7519 / 8037 vectors; `alg: none`; HS/RS algorithm confusion; `kid` injection; `exp` / `nbf` / `iat` with clock skew; `aud` / `iss`; oversized tokens; JWK set rotation |
| Sessions | fixation (new id after login), logout invalidation, cookie flags (`HttpOnly`, `Secure`, `SameSite`), concurrent sessions |
| OAuth 2.0 / OpenID Connect login | missing, wrong, duplicated and replayed `state`; the callback in another browser (login CSRF); the saved request used once; replayed codes; mixed-up registrations; provider errors; RFC 9207 `iss`; `nonce`; ID tokens of another issuer or audience, expired, `alg: none`, HS/RS confusion, another key, unknown `kid`; user info of another subject; no open redirect after login; fixation; CSRF on logout; the login page escaped |
| CSRF | missing / wrong / reused tokens, safe methods, the cookie-to-header pattern |
| CORS | `*` with credentials refused, reflected origins, pre-flights reaching handlers |
| Headers | HSTS only over HTTPS, frame options, content type options, cache control on authenticated responses |
| Method security | `@PreAuthorize` on proxies (calls inside the bean bypass it, documented and tested), SpEL injection through arguments |
| WebSocket / SSE | the handshake authenticated by the filter chain, the user kept for the connection, origin checks |
| Denial of service | huge headers and bodies, slow requests, many sessions, expensive hashes per request (rate limits documented) |

## 3. Differential tests against Spring Security

A reference Spring Boot application (Java, in `tool/security_reference/`,
run in CI with a JDK) with the same rules as a Dart test application.
The same list of requests (the attack catalog plus generated ones) goes
to both; status codes, `WWW-Authenticate`, `Set-Cookie` flags and
security headers must match, or the difference is documented on purpose.
This catches behaviour nobody thought of writing a test for.

## 4. Generated inputs

- **Fuzzing** of the path normalizer, the matchers, the header parsers,
  the JWT and Basic decoders: random and mutated inputs, invariants
  checked (never throws unhandled, never allows what a stricter matcher
  denies, decoding then encoding round-trips).
- **Property tests** of the access rules: for random rule sets and
  requests, "denied by the rules" implies "denied by the chain".

## 5. Measuring the tests themselves

- **Mutation testing** of the security packages (flip conditions, drop
  checks): a mutant that survives shows a missing test.
- **Coverage** of the security packages close to 100 %, branches
  included; reported in CI.

## 6. Scanners and reviews

- **OWASP ZAP baseline scan** in CI against the example application
  secured by the starter; findings fail the build. Done (October 2026):
  the job `zap` of `.github/workflows/ci.yml` starts the server guide
  (dev, logged in as `ada` with the form login; and `dev,sso`, logged
  in as `ada` through the login form of the Keycloak of
  example/keycloak), seeds every endpoint (`.zap/seed_hook.py`: a JSON
  API has no links to spider) and runs `zap-baseline.py` with a pinned
  image, without `-I`: a warning fails like a failure. Accepted rules
  are in `.zap/rules.tsv`, each with its reason; the `XSRF-TOKEN`
  cookie without `HttpOnly` (scripts must read it) is accepted for that
  cookie only, in the hook. The first scan found three issues of the
  example, fixed before the job went in: the CSP without `form-action`
  and `base-uri`, the `XSRF-TOKEN` and `neon-recent` cookies without
  `SameSite` (and `neon-recent` without `HttpOnly`), the handler names
  in `Server-Timing`.
- **Checklist:** OWASP ASVS level 2 chapters V2 (authentication), V3
  (sessions), V4 (access control), V13 (API), V14 (configuration), each
  item marked with the test that covers it.
- **Reviews:** a dedicated security review pass on every change of these
  packages (adversarial: try to break the change), and an external audit
  before 1.0.

## 7. A hard security run on a Docker network (before the 0.5.0 release)

The owner's request (October 2026), after the ten review rounds: one run
only about security, with the attacking tools security testers use, on
our own applications in an isolated Docker network (no route to the
internet; nothing aimed outside it).

- **The stand:** about five backends on our stack, each using several of
  our servers and features differently — form login with sessions; a
  resource server with JWT and DPoP; `oauth2Login()` with the Keycloak of
  example/keycloak; WebSocket and SSE; multipart and files; one backend
  in several instances behind a proxy — and frontends that talk to
  several backends at once: Flutter web in `server` and `spa` mode, the
  native apps' flows driven by scripts.
- **Nothing goes where it shouldn't:** all outgoing traffic of every
  container through one observing proxy that records every request; the
  run fails on any request to an origin that shouldn't get it, a cookie
  or token sent to the wrong host, credentials to a third-party API,
  more calls to a provider's metadata than expected.
- **The attacks:** an active ZAP scan (CI runs the passive baseline
  only); injections (SQL where a backend has a database, SpEL, header,
  path, log and template injection, JSON and YAML payloads); fuzzing of
  paths, parameters, headers and bodies; brute force on the logins and
  token endpoints (lockout, rate limits, timing); floods of sessions,
  WebSocket connections and messages, multipart parts, large and slow
  bodies; JWT and OAuth attacks (`alg`, `typ`, `kid`, keys in the token,
  replayed and foreign DPoP proofs, `state` / `nonce` / PKCE, redirect
  and mix-up); CORS and CSRF from a hostile origin; TLS and headers.
- **Sessions especially:** the owner doubts the in-memory sessions; prove
  what the new rule promises (no session before a login; at the limit
  expired ones go, then new ones are refused; a flood can't log anyone
  out) under load, not only in unit tests.
- **Output:** each finding confirmed with a probe, fixed with a
  regression test, listed in `roadmap/fix_plan.md`; the stand kept as
  scripts (a compose file and the attack runs) so it can be run again
  before each release.

## How the owner can judge it

Without reading the code: `docs/security.md` (what is promised), the ASVS
checklist with links to tests, the differential report (where Dart and
Spring differ), the mutation and coverage scores, the ZAP report. A red
mark in any of them blocks a release of the security packages.
