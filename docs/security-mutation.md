# Mutation testing of the security packages

Passing tests show little if they would also pass with broken code.
Mutation testing checks that: `tool/mutation_test.dart` changes the code
in one small way at a time and runs the package's tests against each
change. Typical changes: a flipped condition, `true` ↔ `false`, `==` ↔
`!=`, `&&` ↔ `||`, a bound off by one, a dropped `!`, `isEmpty` ↔
`isNotEmpty`, `any` ↔ `every`. The differential tests are left out, since
they need the Spring application.

A change that no test notices is a missing test, unless it changes nothing
anyone can observe. This is section 5 of
[roadmap/security_verification.md](../roadmap/security_verification.md).

```sh
dart run tool/mutation_test.dart spring_security_core \
  $(cd spring_security_core && find lib/src -name '*.dart' ! -name 'offload_*')
dart run tool/mutation_test.dart spring_boot_starter_security \
  $(cd spring_boot_starter_security && find lib/src -name '*.dart')
```

| Package | Mutants (compiling) | Noticed | Score |
|---|---|---|---|
| `spring_security_core` | 264 | 259 | 98.1 % |
| `spring_boot_starter_security` | 356 | 351 | 98.6 % |
| `spring_boot_starter_security`, DPoP (`lib/src/jwt/dpop.dart`) | 70 | 68 | 97.1 % |
| `spring_boot_starter_security`, `oauth2Login()` (`lib/src/oauth2/`) | 61 | 56 | 91.8 % (the 5 changes not noticed are in the table below) |
| `spring_boot_starter_oauth2_client`: the ID token validator, the DPoP proof builder, the authorization request and response | 35 | 35 | 100 % |

The last three rows were measured in October 2026, for the SSO and DPoP
code. `--test` runs the named test files first and the whole suite only
for a change they did not notice, so a run takes minutes:

```sh
dart run tool/mutation_test.dart spring_boot_starter_security lib/src/jwt/dpop.dart \
  --test test/dpop_test.dart --test test/dpop_client_test.dart
dart run tool/mutation_test.dart spring_boot_starter_security \
  $(cd spring_boot_starter_security && ls lib/src/oauth2/*.dart) \
  --test test/oauth2_login_test.dart --test test/oauth2_login_parts_test.dart \
  --test test/oauth2_login_auto_configuration_test.dart
dart run tool/mutation_test.dart spring_boot_starter_oauth2_client \
  lib/src/oidc/oidc_id_token_validator.dart lib/src/dpop/dpop_proof_builder.dart \
  lib/src/endpoint/authorization_request.dart
```

Their first runs noticed 68.6 % (DPoP), 70.5 % (`oauth2Login()`) and
77.1 % (the client) of the changes. The tests added for the rest: the
`jti` cache's limits and purges (a size of 1, the purge every 10 seconds
and, when full, after 50 ms, for the whole cache and per key), the RSA
keys of proofs (2 048 and 8 192 bits exactly, an even, too small or too
long exponent), a proof of exactly the largest length (in the factory and
in the filter), HMAC beside RS256 refused, no `error_uri` in DPoP
challenges (`test/dpop_test.dart`); no session created by reading or
removing the saved login and the authorized clients, the provider's
login authenticated, the logout's absolute URLs in capitals behind a
context path (`test/oauth2_login_parts_test.dart`); the authorization
response's `statusError` and its parameters given twice
(`spring_boot_starter_oauth2_client/test/token_endpoint_test.dart`).
Not measured: the `oauth2Login()` parts of `http_security.dart` (the
configurer: a run over the whole file takes hours), and the app login's
own checks of the redirect (`NativeOAuth2LoginService` of
`spring_boot_starter_flutter_security`: its tests run with
`flutter test`, which the tool does not).

The DPoP and `oauth2Login()` changes nothing notices:

