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
3. **Spring AI** ([spring_ai.md](spring_ai.md)): chat and embedding models
   of the providers (Anthropic, OpenAI, Gemini, Ollama, ...) behind one
   `ChatClient`.
4. **MVC beyond REST** ([spring_boot_starter_web.md](spring_boot_starter_web.md),
   *MVC: views and static resources*): first find out whether it is worth
   it. With it, maybe (not decided): browser SSO on the server,
   `oauth2Login()` with OpenID Connect
   ([spring_boot_starter_security](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)),
   which only pages rendered by the server (or a backend-for-frontend)
   need; apps log in on the client and send tokens, which the resource
   server already checks.
5. Later: the [MCP server starter](spring_ai_starter_mcp_server.md), the
   actuator, data, the rest of the table.
6. Under question, far off: **the starters on the generator** —
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
| [spring_boot_starter_security.md](spring_boot_starter_security.md) | `spring_boot_starter_security` | done: filter chain, Basic, form login, sessions, CSRF, CORS, headers, JWT resource server; next: remember-me, session registry, opaque tokens |
| [security_verification.md](security_verification.md) | security packages | done except the ZAP scan and coverage in CI: threat model, attack catalog as tests, differential tests against Spring Security, fuzzing, test vectors, mutation testing, ASVS checklist |
| [spring_ai.md](spring_ai.md) | `spring_ai_*` | planned after security: `ChatClient`, model providers as starters, streaming, tool calling, structured output, chat memory, embeddings |
| [spring_ai_starter_mcp_server.md](spring_ai_starter_mcp_server.md) | `spring_ai_starter_mcp_server` | later (low priority); the web starter's prerequisites exist: MCP servers from beans (`@McpTool`, `@McpResource`, `@McpPrompt`), Streamable HTTP and stdio |
| [spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md) | `spring_boot_starter_oauth2_client` | planned: tokens for Feign / WebSocket, PKCE login in apps |
| [spring_boot_starter_data.md](spring_boot_starter_data.md) | `spring_boot_starter_data_*` | planned: entities, repositories, `@Transactional` |
| [spring_boot_starter_retry.md](spring_boot_starter_retry.md) | `spring_boot_starter_retry` | planned: `@Retryable`, `@Recover` |
| [spring_boot_starter_http.md](spring_boot_starter_http.md) | `spring_boot_starter_http` | planned: `RestClient`, `@HttpExchange` |
| [spring_boot_starter_feign.md](spring_boot_starter_feign.md) | `spring_boot_starter_feign` | next steps: files and forms, `FallbackFactory`, circuit breaker |
| [spring_boot_starter_websocket.md](spring_boot_starter_websocket.md) | `spring_boot_starter_websocket` | clients and server endpoints (on the web starter) done; next: STOMP, connection state |
| [spring_boot_starter_scheduling.md](spring_boot_starter_scheduling.md) | `spring_boot_starter_scheduling` | next: `TaskExecutor` (a pool of worker isolates), `@Async` on it |
| [spring_boot_starter_cache.md](spring_boot_starter_cache.md) | `spring_boot_starter_cache` | next: persistent stores |
| [spring_boot_starter_test.md](spring_boot_starter_test.md) | `spring_boot_starter_test` | test classes with annotations (done, [docs/testing.md](../docs/testing.md)); next: editor run buttons and snippets |
| [spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md) | `spring_boot_starter_flutter_test` | planned: Flutter tests on top of the test starter (`@WidgetTest`, `pumpSpring`, themes, platforms, goldens), spec in [docs/flutter-testing.md](../docs/flutter-testing.md) |
| [spring_boot_starter_flutter.md](spring_boot_starter_flutter.md) | `spring_boot_starter_flutter` | first version: `SpringApplicationWidget`, beans in widgets, lifecycle, platform profiles; the app widget and themes from properties (done), next: navigation, settings, `TokenStore` |
| [flutter_spring_signals.md](flutter_spring_signals.md) | `flutter_spring_signals` | planned: `@Signal` fields |
| [flutter_spring_scene.md](flutter_spring_scene.md) | `flutter_spring_scene` | planned: Flutter Scene (3D) |
| [flutter_spring_rust.md](flutter_spring_rust.md) | `flutter_spring_rust` | planned: Rust code as beans |
| [editor_extensions.md](editor_extensions.md) | Zed extensions | next steps of `dart_spring`, the Flutter extension |
