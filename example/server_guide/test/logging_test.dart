// Chapter 11, logging: levels and groups from the properties, fields
// added by the request filter, the LogBuffer behind /api/admin/logs, and
// the log file of the prod profile.
@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'support/app.dart';

MockRequestBuilder asAdmin(String path) =>
    MockRequestBuilder(HttpMethod.get, path)
      ..with_(user('root').roles(['USER', 'ADMIN']));

void main() {
  group('dev', () {
    final app = neonBooks();

    test('levels: the `shop` log group is at debug, the rest at info', () {
      // logging.group.shop=neon,neon_books_server
      expect(SpringLog.levelOf('neon.audit'), SpringLogLevel.debug);
      expect(
        SpringLog.levelOf('neon_books_server.OrderService'),
        SpringLogLevel.debug,
      );
      expect(SpringLog.levelOf('spring.web.mvc'), SpringLogLevel.info);
    });

    test('the LogBuffer behind /api/admin/logs, with filters', () async {
      await app.mockMvc.get('/api/books/9780000000000'); // a warning
      final result = await app.mockMvc
          .perform(asAdmin('/api/admin/logs')..params['level'] = 'warn')
          .andExpect(status: 200)
          .andReturn();
      final lines = (jsonOf(result)! as List).cast<Map<String, Object?>>();
      expect(lines.map((l) => l['level']).toSet(), {'WARN'});
      expect(lines.last, {
        'time': isA<String>(),
        'level': 'WARN',
        'logger': 'neon.audit',
        'message': contains('no book 9780000000000'),
        // SpringLog.withFields of RequestIdFilter: every line of a request.
        'fields': {'request': isA<String>()},
      });
      final sampleData = await app.mockMvc
          .perform(
            asAdmin('/api/admin/logs')
              ..params['logger'] = 'neon_books_server.SampleData',
          )
          .andReturn();
      expect(jsonOf(sampleData), [
        containsPair('message', '8 sample books loaded from books.json'),
      ]);
    });

    test('the buffer is a bean, as for a log screen', () {
      final buffer = app.getBean<LogBuffer>();
      expect(buffer.loggerNames, contains('neon_books_server.SampleData'));
    });
  });

  group('prod', () {
    final app = neonBooks(profiles: ['prod', 'test']);

    test('a log file (logging.file.name in application-prod.yml)', () {
      expect(app, hasSingleBean<LoggingSystem>());
      final file = LoggingSystem.instance.file!;
      expect(file.path, 'build/logs/neon-books.log');
      file.flush();
      expect(
        File(file.path).readAsStringSync(),
        contains('neon-books'), // Spring Boot's file pattern
      );
    });
  });
}
