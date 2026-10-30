# Security of the security packages

This page says what `spring_security_core` and
`spring_boot_starter_security` promise, against whom, and how that is
shown, so that anyone can check it. Which of Spring Security's features
the packages have, and which not yet:
[security-spring-comparison.md](security-spring-comparison.md).

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
  tokens; bearer tokens (JWT); the authorization codes, PKCE verifiers
  and tokens (access, refresh, ID) of single sign-on (`oauth2Login()`),
  kept on the server, never sent to the browser.
- **DPoP-bound access tokens** (RFC 9449): accepted only with a fresh
  proof signed by the key the token is bound to (`cnf.jkt`), for this
  request (method and URL) and this token, once. The URL is the one the
  request reached the server with, its host from the `Host` header,
  which the client chooses: a token and proof made for another server
  pass the `htu` check when the request names that server. What keeps
  the tokens of other servers out is their audience
  (`spring.security.oauth2.resourceserver.jwt.audiences`); set it when
  the identity provider issues tokens for several APIs.
- **The client's DPoP key** (`spring_boot_starter_oauth2_client`): the
  private key that signs the proofs of a client's token requests and API
  calls stays in the `DPoPKey`; the proofs, the tokens and the key are
  never logged or shown by `toString`. In apps
  (`spring_boot_starter_flutter_security`) the key is made and used in
  the Secure Enclave (iOS, macOS with one) or the Android Keystore and
  never reaches the app's memory; without a Secure Enclave (the iOS
  simulator, older Macs, a macOS build without the data protection
  keychain) it is a software key of the Keychain, which the app's code
  never handles but the system's Security framework loads into the
  app's process to sign; on Windows and Linux it is kept in the
  `SecretStore` (DPAPI, the Secret Service: readable by any program of
  the same user). The stored DPoP tokens are used only with the key
  they are bound to. In a browser that logs in by itself (spa mode) the
  key is a WebCrypto key made with `extractable: false`: the page signs
  with it and no script can export it, though the browser writes it to
  its profile on disk.
- **A browser's own login** (spa mode of
  `spring_boot_starter_flutter_security`): the tokens stay in the tab's
  memory, never in `localStorage`, `sessionStorage` or IndexedDB; the
  authorization request (with the PKCE verifier) waits in the tab's
  `sessionStorage` only while the page is at the provider; only the
  answer to this tab's own request logs anyone in.
- **Logins through an identity provider** (`oauth2Login()`): only the
  user the provider authenticated, for this client and this login, is
  logged in, in the browser that started the login.

### Against whom

