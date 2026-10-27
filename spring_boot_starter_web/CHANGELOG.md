## Unreleased

- `HttpSession`: `request.getSession()`, an in-memory `HttpSessionRepository` with expiry and a limit (`server.servlet.session.timeout`, `.max-sessions`, `.cookie.*`; `SameSite=Lax` by default), `changeSessionId()`; the session cookie is written by `HttpSessionFilter`.
- `@RequestParam` reads the fields of `application/x-www-form-urlencoded` bodies too, like Spring MVC (`readFormParameters`).
- A request target starting with `//` is no longer read as a host by `dart:io`: the path keeps its `//` (and is answered 404, or refused by the security starter's firewall).

## 0.3.2

- Initial version: Spring MVC for Dart. `@RestController` classes with `@GetMapping`, `@PostMapping`, ... on `dart:io`'s `HttpServer` (`server.*` properties), path variables, request parameters, headers and cookies, JSON bodies through the `ObjectMapper`, `@Valid` bodies, `ResponseEntity`, errors as `ProblemDetail` with `@ExceptionHandler` and `@RestControllerAdvice`, server-sent events (`EventStream`, `SseEmitter`), filters, interceptors, CORS, WebSocket endpoints of `spring_boot_starter_websocket` on the same server; `MockMvc` and `springBootTest(webEnvironment:)` in `spring_boot_starter_test`.
