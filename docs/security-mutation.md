# Mutation testing of the security packages

[roadmap/security_verification.md](../roadmap/security_verification.md),
section 5: `tool/mutation_test.dart` changes the code one small way at a
time (a flipped condition, `true` ↔ `false`, `==` ↔ `!=`, `&&` ↔ `||`, a
bound off by one, a dropped `!`, `isEmpty` ↔ `isNotEmpty`, `any` ↔
`every`, ...) and runs the package's tests (without the differential
ones, which need the Spring application). A change no test notices is a
missing test, unless it changes nothing anyone can observe.

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

The first honest run (after a bug in the tool that produced unchanged
"mutants" was fixed) noticed 62 % in the starter: 137 changes, mostly in
the firewall's defensive checks, the cookie CSRF repository, the
configurers' options and the JWT key checks, went unnoticed. The tests
added for them are the files of `test/` named after those parts
(`firewall_test.dart`, `csrf_test.dart`, `http_security_test.dart`,
`jose_test.dart`, ...).

## The changes no test can notice

Each was checked by reading the code; none changes behaviour.

| Where | Change | Why nothing changes |
|---|---|---|
| `spring_security_core` `password_encoder.dart:337` | `bytes.length <= saltLength` → `<` | With exactly a salt and no hash, the next check (`expected.length != hashBytes`) refuses it too. |
| `password_encoder.dart:485` | `encoded.length < 2` → `<= 2` | An scrypt hash needs three `$`; no 2-character text parses either way. |
| `password_encoder.dart:629` | `end < 0` → `<= 0` | The text starts with `{`, so `}` is never at index 0. |
| `method_security_interceptor.dart:210` | `invocation is AsyncMethodInvocation && result is Future` → `\|\|` | The generator makes every method returning a `Future` an `AsyncMethodInvocation`, and an async invocation always returns a `Future`. |
| `method_security_interceptor.dart:223` | `read = true` → `false` | Only a cache: the context is read again, with the same result, in the same call. |
| `spring_boot_starter_security` `jose.dart:157` | `y >= p` → `y > p` | `y = p` is `y ≡ 0`, a point of order 2; P-256, P-384 and P-521 have prime order, so none exists and the curve check refuses it anyway. |
| `jose.dart:344` | the `default` branch `false` → `true` | Unreachable: `VerificationKey` is sealed, and the key type was matched to the algorithm before. |
| `jwt_decoder.dart:52` | the default of `refresh` in the abstract `JwkSource.keys` | Dart uses the default of the implementation that is called. |
| `jwt_decoder.dart:65` | the default of `refresh` in `StaticJwkSource.keys` | A static source ignores `refresh`. |
| `filter_chain.dart:126` | the marker attribute `true` → `false` | Only its presence is read (`containsKey`). |

The calls into `pointycastle` were later moved into one file per package
(`kdf_primitives.dart`, `signature_primitives.dart`, see
[dependencies.md](dependencies.md#pointycastle-third-party-to-be-removed));
`jose.dart` and `signature_primitives.dart` were checked again after the
move, with the same two unnoticed changes as before.

One more change that went unnoticed pointed at dead code instead: the
firewall's `_printable` had an `allowSpace` parameter every caller set to
`false`. It was removed.
