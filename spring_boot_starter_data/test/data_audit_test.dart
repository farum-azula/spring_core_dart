// Release-build behaviour without the startup checks, and what a request can
// make the starter do: a sync @Transactional method is refused before its
// body runs, a LIKE pattern takes linear time, a sort is limited and may be
// allow-listed.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'transaction/support/recording_transaction_manager.dart';

final class _Call implements MethodInvocation {
  _Call(this.signature, this.onProceed);

  @override
  final MethodSignature signature;
  final Object? Function() onProceed;

  @override
  List<Object?> get args => const [];

  @override
  Object get target => this;

  @override
  Object get proxy => this;

  @override
  Object? proceed([List<Object?>? arguments]) => onProceed();

  @override
  String toShortString() => 'Orders.sync()';
}

void main() {
  test(
    'a sync @Transactional method fails before its body runs, with nothing '
    'committed (CD-5)',
    () async {
      final manager = RecordingTransactionManager();
      final interceptor = TransactionInterceptor(transactionManager: manager);
      var ran = 0;
      const signature = MethodSignature(
        name: 'sync',
        declaringType: 'Orders',
        targetType: 'Orders',
        returnType: 'int',
        annotations: [Transactional()],
      );
      expect(
        () => interceptor.invoke(
          _Call(signature, () {
            ran++;
            return 5;
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not a Future'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(ran, 0);
      expect(manager.calls, isEmpty);
    },
  );

  group('LIKE in Dart (D1)', () {
    test('matches as SQL does', () {
      bool like(String pattern, String text) =>
          LikePattern(pattern).matches(text);
      expect(like('%Dune%', 'The Dune book'), isTrue);
      expect(like('D_ne', 'Dune'), isTrue);
      expect(like('D_ne', 'Dne'), isFalse);
      expect(like('a%b', 'ab'), isTrue);
      expect(like('a%b', 'axxbxb'), isTrue);
      expect(like('a%b', 'axxbx'), isFalse);
      expect(like(r'100\%', '100%'), isTrue);
      expect(like(r'100\%', '1000'), isFalse);
      expect(like(r'a\_b', 'axb'), isFalse);
      expect(like('', ''), isTrue);
      expect(like('%', ''), isTrue);
      expect(like('_', ''), isFalse);
      expect(like('a\nb', 'a\nb'), isTrue);
      expect(like('a_b', 'a\nb'), isTrue);
    });

    test('a pattern made to backtrack takes linear time', () {
      final watch = Stopwatch()..start();
      expect(LikePattern('${'%a' * 30}%b').matches('a' * 4000), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a pattern longer than SQLite allows is refused', () {
      expect(
        () => LikePattern('a' * (LikePattern.maxLength + 1)),
        throwsA(isA<InvalidDataAccessApiUsageException>()),
      );
    });
  });

  group('sort from a request', () {
    const paging = WebPaging();

    test('more than 16 properties is a 400 (D3)', () {
      expect(
        () => paging.sort({
          'sort': [for (var i = 0; i < 17; i++) 'p$i'],
        }),
        throwsA(isA<InvalidPagingRequestException>()),
      );
      final many = paging.sort({'sort': List.filled(5000, 'title')});
      expect(many.orders.map((o) => o.property), ['title']);
    });

    test('a property named twice keeps its first order (D3)', () {
      final sort = paging.sort({
        'sort': ['title,desc', 'year', 'title'],
      });
      expect(sort.orders.map((o) => '${o.property} ${o.direction.name}'), [
        'title desc',
        'year asc',
      ]);
    });

    test('@AllowedSortProperties refuses another property (D2)', () {
      const allowed = AllowedSortProperties(['title', 'year']);
      expect(
        paging
            .sort({
              'sort': ['year,desc'],
            }, allowed: allowed)
            .orders
            .single
            .property,
        'year',
      );
      expect(
        () => paging.pageable({
          'sort': ['passwordHash'],
        }, allowed: allowed),
        throwsA(isA<PropertyReferenceException>()),
      );
      expect(
        paging
            .pageable(
              {},
              pageableDefault: const PageableDefault(sort: ['rating']),
              allowed: allowed,
            )
            .sort
            .orders
            .single
            .property,
        'rating',
        reason: 'the defaults are the developer’s',
      );
    });
  });
}