| Where | Change | Why nothing changes |
|---|---|---|
| `dpop.dart:225` | `left <= 0` → `< 0` | A key's count of 0 is kept instead of removed: it reads as no entry (`?? 0`). |
| `dpop.dart:408` | `parsed.hasPort && parsed.port != defaultPort` → `\|\|` | Dart's `Uri` drops a default port, so `hasPort` already means another port. |
| `authorization_request_redirect.dart:155` | `getSession(create: false)` → `true` | Reached only when a saved request was found, so there is a session. |
| `login.dart:567` | `result.principal == null \|\| result.accessToken == null` → `&&` | The token's constructors set both or neither. |
| `oidc_logout.dart:155` | `full.length > path.length` → `>=` | With equal lengths the context path is the empty text either way. |
| `oidc_logout.dart:158` | `full.length > 1` → `>=` | A full path of one character is `/`: the context path is empty either way. |
| `oidc_logout.dart:159` | `full.length - 1` → `+ 1` | Unreachable: a full path ending in `/` is handled by the first `if`. |

The `response_mode=form_post` code was first measured while being
written: 7 changes went unnoticed (80.3 %), a posted response with `code`
or `error` (not only `state`) in the query and the warning about a session
cookie that a cross-site POST did not bring (logged once). The tests added
in `test/oauth2_form_post_test.dart`: a form post with `code`, `error` or
`state` in the query is refused and leaves the login alone; the warning is
logged once, by a post without a session only (not by a GET, nor by a post
with a session), and holds neither the code nor the state.

The first honest run noticed only 62 % of the changes in the starter (an
earlier bug in the tool had produced unchanged "mutants"). 137 changes
went unnoticed, mostly in the firewall's defensive checks, the cookie CSRF
repository, the configurers' options and the JWT key checks. The tests
added for them are the files of `test/` named after those parts
(`firewall_test.dart`, `csrf_test.dart`, `http_security_test.dart`,
`jose_test.dart`, ...).

## The changes no test can notice

Each one was checked by reading the code; none changes behaviour. The
line numbers are those of the current code.

| Where | Change | Why nothing changes |
|---|---|---|
| `spring_security_core` `password_encoder.dart:414` | `bytes.length <= saltLength` → `<` | With exactly a salt and no hash, the next check (`expected.length != hashBytes`) refuses it too. |
| `password_encoder.dart:577` | `encoded.length < 2` → `<= 2` | An scrypt hash needs three `$`; no 2-character text parses either way. |
| `password_encoder.dart:759` | `end < 0` → `<= 0` | The text starts with `{`, so `}` is never at index 0. |
| `method_security_interceptor.dart:242` | `invocation is AsyncMethodInvocation && result is Future` → `\|\|` | The generator makes every method returning a `Future` an `AsyncMethodInvocation`, and an async invocation always returns a `Future`. |
| `method_security_interceptor.dart:255` | `read = true` → `false` | It is only a cache: the context is read again, with the same result, in the same call. |
| `spring_boot_starter_security` `jose.dart:189` | `y >= p` → `y > p` | `y = p` is `y ≡ 0`, a point of order 2. P-256, P-384 and P-521 have prime order, so no such point exists, and the curve check refuses it anyway. |
| `jose.dart:394` | the `default` branch `false` → `true` | Unreachable: `VerificationKey` is sealed, and the key type was matched to the algorithm before. |
| `jwt_decoder.dart:99` | the default of `refresh` in the abstract `JwkSource.keys` | Dart uses the default of the implementation that is called. |
| `jwt_decoder.dart:113` | the default of `refresh` in `StaticJwkSource.keys` | A static source ignores `refresh`. |
| `filter_chain.dart:189` | the marker attribute `true` → `false` | Only its presence is read (`containsKey`). |

The calls into `pointycastle` were later moved into one file per package
(`kdf_primitives.dart` and `signature_primitives.dart`, see
[dependencies.md](dependencies.md#pointycastle-third-party-to-be-removed)).
`jose.dart` and `signature_primitives.dart` were checked again after the
move, with the same two unnoticed changes as before.

One more unnoticed change pointed at dead code instead: the firewall's
`_printable` had an `allowSpace` parameter that every caller set to
`false`. It was removed.
