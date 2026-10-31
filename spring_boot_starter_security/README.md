# spring_boot_starter_security

Security for web applications built with
[`spring_boot_starter_web`](../spring_boot_starter_web/README.md): a filter
chain in front of the controllers decides who may call which endpoint,
logs users in, and protects browser sessions.

A server with any endpoint that is not public needs this: it must know who
is calling (a login form, HTTP Basic, a token from an identity provider),
refuse what that user may not do, keep a page on another site from using
the user's session (CSRF), and send the headers that keep browsers safe.
Writing those checks by hand in every controller is easy to get wrong.
With this starter they live in one place, run before any controller, and
are on as soon as the dependency is listed.

```yaml
dependencies:
  spring_boot_starter_security: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3
  spring_boot_starter_test: ^0.4.3     # MockMvc, springBootTest
```

It brings the web starter,
[`spring_security_core`](../spring_security_core/README.md) (users,
password hashes, `@PreAuthorize` on bean methods) and
[`spring_boot_starter_oauth2_client`](../spring_boot_starter_oauth2_client/README.md)
(the registrations of single sign-on), so this one dependency is enough.

*In the guides:* [server, 4. Security](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#4-security).

## Secure by default

With the starter listed and nothing configured, as in Spring Boot:

- every request needs a login;
- a browser asking for a page is redirected to a generated login page,
  `/login`; programs and `curl` get a `401` with `WWW-Authenticate:
  Basic`; scripts (`X-Requested-With: XMLHttpRequest`) get a plain `401`,
  so no browser password dialog appears;
- there is one user, `user`, whose password is
  `spring.security.user.password` or, when that is not set, a random one
  logged at startup (for development only);
- CSRF protection, security headers and logout at `POST /logout` are on.

```properties
# A development user instead of the generated password.
spring.security.user.name=admin
spring.security.user.password=change-me
spring.security.user.roles=ADMIN
```

The default user disappears as soon as the application has its own users:
a `UserDetailsService`, an `AuthenticationProvider`, an
`AuthenticationManager` or a `JwtDecoder` bean, the JWT properties below,
or an OAuth2 client registration (unless `spring.security.user.name` or
`.password` is set). Its password is stored as `{noop}` unless it already starts with an
`{id}`. With a `PasswordEncoder` bean it is stored as given, so it must
already be encoded, and a generated password cannot log in.

| Property | Default |
|---|---|
| `spring.security.user.name` | `user` |
| `spring.security.user.password` | a random one, logged at startup |
| `spring.security.user.roles` | none |
| `spring.security.filter.order` | `-100`: the place of the security filter among the web filters |
| `spring.security.oauth2.resourceserver.jwt.*` | see [JWT resource servers](#jwt-resource-servers) |

## Your rules

Declare a `SecurityFilterChain` bean to replace the default chain. Each
bean method that takes an `HttpSecurity` gets a fresh builder:

```dart
@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth
          .requestMatchers('/public/**').permitAll()
          .requestMatchers('/api/admin/**').hasRole('ADMIN')
          // Anyone may read the catalogue; changing it needs a login.
          .requestMatchersFor(HttpMethod.get, ['/api/books/**']).permitAll()
          .anyRequest().authenticated())
      .formLogin()
      .httpBasic()
      .build();

  // The users and their hashed passwords.
  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
        User.withUsername('ada').password('{argon2}...').roles(['USER']).build(),
      ]);
}
```

Spring (Java):

```java
@Bean
SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
  return http
      .authorizeHttpRequests(auth -> auth
          .requestMatchers("/public/**").permitAll()
          .requestMatchers("/api/admin/**").hasRole("ADMIN")
          .requestMatchers(HttpMethod.GET, "/api/books/**").permitAll()
          .anyRequest().authenticated())
      .formLogin(Customizer.withDefaults())
      .httpBasic(Customizer.withDefaults())
      .build();
}
```

- **Rules** use the router's path patterns (`/api/**`, `/users/{id}`) on
  the path the router sees, so a rule covers exactly what the controllers
  under it serve. Paths are case-sensitive and a trailing slash counts:
  protect `/admin` and `/admin/**` when both exist. The first matching
  rule decides, and a request that no rule matches is **denied**. Besides
  `permitAll`, `denyAll`, `authenticated`, `fullyAuthenticated`,
  `anonymous`, `hasRole`, `hasAnyRole`, `hasAuthority` and
  `hasAnyAuthority`, `access(...)` takes any `AuthorizationManager`; it
  receives the path variables of the rule's pattern
  (`context.variables['id']`), for rules such as "users may only read
  their own profile".
- **A chain without `authorizeHttpRequests`** lets every request through,
  with a warning in the log.
- **Logins:** `httpBasic()`; `formLogin()`, with the generated page or
  your own (`formLogin((f) => f.loginPage('/sign-in'))`, a page every user
  must be allowed to reach); `oauth2ResourceServer((s) => s.jwt())` for
  bearer tokens. A form or Basic login without any user in the
  application fails the startup.
- **Sessions:** a login gives the session a new id, so an id planted
  before the login is worthless (session fixation). APIs whose clients
  send credentials or a token with every request use no session at all:
  `sessionManagement((s) =>
  s.sessionCreationPolicy(SessionCreationPolicy.stateless))`.
- **Several chains:** `securityMatcher('/api/**')` limits a chain to some
  paths; order the beans with `@Order`. The first chain whose matcher fits
  handles the request. A chain that matches every request must come last,
  or the startup fails. A request that no chain matches goes on without
  any security filter, as in Spring, so keep a last chain without
  `securityMatcher`.
- **Headers:** `nosniff`, no caching, `X-Frame-Options: DENY` and, over
  HTTPS, HSTS are sent by default. `headers((h) => ...)` changes them:
  `contentSecurityPolicy(...)`, `referrerPolicy(...)`,
  `frameOptions(XFrameOptionsMode.sameOrigin)`, `addHeaderWriter(...)`.
- **CORS** is on, with the router's rules, pre-flight requests included:
  those of the `CorsConfigurationSource` bean named
  `corsConfigurationSource` alone where it has some (as Spring Security
  applies that bean; a bean of the type with another name, such as
  `apiCors`, is ignored, several never fail the start, and a bean of that
  name of another type does, as in Spring), else the `WebMvcConfigurer`
  mappings and the `@CrossOrigin` of the handler the router would call
  (chosen with its `consumes`, `produces` and `headers` too). The handler
  mappings are asked in order, as for the request itself, as Spring's
  `HandlerMappingIntrospector` asks them: a request another mapping
  takes, such as a WebSocket handshake, gets only the bean's rules, never
  the `addCorsMappings` ones (the endpoint's `allowedOrigins` decide). The
  router leaves a request the filter allowed as it is, so CORS works the
  same with and without this starter. A request's origin and method are
  checked (a `HEAD` or `DELETE` the rules do not list is a 403, before
  the security checks);
  `cors((c) => c.configurationSource(...))` takes other rules.
- **Your own filters:** `addFilterBefore`, `addFilterAfter` and
  `addFilterAt` place a `WebFilter` relative to a built-in filter class
  (`addFilterAfter(MyFilter(), CsrfFilter)`).

## CSRF protection

Cross-site request forgery is a page on another site making the user's
browser send a request to your application, with the user's cookies. CSRF
protection makes every state-changing request carry a token that such a
page cannot know.

What is checked: every method except GET, HEAD, TRACE and OPTIONS needs
the token, in the header `X-CSRF-TOKEN` or the form field `_csrf` (by
default the token is kept in the session). What happens on failure:

- no token stored for the client yet (a first request, an expired
  session): `403`, and a new token is created for the next try;
- a token missing from the request, or not equal to the stored one
  (compared in constant time): `403`.

The `403` comes also for anonymous users; they are not asked to log in. A
login form posted without the token is refused too.

**Pages rendered by the server** put the token in their forms as a hidden
field. `csrfTokenOf(request)` gives it (and creates it when the client has
none):

```dart
@GetMapping('/form')
String form(ServerHttpRequest request) {
  final csrf = csrfTokenOf(request)!;
  return '<input type="hidden" name="${csrf.parameterName}" value="${csrf.token}">';
}
```

By default each page gets the token masked with fresh random bytes
(`XorCsrfTokenRequestAttributeHandler`), so the bytes are never the same
twice and cannot be guessed from the size of compressed responses
(BREACH).

**Single-page and Flutter web apps** render no forms: they read the token
from a cookie, `XSRF-TOKEN`, and send it back in the `X-XSRF-TOKEN`
header. That needs two settings together: a cookie that scripts can read,
and a handler that accepts the raw cookie value. With the cookie alone,
the default handler expects a masked token, and the raw value the script
sends is refused with `403`.

```dart
.csrf((c) => c
    .csrfTokenRepository(const CookieCsrfTokenRepository.withHttpOnlyFalse())
    // The script sends the cookie value as it is, not a masked token.
    .csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler()))
```

The token is created only when something reads it or a check needs it.
For the client to have the cookie before its first `POST`, add a filter
that reads the token on every request, as the server guide does:

```dart
// Reading the token writes the XSRF-TOKEN cookie when it is new.
final class CsrfCookieFilter extends OncePerRequestFilter {
  @override
  Future<void> doFilterInternal(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    csrfTokenOf(request);
    return chain.doFilter(request, response);
  }
}

// In the chain:
.addFilterAfter(CsrfCookieFilter(), CsrfFilter)
```

Spring (Java):

```java
http.csrf(c -> c
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
    .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler()));
```

**APIs authenticated only by headers** (Basic, bearer tokens), never by
cookies, can turn it off: `csrf((c) => c.disable())`. A browser does not
send those headers by itself, so another site cannot forge such a
request. `csrf((c) => c.ignoringRequestMatchers('/webhooks/**'))` exempts
single paths, such as a webhook a third party posts to. With
`oauth2ResourceServer()`, requests that carry a token in the header
(`Authorization: Bearer`, or `DPoP` with a proof) are exempt by
themselves, as in Spring, while the browser's session requests of the
same chain keep their CSRF check. A page of another origin can add
such a header only where the CORS configuration lets its origin send
it with credentials, and such an origin can read the CSRF token anyway.
The exempt request goes on to the token filters, which log it in with
the token or refuse it with `401`, whatever cookies come with it. Two
limits keep that true:

- only the header counts: a token in the `access_token` query string
  never exempts a request, since any page can post a form to such a URL
  (the parameter is read in `GET` requests only, see below);
- the chain's logout URL and form login URL keep their CSRF check even
  with a token header: their filters act on the browser's session
  before any token is looked at (Spring exempts them). A filter of your
  own added before the token filters (`addFilterBefore(...,
  BearerTokenAuthenticationFilter)`) sees such a request before its
  token is checked too: it must not act on the session for it.

## JWT resource servers

An API whose users log in at an identity provider (Keycloak, Auth0, ...)
receives a JSON Web Token with every request and must check it. Set the
provider and the API's audience:

```properties
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.example.com
# or: spring.security.oauth2.resourceserver.jwt.jwk-set-uri=https://login.example.com/jwks
spring.security.oauth2.resourceserver.jwt.audiences=my-api
```

With `issuer-uri` or `jwk-set-uri` set, the default chain needs a valid
bearer token on every request, and there is no default user. Or declare a
chain with `oauth2ResourceServer((s) => s.jwt())`, usually with a
`stateless` session policy.

| Property | Default |
|---|---|
| `spring.security.oauth2.resourceserver.jwt.issuer-uri` | none; the keys come from the issuer's metadata |
| `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` | none; the URL of the provider's public keys |
| `spring.security.oauth2.resourceserver.jwt.jws-algorithms` | `RS256`; used with `jwk-set-uri` only |
| `spring.security.oauth2.resourceserver.jwt.audiences` | none: no audience check |
| `spring.security.oauth2.resourceserver.jwt.authority-prefix` | `SCOPE_` |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-name` | `scope`, else `scp` |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-delimiter` | a space |
| `spring.security.oauth2.resourceserver.jwt.principal-claim-name` | `sub` |

With `jwk-set-uri`, the issuer (when `issuer-uri` is set too) and the
audiences are checked. With `issuer-uri` alone, `jws-algorithms` is not
used: the algorithms are those the provider's keys allow.

What is checked, in order; any failure is a `401` with `WWW-Authenticate:
Bearer error="invalid_token"`:

1. The token is parsed strictly: never `alg: none`, no `crit` header, no
   nested or encrypted tokens, at most 64 KiB.
2. Its `alg` must be an accepted one and fit the key, so an RSA public key
   is never used as an HMAC secret (algorithm confusion). Supported:
   RS256 to RS512, PS256 to PS512, ES256 to ES512, and HS256 to HS512 with
   `NimbusJwtDecoder.withSecretKey`.
3. The signature is checked with the key of the token's `kid`. Keys named
   in the token itself (`jku`, `jwk`, `x5u`) are ignored: a token cannot
   bring its own key.
4. `typ` is `JWT` (in any case) or absent, as in Spring Security 7: the
   provider's other JWTs, signed with the same keys, are no access
   tokens (logout tokens `logout+jwt`, security events `secevent+jwt`,
   and DPoP proofs `dpop+jwt`). `at+jwt` (RFC 9068) is refused too, as
   in Spring; for a provider that types its access tokens so, declare a
   `JwtDecoder` bean whose validator starts with
   `JwtTypeValidator(['at+jwt', 'JWT'], allowEmpty: true)`.
5. `exp` and `nbf` are checked with 60 seconds of clock skew, then the
   issuer and the audiences as configured.
6. A token bound to a client certificate (`cnf.x5t#S256`, RFC 8705) is
   refused, with either scheme: it is valid only over a TLS connection
   made with that certificate, and the web starter does not hand client
   certificates to the security filters, so the binding cannot be
   checked (Spring refuses such a token too when the request has no
   client certificate).

The provider's keys are cached for 5 minutes. A token with an unknown
`kid` fetches them again, at most once every 30 seconds, so made-up ids
cannot flood the provider. A failed fetch counts too, and so does a
failed lookup of the issuer's metadata (`issuer-uri` alone): while the
provider is down, tokens fail with a `401` (or keep the keys fetched
before) and the provider gets one attempt every 30 seconds, never one
per token. A valid token without the rights a rule needs
gets `403` with `error="insufficient_scope"`. Bearer tokens in the query
string (`access_token=`) are ignored unless the
`DefaultBearerTokenResolver` allows them (`allowUriQueryParameter`, for
server-sent events from a browser), and then only in `GET` requests, as
in Spring; such a token never exempts a request from CSRF.

Scopes become `SCOPE_x` authorities, so a rule reads
`hasAuthority('SCOPE_orders.read')`. `@AuthenticationPrincipal() Jwt jwt`
gives the token to a controller, and method security expressions can read
`principal.claims['tenant']`.

The signatures are verified with Bouncy Castle's Dart port
(`pointycastle`), a third-party package
[to be replaced](../docs/dependencies.md#pointycastle-third-party-to-be-removed).

## DPoP-bound access tokens

A `Bearer` token works for whoever holds it, until it expires. A
DPoP-bound token (RFC 9449) is bound to a key that only the client (a
Flutter app, say) has: with each request the client sends a short JWT
signed with that key, the proof, so a stolen token alone is useless.
Keycloak, Okta, Auth0 and Spring Authorization Server issue such tokens;
their `cnf.jkt` claim is the thumbprint (RFC 7638) of the client's key.

Nothing to configure: `oauth2ResourceServer((s) => s.jwt())` (or the
`issuer-uri` / `jwk-set-uri` properties) accepts both kinds of tokens, as
in Spring Security 6.5.

```http
GET /api/orders HTTP/1.1
Authorization: DPoP eyJhbGciOiJSUzI1NiIs...
DPoP: eyJ0eXAiOiJkcG9wK2p3dCIsImFsZyI6IkVTMjU2IiwiandrIjp7...
```

What is checked; any failure is a `401` with
`WWW-Authenticate: DPoP error="...", algs="RS256 ... ES512"`:

1. Exactly one `DPoP` header, at most 8 KiB (`invalid_request`
   otherwise).
2. The access token, as a `Bearer` token is (`invalid_token`); it must
   have a `cnf.jkt` claim (`invalid_dpop_proof` otherwise, before the
   proof is read).
3. The proof (`invalid_dpop_proof`): `typ` is `dpop+jwt`; `alg` is RS*,
   PS* or ES*, never `none` or HS*; the signature verifies with the
   public key of its own `jwk` header, an EC key on its curve or an RSA
   key of 2 048 to 8 192 bits, without private members (`d`, ...);
   `htm` is the request's method (case-sensitive); `htu` its URL; `iat`
   is within 30 seconds of the server's clock; `ath` is the hash of the access token;
   the thumbprint of its key equals the token's `cnf.jkt`.
4. Its `jti` was not used before; it is recorded only now, for a proof
   that passed everything else.

A token with `cnf.jkt` sent as `Bearer` is refused (`invalid_token`),
with or without a `DPoP` header, and so is a token also bound to a
client certificate (`cnf.x5t#S256`), even with a valid proof. A `DPoP` header next to an unbound
`Bearer` token is ignored, as in Spring. On success the request has the
same `JwtAuthenticationToken` as with a `Bearer` token: rules, scopes,
`@AuthenticationPrincipal() Jwt` and `@PreAuthorize` work unchanged, and
`jwt.jwkThumbprint` gives the `cnf.jkt`.

`htu` is compared with the URL the request reached the server with:
scheme, host (the `Host` header) and port as the server sees them, and the
path, after RFC 3986 normalization (case of scheme and host, default
port, percent-encoding), query and fragment ignored. Behind a proxy that
terminates TLS, the server sees `http`, and proofs for `https://...` are
refused until the web starter reads forwarded headers: pass the scheme
through, or terminate TLS in the application (`server.ssl.*`).

The ids of used proofs are kept in memory until 5 seconds after the time
window (`iat` + 30 s + 5 s: the `iat` check reads the clock a moment
before the store does, and an id dropped at the very end of the window
would let the proof through once more), at most 100 000 and 1 000 per
client key, as in Spring; a recorded id is refused until a purge drops
it, and when full, new proofs are refused until old ids expire (never
forgotten early). Only proofs
signed with the key their token is bound to are recorded, so the limit
per key holds per bound key: a client with one valid token cannot fill
the store with proofs of keys it makes up. A client that gets many
tokens, each bound to another key, could still fill it (1 000 per key)
and have new proofs refused for everyone while those ids are kept (up
to twice the 30-second skew plus 5 seconds); the identity provider's
limits on token requests, or a shared store with its own quotas, are the
defence there. With several instances behind a load balancer, a proof
could be replayed on another one: give them a shared store, which keeps
each id until the `expiresAt` it is given (a TTL) and refuses it until
then. A `DPoPProofJwtDecoderFactory` bean replaces the default:

```dart
@Bean()
DPoPProofJwtDecoderFactory dPoPProofs(RedisJtiCache cache) =>
    DPoPProofJwtDecoderFactory(
      jtiCache: cache, // a DPoPProofJtiCache shared by the instances
      clockSkew: const Duration(seconds: 30),
    );
```

## Single sign-on: oauth2Login

Users log in at an identity provider (Keycloak, Google, GitHub, Auth0,
Okta, ...) instead of with a password of the application: the browser is
sent to the provider's login page and comes back logged in. This is
OAuth 2.0's authorization code flow, with OpenID Connect when the
provider has it; the server is the client, with its own secret.

Use it for pages rendered by the server, and for a **Flutter web app**:
the server is the app's backend (BFF), keeps the tokens, and the browser
holds only the session cookie (`HttpOnly`), which no injected script can
read. A web page has no safe place for tokens, so it never gets them.
The Flutter web app's side is `OAuth2LoginService` of
[`spring_boot_starter_flutter_security`](../spring_boot_starter_flutter_security/README.md#the-web-the-server-logs-in):
it starts the login here, asks a "who is logged in" endpoint of the
application, and posts the logout with the CSRF token. Native apps log in themselves (`OAuth2LoginService` of
[`spring_boot_starter_flutter_security`](../spring_boot_starter_flutter_security/README.md#the-app-login))
and send their access token; a chain can accept both (below). The reasons:
[roadmap](../roadmap/spring_boot_starter_oauth2_client.md#which-flow-where-the-security-decision).

Configure a registration, as in Spring Boot, and the default chain logs
browsers in through it:

```properties
spring.security.oauth2.client.registration.keycloak.client-id=neon-web
spring.security.oauth2.client.registration.keycloak.client-secret=${KEYCLOAK_SECRET}
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon
```

The provider must accept the redirect URI
`{baseUrl}/login/oauth2/code/{registrationId}`
(`http://localhost:8080/login/oauth2/code/keycloak`). Or in a chain of
your own:

```dart
@Bean()
SecurityFilterChain web(
  HttpSecurity http,
  ClientRegistrationRepository registrations,
) => http
    .authorizeHttpRequests((auth) => auth
        .requestMatchers('/', '/public/**').permitAll()
        .anyRequest().authenticated())
    .oauth2Login((login) => login
        // The Flutter web app, served from another port of the same site.
        .defaultSuccessUrl('http://localhost:5050/', alwaysUse: true))
    // Native apps send the provider's access tokens.
    .oauth2ResourceServer((server) => server.jwt())
    // Logging out ends the session at the provider too.
    .logout((logout) => logout.logoutSuccessHandler(
        OidcClientInitiatedLogoutSuccessHandler(
          registrations,
          postLogoutRedirectUri: '{baseUrl}/',
        )))
    .build();
```

What happens:

1. A browser that must log in goes to the generated login page, which
   lists the registrations; with exactly one (and no form login) it goes
   straight to `/oauth2/authorization/{registrationId}`. Scripts
   (`X-Requested-With: XMLHttpRequest`) go to the login page. With
   `oauth2ResourceServer` too, programs asking for JSON get a `401`
   instead, which a Flutter web app turns into a navigation to
   `/oauth2/authorization/keycloak`.
2. `/oauth2/authorization/{registrationId}` keeps a new authorization
   request in the session (a random `state`, a PKCE verifier, an OpenID
   Connect `nonce`) and redirects to the provider. An unknown
   registration is a `400`.
3. The provider redirects back to `/login/oauth2/code/{registrationId}`
   (or, for a registration with `response-mode=form_post`, posts the
   response there as a form, below). The saved request is taken by its
   `state` and removed (a callback works once); a callback without one,
   with another `state`, or for another registration fails. An `error`
   from the provider fails, so does an `iss` parameter (RFC 9207) of
   another issuer.
4. The code is exchanged at the token endpoint with the PKCE verifier and
   the exact redirect URI of the request. The ID token's signature is
   checked with the provider's keys (its JWK Set: `alg: none`, another
   key or an unknown `kid` fail), then its issuer, audience, `azp`,
   expiry and `nonce`. The user info is loaded; its `sub` must be the ID
   token's. The authorities (`OIDC_USER`, `SCOPE_*`) go through the
   `GrantedAuthoritiesMapper` bean, if any.
5. The session gets a new id, keeps the user and the tokens (the
   `OAuth2AuthorizedClientRepository`), and the browser goes back to the
   page it wanted, else to `defaultSuccessUrl` (`/`). That URL is
   configuration, a path or an absolute `http(s)` URL: nothing in the
   request can send the browser elsewhere. A failure goes to
   `/login?error`, without its reason.

| `oauth2Login` option | Default |
|---|---|
| `loginPage` | the generated page at `/login` |
| `defaultSuccessUrl(url, alwaysUse:)` | `/`; the saved page first |
| `failureUrl`, `successHandler`, `failureHandler` | `/login?error`; the redirects |
| `authorizationEndpoint`: `baseUri`, `authorizationRequestRepository`, `authorizationRequestResolver` | `/oauth2/authorization`, the session, `DefaultOAuth2AuthorizationRequestResolver` |
| `redirectionEndpoint`: `baseUri` (or `loginProcessingUrl`) | `/login/oauth2/code/*` |
| `tokenEndpoint`: `accessTokenResponseClient` | the bean, else on the `HttpTransport` |
| `userInfoEndpoint`: `userService`, `oidcUserService`, `userAuthoritiesMapper` | the beans, else `DefaultOAuth2UserService`, `OidcUserService`, none |
| `clientRegistrationRepository`, `authorizedClientRepository`, `authorizedClientService` | the beans |
| `idTokenDecoder` | the `OidcIdTokenDecoder` bean, an `OidcIdTokenDecoderFactory` (signatures checked) |

A controller gets the user as `@AuthenticationPrincipal() OAuth2User user`
(an `OidcUser` with OpenID Connect), and the tokens from the
`OAuth2AuthorizedClientRepository` bean. The session cookie must reach
the callback, a top-level redirect from the provider: keep it
`SameSite=Lax` (the default), not `Strict`. A Flutter web app and the
server must be on the same site (`localhost` with two ports,
`app.example.com` and `api.example.com`), and the app's requests must
send cookies (`credentials: 'include'`) and the CSRF token on `POST`,
`PUT` and `DELETE`.

### The response as a form post (`response_mode=form_post`)

With `response-mode=form_post` on a registration (the default of the
`apple` provider) the authorization request carries
`response_mode=form_post`, and the provider's page posts `code`, `state`
(and Apple's `user`) to the callback as an
`application/x-www-form-urlencoded` form, so they never appear in a URL,
a log or the history:

```properties
spring.security.oauth2.client.registration.keycloak.response-mode=form_post
```

The callback then takes the response from the body of a `POST` (at most
64 KB) with the same checks as a redirect: the `state` of the saved
request (found once, then removed), the registration, the issuer, the
code exchange. The response must come the way the login asked for it: a
`GET` for a form post login, or a `POST` for a query login, fails
(`invalid_request`) and leaves the login in progress alone, and so does a
response split between the query and the body.

- **CSRF:** `oauth2Login()` exempts the callback's `POST` from the CSRF
  filter (the provider's page has no CSRF token of this site); the
  `state`, bound to the browser by the signed authorization request
  cookie, is that callback's CSRF protection (RFC 6749 §10.12). Other
  `POST`s keep it.
- **The cookie:** the provider's post is a cross-site `POST`, which
  carries only `SameSite=None; Secure` cookies. For a form post login
  the authorization request cookie is made so over HTTPS (directly, or
  behind a TLS proxy the server trusts); over plain HTTP no saved
  request is found and the login fails, closed, with a warning in the
  log. The page to come back to (a `Lax` cookie) is not sent with the
  post: after a form post login the user lands on the default page.
  With `HttpSessionOAuth2AuthorizationRequestRepository` instead, the
  session cookie needs `server.servlet.session.cookie.same-site=none`
  over HTTPS. The CSRF protection of the other requests does not rest
  on `SameSite`.
- **Apple's `user`:** the first login's name and e-mail (JSON) reach the
  user service as `userRequest.additionalParameters['user']`, next to the
  token response; parameters named like the token response's
  (`id_token`, `access_token`, ...) are not passed on. It is not signed:
  store the name, never decide who the user is by it.

Spring Security has no `response_mode` setting: there, the application
adds the parameter with an authorization request customizer, exempts the
callback from CSRF (`csrf.ignoringRequestMatchers("/login/oauth2/code/*")`)
and its callback reads the parameters of any method.

### Login with Google

```properties
spring.security.oauth2.client.registration.google.client-id=123-abc.apps.googleusercontent.com
spring.security.oauth2.client.registration.google.client-secret=${GOOGLE_SECRET}
```

The `google` registration gets its endpoints from `CommonOAuth2Provider`
(scopes `openid profile email`). In Google Cloud (APIs & Services >
Credentials) create a **Web application** client with the authorized
redirect URI `https://<your server>/login/oauth2/code/google`
(`http://localhost:8080/...` for development); its secret stays on the
server. Apps use other client types
([the app's side](../spring_boot_starter_flutter_security/README.md#login-with-google)).

- **Roles:** Google sends none. Give them in a `GrantedAuthoritiesMapper`
  bean, from your database or a list:

  ```dart
  @Component()
  class Admins implements GrantedAuthoritiesMapper {
    Admins(this._users);
    final UserRepository _users;

    @override
    List<GrantedAuthority> mapAuthorities(
      Iterable<GrantedAuthority> authorities,
    ) => [
      ...authorities,
      for (final authority in authorities)
        if (authority is OidcUserAuthority &&
            _users.isAdmin(authority.idToken.subject))
          SimpleGrantedAuthority('ROLE_ADMIN'),
    ];
  }
  ```

- **Keep users by `sub`**, never by e-mail (an address can change owner;
  another provider may send one it never verified: account takeover).
  Use the e-mail only with `email_verified=true`.
- **Refresh tokens are not rotated:** one long-lived refresh token (given
  at the first consent), so keep it safe and revoke it when the user
  logs out or deletes the account.

### Sign in with Apple

```properties
# The Services ID of the web login.
spring.security.oauth2.client.registration.apple.client-id=books.neon.web
spring.security.oauth2.client.registration.apple.client-authentication-method=client_secret_post
# The client secret is a JWT this server signs with the team's key.
spring.security.oauth2.client.registration.apple.client-secret-jwt.issuer=ABCDE12345
spring.security.oauth2.client.registration.apple.client-secret-jwt.key-id=XYZ987KEY1
spring.security.oauth2.client.registration.apple.client-secret-jwt.private-key-location=file:/run/secrets/AuthKey_XYZ987KEY1.p8
# Over HTTPS only: Apple posts the response back (response_mode=form_post).
```

The `apple` registration (`CommonOAuth2Provider.apple`, an addition:
Spring has none) has Apple's endpoints, the scopes `openid name email`,
`client_secret_post`, no user-info endpoint (the ID token holds `sub`
and the e-mail) and `response-mode=form_post`, which Apple requires
when the login asks for the name or the e-mail. In the Apple Developer
account: a **Services ID** (the client id) with Sign in with Apple
enabled, its domain and the return URL
`https://<your server>/login/oauth2/code/apple` (Apple accepts neither
`localhost` nor an IP: test on a real domain over HTTPS); a **key** with
Sign in with Apple enabled (the `.p8` file, downloadable once, and its
key id); the **team id**.

- **The client secret** is a JWT signed ES256 with that key: header
  `{"alg":"ES256","kid":<key id>}`, claims `iss` (team id), `iat`, `exp`
  (at most six months later), `aud` (`https://appleid.apple.com`), `sub`
  (the client id). The OAuth2 client's `JwtClientSecret` makes it per
  request from the `client-secret-jwt.*` properties (one hour by default,
  `lifetime`; cached until a tenth of it is left); the key is read at the
  first token request, from `private-key-location` (`file:`,
  `classpath:`) or `private-key` (the PEM itself, from an environment
  variable), and is never logged or shown.
- **form post and the cookie:** see [above](#the-response-as-a-form-post-response_modeform_post).
- **Name and e-mail come once**, on the first login, in the posted `user`
  (`userRequest.additionalParameters['user']` of your `OidcUserService`):
  store them then. Keep users by `sub`; the e-mail may be a private relay
  address (`is_private_email`), and `email_verified` comes as a string.
- **An iOS or macOS app** signs in with Apple's sheet and sends its code
  to an endpoint of this server, which exchanges it with the app's
  registration (the App ID, the bundle id, as client id; the same key):

  ```dart
  // The app's Sign in with Apple: the code of the sheet, exchanged here
  // with the client secret no app may hold. The app's registration has
  // token-uri=https://api.neon.example/oauth2/apple/token.
  @RestController()
  class AppleCodeController {
    AppleCodeController(this._registrations, this._tokens, this._idTokens);

    final ClientRegistrationRepository _registrations;
    final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest>
    _tokens;
    final OidcIdTokenDecoder _idTokens;

    @PostMapping('/oauth2/apple/token')
    Future<Map<String, Object?>> token(@RequestParam('code') String code) async {
      final app = (await _registrations.findByRegistrationId('apple-app'))!;
      final request = OAuth2AuthorizationRequest(
        authorizationUri: app.providerDetails.authorizationUri!,
        clientId: app.clientId,
        redirectUri: '', // the sheet sent none: no redirect_uri
        state: 'native',
      );
      final apple = await _tokens.getTokenResponse(
        OAuth2AuthorizationCodeGrantRequest(
          app,
          OAuth2AuthorizationExchange(
            request,
            OAuth2AuthorizationResponse(redirectUri: '', code: code),
          ),
        ),
      );
      // Signature, issuer, audience (the bundle id), expiry.
      final idToken = await _idTokens.decode(
        app,
        apple.additionalParameters['id_token']! as String,
      );
      // Find or create the user by idToken.subject; keep Apple's refresh
      // token here (check it at most once a day, revoke it when the
      // account is deleted), and answer the app with your API's tokens.
      return {
        'access_token': await apiTokens.issueFor(idToken.subject),
        'token_type': 'Bearer',
        'expires_in': 3600,
        'id_token': idToken.tokenValue,
      };
    }
  }
  ```

  `apiTokens` stands for whatever issues your API's tokens (an
  authorization server; Apple's own access token is no use to your API).
  The endpoint is reachable without login (`permitAll()`, and outside the
  CSRF protection: the app has no session); the code is the credential,
  valid five minutes, once, and only for this client.
- Revoke the user's tokens (`https://appleid.apple.com/auth/revoke`,
  with the client secret) when they delete their account, as the App
  Store requires.

## In controllers

A controller method can ask for the current user:

```dart
@GetMapping('/me')
String me(Authentication authentication) => authentication.name;

@GetMapping('/profile')
String profile(@AuthenticationPrincipal() UserDetails user) => user.username;
```

A `Principal` parameter and `@CurrentSecurityContext() SecurityContext`
work too. `@PreAuthorize` and the other method security annotations of
[`spring_security_core`](../spring_security_core/README.md) work on
controllers and services. A denied call becomes a `403`; a caller who is
not logged in is asked to log in instead (a `401`, or the login page for a
browser).

## Tests

`package:spring_boot_starter_security/testing.dart` makes `MockMvc`
requests as a given user, without a real login:

```dart
import 'package:spring_boot_starter_security/testing.dart';

// An admin may open the admin API.
await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.get, '/api/admin')
      ..with_(user('ada').roles(['ADMIN'])))
    .andExpect(status: 200);

// A POST needs a CSRF token as well as a user.
await app.mockMvc
    .perform(MockRequestBuilder(HttpMethod.post, '/api/books')
      ..with_(user('ada'))
      ..with_(csrf()))
    .andExpect(status: 201);
```

`jwt()`, `httpBasic(user, password)`, `anonymous()`, `userDetails(...)`
and `authentication(...)` exist too, as in `spring-security-test`. The
library also re-exports `withMockUser` and its siblings from
`spring_security_core`.

## The firewall

Before any rule is looked at, requests whose path could be read two ways
are refused with `400`. Otherwise an attacker who makes a rule read
`/admin` differently from the router could reach a protected controller
through an unprotected rule. Refused:

- in the path: `;` and `%3B`, an encoded `/` (`%2F`), `\` and `%5C`, an
  encoded `%` (`%25`) or `.` (`%2E`), `//`, `.` and `..` segments, spaces,
  control and non-ASCII characters, `%00`, line separators;
- a request target that Dart would read as a host (`//host/path`);
- methods other than DELETE, GET, HEAD, OPTIONS, PATCH, POST and PUT
  (TRACE echoes the request, cookies included);
- header names that are not printable ASCII, and header values with
  control characters (a tab is allowed).

A `StrictHttpFirewall` bean with one `allow...` option turned on relaxes a
single rule, for an application that really needs such paths
(`StrictHttpFirewall(allowUrlEncodedSlash: true)`).

## Size limits

So that one request cannot make the server do unbounded work:

- an `Authorization: Basic` header longer than 8 192 characters, or sent
  twice, fails as bad credentials;
- a bearer token over 64 KiB is refused, a DPoP proof over 8 KiB too;
- the login filter reads a form body of at most 64 KB. When the CSRF
  token comes as a form field, though, the CSRF filter has already read
  the form with the web starter's 1 MiB limit, and the login filter uses
  those fields;
- only a login makes a session. Before it, what the chain must
  remember is in cookies signed by the server: the CSRF token
  (`XSRF-TOKEN`), the page to come back to (`REDIRECT_URI`,
  `CookieRequestCache`) and the OAuth 2.0 authorization request
  (`OAUTH2_AUTHORIZATION_REQUEST`,
  `CookieOAuth2AuthorizationRequestRepository`). A cookie is read only
  when its signature, name and expiry are right, and the page to come
  back to only when it is a path of this site. Clients that are not
  logged in therefore fill no memory. Set
  `spring.security.cookie.secret` (32 characters or more) to the same
  value on every instance behind a proxy; without it, a random key of
  the process signs the cookies. Spring's session versions
  (`HttpSessionRequestCache`, `HttpSessionCsrfTokenRepository`,
  `HttpSessionOAuth2AuthorizationRequestRepository`) can still be set;
- sessions are limited by `server.servlet.session.max-sessions` (10 000
  by default). When the store is full, expired sessions are removed;
  if none is, the login is refused with `503`. No live session is
  removed to make room;
- each user holds at most 10 sessions: a new login ends the user's
  least recently used session, or is refused with
  `maxSessionsPreventsLogin(true)`. So filling the store takes as many
  accounts as a tenth of the limit. Set it in a chain
  (`sessionManagement((s) => s.maximumSessions(n))`, `-1` for none,
  Spring's default) or for every chain with sessions in the properties
  (not in Spring Boot):

  ```properties
  spring.security.session.maximum-sessions=3
  spring.security.session.max-sessions-prevents-login=false
  ```

  Chains without sessions (`stateless`, bearer tokens, HTTP Basic)
  ignore them;
- a failed call to the identity provider (its metadata, its JWK Set) is
  made again 30 seconds later at the earliest, never once per request;
- password hashing runs only for requests that carry credentials, and
  at most half the processors hash at once
  (`spring.security.password-checks.max-concurrent`), with eight times
  that waiting (`spring.security.password-checks.max-queued`): above
  that a login gets `503` with `Retry-After: 1` at once, so a flood of
  wrong passwords takes half the CPU at most and the rest of the
  application keeps its speed (limit logins in front all the same).

## Behaviour to know

As the code behaves today:

- `headers((h) => h.defaultsDisabled())` makes later `frameOptions`,
  `httpStrictTransportSecurity`, `contentTypeOptions`, `xssProtection`
  and `cacheControl` calls do nothing; only `contentSecurityPolicy`,
  `referrerPolicy` and `addHeaderWriter` still add headers (Spring adds
  the headers configured after it).
- Users given to a chain with `HttpSecurity.userDetailsService(...)` never
  get their old password hashes upgraded at login; users of a
  `UserDetailsService` bean do.
- With only `issuer-uri`, `jws-algorithms` is ignored (see above).

## Differences from Spring Security

Checked by sending the same requests to this starter and to Spring
Security 7.1 ([tool/security_reference](../tool/security_reference/README.md),
`test/differential_test.dart`). What differs on purpose:

- **Errors are not re-dispatched to `/error`.** Spring Boot sends a 400 or
  403 through the security chain again for `/error`, where the request is
  anonymous: a client gets `401` instead, and after a form login without
  a CSRF token the user lands on `/error`. Here the 400 or 403 is the
  answer.
- **dart:io normalizes paths** (`..`, `%2e%2e`, `\`) before the
  application (RFC 3986). The rules see the normalized path, as the router
  does; Spring's firewall refuses the raw path instead.
- **CORS is on by default**, with the router's rules; Spring needs
  `.cors()`. With a `CorsConfigurationSource` bean named
  `corsConfigurationSource` both apply only the bean's rules where it has
  some, `@CrossOrigin` included (the
  differential test: a pre-flight and a `GET` to `/api/cors` from its
  `@CrossOrigin` origin are a 403 in both). Where the bean has none,
  Spring's `CorsFilter` still ends every pre-flight, with a 200 without
  CORS headers, so the browser blocks a call that `@CrossOrigin` allows;
  here the pre-flight is answered from the handler's rules, as the
  actual request is in both.
- **Sessions:** only a login makes one; Spring Security keeps the CSRF
  token, the saved request and the OAuth 2.0 authorization request in
  the session, here they are signed cookies (see the size limits
  above). The session cookie is `SameSite=Lax` by default
  (`server.servlet.session.cookie.same-site`), and sessions are limited
  (`server.servlet.session.max-sessions`, 10 000; at the limit a new
  login is refused with 503, as WebFlux's `InMemoryWebSessionStore`).
  Spring Boot on Tomcat has no limit of its own.
- **CSRF and token requests:** only a token in the header
  (`Authorization: Bearer`, or `DPoP` with a proof) exempts a request
  from CSRF. Spring exempts whatever its `BearerTokenResolver` finds,
  which with `allowFormEncodedBodyParameter` includes a token in a
  form a cross-site page can post. The chain's logout and login URLs
  keep their CSRF check with a token header; Spring exempts them, and
  its logout filter then logs the session out before the token is
  looked at (the differential test: `POST /logout` with a `Bearer`
  token, `403` here, Spring's logout redirect there).
- **Certificate-bound tokens** (`cnf.x5t#S256`, RFC 8705) are always
  refused. Spring checks them against the request's client
  certificate; the web starter does not hand client certificates to the
  security filters yet.
- **Errors are `ProblemDetail`** (`application/problem+json`), never the
  exception's message.
- **Two `Authorization` headers** are refused (Spring reads the first).
- **A failed Basic login creates no session** (Spring's creates one
  through `/error`).
- **`SessionCreationPolicy`** has `ifRequired` (the default) and
  `stateless` only, not `always` and `never`.
- **`oauth2Login()`** also checks that the callback came to the redirect
  URI of its own login (no mixed-up registrations), and the RFC 9207 `iss`
  parameter (PKCE for every client, as Spring Security 7.1). The OAuth2
  client's `TokenEndpointOidcIdTokenDecoder` (it trusts the token
  endpoint's TLS) is never taken for it: ID token signatures are always checked. The login
  page never shows why a login failed. With both OAuth2 clients and a
  `JwtDecoder`, the default chain accepts bearer tokens too (Spring Boot's
  has `oauth2Login()` only). The callback reads the response from the
  query of a `GET`, or from the form of a `POST` for a registration with
  `response-mode=form_post` (Spring sends no `response_mode` and reads
  the parameters of any method; here a `HEAD`, `PUT`, ... callback fails
  with `invalid_request` and leaves the login in progress alone); the
  callback's `POST` is exempt from CSRF by itself, the `state`
  protecting it. A registration without `issuer-uri` cannot check the
  `iss` parameter (nothing to compare with); its callback path keeps it
  apart from the other registrations. The `apple` common provider
  and the JWT client secret (`client-secret-jwt.*`) are additions.
  Compared with Spring
  Security 7.1 by the differential test (the same browser steps against
  the same fake OpenID Connect provider): the redirect to the provider,
  the login and the saved page, wrong, missing and replayed `state`, the
  callback in another browser, provider errors, used and injected codes,
  ID tokens of another audience or nonce and the OpenID Connect logout end
  the same. What differs: a redirect back whose `iss` is not the issuer
  (Spring logs the user in), a redirect back to another registration's
  callback (Spring logs the user in), an unknown registration id (Spring:
  `500`, then the login through `/error`; here `400`), and a failed login
  creates no session (Spring keeps the exception in a new one).

- **DPoP** (RFC 9449; compared with Spring Security 7.1 by the
  differential test, 32 requests: the valid proof and the attacks of
  `test/dpop_test.dart`, tokens of other types and certificate-bound
  tokens, all answered as Spring does; and 4 state-changing token
  requests with CSRF on): DPoP-bound tokens are accepted by default
  (Spring 7.1 needs `oauth2ResourceServer(o -> o.dPoP(...))`); `htu` is
  compared as RFC 9449 §4.3 says, after RFC 3986 normalization and
  without its query (Spring compares the text: a host in capitals or a
  query fails there); `htm` is case-sensitive, as HTTP methods are
  (Spring ignores case). A DPoP-bound token sent as `Bearer` is refused,
  as in Spring (RFC 9449 §7.2), with one failure event (Spring publishes
  a success first); the challenges' error codes are Spring's. Requests
  with `Authorization: DPoP` and a `DPoP` proof need no CSRF token, as
  `Bearer` ones (Spring's `registerDefaultCsrfOverride` exempts `Bearer`
  only, so with CSRF on its chain answers a DPoP `POST` with `403`): a
  browser never sends either header by itself, and the token decides.
  The proof's key is compared with `cnf.jkt` before its `jti` is
  recorded (Spring records the `jti` first), and the `jti` is kept until
  `iat` + skew + 5 seconds (Spring: `iat` + skew, so a purge at that
  moment could let the proof through once more).
  The used proof ids go to a
  `DPoPProofJtiCache` (Spring: a `Cache`), and the proof's checks are
  changed with a `DPoPProofJwtDecoderFactory` bean (Spring has no
  setting for them); the error code is the `invalidDPoPProof` constant
  (Spring: `OAuth2ErrorCodes.INVALID_DPOP_PROOF`). No `DPoP-Nonce`
  challenges, as in Spring's resource server.

Also not there yet (the full list:
[docs/security-spring-comparison.md](../docs/security-spring-comparison.md);
planned in [roadmap/spring_boot_starter_security.md](../roadmap/spring_boot_starter_security.md)):

- **Logins:** `rememberMe()`, `oneTimeTokenLogin()`, passkeys
  (`webAuthn()`), `x509()`, pre-authentication by a proxy's header,
  switch user, multi-factor authentication.
- **Sessions:** `maximumSessions` and the session registry,
  `invalidSessionUrl`.
- **OAuth 2.0:** `oauth2Client()` and `@RegisteredOAuth2AuthorizedClient`,
  OIDC back-channel logout (`oidcLogout()`), opaque tokens
  (`opaqueToken()`), several issuers in one chain
  (`JwtIssuerAuthenticationManagerResolver`), bearer tokens in a form
  body, certificate-bound access tokens over mTLS (RFC 8705; refused
  until then), `jwt.public-key-location`.
- **SAML 2.0** (`saml2Login()`): left out on purpose, it needs an XML
  signature stack.
- **Other:** `csrf.spa()`, `redirectToHttps()`, `hasIpAddress`,
  `web.ignoring()`, `PathRequest`, observability, the `oauth2Login()` /
  `oidcLogin()` test post-processors and the `authenticated()` result
  matchers.

How the packages are shown to be safe: [docs/security.md](../docs/security.md).
