# Roadmap

Plans and sketches of coming features, one file per package. Each file says
what is done and what is planned; code in the sketches shows the intended
API and may change. Nothing here is promised in a fixed order.

Rules every plan follows:

- Spring first: Spring's names and behaviour, and where a feature differs
  from Spring (or does not exist there), the docs say so.
- No reflection: everything is generated at build time, so it works in AOT
  executables, Flutter and minified JavaScript.
- Property names: Spring Boot's key where Boot has one (renamed only where
  its name is Java history: see the renamed properties in
  [docs/configuration.md](../docs/configuration.md)); a key of our own sits
  under its starter (`spring.flutter.*`, `spring.data.*`). A key that only
  one kind of platform reads carries it as a segment, so its name says
  where it applies: `spring.flutter.web.*`, `spring.flutter.desktop.*`,
  `spring.flutter.security.web.mode`. A value for one OS goes into its
  platform profile file (`application-macos.properties`), not into a key
  per OS.
- Dependencies: the runtime packages use only this repository, the Dart and
  Flutter SDKs and packages of the Dart, Flutter and Google teams. A package
  nothing here should replace (Flutter Scene, signals, a Rust bridge,
  database drivers) is an exception allowed only in its own starter
  (`tool/check_dependencies.dart`).
- Fewest dependencies for the user: an application lists only what it
  chooses — `spring_boot_dart` (or one starter) and, as a dev dependency,
  the generator. Everything a package builds on comes with it and is
  re-exported, so its code is usable without listing it and the analyzer
  never asks for it (`depend_on_referenced_packages`): nobody adds
  `spring_core_dart` next to `spring_boot_dart`, or `spring_web_dart` next
  to Feign. See [dependencies.md](dependencies.md).

## Priorities

**First, as soon as possible (the owner, November 2026): the generator,
one module per starter** ([generator_by_starter.md](generator_by_starter.md)):
a folder and one interface per starter in the generator, a part runs only
when the application depends on its starter, tests per part; no change of
the generated code. Before any new starter adds to the generator.

What comes next, in order:

