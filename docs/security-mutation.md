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
