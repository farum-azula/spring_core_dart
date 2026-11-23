// What a debug build shows and what the app's files keep: the debug panel's
// Configuration tab masks by the family's SecretNames rule and the password
// of a URL (S-03); the resource cache keeps no `no-store` answer, no
// `private` one on the disk, no token of a signed address, nothing over
// plain http by default (S-05).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';

class _Server implements HttpTransport {
  String? cacheControl;
  final requests = <HttpRequest>[];

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      throw UnimplementedError('only stream is used');

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    return StreamedHttpResponse(
      200,
      headers: HttpHeaders({
        'Content-Type': 'text/plain',
        'Cache-Control': ?cacheControl,
      }),
      body: Stream.value(Uint8List.fromList(utf8.encode('body'))),
      request: request,
    );
  }

  @override
  void close() {}
}

void main() {
  test(
    'the Configuration tab masks by SecretNames and URL passwords (S-03)',
    () {
      final environment = StandardEnvironment()
        ..propertySources.addFirst(
          MapPropertySource('probe', {
            'spring.datasource.url': 'postgres://ada:PROBE_URL_PW@db/x',
            'db.pwd': 'PROBE_PWD',
            'smtp.passwd': 'PROBE_PASSWD',
            'tls.passphrase': 'PROBE_PASSPHRASE',
            'app.password': 'PROBE_PASSWORD',
            'app.keyboard-layout': 'azerty',
            'app.link': 'https://x.test/a?sslpassword=PROBE_Q&page=2',
          }),
        );
      final shown = {
        for (final (name, value, source) in DebugConfigurationSection(
          environment,
        ).properties())
          if (source == 'probe') name: value,
      };
      expect(shown.values.join(' '), isNot(contains('PROBE_')));
      expect(shown['spring.datasource.url'], 'postgres://ada:******@db/x');
      expect(shown['db.pwd'], '******');
      expect(shown['app.keyboard-layout'], 'azerty');
      expect(shown['app.link'], contains('page=2'));
    },
  );

  group('the resource cache (S-05)', () {
    late InMemoryCacheStore store;
    late _Server server;

    ResourceCache cache({bool allowInsecure = false}) => ResourceCache(
      store: store,
      fetcher: RemoteFetcher(
        transport: server,
        timeout: const Duration(seconds: 5),
        maxBytes: 1 << 20,
        allowInsecure: allowInsecure,
      ),
    );

    Future<List<String>> files() => store.list(ResourceCache.root);

    setUp(() {
      store = InMemoryCacheStore();
      server = _Server();
    });

    test('no-store: kept nowhere, asked every time', () async {
      server.cacheControl = 'no-store';
      final resource = cache().resource(Uri.parse('https://cdn.test/me'));
      expect(utf8.decode(await resource.readAsBytes()), 'body');
      expect(utf8.decode(await resource.readAsBytes()), 'body');
      expect(server.requests, hasLength(2));
      expect(await files(), isEmpty);
    });

    test('private: kept for the run, not on the disk', () async {
      server.cacheControl = 'private, max-age=60';
      final resource = cache().resource(Uri.parse('https://cdn.test/me'));
      await resource.readAsBytes();
      await resource.readAsBytes();
      expect(server.requests, hasLength(1));
      expect(await files(), isEmpty);
    });

    test('a later no-store answer removes the kept copy', () async {
      final uri = Uri.parse('https://cdn.test/me');
      final first = cache();
      await first.resource(uri).readAsBytes();
      expect(await files(), isNotEmpty);
      server.cacheControl = 'no-store';
      await first.resource(uri).refresh();
      expect(await files(), isEmpty);
    });

    test('a signed address keeps its bytes, not its token', () async {
      final resource = cache().resource(
        Uri.parse('https://cdn.test/object/a.png?token=PROBE_TOKEN'),
      );
      await resource.readAsBytes();
      final kept = await files();
      expect(kept, hasLength(2));
      for (final path in kept) {
        expect(
          utf8.decode((await store.read(path))!, allowMalformed: true),
          isNot(contains('PROBE_TOKEN')),
        );
      }
    });

    test('plain http is not kept by default', () async {
      final insecure = Uri.parse('http://cdn.test/a.png');
      expect(cache().keeps(insecure), isFalse);
      expect(cache(allowInsecure: true).keeps(insecure), isTrue);
      expect(cache().keeps(Uri.parse('https://cdn.test/a.png')), isTrue);
    });
  });
}
