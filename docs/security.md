# Security of the security packages

This page says what `spring_security_core` and
`spring_boot_starter_security` promise, against whom, and how that is
shown, so that anyone can check it.

**Found a security problem?** Open a regular
[issue](https://github.com/farum-azula/spring_core_dart/issues): the code is
open source, and everyone using it should know. Include the package and
version, what an attacker can do, and a request or a test that shows it.
Fixes go into the latest version of the family.

## What the security packages promise

`spring_security_core` holds users, password hashes, the security context
and method security. `spring_boot_starter_security` adds the filter chain
in front of the web starter's controllers. This section is the threat
model both are built and tested against;
[roadmap/security_verification.md](../roadmap/security_verification.md)
describes how the tests show it.

### What is protected

- **Endpoints** of `spring_boot_starter_web`: controllers, functional
  handlers, static resources, WebSocket handshakes and server-sent event
  streams. Every request passes the same filter chain.
- **Method calls** on beans with `@PreAuthorize`, `@PostAuthorize` and
  `@Secured`, through the bean's proxy, whoever the caller is: a
  controller, another bean, a scheduled task.
- **Credentials**: passwords, kept only as hashes; session ids; CSRF
  tokens; bearer tokens (JWT).

### Against whom

| Attacker | Can | Must not be able to |
|---|---|---|
| Anonymous client | send any bytes over HTTP | reach a protected endpoint or method; learn whether a user exists; make the server spend unbounded work on one request |
| Another user | log in with their own account | act with more authorities than theirs; read or reuse someone else's session |
| Holder of a stolen or forged token | replay a token, alter it, sign it with another key or algorithm | use an expired, not-yet-valid, wrongly signed, `alg: none` or wrong-audience token |
| A malicious web page in the user's browser | make the browser send requests with its cookies | change state with the user's session (CSRF); read responses across origins unless CORS allows it; frame the application |
| A crafted URL | percent-encoding, `..`, `;`, `//`, backslashes, Unicode | be matched by a security rule differently than by the router |

### Out of scope

- The host, the operating system and the Dart VM.
- TLS. Terminate it in front of the application (a reverse proxy) or with
  the web starter's `server.ssl.*`; the packages see whether a request was
  secure.
- The application's own business logic, and the data it chooses to
  return to an authorized user.
- Rate limiting and lockout after failed logins. Put them in front (the
  proxy) or in a listener of the authentication failure events; the
  packages do not count attempts.
- A Flutter app's local checks. `@PreAuthorize` in an app protects the UI
  flow, not the data: an app can be taken apart, so the server must check
  again.

### Rules the code follows

1. **Secure by default**, as in Spring Boot. With the starter listed,
   every request needs authentication, a request that no rule matches is
   denied, security headers are on, and CSRF protection is on for
   state-changing requests.
2. **Fail closed.** An error inside a security filter, a matcher, a
   decoder or an expression ends the request with 400, 401 or 403; the
   request never passes on.
3. **One path model.** The security rules and the router use the same
   `PathPattern` on the same path. Requests whose path could be read two
   ways (encoded `/`, `\`, `.` and `%`, `..` and `.` segments, `;`, `//`,
   control characters) are refused with 400 before any rule is looked at,
   as Spring Security's `StrictHttpFirewall` does.
4. **No secrets in answers or logs.** A failed login says only "bad
   credentials", for an unknown user as for a wrong password, and takes
   about the same time. Passwords, tokens and session ids are never
   logged.
5. **Vetted cryptography only.** Signatures, MACs and key derivation come
   from Bouncy Castle's Dart port (`pointycastle`); nothing is written by
   hand. Secrets are compared in constant time, and random values come
   from `Random.secure()`. `pointycastle` is a third-party package, used by
   one file per package, and is to be replaced by a Dart team package when
   one covers these algorithms
   ([docs/dependencies.md](dependencies.md#pointycastle-third-party-to-be-removed));
   CI checks it for known vulnerabilities.
6. **Bounded work.** Each input has a size limit:
   - a bearer token: 64 KiB;
   - an `Authorization: Basic` header: 8 192 characters;
   - a login form: the login filter reads at most 64 KB of the body. When
     the CSRF token is sent as a form field, the CSRF filter has already
     read the form, with the web starter's 1 MiB limit, and the login
     filter uses those fields;
   - the number of sessions: `server.servlet.session.max-sessions`
     (10 000 by default).

   Password hashing runs only for requests that carry credentials.

## How it is shown

Evidence that can be checked without reading the code
([roadmap/security_verification.md](../roadmap/security_verification.md)):

| Evidence | Where | Result |
|---|---|---|
| The attack catalog as tests: ambiguous paths, malformed credentials, CSRF, CORS, cookies, headers, JWT attacks (`alg: none`, algorithm confusion, embedded keys, `kid` tricks, expiry), method security | `spring_boot_starter_security/test/`, `spring_security_core/test/` | 341 tests in the core and 544 in the starter, plus 12 integration tests on a real server, all passing (counted with `dart test`, October 2026) |
| The same requests sent to Spring Security 7.1 (Spring Boot 4.1) and to the starter: statuses, challenges, redirects, headers, cookies | `tool/security_reference`, `test/differential_test.dart`, CI job "Security compared with Spring Security" | equal, except the differences listed in the starter's README |
| Password hashes written by Spring and checked here, and the other way | `tool/security_reference`, `spring_security_core/test/vectors/` | all match |
| RFC 7515 test vectors (JWS) | `test/vectors/rfc7515.json` | all verify |
| Generated inputs (seeded): random paths through the firewall, random rule sets, random `Authorization` headers, mutated tokens | `test/fuzz_test.dart` | no input lets an ambiguous path through, allows what the rules deny, or throws anything unexpected |
| Mutation testing: small changes to the code must make a test fail | `tool/mutation_test.dart` | 98.1 % (core) and 98.6 % (starter) of the changes are noticed; the rest change nothing observable, each explained in [docs/security-mutation.md](security-mutation.md) |
| Line coverage | `dart test --coverage` | 99.9 % of the core's lines (one unreachable defensive line), 100 % of the starter's |
| OWASP ASVS 4.0.3 level 2 (V2, V3, V4, V13, V14) | [docs/security-asvs.md](security-asvs.md) | each requirement with its status and test |

Not done yet: an OWASP ZAP scan in CI, and an external review.
