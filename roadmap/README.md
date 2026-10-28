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
   session registry, opaque tokens, the ZAP scan) is in the two files.
3. ~~**Documentation comments, first after the 0.4.x release**
   ([documentation.md](documentation.md)): every `///` of every package
   rewritten to say what the thing is, why it exists and when you need it,
   understandable without knowing Spring.~~ Done (October 2026): the `///`
   comments, the READMEs and `docs/`.
4. ~~**Single sign-on** ([spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md)):
   OAuth 2.0 / OpenID Connect for servers (`oauth2Login()`) and apps
   (PKCE, tokens in the Keychain / Keystore).~~ Done (October 2026), with
   Keycloak in the examples; what is left (the differential test against
   Spring, mutation testing, tokens on WebSocket handshakes) is in the file.
5. **Flutter security** ([spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md)):
   the SSO's platform code out of `spring_boot_starter_flutter` into
   `spring_boot_starter_flutter_security` (apps without a login carry
   none of it), `SecretStore` / `SecretTemplate` for the app's own
   secrets, display-only widgets that follow the user, login screens and
   provider buttons (Google, Apple, Microsoft, GitHub), DPoP on the
   server and in the apps, the SSO's hardening.
6. **RestClient and RestTemplate** ([rest_client.md](rest_client.md)) in
   `spring_web_dart`, the `RestClient.Builder` bean in `spring_boot_dart`;
   `@HttpExchange` later.
7. **Logging like Spring's** (the logging section of
   [spring_core_dart.md](spring_core_dart.md#logging-like-springs)): the
   root level INFO without the logging starter too, as in Spring; the
   framework's own debug and trace lines for its main steps (beans
   created, config files loaded, requests mapped and completed, the
   security chain's decisions), with Spring's texts; the `web` log group;
   `--debug` and `--trace` as in Boot.
8. **Spring AI** ([spring_ai.md](spring_ai.md)): chat and embedding models
   of the providers (Anthropic, OpenAI, Gemini, Ollama, ...) behind one
   `ChatClient`, all in one package (`spring_boot_starter_ai`).
9. **MVC beyond REST** ([spring_boot_starter_web.md](spring_boot_starter_web.md),
   *MVC: views and static resources*): first find out whether it is worth
   it. Browser SSO on the server, `oauth2Login()` with OpenID Connect, is
   done without it
   ([spring_boot_starter_security](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)):
   Flutter web uses the server as its backend-for-frontend.
10. Later: [MCP](spring_ai_mcp.md) in the AI starter, the
   actuator, data, the rest of the table.
11. Under question, far off: **the starters on the generator** —
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
| [security_verification.md](security_verification.md) | security packages | done except the ZAP scan and coverage in CI: threat model, attack catalog as tests, differential tests against Spring Security, fuzzing, test vectors, mutation testing, ASVS checklist |
| [spring_ai.md](spring_ai.md) | `spring_boot_starter_ai` | planned: `ChatClient`, the model providers in one package, streaming, tool calling, structured output, chat memory, embeddings |
| [spring_ai_mcp.md](spring_ai_mcp.md) | `spring_boot_starter_ai` | MCP, later (low priority); the web starter's prerequisites exist: MCP servers from beans (`@McpTool`, `@McpResource`, `@McpPrompt`), Streamable HTTP and stdio |
| [spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md) | `spring_boot_starter_oauth2_client` | done: registrations from `spring.security.oauth2.client.*`, discovery, PKCE logins of apps (`OAuth2LoginService`), refresh, `TokenStore`, Bearer tokens on Feign; next: tokens on WebSocket handshakes |
| [spring_boot_starter_data.md](spring_boot_starter_data.md) | `spring_boot_starter_data_*` | planned: entities, repositories, `@Transactional` |
| [spring_boot_starter_retry.md](spring_boot_starter_retry.md) | `spring_boot_starter_retry` | planned: `@Retryable`, `@Recover` |
| [rest_client.md](rest_client.md) | `spring_web_dart`, `spring_boot_dart` | planned: `RestClient`, `RestTemplate` (no package of its own), later `@HttpExchange` |
| [spring_boot_starter_feign.md](spring_boot_starter_feign.md) | `spring_boot_starter_feign` | next steps: files and forms, `FallbackFactory`, circuit breaker |
| [spring_boot_starter_websocket.md](spring_boot_starter_websocket.md) | `spring_boot_starter_websocket` | clients and server endpoints (on the web starter) done; next: STOMP, connection state |
| [spring_boot_starter_scheduling.md](spring_boot_starter_scheduling.md) | `spring_boot_starter_scheduling` | next: `TaskExecutor` (a pool of worker isolates), `@Async` on it |
| [spring_boot_starter_cache.md](spring_boot_starter_cache.md) | `spring_boot_starter_cache` | next: persistent stores |
| [spring_boot_starter_test.md](spring_boot_starter_test.md) | `spring_boot_starter_test` | test classes with annotations (done, [docs/testing.md](../docs/testing.md)); next: editor run buttons and snippets |
| [spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md) | `spring_boot_starter_flutter_test` | planned: Flutter tests on top of the test starter (`@WidgetTest`, `pumpSpring`, themes, platforms, goldens), spec in [docs/flutter-testing.md](../docs/flutter-testing.md) |
| [spring_boot_starter_flutter_security.md](spring_boot_starter_flutter_security.md) | `spring_boot_starter_flutter_security` | planned: the platform code of logins and secrets moved out of the Flutter starter, `SecretStore` / `SecretTemplate`, display-only authorization widgets, login screens and provider buttons |
| [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md) | `spring_boot_starter_flutter` | first version: `SpringApplicationWidget`, beans in widgets, lifecycle, platform profiles; the app widget and themes from properties, the `TokenStore` and login browser on own platform code (done), next: navigation, settings |
| [flutter_spring_signals.md](flutter_spring_signals.md) | `flutter_spring_signals` | planned: `@Signal` fields |
| [flutter_spring_scene.md](flutter_spring_scene.md) | `flutter_spring_scene` | planned: Flutter Scene (3D) |
| [flutter_spring_rust.md](flutter_spring_rust.md) | `flutter_spring_rust` | planned: Rust code as beans |
| [editor_extensions.md](editor_extensions.md) | Zed extensions | next steps of `dart_spring`, the Flutter extension |
