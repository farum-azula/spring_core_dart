# security_reference

The Spring side of the security verification
([roadmap/security_verification.md](../../roadmap/security_verification.md)):
a Spring Boot application (Spring Security 7, Java 21, Maven) the Dart
security packages are compared with.

```sh
cd tool/security_reference
mvn -q -DskipTests package
run() { java -Dloader.main=dev.farumazula.reference.$1 -cp target/security-reference-0.0.0.jar \
  org.springframework.boot.loader.launch.PropertiesLauncher "${@:2}"; }
```

## The requests of the differential test

`spring_boot_starter_security/test/differential_test.dart` starts the jar
three times: as it is (the rules of `ReferenceApplication`), with the
profile `oauth2` (`OAuth2LoginReference`: `oauth2Login()` with one
registration, `fake`, from `application-oauth2.properties`, and the
OpenID Connect logout) and with the profile `dpop`
(`DPoPResourceServerReference`: Spring Boot's resource server chain with
`dPoP()`). For the last two the test starts its fake OpenID Connect
provider first and passes its address
(`--spring.security.oauth2.client.provider.fake.issuer-uri=...`, which
Spring discovers at startup, or
`--spring.security.oauth2.resourceserver.jwt.jwk-set-uri=...`). The Dart
applications get the same requests.

## Password hashes, both ways

Spring writes hashes with its encoders (Argon2, PBKDF2, scrypt with
`defaultsForSpringSecurity_v5_8`, and the delegating encoder); the Dart tests
check them (`spring_security_core/test/password_encoder_test.dart`):

```sh
run PasswordVectors write ../../spring_security_core/test/vectors/spring_password_hashes.json
```

The Dart encoders write hashes; Spring checks them (every line `ok`):

```sh
(cd ../../spring_security_core && dart run test/vectors/write_password_hashes.dart \
  test/vectors/dart_password_hashes.json)
run PasswordVectors check ../../spring_security_core/test/vectors/dart_password_hashes.json
```

What the comparison found so far:

- Spring Security 7 never matches an empty password (it still hashes one):
  the Dart encoders do the same.
- Spring's delegating encoder writes `{bcrypt}`, which the Dart side does
  not check (no vetted BCrypt): it fails with an error saying so; Dart writes
  `{argon2}`, which Spring checks.
