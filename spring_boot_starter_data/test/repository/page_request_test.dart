// A page or a sort asked for by a request: what PageRequest and Direction
// accept, and what the errors say (they are written in logs, and the name
// or the number may come from a client).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

void main() {
  group('PageRequest.of', () {
    test('a page and a size in range', () {
      final request = PageRequest.of(3, 20);
      expect(request.offset, 60);
      expect(request.next().offset, 80);
      expect(PageRequest.of(0, 1).offset, 0);
    });

    test('a negative page and a size below one are refused', () {
      expect(() => PageRequest.of(-1, 10), throwsArgumentError);
      expect(() => PageRequest.of(0, 0), throwsArgumentError);
      expect(() => PageRequest.of(0, -3), throwsArgumentError);
      expect(
        () => PageRequest.of(-1, 10),
        throwsA(isA<InvalidPagingRequestException>()),
      );
    });

    test('an offset that would wrap around is refused, not folded into '
        'another page', () {
      // 2^61 * 8 = 2^64: offset 0 with 64-bit integers.
      expect(() => PageRequest.of(1 << 61, 8), throwsArgumentError);
      // 2^62 + 1 times 2: a negative offset with 64-bit integers.
      expect(() => PageRequest.of((1 << 62) + 1, 2), throwsArgumentError);
      expect(
        () => PageRequest.of(9223372036854775807, 9223372036854775807),
        throwsArgumentError,
      );
      expect(
        () => PageRequest.of(0, 9223372036854775807),
        throwsArgumentError,
      );
    });

    test('the last page that fits is accepted, the next one is not', () {
      const max = PageRequest.maxOffset;
      expect(PageRequest.of(max - 10, 1).offset, max - 10);
      // page * size + size <= maxOffset
      final edge = PageRequest.of(max ~/ 10 - 1, 10);
      expect(edge.offset + 10, lessThanOrEqualTo(max));
      expect(() => PageRequest.of(max ~/ 10, 10), throwsArgumentError);
      expect(() => edge.next().next(), throwsArgumentError);
      expect(() => PageRequest.of(max, 1), throwsArgumentError);
    });

    test('the offset is never negative', () {
      for (final (page, size) in [
        (0, 1),
        (1, 1),
        (1 << 40, 1 << 12),
        (PageRequest.maxOffset - 1, 1),
      ]) {
        expect(PageRequest.of(page, size).offset, greaterThanOrEqualTo(0));
      }
    });

    test('withPage and next are checked too', () {
      final request = PageRequest.of(0, 1 << 50);
      expect(request.withPage(3).offset, 3 << 50);
      expect(() => request.withPage(8), throwsArgumentError);
      expect(() => request.withPage(-1), throwsArgumentError);
    });

    test('the message says what is wrong and escapes the value', () {
      final error = InvalidPagingRequestException(
        'x\r\ny',
        'direction',
        'invalid',
      );
      expect(error.toString(), isNot(contains('\n')));
      expect(error.toString(), contains('x<EOL><EOL>y'));
      expect(error.invalidValue, 'x\r\ny');
      expect(error, isA<ArgumentError>());
    });
  });

  group('Direction.fromString', () {
    test('asc and desc, in any case', () {
      expect(Direction.fromString('ASC'), Direction.asc);
      expect(Direction.fromString('Desc'), Direction.desc);
    });

    test('anything else is an InvalidPagingRequestException that cannot '
        'forge a log line', () {
      for (final value in ['up', '', 'desc\r\n2026 INFO FORGED']) {
        expect(
          () => Direction.fromString(value),
          throwsA(
            isA<InvalidPagingRequestException>()
                .having((e) => e.invalidValue, 'invalidValue', value)
                .having(
                  (e) => '$e',
                  'toString',
                  allOf(isNot(contains('\r')), isNot(contains('\n'))),
                ),
          ),
        );
      }
      expect(() => Direction.fromString('up'), throwsArgumentError);
    });
  });

  group('PropertyReferenceException', () {
    test('the name is written escaped, quoted and cut', () {
      final error = PropertyReferenceException(
        'title\r\n2026-11-01 INFO FORGED',
        'Book',
      );
      expect(error.message, isNot(contains('\r')));
      expect(error.message, isNot(contains('\n')));
      expect('$error', isNot(contains('\n')));
      expect(
        error.message,
        contains('"title<EOL><EOL>2026-11-01 INFO FORGED"'),
      );
      expect(error.propertyName, 'title\r\n2026-11-01 INFO FORGED');
      expect(error.typeName, 'Book');
      expect(error, isA<InvalidDataAccessApiUsageException>());
      expect(error, isA<NonTransientDataAccessException>());
      final long = PropertyReferenceException('x' * 500, 'Book');
      expect(long.message.length, lessThan(250));
      expect(long.message, contains('(truncated)'));
    });

    test('control characters other than line breaks are replaced too', () {
      final error = PropertyReferenceException('a\u001b[31mb\u0000', 'Book');
      expect(error.message, isNot(contains('\u001b')));
      expect(error.message, isNot(contains('\u0000')));
    });
  });
}
