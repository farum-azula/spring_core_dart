# Roadmap

Plans and sketches of coming features, one file per package. Each file says
what is done and what is planned; code in the sketches shows the intended
API and may change. Nothing here is promised in a fixed order.

Rules every plan follows:

- Spring first: Spring's names and behaviour, and where a feature differs
  from Spring (or does not exist there), the docs say so.
- No reflection: everything is generated at build time, so it works in AOT
  executables, Flutter and minified JavaScript.
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
7. **The edge starter, a 0.5.x patch** ([serverless.md](serverless.md)):
   Spring Boot for Dart applications compiled to JavaScript behind a
   fetch handler, first on Supabase Edge Functions (Supabase's
   environment and Auth JWTs, deploys from GitHub Actions on every
   push), then Deno Deploy, Cloudflare Workers, Vercel and Netlify Edge.
   Designed first, on its own: what the other starters do where they
   cannot work fully (timers, in-memory caches and sessions, files,
   isolates) without starters knowing any platform (the open section of
   [serverless.md](serverless.md)).
8. **The web server after Netty, not Tomcat** (the owner's decision,
   October 2026; for 0.6.0, since defaults change): Dart's server runs on
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
9. **Typed keys from the configuration** (the section in
   [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md#typed-keys-from-the-configuration-generated)):
   the generator writes getters for the theme's colors, spacing, text
   styles, tokens and theme names (`context.theme.colors.surfaceContainerLow`)
   and for the messages (`context.messages.basket.total(sum)`); then
   assets and routes. A renamed key fails the build, not the app.
10. **RestClient and RestTemplate** ([rest_client.md](rest_client.md)) in
   `spring_web_dart`, the `RestClient.Builder` bean in `spring_boot_dart`;
   `@HttpExchange` later.
11. **Logging like Spring's** (the logging section of
   [spring_core_dart.md](spring_core_dart.md#logging-like-springs)): the
   root level INFO without the logging starter too, as in Spring; the
   framework's own debug and trace lines for its main steps (beans
   created, config files loaded, requests mapped and completed, the
   security chain's decisions), with Spring's texts; the `web` log group;
   `--debug` and `--trace` as in Boot.
12. **Spring AI** ([spring_ai.md](spring_ai.md)): chat and embedding models
   of the providers (Anthropic, OpenAI, Gemini, Ollama, ...) behind one
   `ChatClient`, all in one package (`spring_boot_starter_ai`).
13. **MVC beyond REST** ([spring_boot_starter_web.md](spring_boot_starter_web.md),
   *MVC: views and static resources*): first find out whether it is worth
   it. Browser SSO on the server, `oauth2Login()` with OpenID Connect, is
   done without it
   ([spring_boot_starter_security](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)):
   Flutter web uses the server as its backend-for-frontend.
14. Later: [MCP](spring_ai_mcp.md) in the AI starter, the
   actuator, data, the rest of the table.
15. Under question, far off: **the starters on the generator** —
   `@AutoConfiguration` classes with `@Bean` methods instead of the
   hand-written `BeanDefinition`s of their auto-configurations. For now
   hand-written stays: it reads better for this code and needs no
   generator round trip; the beans an application gets are the same
   either way.

| File | Package | Status |
|---|---|---|
| [spring_core_dart.md](spring_core_dart.md) | `spring_core_dart`, generator | JSON next steps, incremental generation per library, Jakarta annotations under question |
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
| [spring_boot_starter_data.md](spring_boot_starter_data.md) | `spring_boot_starter_data_*` | planned: entities, repositories, `@Transactional` |
| [spring_boot_starter_retry.md](spring_boot_starter_retry.md) | `spring_boot_starter_retry` | planned: `@Retryable`, `@Recover` |
| [review_0_5.md](review_0_5.md) | all packages | planned: the review before 0.5.0 (bugs and differences from Spring, security, vulnerabilities), then the minor release |
| [serverless.md](serverless.md) | `spring_boot_starter_edge` (name to settle) | planned, a 0.5.x patch: Spring Boot for Dart applications on Supabase Edge Functions, Deno Deploy, Cloudflare Workers; deploys from GitHub Actions |
| [rest_client.md](rest_client.md) | `spring_web_dart`, `spring_boot_dart` | planned: `RestClient`, `RestTemplate` (no package of its own), later `@HttpExchange` |
| [spring_boot_starter_feign.md](spring_boot_starter_feign.md) | `spring_boot_starter_feign` | next steps: files and forms, `FallbackFactory`, circuit breaker |
| [spring_boot_starter_websocket.md](spring_boot_starter_websocket.md) | `spring_boot_starter_websocket` | clients and server endpoints (on the web starter) done; next: STOMP, connection state |
| [spring_boot_starter_scheduling.md](spring_boot_starter_scheduling.md) | `spring_boot_starter_scheduling` | next: `TaskExecutor` (a pool of worker isolates), `@Async` on it |
| [spring_boot_starter_cache.md](spring_boot_starter_cache.md) | `spring_boot_starter_cache` | next: persistent stores |
| [spring_boot_starter_test.md](spring_boot_starter_test.md) | `spring_boot_starter_test` | test classes with annotations (done, [docs/testing.md](../docs/testing.md)); next: editor run buttons and snippets |
| [spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md) | `spring_boot_starter_flutter_test` | planned: Flutter tests on top of the test starter (`@WidgetTest`, `pumpSpring`, themes, platforms, goldens), spec in [docs/flutter-testing.md](../docs/flutter-testing.md) |
| [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md) | `spring_boot_starter_flutter_security` | done: the app login (`OAuth2LoginService`, the login windows) moved out of the OAuth2 client, the platform code of logins and secrets out of the Flutter starter, `SecretStore` / `SecretTemplate`, display-only widgets that follow the user (`PrincipalNotifier`, `PrincipalBuilder`, `PrincipalView`), the web login in server mode (backend-for-frontend, `ServerOAuth2LoginService`) and in spa mode (the browser logs in, `SpaOAuth2LoginService`, a non-extractable WebCrypto DPoP key), DPoP keys of the apps (`PlatformDPoPKey`: Secure Enclave / Keychain, Android Keystore, `SecretStore`); login screens (`LoginForm`, `OAuth2LoginButton`, the Google, Apple, Microsoft and GitHub buttons), the hardening (October 2026); next: its runs on devices (the Windows and Linux stores' first CI run, iOS cancel, https redirects) |
| [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md) | `spring_boot_starter_flutter` | first version: `SpringApplicationWidget`, beans in widgets, lifecycle, platform profiles; the app widget and themes from properties (done; the secret store and login window moved to `spring_boot_starter_flutter_security`), next: navigation, settings |
| [flutter_spring_signals.md](flutter_spring_signals.md) | `flutter_spring_signals` | planned: `@Signal` fields |
| [flutter_spring_scene.md](flutter_spring_scene.md) | `flutter_spring_scene` | planned: Flutter Scene (3D) |
| [flutter_spring_rust.md](flutter_spring_rust.md) | `flutter_spring_rust` | planned: Rust code as beans |
| [editor_extensions.md](editor_extensions.md) | Zed extensions | next steps of `dart_spring`, the Flutter extension |
