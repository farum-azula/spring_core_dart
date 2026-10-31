// The log lines of error answers: a flood of refused requests (the 503 of
// the session limit) must not write one error with a stack trace each.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

void main() {
  late List<SpringLogRecord> records;
  late void Function() stop;
  var now = DateTime(2026, 10, 29);
  final writer = ResponseWriter(mapper: ObjectMapper(), clock: () => now);

  setUp(() {
    records = [];
    stop = SpringLog.listen((record) {
      if (record.loggerName == 'spring.web.mvc' &&
          record.level.index >= SpringLogLevel.warning.index) {
        records.add(record);
      }
    });
  });

  tearDown(() => stop());

  Future<MockServerHttpResponse> answer(Object error) async {
    final response = MockServerHttpResponse();
    await writer.writeError(
      error,
      StackTrace.current,
      MockServerHttpRequest(HttpMethod.get, '/api/books'),
      response,
    );
    return response;
  }

  test('5xx answers asked for by an exception: one warning without a '
      'stack trace per interval', () async {
    for (var i = 0; i < 3; i++) {
      final response = await answer(TooManyActiveSessionsException(10));
      expect(response.statusCode, 503);
      expect(response.headers.contentType, MediaType.applicationProblemJson);
    }
    expect(records, hasLength(1));
    expect(records.single.level, SpringLogLevel.warning);
    expect(records.single.stackTrace, isNull);
    expect(records.single.error, isNull);
    expect(records.single.message, contains('503'));

    now = now.add(ResponseWriter.warningInterval);
    await answer(TooManyActiveSessionsException(10));
    expect(records, hasLength(2));
    expect(records.last.message, contains('2 more of these not logged'));
    // Another kind has its own interval.
    await answer(ResponseStatusException(HttpStatus.badGateway));
    expect(records, hasLength(3));
  });

  test('an unexpected exception is still an error with its stack '
      'trace', () async {
    final response = await answer(StateError('broken'));
    expect(response.statusCode, 500);
    expect(records.single.level, SpringLogLevel.error);
    expect(records.single.error, isA<StateError>());
    expect(records.single.stackTrace, isNotNull);
  });
}
