# spring_boot_starter_feign

Done: `@FeignClient` interfaces, JSON through the `ObjectMapper`,
interceptors, error decoding, retries, fallbacks,
`spring.cloud.openfeign.client.config.*`, server-sent events
(`EventStream<T>`).

## Next steps

Form and multipart bodies, `@SpringQueryMap`, a `FallbackFactory` that sees
the error, circuit breaker integration, per-client connection timeouts, and
editor checks of `{variables}` against `@PathVariable` parameters in the Zed
extension.

## Files and forms (sketch)

Today a file goes as a raw body (`@RequestBody() Uint8List`) and comes back
as `Future<Uint8List>`, both whole in memory. Planned, in the style of
Spring Cloud OpenFeign:

```dart
@PostMapping('/books/{isbn}/files', consumes: MediaType.multipartFormData)
Future<UploadResult> upload(
  @PathVariable() String isbn,
  @RequestPart('file') MultipartFile file,   // fromBytes / fromStream / fromPath (VM)
  @RequestPart('meta') FileMeta meta,        // an object → a JSON part
  @RequestPart('note') String note,          // a text field
);

@PostMapping('/login', consumes: MediaType.applicationFormUrlencoded)
Future<Token> login(@RequestParam('user') String user, @RequestParam('password') String password);

@GetMapping('/exports/{id}')
Stream<List<int>> download(@PathVariable() String id);   // streamed, not in memory
```

This needs a multipart encoder and streamed request bodies in the
`spring_web_dart` transports (`dart:io` and `fetch`), startup checks (e.g.
`@RequestPart` without a multipart `consumes`), and tests against a local
server.
