// The framework's own log lines, as Spring writes them: the request, the
// handler, the answer, sessions, multipart; and that no secret reaches any
// log level.
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('at trace with spring.mvc.log-request-details', () {
    final app = springBootTest(
      testApplication,
      properties: {
        'logging.level.root': 'trace',
        'spring.mvc.log-request-details': 'true',
      },
    );
    late List<SpringLogRecord> records;
    late void Function() stop;

    setUp(() {
      records = [];
      stop = SpringLog.listen(records.add);
    });
    tearDown(() => stop());

    String all() => records.map((r) => '${r.message} ${r.fields}').join('\n');

    Iterable<SpringLogRecord> web() =>
        records.where((r) => r.loggerName.startsWith('spring.web'));

    test('the request, the handler and the answer', () async {
      await app.mockMvc
          .get('/api/books', params: {'q': 'dart'})
          .andExpect(status: 200);
      final messages = web().map((r) => r.message).toList();
      expect(
        messages,
        contains(startsWith('GET "/api/books", parameters={q=[dart]}')),
      );
      expect(messages, contains('Mapped to BookController#search()'));
      expect(messages, contains('Completed 200 OK'));
      final request = web().firstWhere((r) => r.message.startsWith('GET "'));
      expect(request.level, SpringLogLevel.debug);
      expect(request.message, contains('headers={'));
    });

    test('an error answer: Resolved [Type: detail]', () async {
      await app.mockMvc.get('/nowhere/at/all').andExpect(status: 404);
      expect(
        web().map((r) => r.message),
        contains(allOf(startsWith('Resolved ['), contains('Exception: '))),
      );
      expect(web().map((r) => r.message), contains('Completed 404 Not Found'));
    });

    test('no secret reaches a log, at any level', () async {
      final first = await app.mockMvc.get('/session/count');
      final id = first.response.cookies
          .firstWhere((c) => c.name == 'JSESSIONID')
          .value;
      records.clear();
      await app.mockMvc.get(
        '/session/count',
        headers: {
          'cookie': 'JSESSIONID=$id; tracking=cookie-value-123',
          'authorization': 'Bearer auth-value-456',
          'x-api-key': 'header-secret-xyz',
          'x-plain': 'visible-value',
        },
        params: {'password': 'secret-xyz', 'user': 'ann'},
      );
      await app.mockMvc.post(
        '/api/books/json-only',
        json: {'note': 'body-secret-abc'},
        headers: {'authorization': 'Bearer auth-value-456'},
      );
      await app.mockMvc.post(
        '/session/rotate',
        headers: {'cookie': 'JSESSIONID=$id'},
      );
      await app.mockMvc.post(
        '/session/invalidate',
        headers: {'cookie': 'JSESSIONID=$id'},
      );
      final text = all();
      expect(records, isNotEmpty);
      for (final secret in [
        id,
        'cookie-value-123',
        'auth-value-456',
        'header-secret-xyz',
        'secret-xyz',
        'body-secret-abc',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      // Not everything is hidden: the plain header and parameter show.
      expect(text, contains('visible-value'));
      expect(text, contains('user=[ann]'));
      expect(text, contains('password=[masked]'));
      expect(text, contains('x-api-key: masked'));
    });

    test('a line break from the client is <EOL>, never a line', () async {
      await app.mockMvc.get('/api/books', params: {'q': 'a\r\nFORGED line'});
      await app.mockMvc.get('/nope\r\nFORGED path');
      final text = all();
      expect(text, contains('a<EOL><EOL>FORGED line'));
      expect(text, contains('/nope'));
      for (final record in web()) {
        expect(record.message, isNot(contains('\n')));
        expect(record.message, isNot(contains('\r')));
      }
    });

    test('multipart: counts and sizes, never contents or file names', () async {
      await app.mockMvc
          .multipart(
            '/files/upload',
            files: [
              MockMultipartFile(
                'file',
                'private-name.txt',
                'text/plain',
                utf8.encode('file-content-789'),
              ),
            ],
            params: {'note': 'field-content-321'},
          )
          .andExpect(status: 200);
      final messages = web().map((r) => r.message).toList();
      expect(
        messages,
        contains(startsWith('Read a multipart request: 1 files, 1 fields')),
      );
      expect(messages, contains('Part "file": a file of 16 bytes'));
      expect(messages, contains('Part "note": a field of 17 bytes'));
      final text = all();
      for (final secret in [
        'private-name.txt',
        'file-content-789',
        'field-content-321',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('sessions: created, id changed, invalidated', () async {
      final first = await app.mockMvc.get('/session/count');
      final id = first.response.cookies
          .firstWhere((c) => c.name == 'JSESSIONID')
          .value;
      final rotated = await app.mockMvc.post(
        '/session/rotate',
        headers: {'cookie': 'JSESSIONID=$id'},
      );
      final newId = rotated.response.cookies
          .firstWhere((c) => c.name == 'JSESSIONID')
          .value;
      await app.mockMvc.post(
        '/session/invalidate',
        headers: {'cookie': 'JSESSIONID=$newId'},
      );
      final messages = web().map((r) => r.message).toList();
      expect(messages, contains('Created a session'));
      expect(messages, contains('Changed the session id'));
      expect(messages, contains('Invalidated the session'));
    });
  });

  test('startup: the mappings are counted at debug, each at trace', () async {
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen(records.add);
    addTearDown(stop);
    final before = SpringLog.level;
    addTearDown(() => SpringLog.level = before);
    SpringLog.level = SpringLogLevel.trace;
    await webRunner().runAsync((context) async {
      expect(context.startupFailure, isNull);
    });
    final mvc = records.where((r) => r.loggerName == 'spring.web.mvc');
    final count = mvc.firstWhere(
      (r) => r.message.endsWith("mappings in 'requestMappingHandlerMapping'"),
    );
    expect(count.level, SpringLogLevel.debug);
    final each = mvc.where((r) => r.message.startsWith('Mapped GET '));
    expect(each, isNotEmpty);
    expect(each.every((r) => r.level == SpringLogLevel.trace), isTrue);
  });

  group('without details', () {
    final app = springBootTest(
      testApplication,
      properties: {'logging.level.root': 'debug'},
    );
    late List<SpringLogRecord> records;
    late void Function() stop;

    setUp(() {
      records = [];
      stop = SpringLog.listen(records.add);
    });
    tearDown(() => stop());

    test('parameters and headers are masked', () async {
      await app.mockMvc.get(
        '/api/books',
        headers: {'x-plain': 'visible-value'},
        params: {'q': 'dart'},
      );
      final text = records.map((r) => r.message).join('\n');
      expect(text, contains('GET "/api/books", parameters={masked}'));
      expect(text, isNot(contains('dart')));
      expect(text, isNot(contains('visible-value')));
    });
  });

  group('at info', () {
    final app = springBootTest(
      testApplication,
      properties: {'logging.level.root': 'info'},
    );
    late List<SpringLogRecord> records;
    late void Function() stop;

    setUp(() {
      records = [];
      stop = SpringLog.listen(records.add);
    });
    tearDown(() => stop());

    test('none of the request lines appear', () async {
      await app.mockMvc.get('/session/count');
      await app.mockMvc.get('/api/books/nope');
      expect(
        records.where((r) => r.loggerName.startsWith('spring.web')),
        isEmpty,
      );
    });
  });
}
