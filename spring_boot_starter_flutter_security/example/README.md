# spring_boot_starter_flutter_security: example

A Flutter app that logs its user in with Keycloak, keeps a PIN's
settings as a secret, and shows what the user may do.

[`example.dart`](example.dart) is the whole app:

- `Account` is a service on `OAuth2LoginService`, the app login:
  `restore` brings back the last run's user, `login` opens the system's
  login window (a Safari sheet on iOS and macOS, a Chrome tab on Android,
  the default browser with a loopback redirect on Windows and Linux),
  `logout` revokes the tokens. It keeps the PIN's settings with
  `SecretTemplate`, as JSON in the Keychain or the Keystore under the key
  `app.pin`.
- The app bar's title is a `PrincipalBuilder`: the user's name after a
  login, `Guest` after a logout.
- `PrincipalView(hasRole: 'ADMIN', ...)` shows the admin tools to admins
  only, and `PrincipalView(authenticated: false, ...)` the sign-in button
  to nobody logged in. For display only: the server checks access.

The generator writes `example.spring.dart` from it
(`dart run build_runner build`).

## Run it

`example.dart` lives inside the package, which has no platform folders.
To run it, make an app around it, add the Keycloak registration of the
package README to `lib/resources/application.properties`, and on Android
declare the redirect activity (README, "Android: declare the redirect"):

```sh
flutter create pin_app && cd pin_app
flutter pub add spring_boot_starter_flutter_security
flutter pub add dev:build_runner dev:spring_core_dart_generator
# copy example.dart to lib/main.dart, and change its import
# 'example.spring.dart' to 'main.spring.dart'
dart run build_runner build
flutter run
```

A complete app, with Keycloak in Docker: the
[Flutter guide](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide).
