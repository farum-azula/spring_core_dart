// The starter's example (example/main.dart), as a platform calls it.
import 'dart:convert';

import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:test/test.dart';

import '../example/spring_gen/main.spring.dart';

void main() {
  final function = FetchApplication(
    () => springApplication,
    properties: const {
      'logging.level.root': 'off',
      'spring.security.oauth2.resourceserver.jwt.jwk-set-uri':
          'https://example.com/.well-known/jwks.json',
    },
  );
  tearDownAll(function.close);

  test('the books are open to everyone', () async {
    final response = await function.fetch(
      FetchRequest('GET', Uri.parse('https://fn.example.com/books')),
    );
    expect(response.status, 200);
    expect(jsonDecode(utf8.decode(await response.readBytes())), hasLength(2));
  });

  test('suggesting one needs a token', () async {
    final response = await function.fetch(
      FetchRequest(
        'POST',
        Uri.parse('https://fn.example.com/books'),
        headers: const [('content-type', 'application/json')],
        body: Stream.value(utf8.encode('{"isbn":"1","title":"x"}')),
      ),
    );
    expect(response.status, 401);
  });

  test('the schedule runs its handler', () async {
    await function.scheduled(EdgeScheduledEvent(time: DateTime.utc(2026)));
  });

  test('nothing in it is warned about but the sessions it does not use', () {
    final found = function.context!.getBean<EdgeWarnings>().found;
    expect(found.where((line) => !line.startsWith('sessions')), isEmpty);
  });
}
