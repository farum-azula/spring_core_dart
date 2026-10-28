# The guides

Two applications of one bookstore, NEON Books, that use everything the
family offers, written to be read chapter by chapter: each chapter says
what it shows, which files to open, what to try and which test proves it.
The documentation links to their chapters.

| Folder | What | Run |
|---|---|---|
| [`server_guide/`](server_guide/README.md) | The bookstore's server: beans, configuration, a REST API with files and server-sent events, Spring Security (sessions, CSRF, roles, method security, single sign-on with Keycloak), WebSocket, events and AOP, cache, scheduling, Feign, validation, logging, testing, the advanced extension points | `dart run bin/main.dart` |
| [`flutter_guide/`](flutter_guide/README.md) | The bookstore's Flutter app, a client of the server: state in beans, themes and texts from properties, assets, Feign clients and a WebSocket with a session, login and roles, single sign-on with Keycloak, cache, scheduling, validation, a log screen, widget tests, goldens and end-to-end tests against the server | `flutter run` |

[`keycloak/`](keycloak/README.md) is the identity provider of their
single sign-on (`docker compose up`): a realm with the same users, a
client for the server and one for the app.

Both are kept working by CI: their tests, the generated code, the app's
end-to-end tests against the running server, the server as minified
JavaScript and the app's golden screenshots.
