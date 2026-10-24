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

| File | Package | Status |
|---|---|---|
| [spring_core_dart.md](spring_core_dart.md) | `spring_core_dart`, generator | JSON next steps, incremental generation per library |
| [fix_plan.md](fix_plan.md) | all packages | open differences from Spring 7 / Boot 4 found in reviews, how close each area is |
| [spring_boot_starter_web.md](spring_boot_starter_web.md) | `spring_boot_starter_web` | planned: controllers, SSE, WebSocket endpoints, `MockMvc` |
| [spring_security_core.md](spring_security_core.md) | `spring_security_core` | planned: security context, `@PreAuthorize` (server and app) |
| [spring_boot_starter_security.md](spring_boot_starter_security.md) | `spring_boot_starter_security` | planned: incoming requests — filter chain, Basic, sessions, JWT |
| [spring_boot_starter_oauth2_client.md](spring_boot_starter_oauth2_client.md) | `spring_boot_starter_oauth2_client` | planned: tokens for Feign / WebSocket, PKCE login in apps |
| [spring_boot_starter_data.md](spring_boot_starter_data.md) | `spring_boot_starter_data_*` | planned: entities, repositories, `@Transactional` |
| [spring_boot_starter_retry.md](spring_boot_starter_retry.md) | `spring_boot_starter_retry` | planned: `@Retryable`, `@Recover` |
| [spring_boot_starter_http.md](spring_boot_starter_http.md) | `spring_boot_starter_http` | planned: `RestClient`, `@HttpExchange` |
| [spring_boot_starter_feign.md](spring_boot_starter_feign.md) | `spring_boot_starter_feign` | next steps: files and forms, `FallbackFactory`, circuit breaker |
| [spring_boot_starter_websocket.md](spring_boot_starter_websocket.md) | `spring_boot_starter_websocket` | next steps: STOMP, connection state |
| [spring_boot_starter_scheduling.md](spring_boot_starter_scheduling.md) | `spring_boot_starter_scheduling` | next: `TaskExecutor` (a pool of worker isolates), `@Async` on it |
| [spring_boot_starter_cache.md](spring_boot_starter_cache.md) | `spring_boot_starter_cache` | next: persistent stores |
| [flutter_spring.md](flutter_spring.md) | `flutter_spring` | planned: Spring instead of the Flutter package stack |
| [flutter_spring_signals.md](flutter_spring_signals.md) | `flutter_spring_signals` | planned: `@Signal` fields |
| [flutter_spring_scene.md](flutter_spring_scene.md) | `flutter_spring_scene` | planned: Flutter Scene (3D) |
| [flutter_spring_rust.md](flutter_spring_rust.md) | `flutter_spring_rust` | planned: Rust code as beans |
| [editor_extensions.md](editor_extensions.md) | Zed extensions | next steps of `dart_spring`, the Flutter extension |
