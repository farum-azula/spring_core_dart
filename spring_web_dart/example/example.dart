// spring_web_dart on its own: the HTTP transport of the platform against a
// small local server, and MockHttpTransport as used in tests. In an
// application you rarely call the transport yourself: Feign clients
// (spring_boot_starter_feign) build requests from the mapping annotations.

// The example shows its results on the console.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';

/// The annotations a Feign client interface carries (with @FeignClient
/// from spring_boot_starter_feign on the class).
abstract interface class CatalogApi {
  @GetMapping('/books/{isbn}')
  Future<Map<String, Object?>> find(@PathVariable('isbn') String isbn);

  @PostMapping.of(path: '/books', consumes: MediaType.applicationJson)
  Future<ResponseEntity<Map<String, Object?>>> create(
    @RequestBody() Map<String, Object?> book,
    @RequestHeader('X-Request-Id') String requestId,
  );
}

Future<void> main() async {
  // A local server standing in for a real API.
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..headers.contentType = io.ContentType.json
      ..write(
        jsonEncode({'isbn': request.uri.pathSegments.last, 'title': 'Dune'}),
      );
    await request.response.close();
  });

  // dart:io here; fetch on the web.
  final transport = platformHttpTransport(
    connectTimeout: const Duration(seconds: 3),
  );
  final response = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://127.0.0.1:${server.port}/books/978-0'),
      headers: HttpHeaders({
        HttpHeaders.acceptHeader: MediaType.applicationJson,
      }),
      timeout: const Duration(seconds: 5),
    ),
  );
  print('${response.statusCode} ${response.bodyText}');
  // 200 {"isbn":"978-0","title":"Dune"}
  transport.close();
  await server.close();

  // In tests: prepared answers instead of a server.
  final mock = MockHttpTransport()
    ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'})
    ..when(HttpMethod.get, '/books/2').respond(HttpStatus.notFound);
  final found = await mock.send(
    HttpRequest(method: HttpMethod.get, url: Uri.parse('https://api/books/1')),
  );
  final missing = await mock.send(
    HttpRequest(method: HttpMethod.get, url: Uri.parse('https://api/books/2')),
  );
  print(
    '${found.bodyText}, ${HttpStatus.valueOf(missing.statusCode).reasonPhrase}',
  );
  // {"isbn":"1"}, Not Found
}
