# spring_boot_starter_feign

Done: `@FeignClient` interfaces, JSON through the `ObjectMapper`,
interceptors, error decoding, retries, fallbacks,
`spring.cloud.openfeign.client.config.*`, server-sent events
(`EventStream<T>`), form bodies (`@RequestBody` Map or object with
`consumes: application/x-www-form-urlencoded`), multipart bodies
(`@RequestPart`: `MultipartFile`, bytes, text fields, JSON parts).

## Next steps

Form parameters (`@RequestParam` as form fields), streamed uploads and
downloads, `@SpringQueryMap`, a `FallbackFactory` that sees the error,
circuit breaker integration, per-client connection timeouts, and editor
checks of `{variables}` against `@PathVariable` parameters in the Zed
extension.

## Files and forms (sketch)

Done: multipart bodies, like Spring Cloud OpenFeign with `@RequestPart`:

```dart
@PostMapping.of(path: '/books/{isbn}/files', consumes: MediaType.multipartFormData)
Future<UploadResult> upload(
  @PathVariable() String isbn,
  @RequestPart('file') MultipartFile file,   // a file part (List<MultipartFile>: one per file)
  @RequestPart('meta') FileMeta meta,        // an object → a JSON part
  @RequestPart('note') String note,          // a text field
);
```

The body is encoded with `MultipartBody` of `spring_web_dart`, in memory,
once per call (retries resend the same bytes); startup checks reject
`@RequestPart` with `@RequestBody`, with a non-multipart `consumes`, or
together with another role on one parameter. Tests read the recorded body
with `MultipartParser` (`test/feign_multipart_test.dart`).

Still planned:

```dart
@PostMapping('/login', consumes: MediaType.applicationFormUrlencoded)
Future<Token> login(@RequestParam('user') String user, @RequestParam('password') String password);

@GetMapping('/exports/{id}')
Stream<List<int>> download(@PathVariable() String id);   // streamed, not in memory
```

This needs streamed request bodies in the `spring_web_dart` transports
(`dart:io` and `fetch`) so large files are not held in memory
(`MultipartFile.openRead` instead of `bytes`), `@RequestParam` as form
fields of a form-urlencoded method (today they go to the query, like
Spring Cloud OpenFeign), and tests against a local server.
