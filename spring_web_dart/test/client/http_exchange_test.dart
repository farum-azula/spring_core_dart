import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  test('the shortcut annotations are HttpExchanges with their method', () {
    const annotations = <HttpExchange>[
      GetExchange('/books/{isbn}'),
      PostExchange.of(url: '/books', contentType: MediaType.applicationJson),
      PutExchange('/books/{isbn}'),
      PatchExchange('/books/{isbn}'),
      DeleteExchange.of(url: '/books/{isbn}', headers: ['X-Reason=sold']),
      HttpExchange.of(url: '/books/{isbn}', method: HttpMethod.head),
    ];
    expect(
      [for (final a in annotations) a.method],
      [
        HttpMethod.get,
        HttpMethod.post,
        HttpMethod.put,
        HttpMethod.patch,
        HttpMethod.delete,
        HttpMethod.head,
      ],
    );
    expect(annotations[1].contentType, MediaType.applicationJson);
    expect(annotations[4].headers, ['X-Reason=sold']);
    const onInterface = HttpExchange('/v1');
    expect(onInterface.method, isNull);
    expect(onInterface.accept, isEmpty);
    const get = GetExchange.of(
      accept: [MediaType.applicationJson],
      version: '2',
    );
    expect(get.url, '');
    expect(get.version, '2');
  });

  test('ImportHttpServices: the default group', () {
    const imported = ImportHttpServices(types: [String]);
    expect(imported.group, ImportHttpServices.defaultGroup);
    expect(imported.group, 'default');
    expect(
      const ImportHttpServices(group: 'catalog').types,
      isEmpty,
    );
  });
}