1. ~~**Files on the web starter:** multipart uploads (`MultipartFile`,
   `@RequestPart`), `Resource` responses (`ByteArrayResource`,
   `FileSystemResource`, `Range` requests), byte streams and
   `StreamingResponseBody`, `MockMvc.multipart`, multipart bodies in
   Feign.~~ Done; what is left (byte-range lists, `ETag`, streamed Feign
   uploads) is in [spring_boot_starter_web.md](spring_boot_starter_web.md#files-multipart-resources-byte-streams).
2. ~~**Spring Security** ([spring_security_core](spring_security_core.md),
   [spring_boot_starter_security](spring_boot_starter_security.md)), with
   the verification plan of [security_verification.md](security_verification.md):
   it must be shown to be safe, not assumed.~~ Done, with the evidence of
   [docs/security.md](../docs/security.md); what is left (BCrypt, multi-factor,
   session registry, opaque tokens) is in the two files; the ZAP scan runs
   in CI (October 2026).
3. ~~**Documentation comments, first after the 0.4.x release**
   ([documentation.md](documentation.md)): every `///` of every package
   rewritten to say what the thing is, why it exists and when you need it,
   understandable without knowing Spring.~~ Done (October 2026): the `///`
   comments, the READMEs and `docs/`.
4. ~~**Single sign-on** ([spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md)):
   OAuth 2.0 / OpenID Connect for servers (`oauth2Login()`) and apps
   (PKCE, tokens in the Keychain / Keystore).~~ Done (October 2026), with
   Keycloak in the examples; the differential test against Spring and
   mutation testing are done too (October 2026); what is left is in the
   file.
5. ~~**Flutter security**~~ Done (October 2026) ([spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md)):
   ~~the SSO's platform code out of `spring_boot_starter_flutter` into
   `spring_boot_starter_flutter_security` (apps without a login carry
   none of it), the app login out of the OAuth2 client (which is now
   exactly Spring's), `SecretStore` / `SecretTemplate` for the app's own
   secrets, display-only widgets that follow the user~~ (done, October
   2026); ~~login screens and
   provider buttons (Google, Apple, Microsoft, GitHub)~~ (done, October
   2026), ~~DPoP's native
   keys in the apps~~ (done, October 2026), ~~the web login without a
   server (`spa` mode, the WebCrypto key)~~ (done, October 2026), the
   SSO's hardening (done, October 2026; the Windows and Linux stores
   run in CI; left for devices: cancelling on iOS, https redirects).
6. **The review before 0.5.0** ([review_0_5.md](review_0_5.md)), after the
   security patch (0.4.3): every package checked for bugs and differences
   against Spring 7 / Boot 4 / Security 7 like the October 2026 reviews
   (the new OAuth2 client, `oauth2Login()`, DPoP and the Flutter security
   package first), a security review of everything since 0.4.2, the
   dependencies' known vulnerabilities (Dart, Gradle, Swift), the threat
   model and ASVS checklist extended, the ZAP scan; then **0.5.0**, the
   minor release.
7. ~~**The data starter**~~ Done, to be released as 0.6.0 (checklist:
   [release_0_6.md](release_0_6.md)) ([spring_boot_starter_data.md](spring_boot_starter_data.md);
   the owner's order, October 2026): Spring Data JDBC's model, one
   starter without drivers (the application's `postgres` / `sqlite3`
   wired by the generator), several databases, transactions with the
   propagation × isolation test matrix, `@Version` and `@Lock`,
   `JdbcTemplate` / `JdbcClient`, containers in tests
   ([spring_boot_starter_test.md](spring_boot_starter_test.md)). Redis is out of 0.6.0, postponed
   indefinitely (the owner, November 2026).
8. **The Supabase starter**, after the generator's split by starter
   ([spring_boot_starter_supabase.md](spring_boot_starter_supabase.md)):
   our own client (no Supabase packages), everything as Spring beans in
   the first version: the database through Spring Data (PostgreSQL by
   `db.url`, else PostgREST, decided at build time), Auth through Spring
   Security front and back (one session, ours), Realtime as streams (a
   Phoenix Channels client in the WebSocket starter first), Storage as
   `StorageTemplate`, Edge Functions as an interface; nothing about
   Supabase in the generator.
9. **The edge starter** ([serverless.md](serverless.md)), after the
   Supabase starter, so an Edge Function on Supabase uses it:
   Spring Boot for Dart applications compiled to JavaScript behind a
   fetch handler, first on Supabase Edge Functions (Supabase's
   environment and Auth JWTs, deploys from GitHub Actions on every
   push), then Deno Deploy, Cloudflare Workers, Vercel and Netlify Edge.
   What the other starters cannot do fully there (timers, in-memory
   caches and sessions) is not blocked: the edge starter logs one
   warning list at start (the owner, November 2026; what cannot compile
   the compiler stops).
10. **0.6.2: the theme** (the owner, November 2026; branch `theme`), in
   the Flutter starter ([spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#typed-keys-from-the-configuration-generated)):
   - typed keys from the configuration: the generator writes getters for
     the theme's colors, spacing, text styles, tokens and theme names
     (`context.theme.colors.surfaceContainerLow`, `context.theme.spacing.m`)
     and for the messages (`context.messages.basket.total(sum)`); a renamed
     key fails the build, not the app (assets and routes later) — done,
     from the `spring_flutter_keys` builder;
   - the components' states (hovered, pressed, focused, disabled) and every
     component theme of Flutter (about 50, today 16) and Cupertino's — no
     generated widgets;
   - the theme from a URL or GitHub under a name of the app's choice,
     cached through `FileTemplate`, a new bean for the app's files (kept,
     cache, documents, temporary; a replaceable `FileStore`);
   - `resources:` in place of `classpath:` (the prefix that points into
     `lib/resources/`; `classpath` is Java history like `servlet` and
     `jackson`): `resources:` everywhere a location is read
     (`spring.config.import`, `@PropertySource`,
     `spring.sql.migration.locations`, ...); `classpath:` is not a location.
   Then **0.6.3: themes without Dart** (done, unreleased; the owner, November 2026; branch
   `theme`; [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#themes-without-dart-063-the-owner-november-2026)):
   the generated keys in `lib/spring_gen/theme.spring.keys.dart` / `lib/spring_gen/messages.spring.keys.dart`
   as parts of the main `.spring.dart`; references (`$colors.primary`) and
   color objects; nested tokens; `styles.*` with states and
   `ThemeStates`; typed motion and `animations.*` with `ThemeAnimation`;
   the background in the theme (`ThemeBackground`); images from the
   network with a persistent cache (`ThemeImage`) — all done in 0.6.3
   (unreleased); the example is `example/themes/neon` with its
   design system as a library (`example/themes/neon_ui`; since November 2026 in [farum-azula/themes](https://github.com/farum-azula/themes), released by tags), next to a Material
   and a Cupertino showcase (`example/themes/`), later a repository of
   its own used as a library.
   Then **the release after 0.7.0** (the owner,
   November 2026): navigation, deep links, SEO, Markdown and the screen
   map, released together; what goes into which package is in
   [spring_boot_starter_flutter_navigation.md](spring_boot_starter_flutter_navigation.md#the-release-what-goes-where).
   With them, static resources in the web starter
   ([spring_boot_starter_web.md](spring_boot_starter_web.md#static-resources-the-navigation-patch-the-owner-november-2026)),
   verified hard in Docker, and the actuator's first part (`health`,
   `info`, `mappings`; [spring_boot_actuator.md](spring_boot_actuator.md#first-part-with-the-navigation-patch)).
   Three new packages: `spring_boot_starter_flutter_navigation`,
   `spring_boot_actuator`, `spring_boot_starter_actuator`.
   Built on the branch `feat/0.7.1` (November 2026): all of it, with
   tests; the static resources compared with Spring Boot (differential),
   their Docker fuzzing and ZAP run still to do; the actuator compared
   with Boot 4.1.2's (differential). Left in the files: the navigation's
   restored stack and constants per Markdown file, the deep links of
   Windows and Linux (later, the owner), embedding big static files.
   Then **the site** (the owner, November 2026): the documentation site
   built on Spring itself (a Flutter web app on the starters and the
   navigation starter); the guides, the examples and the docs move there.
   It must read well for other models too: `llms.txt` with a map of the
   docs, a plain Markdown page per topic, full examples to copy. A
   Flutter web page draws on a canvas, so search engines and models see
   no text; not a tool of the site's own but a feature of the starters
   (the owner, November 2026): `spring.flutter.web.seo.*` in the Flutter
   starter ([spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#search-engines-previews-and-models-springflutterwebseo))
   and `@Route(title:, content:)` / `@RouteInfo` in the navigation starter
   ([spring_boot_starter_flutter_navigation.md](spring_boot_starter_flutter_navigation.md#search-engines-seo-and-title)).
   The docs are Markdown in the site's `lib/resources/content/`; the app
   renders them with the theme (code colored by `styles.code.*`), and the
   build writes for every page `<path>/index.html` with its `<head>` and
   its text in plain HTML under the page loader, never shown and never
   removed, plus `<path>.md`, `llms.txt`, `llms-full.txt` and
   `sitemap.xml`; pages come from the routes, from Markdown folders in the
   configuration and from pages listed by hand. Hosted on Cloudflare
   Pages (the owner, November 2026; the free plan, with the domain): it
   serves `<path>/index.html` at `<path>`, and the build also writes its
   `_headers` (the security headers and the CSP of the configuration) and
   `404.html`. The way kept in mind: the site served by our own web starter,
   choosing by content negotiation like Spring MVC (`Accept:
   text/markdown` → Markdown, a crawler → HTML, a browser → the app).
11. **RestClient and RestTemplate** ([rest_client.md](rest_client.md)) in
   `spring_web_dart`, the `RestClient.Builder` bean in `spring_boot_dart`;
   `@HttpExchange` later.
12. ~~**Logging like Spring's**~~ Done after 0.5.0 (October 2026,
   unreleased; the owner moved it up): INFO by default without the logging
   starter, the framework's debug and trace lines with Spring's texts
   (container, web, WebSocket, security, OAuth2), the `web` and `sql`
   groups, `--debug` / `--trace`, `spring.mvc.log-request-details`,
   values from clients through `LogFormatUtils.formatValue` (no forged
   lines), the console on standard output (`print` in Flutter and on the
   web), guard tests that no secret reaches the log at trace; what is
   left is in [spring_core_dart.md](spring_core_dart.md#logging-like-springs).
13. **Spring AI** ([spring_ai.md](spring_ai.md)): chat and embedding models
   of the providers (Anthropic, OpenAI, Gemini, Ollama, ...) behind one
   `ChatClient`, all in one package (`spring_boot_starter_ai`).
14. **The web server after Netty, not Tomcat** (the owner's decision,
   October 2026; below the Flutter items by the owner's order; a minor
   release when it comes, since defaults change): Dart's server runs on
   one event loop, as Netty does, so its limits and defaults follow
   Spring Boot on Reactor Netty — only the server's behaviour; no
   WebFlux, no reactive API (handlers stay as they are). Go through what
   the reviews made "as Tomcat": the WebSocket message limits (Tomcat's
   8 KB vs Netty's 64 KB frame payload), the send-buffer limits (Netty's
   write-buffer water marks), compression and its `Vary` rules, the
   connection and idle timeouts (`server.netty.connection-timeout`,
   `server.netty.idle-timeout`), the request line and header limits
   (`server.netty.max-initial-line-length`, 8 KB of headers),
   `server.netty.max-keep-alive-requests`, header validation, bodiless
   answers, graceful shutdown. Boot's `server.netty.*` keys where Boot
   has them; each moved default in the CHANGELOG as breaking.
15. **MVC beyond REST** ([spring_boot_starter_web.md](spring_boot_starter_web.md),
   *MVC: views and static resources*): first find out whether it is worth
   it. Browser SSO on the server, `oauth2Login()` with OpenID Connect, is
   done without it
   ([spring_boot_starter_security](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)):
   Flutter web uses the server as its backend-for-frontend.
16. **Generated code: speed, size, platforms**, released in 0.7.0 (November 2026; what is left stays in the file) ([generated_code_performance.md](generated_code_performance.md)):
   a release of its own (the owner's decision, November 2026), measured
   before and after: no `Function.apply` in generated code, direct AOP
   when the chain is known, conditions and bean order decided by the
   build, smaller descriptions, `@pragma` where it pays, per-platform
   code through compile-time constants (deferred loading on the web),
   incremental output per library (a change regenerates only what
   depends on it), and `docs/codegen.md` describing every kind of
   generated code.
17. Later: [MCP](spring_ai_mcp.md) in the AI starter, the
   actuator, MongoDB, the rest of the table.
18. Under question, far off: **the starters on the generator** —
   `@AutoConfiguration` classes with `@Bean` methods instead of the
   hand-written `BeanDefinition`s of their auto-configurations. For now
   hand-written stays: it reads better for this code and needs no
   generator round trip; the beans an application gets are the same
   either way.
19. **What else the build can leave out** (the owner, November 2026; to
   think through before any change): `AutoConfigurationModule(build:
   AutoConfigurationBuild(...))` removes a module, and everything only it
   reaches, from the application or from release builds. Only the Flutter
   starter's debug panel uses it so far. Candidates, each with its gain in
   size and start time measured first: the actuator's endpoints in mobile
   apps, the parts of starters only development needs, and
   `@SpringBootApplication(exclude:)` decided by the build (today an
   excluded module stays in the code and only registers no beans).

| File | Package | Status |
|---|---|---|
| [generator_by_starter.md](generator_by_starter.md) | generator | planned, as soon as possible: a module per starter (folder, one interface to the core, runs only with its starter), tests per part, the generated code unchanged |
| [generated_code_performance.md](generated_code_performance.md) | generator, all packages | planned, a release of its own: faster and smaller generated code, incremental output per library (with the editor metadata per starter and properties typed in code instead of the hand file), per-platform branches, `docs/codegen.md` |
| [spring_core_dart.md](spring_core_dart.md) | `spring_core_dart`, generator | JSON next steps, Jakarta annotations under question (incremental generation moved to [generated_code_performance.md](generated_code_performance.md)) |
| [dependencies.md](dependencies.md) | all packages | what an application must list (one package and the generator), what each package re-exports, the gaps left |
| [fix_plan.md](fix_plan.md) | all packages | open differences from Spring 7 / Boot 4 found in reviews, how close each area is |
| [spring_boot_starter_web.md](spring_boot_starter_web.md) | `spring_boot_starter_web` | first version on `dart:io` behind a replaceable `WebServerFactory` (done): controllers, `ProblemDetail`, SSE and `SseEmitter`, files (multipart uploads, `Resource` downloads with `Range`, byte streams), filters, CORS, WebSocket endpoints, `MockMvc`, the slots for Spring Security; next: a shared session store, static files, forwarded headers, Flutter isolates (blocking warnings, JSON offload, background server), `shelf` |
| [spring_boot_actuator.md](spring_boot_actuator.md) | `spring_boot_actuator` | planned on the web starter: beans, env, conditions, loggers, logs, health — over HTTP, in the editor extensions, in apps |
| [spring_security_core.md](spring_security_core.md) | `spring_security_core` | done: security context, users, password encoders, method security; next: BCrypt, multi-factor |
| [spring_boot_starter_security.md](spring_boot_starter_security.md) | `spring_boot_starter_security` | done: filter chain, Basic, form login, OAuth 2.0 / OpenID Connect login (`oauth2Login`), sessions, CSRF, CORS, headers, JWT resource server; next: remember-me, session registry, opaque tokens |
| [security_verification.md](security_verification.md) | security packages | done except coverage in CI: threat model, attack catalog as tests, differential tests against Spring Security, fuzzing, test vectors, mutation testing, ASVS checklist, the ZAP baseline scan in CI |
| [spring_ai.md](spring_ai.md) | `spring_boot_starter_ai` | planned: `ChatClient`, the model providers in one package, streaming, tool calling, structured output, chat memory, embeddings |
| [spring_ai_mcp.md](spring_ai_mcp.md) | `spring_boot_starter_ai` | MCP, later (low priority); the web starter's prerequisites exist: MCP servers from beans (`@McpTool`, `@McpResource`, `@McpPrompt`), Streamable HTTP and stdio |
| [spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md) | `spring_boot_starter_oauth2_client` | done: Spring's OAuth2 client: registrations from `spring.security.oauth2.client.*`, discovery, the token endpoint of every grant with PKCE, authorized clients and their refresh, users, Bearer and DPoP tokens on Feign (DPoP `auto` by default), the token headers of WebSocket handshakes (`OAuth2AccessTokenHeaders`), the hardening (the plain `http://` warning, one discovery with the resource server, differential and mutation tests); next: runs on devices |
| [spring_boot_starter_data.md](spring_boot_starter_data.md) | `spring_boot_starter_data` | done, in 0.6.0: Spring Data JDBC's model, one starter without drivers (the application's `postgres` / `sqlite3` wired by the generator), SQLite and PostgreSQL (Redis postponed indefinitely), `@Transactional` compared with Spring's propagation and isolation matrix, `@Version`, `@Lock`, SpEL in `@Query` compiled by the build, migrations, `@DataTest`, `JdbcTemplate` and `JdbcClient`; what is left is in the file |
| [release_0_6.md](release_0_6.md) | all packages | the checklist of the 0.6.0 release: what was verified, what remains before the Release button |
| [spring_boot_starter_supabase.md](spring_boot_starter_supabase.md) | `spring_boot_starter_supabase` | planned after the generator's split by starter: our own client, Spring Data (SQL by `db.url`, else PostgREST), Spring Security front and back, Realtime as streams, `StorageTemplate`, Edge Functions; nothing about Supabase in the generator |
| [spring_boot_starter_retry.md](spring_boot_starter_retry.md) | `spring_boot_starter_retry` | planned: `@Retryable`, `@Recover` |
| [review_0_5.md](review_0_5.md) | all packages | planned: the review before 0.5.0 (bugs and differences from Spring, security, vulnerabilities), then the minor release |
| [serverless.md](serverless.md) | `spring_boot_starter_edge` | built (November 2026): Spring Boot for Dart applications on Supabase Edge Functions, Cloudflare Workers, AWS Lambda, Deno Deploy, Netlify and Vercel, as JavaScript or WebAssembly, with a deploy workflow; not yet: more Cloudflare bindings, Azure and Google Cloud Functions |
| [rest_client.md](rest_client.md) | `spring_web_dart`, `spring_boot_dart` | planned: `RestClient`, `RestTemplate` (no package of its own), later `@HttpExchange` |
| [spring_boot_starter_feign.md](spring_boot_starter_feign.md) | `spring_boot_starter_feign` | next steps: files and forms, `FallbackFactory`, circuit breaker |
| [spring_boot_starter_websocket.md](spring_boot_starter_websocket.md) | `spring_boot_starter_websocket` | clients and server endpoints (on the web starter) done; next: STOMP, connection state |
| [spring_boot_starter_scheduling.md](spring_boot_starter_scheduling.md) | `spring_boot_starter_scheduling` | next: `TaskExecutor` (a pool of worker isolates), `@Async` on it |
| [spring_boot_starter_cache.md](spring_boot_starter_cache.md) | `spring_boot_starter_cache` | next: persistent stores |
| [spring_boot_starter_test.md](spring_boot_starter_test.md) | `spring_boot_starter_test` | test classes with annotations and containers in tests (Docker client of our own, `@Container`, `@ServiceConnection`, Ryuk; done, [docs/testing.md](../docs/testing.md)); next: editor run buttons and snippets, Windows' named pipe, Docker Compose for development |
| [spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md) | `spring_boot_starter_flutter_test` | planned: Flutter tests on top of the test starter (`@WidgetTest`, `pumpSpring`, themes, platforms, goldens), spec in [docs/flutter-testing.md](../docs/flutter-testing.md) |
| [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md) | `spring_boot_starter_flutter_security` | done: the app login (`OAuth2LoginService`, the login windows) moved out of the OAuth2 client, the platform code of logins and secrets out of the Flutter starter, `SecretStore` / `SecretTemplate`, display-only widgets that follow the user (`PrincipalNotifier`, `PrincipalBuilder`, `PrincipalView`), the web login in server mode (backend-for-frontend, `ServerOAuth2LoginService`) and in spa mode (the browser logs in, `SpaOAuth2LoginService`, a non-extractable WebCrypto DPoP key), DPoP keys of the apps (`PlatformDPoPKey`: Secure Enclave / Keychain, Android Keystore, `SecretStore`); login screens (`LoginForm`, `OAuth2LoginButton`, the Google, Apple, Microsoft and GitHub buttons), the hardening (October 2026); next: its runs on devices (the Windows and Linux stores' first CI run, iOS cancel, https redirects) |
| [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md) | `spring_boot_starter_flutter` | first version: `SpringApplicationWidget`, beans in widgets, lifecycle, platform profiles; the app widget and themes from properties (done; the secret store and login window moved to `spring_boot_starter_flutter_security`), the desktop window from properties (0.6.1: title, transparent or hidden title bar, initial, minimum and maximum size, `DesktopWindow`, `WindowDragArea` on macOS, Windows, Linux), next: navigation, settings |
| [flutter_spring_signals.md](flutter_spring_signals.md) | `flutter_spring_signals` | planned: `@Signal` fields |
| [flutter_spring_scene.md](flutter_spring_scene.md) | `flutter_spring_scene` | planned: Flutter Scene (3D) |
| [flutter_spring_rust.md](flutter_spring_rust.md) | `flutter_spring_rust` | planned: Rust code as beans |
| [editor_extensions.md](editor_extensions.md) | Zed extensions, VS Code and JetBrains (planned) | next steps of `dart_spring`, the Flutter extension; VS Code and JetBrains clients of the same language server after 0.6.3 |
