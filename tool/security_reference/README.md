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