| Attacker | Can | Must not be able to |
|---|---|---|
| Anonymous client | send any bytes over HTTP, open sessions (a login page, a saved request) | reach a protected endpoint or method; learn whether a user exists; make the server spend unbounded work on one request, or call the identity provider once per request; push a logged-in user out of their last session by filling the session limit |
| Another user | log in with their own account, as often as they like | act with more authorities than theirs; read or reuse someone else's session; keep other users from logging in by filling the session limit with their own logins |
| Holder of a stolen or forged token | replay a token, alter it, sign it with another key or algorithm, present another JWT the issuer signed (a logout token, a security event token) or a DPoP proof, present a token bound to a client certificate | use an expired, not-yet-valid, wrongly signed, `alg: none` or wrong-audience token; use a JWT of another type (`typ`) as an access token; use a certificate-bound token without the certificate (it is refused: the server cannot check the binding) |
| A malicious web page in the user's browser | make the browser send requests with its cookies, to any URL (with any query string) and with any form | change state with the user's session (CSRF); log the user out, or into the attacker's account; a request with a `Bearer` or `DPoP` header needs no CSRF token, but a page can add such a header to a request of another origin only where that server's CORS configuration lets its origin send it with credentials, which lets the page read the CSRF token anyway; a token in the query string never exempts a request; read responses across origins unless CORS allows it; frame the application |
| A crafted URL | percent-encoding, `..`, `;`, `//`, backslashes, Unicode | be matched by a security rule differently than by the router (`dart:io` reads a raw `\` in the request target as `/`, resolving `..\`, and raw bytes past ASCII as Latin-1, before either sees the path, where Tomcat answers 400: a proxy in front whose rules look at paths must refuse `\` itself) |
| Holder of a stolen DPoP-bound token, or of a caught proof | send the token as `Bearer`, with a proof of their own key, or replay, alter or re-target a proof (another method, URL, token or time) | use the token without the client's private key; use a proof twice, for another request, another token, or outside its time window; get a proof accepted that is unsigned (`alg: none`), signed with a shared secret (HS*), or that carries a private key |
| Someone who catches a DPoP proof or token a client sent, or answers in the server's place | reuse the proof, read the logs, ask for a nonce again and again, issue a `DPoP` token the client did not ask for | get the client's private key from a proof, a log or a `toString`; make the client loop on `use_dpop_nonce`; get the client to sign a proof for another request (method, URL) or token than the one it sends; get a `DPoP` token accepted that was issued without the client's proof |
| An attacker in a browser's own login (spa mode) | forge, replay or reload the provider's answer to the page; send it from another tab or much later; tamper with the tab's `sessionStorage`; make the token endpoint unreachable | log the page in with an answer it did not ask for, a wrong `state` or `iss`, an ID token with a wrong `nonce`, or without the PKCE verifier; leave the `code` in the address bar; find a token in the browser's storage; use a stolen DPoP-bound token without the page's key |
| An attacker in an app's native login (Sign in with Apple's sheet, App Links) | hand the app a forged or replayed identity token, open a link of the app's domain while a login runs, answer from the app's server in another user's name | log the app in with a token Apple did not sign for this app and this sign-in, or for another user than the sheet's; complete, cancel or end a login with a link that is not its redirect (another path, or the exact path without the login's `state`), on Android or through the desktop's loopback server |
| An attacker in an OAuth 2.0 login (`oauth2Login()`) | forge, replay or redirect the provider's callback (with any method, any body size); steal a code; send another provider's or another login's ID token; add parameters to the callback | log the victim into the attacker's account (login CSRF); use a callback or a code twice; end a login in progress with a callback of the wrong kind; mix up registrations or providers; get an ID token accepted that the provider did not sign for this client and this login, or that is expired; send the browser to another site after the login (open redirect); keep a session id from before the login |

### Out of scope

- The host, the operating system and the Dart VM. Among the VM's
  behaviours: `dart:io`'s HTTP server accepts a request with both
  `Content-Length` and `Transfer-Encoding: chunked` and reads the body
  as chunked, where RFC 9112 asks to refuse it (Tomcat answers 400).
  Behind a proxy that reads such a request by its `Content-Length`,
  requests can be smuggled past the proxy's rules; use a proxy that
  refuses or normalizes them (most do). It also parses the request
  target before the server sees it, with no raw form left: a raw `\`
  becomes `/` (`/files/..\..\secret` arrives as `/secret`) and raw
  bytes past ASCII are read as Latin-1, where Tomcat answers 400. The
  router and the security rules see the same path; a proxy whose rules
  look at paths must refuse `\` itself.
- TLS. Terminate it in front of the application (a reverse proxy) or with
  the web starter's `server.ssl.*`; the packages see whether a request was
  secure.
- The application's own business logic, and the data it chooses to
  return to an authorized user.
- Rate limiting and lockout after failed logins. Put them in front (the
  proxy) or in a listener of the authentication failure events (one
  event per request); the packages do not count attempts. Without a
  limit in front, a flood of new sessions can still push out sessions
  that hold no login yet (a login page just opened), and, when only
  logins are left, one session of the user who holds the most (never a
  user's last one). As many accounts as the session limit, each logged
  in once, still fill it: new sessions are then refused (503) until
  logins end or expire; limit sign-ups and logins in front.
- The `iss` parameter (RFC 9207) of a registration without
  `issuer-uri` (its endpoints configured one by one): there is no
  issuer to compare it with. The redirect URI of each registration still
  keeps the providers apart.
- The identity provider itself, and the TLS of the calls to it (its
  discovery, token, user-info and key endpoints): the server trusts what
  they answer over HTTPS, after the checks of the ID token.
- A Flutter app's local checks. `@PreAuthorize` in an app protects the UI
  flow, not the data: an app can be taken apart, so the server must check
  again.

### Rules the code follows

1. **Secure by default**, as in Spring Boot. With the starter listed,
   every request needs authentication, a request that no rule matches is
   denied, security headers are on, and CSRF protection is on for
   state-changing requests. Requests that carry a token in the header
   (`Authorization: Bearer`, or `DPoP` with a proof) need no CSRF token,
   as in Spring (which exempts `Bearer` only): a browser never adds these
   headers by itself, and a page of another origin can add them only
   where the CORS configuration lets that origin send them with
   credentials (which lets it read the CSRF token anyway). Such a
   request goes on to the token filters, which log it in with the token
   or refuse it (401), whatever cookies come with it. Two limits keep
   that true. Only the header counts, never a token in the
   `access_token` query string (which, as in Spring, is read in `GET`
   requests only), since any page can post a form to such a URL. And the
   chain's logout and form login URLs keep their CSRF check even with a
   token header (Spring exempts them), since their filters act on the
   session before any token is looked at; a filter of the application's
   own placed before the token filters sees such a request before its
   token is checked, too.
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
   - a DPoP proof: 8 KiB; the ids of used proofs: 100 000 in memory,
     1 000 per client key (new proofs are refused when full, old ids are
     never forgotten early). Only proofs signed with the key their token
     is bound to are recorded, after every other check: anyone with a
     valid token can make keys, and those take no room;
   - an `Authorization: Basic` header: 8 192 characters;
   - a login form: the login filter reads at most 64 KB of the body. When
     the CSRF token is sent as a form field, the CSRF filter has already
     read the form, with the web starter's 1 MiB limit, and the login
     filter uses those fields;
   - the number of sessions: `server.servlet.session.max-sessions`
     (10 000 by default). A new session takes the place of an expired
     one, then of the oldest one its client never came back with, then
     of the least recently used one without a login. When only logins
     are left, it takes the place of the least recently used login of
     the user who holds the most sessions, if that user holds two or
     more (users told apart by the name the chain stores in the session
     at login, with the login's source: the same name from an identity
     provider and from the application's own users is two users), so
     one account cannot lock the others out and nobody
     loses their last session; when every login left is another user's,
     the new session is refused (503), as Tomcat refuses sessions above
     its limit;
   - the calls to the identity provider: a failed lookup of its metadata
     or its JWK Set is made again 30 seconds later at the earliest (the
     OAuth2 client's discovery: 10 seconds), never once per request;
     concurrent requests share one call. These pauses, the JWK Set's
     cache lifespan and the DPoP replay cache's purges are measured on a
     monotonic clock: a server clock set back does not stretch them (a
     cached failure served, or a rotated key refused, for hours).

   Password hashing runs only for requests that carry credentials.

## How it is shown

Evidence that can be checked without reading the code
([roadmap/security_verification.md](../roadmap/security_verification.md)):

| Evidence | Where | Result |
|---|---|---|
| The attack catalog as tests: ambiguous paths, malformed credentials, CSRF, CORS, cookies, headers, JWT attacks (`alg: none`, algorithm confusion, embedded keys, `kid` tricks, expiry), method security; JWTs of another `typ` signed with the issuer's key (`logout+jwt`, `secevent+jwt`, `dpop+jwt`, `at+jwt`: refused; `JWT` in any case, or none: accepted), in every default decoder, the app's `JwkSetOidcIdTokenDecoder` (Sign in with Apple) included, checked against the server's `OidcIdTokenDecoderFactory` with the same tokens; a token bound to a client certificate (`cnf.x5t#S256`: refused as `Bearer` and with a valid DPoP proof); anonymous requests ten times over the session limit (every login stays; at the limit with one login per user, new sessions are a 503 and a protected page still sends to the login); one account logged in up to the limit (another user still logs in, the account's least recently used session making room; an anonymous flood then costs the account one more session at most, the other user nothing), the session order (expired, never returned, without a login, then the user holding the most; a login kept across its new id; a login without a user name never pushed out); token requests without a CSRF token in the default chain and in a chain with sessions (`POST`, `PUT`, `DELETE` with a `Bearer` or `DPoP` token), the CSRF check kept without a token or with a malformed one, a forged token header with a session cookie (401, never the session's user), a token header at the logout and login URLs (403: the user stays logged in, no login with the attacker's credentials), a token in the query string of a `POST` (`/logout?access_token=`, `/login?access_token=`, the API: 403; the parameter read in `GET` requests only, for server-sent events); one authentication event per token request (a bound token as `Bearer`, a certificate-bound token, a refused proof: one failure, no success); a JWK Set or issuer metadata endpoint that fails (one attempt every 30 seconds, not one per token) | `spring_boot_starter_security/test/` (`web_attacks_test.dart`, `token_requests_test.dart`, `bearer_test.dart`, `jwt_test.dart`, `dpop_test.dart`, `jwt_failures_test.dart`), `spring_boot_starter_web/test/http_session_test.dart`, `spring_security_core/test/` | 346 tests in the core and 762 in the starter, plus 13 integration tests on a real server, all passing (counted with `dart test`, the integration and differential tags apart, October 2026) |
| The attacks on `oauth2Login()` as tests, against a fake OpenID Connect provider (discovery, token, user-info and JWK endpoints, ID tokens signed with the test keys): a missing, wrong, duplicated or replayed `state`; a callback in another browser (login CSRF); a saved request used once; a replayed code; a callback for registration B with A's `state` (mix-up); an `error` from the provider; an RFC 9207 `iss` of another issuer, or missing when announced; a wrong or missing `nonce`; ID tokens of another issuer or audience, with another `azp`, expired, `alg: none`, HS256 (algorithm confusion), signed by another key with the same `kid`, with an unknown `kid` (no flooding of the key endpoint); a missing ID token; user info about another `sub`; extra parameters on the callback (no open redirect: the target is the saved page of this site or the configured URL); a callback as `HEAD`, `PUT`, `DELETE` or `PATCH` (refused, the login in progress left alone; `PUT` with CSRF on: the CSRF 403); an `iss` for a registration without `issuer-uri` (nothing to compare with: accepted, while its callback path keeps it apart from the others); a new session id at login (fixation); logout still needs the CSRF token; the login page escapes the client names; the application's `TokenEndpointOidcIdTokenDecoder` bean never replaces the signature check | `spring_boot_starter_security/test/oauth2_login_test.dart`, `oauth2_login_auto_configuration_test.dart`, `oauth2_login_parts_test.dart` | all passing |
| The attacks on DPoP-bound tokens (RFC 9449) as tests, through the filter chain: a replayed proof (and a new proof with a used `jti`; a replay at exactly the end of its window, `iat` + skew, also with the `iat` check and the `jti` store reading the clock 50 µs apart: ids are kept 5 s past the window and refused until purged); a stolen token with a proof of another key (`cnf.jkt`); the client's `jwk` with another key's signature; another `htm` (also in lower case); another `htu` (scheme, host, port, path, its case, a trailing `/`, an encoded `/`, user information, relative), while case of scheme and host, the default port, percent-encoding, dot segments, query and fragment do not matter (RFC 9449 §4.3); a stale or future `iat`; a missing or wrong `ath`; a bound token as `Bearer`, with or without a proof; a token also bound to a client certificate (`cnf.x5t#S256`), refused with a valid proof; an unbound token with the DPoP scheme; `alg: none` and HS256 proofs (with a shared secret or the public key as the secret); private members (`d`, `p`, `q`, `dp`, `dq`, `qi`, `oth`, `k`) in the proof's `jwk`; a missing `jwk`, a key named by `kid` instead, a point off its curve, a curve of another algorithm, RSA under 2 048 bits, a `jwk` for encryption or another `alg`; proofs of keys the token is not bound to, of an unbound token or of an invalid one (refused before their `jti` is recorded: the store stays empty); a proof and token made for another server, sent with its name in `Host` (accepted without an audience check, refused with one); a proof with another `typ`, the access token as the proof, a `crit` header; mistyped claims; an oversized proof; no, an empty or two `DPoP` headers; two `Authorization` headers; a malformed `DPoP` header; an invalid access token with a valid proof; no token, proof or key in the answers; a failing `jti` store refuses the proof; the RFC 7638 and RFC 9449 thumbprint and `ath` vectors | `spring_boot_starter_security/test/dpop_test.dart`, `spring_boot_starter_oauth2_client/test/dpop_test.dart` | all passing; in the differential test (32 requests against Spring Security 7.1 with `dPoP()`: the same status and challenge except `htm` in lower case, `htu` with the host in capitals or a query, on purpose, see the starter's README; access tokens of the types `logout+jwt`, `secevent+jwt`, `dpop+jwt`, `at+jwt`, `jwt` and none, and certificate-bound tokens with either scheme, answered the same; and 4 state-changing token requests with CSRF on: `Bearer` the same, a DPoP `POST` accepted here and refused by Spring, whose CSRF check exempts `Bearer` tokens only, and a `POST /logout` with a `Bearer` token refused here (the CSRF check stays at the logout URL) where Spring logs out); in the mutation score (97.2 % of `dpop.dart`) |
| DPoP on the client's side as tests: the software ES256 key against the RFC 6979 vectors (deterministic nonces, no random `k`), its signatures checked with pointycastle's verifier, the JWK round trip and the refusal of a JWK whose `x`/`y` are not its `d`'s; DER to raw `R || S` (leading zeros, high bits, the long form) and the refusal of non-strict DER; proofs as RFC 9449 §4.2 and §7.1 (the `ath` vector), `htu` without query and fragment, a new `jti` each time, no private member in the `jwk`, a DER signature refused; the token endpoint answered `use_dpop_nonce` once (no loop, no answer without a nonce or with DPoP off), a `DPoP` token without a proof refused, `Bearer` kept when issued; `auto` / `true` / `false` per registration; the Feign interceptor's `DPoP <token>` and proof per call, nonces per server, a nonce-only 401 keeps the token; no key, proof or token in logs or `toString`; the client's proofs through the starter's resource server chain (accepted; another method, URL, token or key and a replay refused) | `spring_boot_starter_oauth2_client/test/dpop_client_test.dart`, `spring_boot_starter_security/test/dpop_client_test.dart` | all passing; the proof builder in the mutation score (100 %) |
| The app's DPoP key as tests: the platform channel's key (mocked by a software key answering as the Secure Enclave and the Keystore do: the public key as a point or an X.509 key, DER signatures) signs proofs whose raw `R || S` is the key's, asks the platform once (concurrent proofs too), maps platform errors, refuses a public key off the curve, of another curve or compressed and a signature that is not strict DER; a key gone (`no_key`) is forgotten and replaced; `delete` makes the next proof use a new key; the desktop key is kept in and read back from the `SecretStore`, a damaged stored key is replaced; stored DPoP tokens keep their type and key thumbprint, tokens bound to another key are dropped, records without a type read as `Bearer`, an unknown type or a thumbprint on a `Bearer` token is refused; logout deletes the key (a failing deletion does not stop it); the bean replaces the client's key of one run, none in a browser, an application's key wins; no key in `toString`. On devices: each proof's signature checked with pointycastle against the JWK in its header, the key found again by a new object, deleted, gone under the app (`no_key`, then a new key), the `DPoPKey` bean; a WebSocket handshake's proof has the `http(s)` `htu` | `spring_boot_starter_flutter_security/test/dpop_key_test.dart`, `example/flutter_guide/integration_test/dpop_key_test.dart`, `spring_boot_starter_oauth2_client/test/dpop_client_test.dart` | all passing; on devices: macOS (Keychain key, debug build), iOS 27 simulator (Secure Enclave), Android 17 emulator (Keystore without secure hardware); not yet on a StrongBox phone, Windows or Linux |
| The attacks on a browser's own login (spa mode) as tests, against the fake OpenID Connect provider and a fake page (address, history, storages): another `state`, the provider's `error`, another `iss` and a missing announced one (RFC 9207), a reload of the answer (a replay), an answer in another tab, a request without its PKCE verifier, an answer after the request's lifetime, a wrong `nonce`, the token endpoint refusing or unreachable (CORS named), a client secret refused; the answer removed from the address bar (the app's own parameters and route kept, an app's `?code=` elsewhere untouched); no token in `sessionStorage` or `localStorage`, nothing secret logged; the silent `prompt=none` login, `login_required` as nobody and never a second try; the logout (revocation, refresh token first; the provider's `end_session_endpoint` with `id_token_hint`); the DPoP key loaded at its first use, `dpop_jkt`, proofs on the token request, DER turned into `R || S`; the refresh token rotation warning. End to end against Keycloak 26 (`neon-web`), a scripted browser with cookies: the login form, DPoP tokens whose `cnf.jkt` is the key's, the replay, the silent login, the logout, `login_required`, CORS on the token, user info and revocation endpoints | `spring_boot_starter_flutter_security/test/spa_login_test.dart`, `spa_auto_configuration_test.dart`, `spa_keycloak_e2e_test.dart` (tag `e2e`) | all passing; the WebCrypto, IndexedDB and `history` code itself runs only in a browser, not tested yet |
| The attacks on `oauth2Login()` with `response_mode=form_post` (Sign in with Apple's) as tests, against the fake OpenID Connect provider: a missing, wrong or replayed `state` in the posted form; a post without the session cookie (what a `SameSite=Lax` cookie does on the provider's cross-site post: no login, a warning); a `GET` for a form post login and a `POST` for a query login (refused, the login in progress left alone); the response split between the query and the body, and a complete form post with `code`, `error` or `state` in the query; the warning about the missing session logged once, without the code or the state; a post that is no form; a posted body over 64 KB (a 413, the login left alone); the CSRF exemption only for the callback's `POST`; a posted `id_token` or `access_token` never replacing the token response's (the unsigned `user` reaches the user service only). End to end against Keycloak 26 (`neon-server`): Keycloak's auto-submitting form posted with the session cookie, the code exchanged and the ID token checked with Keycloak's keys, the same response as a `GET` and a replayed post refused | `spring_boot_starter_security/test/oauth2_form_post_test.dart`, `oauth2_form_post_keycloak_e2e_test.dart` (tag `e2e`) | all passing; in the mutation score (the `oauth2Login()` row of docs/security-mutation.md); not yet in the differential test; not tried against Apple itself (no account) |
| Sign in with Apple's sheet in the app as tests (a real `JwkSetOidcIdTokenDecoder` over a mocked JWK Set, ES256 test keys; the sheet mocked): another or no `state`; an identity token signed by another key, of another app (audience), another issuer, expired, with another `nonce` (a replay), about another user than the sheet; a server that answers for another user; a refused client; nothing exchanged before the checks pass; the code and token never in `toString`. The decoder alone: the RFC 7515 RS256 and ES256 vectors, a changed token, `alg: none`, HS256 with the public key, keys inside the token (`jwk`, `jku`, `x5u`, `crit`), a `typ` other than `JWT` or none (`logout+jwt`, `at+jwt`, `secevent+jwt`, `dpop+jwt`, `application/jwt`, `JOSE`, `id_token+jwt`), an unknown `kid` fetched once (at most once a minute), RSA under 2 048 bits, an RSA exponent of 1 (a forged token whose "signature" is the padded hash), even or over 64 bits, a DER signature, the claims; a discovery that fails is tried again 10 seconds later, not on every use. The JWT client secret: Apple's header and claims, the ES256 signature checked with pointycastle, the cache, P-384 and malformed keys refused without key material in the message, a JWT secret with `none` refused before any request | `spring_boot_starter_flutter_security/test/apple_sign_in_test.dart`, `spring_boot_starter_oauth2_client/test/jwk_set_oidc_id_token_decoder_test.dart`, `jwt_client_secret_test.dart` | all passing; the sheet itself (`ASAuthorizationAppleIDProvider`) and Apple's token endpoint not run (no Apple account here) |
| Android App Links: only the redirect of the login that runs (scheme, authority, port, exact path and exactly the login's `state`; the rest of the query checked in Dart) completes it; other links of the host, another path (case, a trailing `/`, an encoded `/`), another host, scheme, port or user information, an authority that is no valid host (matching only itself), the exact path with another, a repeated or no `state` (ignored, the login waits), malformed links, opaque and `http://` redirects are refused (JVM unit tests); an unverified `https` host fails before the page opens. The desktop's loopback server likewise answers only the request with the login's `state` (`test/loopback_test.dart`) | `spring_boot_starter_flutter_security/android/src/test/.../RedirectMatcherTest.kt` (`./gradlew :spring_boot_starter_flutter_security:testDebugUnitTest` in an app's `android/`) | all passing; not run with a verified domain on a device |
| The same requests sent to Spring Security 7.1 (Spring Boot 4.1) and to the starter: statuses, challenges, redirects, headers, cookies | `tool/security_reference`, `test/differential_test.dart`, CI job "Security compared with Spring Security" | equal, except the differences listed in the starter's README. `oauth2Login()` too (both log in at the same fake OpenID Connect provider; 18 scenarios: the redirect to the provider, the login and the saved page, wrong, missing and replayed `state`, the callback in another browser, provider errors, used and injected codes, ID tokens of another audience or nonce, the OpenID Connect logout): 14 end the same; the 4 differences are on purpose (this starter refuses another `iss` and another registration's callback, which Spring accepts; an unknown registration is a 400, not Spring's 500; no session for a failed login) |
| Password hashes written by Spring and checked here, and the other way | `tool/security_reference`, `spring_security_core/test/vectors/` | all match |
| RFC 7515 test vectors (JWS) | `test/vectors/rfc7515.json` | all verify |
| Generated inputs (seeded): random paths through the firewall, random rule sets, random `Authorization` headers, mutated tokens | `test/fuzz_test.dart` | no input lets an ambiguous path through, allows what the rules deny, or throws anything unexpected |
| Mutation testing: small changes to the code must make a test fail | `tool/mutation_test.dart` | 98.1 % (core) and 98.6 % (starter) of the changes are noticed; the rest change nothing observable, each explained in [docs/security-mutation.md](security-mutation.md). The SSO and DPoP code (October 2026): 97.2 % of DPoP (`dpop.dart`), 91.8 % of `oauth2Login()` (`lib/src/oauth2/`, `form_post` code included), 100 % of the OAuth2 client's ID token validator, DPoP proof builder and authorization response; the rest explained there too |
| Line coverage | `dart test --coverage` | 99.9 % of the core's lines (one unreachable defensive line), 100 % of the starter's (`oauth2Login()` included; 4 lines only through the integration tests) |
| OWASP ASVS 4.0.3 level 2 (V2, V3, V4, V13, V14) | [docs/security-asvs.md](security-asvs.md) | each requirement with its status and test |
| OWASP ZAP baseline scan (passive rules) of the server guide as the starter secures it: every endpoint seeded, logged in as `ada` with the form login (dev) and through Keycloak's login form (`sso`, `oauth2Login()`) | CI job "OWASP ZAP baseline", `.zap/rules.tsv` (the accepted rules, each with its reason), `.zap/seed_hook.py` | no failure and no warning outside the accepted rules (dev logged in, dev anonymous, `sso` logged in, run locally with ZAP 2.17.0, October 2026); the first scan's three findings of the example (CSP without `form-action` and `base-uri`, cookies without `SameSite` or `HttpOnly`, handler names in `Server-Timing`) fixed |

Not done yet: an external review.
