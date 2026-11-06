// The handlers of the dispatcher for the actuator's mappings endpoint, in
// Spring WebFlux's shape: the controllers' request mappings with their
// conditions, then the static resources.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  Future<List<Map<String, Object?>>> handlers([
    List<String> properties = const [],
  ]) async {
    late List<Map<String, Object?>> result;
    await webRunner([
      'spring.test.web-environment=mock',
      ...properties,
    ]).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final descriptions = context.getBean<MappingDescriptions>();
      expect(descriptions, isA<DispatcherHandlersMappingDescriptions>());
      expect(descriptions.mappingsName, 'dispatcherHandlers');
      final mappings = descriptions.describeMappings()! as Map;
      expect(mappings.keys, ['webHandler']);
      result = (mappings['webHandler']! as List).cast();
    });
    return result;
  }

  Map<String, Object?> byPredicate(
    List<Map<String, Object?>> all,
    String predicate,
  ) => all.firstWhere((handler) => handler['predicate'] == predicate);

  test('a controller method with its conditions', () async {
    final all = await handlers();
    expect(byPredicate(all, '{GET [/api/books/{isbn}]}'), {
      'predicate': '{GET [/api/books/{isbn}]}',
      'handler': 'BookController#find(String)',
      'details': {
        'handlerMethod': {
          'className': 'BookController',
          'name': 'find',
          'descriptor': '(String isbn) -> Future<Book>',
        },
        'requestMappingConditions': {
          'consumes': <Object?>[],
          'headers': <Object?>[],
          'methods': ['GET'],
          'params': <Object?>[],
          'patterns': ['/api/books/{isbn}'],
          'produces': <Object?>[],
        },
      },
    });
  });

  test('produces and consumes as Spring writes them', () async {
    final all = await handlers();
    final bytes = byPredicate(
      all,
      '{GET [/misc/bytes], produces [application/octet-stream]}',
    );
    expect(
      ((bytes['details']! as Map)['requestMappingConditions']!
          as Map)['produces'],
      [
        {'mediaType': 'application/octet-stream', 'negated': false},
      ],
    );
    final json = byPredicate(
      all,
      '{POST [/misc/json-only], consumes [application/json]}',
    );
    expect(json['handler'], startsWith('MiscController#'));
    expect(byPredicate(all, '{GET [/misc/files/{*path}]}'), isNotNull);
  });

  test('the static resources come last, with the welcome page', () async {
    final all = await handlers();
    expect(all.reversed.take(2).toList().reversed, [
      {
        'predicate': '/**',
        'handler': 'ResourceWebHandler [resources:static/, resources:public/]',
      },
      {'predicate': '(GET && /)', 'handler': 'WelcomePage [index.html]'},
    ]);
  });

  test('without static resources: the controllers alone', () async {
    final all = await handlers(['spring.web.resources.add-mappings=false']);
    expect(
      all.where((h) => '${h['handler']}'.startsWith('ResourceWebHandler')),
      isEmpty,
    );
    expect(all, isNotEmpty);
  });

  group('describeRequestMapping', () {
    test("Spring's RequestMappingInfo.toString for the predicate", () {
      expect(
        describeRequestMapping(
          handler: 'h',
          patterns: ['/a', '/b'],
          methods: ['GET', 'HEAD'],
          params: ['debug'],
          headers: ['X-Api!=1', '!X-Old'],
          consumes: ['application/json'],
          produces: ['application/json', 'text/plain'],
        )['predicate'],
        '{[GET, HEAD] [/a || /b], params [debug], headers [X-Api!=1 || '
        '!X-Old], consumes [application/json], produces [application/json '
        '|| text/plain]}',
      );
      expect(
        describeRequestMapping(handler: 'h', patterns: ['/x'])['predicate'],
        '{ [/x]}',
      );
    });

    test('the conditions as name, value and negated', () {
      final details =
          describeRequestMapping(
                handler: 'h',
                patterns: ['/x'],
                headers: ['X-Api=2', 'X-Old!=1', '!X-Debug', 'X-Any'],
                params: ['page'],
                produces: ['!text/html'],
              )['details']!
              as Map;
      expect(details, isNot(contains('handlerMethod')));
      final conditions = details['requestMappingConditions']! as Map;
      expect(conditions['headers'], [
        {'name': 'X-Api', 'value': '2', 'negated': false},
        {'name': 'X-Old', 'value': '1', 'negated': true},
        {'name': 'X-Debug', 'value': null, 'negated': true},
        {'name': 'X-Any', 'value': null, 'negated': false},
      ]);
      expect(conditions['params'], [
        {'name': 'page', 'value': null, 'negated': false},
      ]);
      expect(conditions['produces'], [
        {'mediaType': 'text/html', 'negated': true},
      ]);
    });
  });
}
