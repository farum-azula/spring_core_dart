# The guides

Two applications of one bookstore, NEON Books, that use everything the
family offers, written to be read chapter by chapter: each chapter says
what it shows, which files to open, what to try and which test proves it.
The documentation links to their chapters.

| Folder | What | Run |
|---|---|---|
| [`server_guide/`](server_guide/README.md) | The bookstore's server: beans, configuration, a REST API with files and server-sent events, Spring Security (sessions, CSRF, roles, method security, single sign-on with Keycloak), WebSocket, events and AOP, cache, scheduling, Feign, validation, logging, testing, the advanced extension points | `dart run bin/main.dart` |
| [`flutter_guide/`](flutter_guide/README.md) | The bookstore's Flutter app, a client of the server: state in beans, themes and texts from properties, assets, Feign clients and a WebSocket with a session, login and roles, single sign-on with Keycloak, cache, scheduling, validation, a log screen, widget tests, goldens and end-to-end tests against the server | `flutter run` |
| [`themes/neon_ui/`](themes/neon_ui/README.md) | A design system as a library: widgets for apps of type `widgets` and a theme in YAML (references, color objects, nested tokens, `styles.*`, animations, a background), with fonts | a library: `flutter test` |
| [`themes/neon/`](themes/neon/README.md) | An app of type `widgets` (no Material, no Cupertino) built from `neon_ui`: states, the glow modal, the background, tokens, logs, a theme that `extends` the library's | `flutter run` |
| [`themes/material/`](themes/material/README.md) | A Material theme showcase: every part of the theme in YAML, on a `MaterialApp` | `flutter run` |
| [`themes/cupertino/`](themes/cupertino/README.md) | A Cupertino theme showcase: a `CupertinoApp` themed from YAML, Cupertino widgets only | `flutter run` |
| [`static_site/`](static_site/README.md) | A Flutter web site served by its own Spring server: the files of `flutter build web` and an API on one port, the app's addresses answered with `index.html` | `flutter build web`, then `dart run bin/main.dart` |
| [`supabase/`](supabase/README.md) | A todo list on a Supabase project (`spring_boot_starter_supabase`): a Flutter app (sign-in, a live list, an avatar in Storage, an Edge Function) and a server (the project's tokens as bearer tokens, SQL with transactions as the caller, a role check), with the project for the Supabase CLI beside them | `supabase start`, then `dart run bin/main.dart` and `flutter run` |
| [`seo_site/`](seo_site/README.md) | A Flutter web site that search engines, link previews and language models can read: a page per route and Markdown file, `sitemap.xml`, `robots.txt`, `llms.txt` (`spring.flutter.web.seo.*`, `@RouteInfo`) | `dart run build_runner build`, then `flutter build web` |
| [`scene/`](scene/README.md) | 3D scenes among Flutter widgets (`spring_boot_starter_flutter_scene`): a model named in the properties, the application's scene under the page, a scene behind a widget, the scenes' tab of the debug panel; every platform set up | `flutter run` |
| [`bloc/`](bloc/README.md) | Bloc and Cubit as beans, with no starter for them: a Cubit for the app, a Bloc with an injected service, a Cubit that lives as long as one screen, their events and state changes heard with `@EventListener` | `flutter run` |

The three designs together are explained in [`themes/`](themes/README.md).

[`keycloak/`](keycloak/README.md) is the identity provider of their
single sign-on (`docker compose up`): a realm with the same users, a
client for the server and one for the app.

Both are kept working by CI: their tests, the generated code, the app's
end-to-end tests against the running server, the server as minified
JavaScript and the app's golden screenshots.
