// Any object may be thrown in Dart; the tests throw strings and plain
// objects on purpose.
// ignore_for_file: only_throw_errors
// The transaction around a test of a @DataTest class: the order of the
// lifecycle methods in it, rollback and commit, and what a failure does.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/testing.dart';
import 'package:test/test.dart';

import '../mapping/support.dart' show Book, testContext;
import '../transaction/support/recording_transaction_manager.dart';

/// A bean factory holding [manager] as the application's transaction
/// manager.
DefaultListableBeanFactory _beans(RecordingTransactionManager manager) =>
    DefaultListableBeanFactory()..registerSingleton(
      'transactionManager',
      manager,
      types: const [PlatformTransactionManager],
    );

void main() {
  late RecordingTransactionManager manager;
  late DefaultListableBeanFactory beans;

  setUp(() {
    manager = RecordingTransactionManager();
    beans = _beans(manager);
  });

  test('a test is rolled back by default', () async {
    var ran = false;
    await runInTestTransaction(beans, () => ran = true);
    expect(ran, isTrue);
    expect(manager.calls, ['begin 1', 'rollback 1']);
  });

  test('with rollback: false it commits', () async {
    await runInTestTransaction(beans, () {}, rollback: false);
    expect(manager.calls, ['begin 1', 'commit 1']);
  });

  test('every test gets a transaction of its own', () async {
    await runInTestTransaction(beans, () {});
    await runInTestTransaction(beans, () {}, rollback: false);
    await runInTestTransaction(beans, () {});
    expect(manager.calls, [
      'begin 1',
      'rollback 1',
      'begin 2',
      'commit 2',
      'begin 3',
      'rollback 3',
    ]);
  });

  test('the lifecycle methods and the test run in the transaction, in order, '
      'and are awaited', () async {
    final steps = <String>[];
    FutureOr<void> step(String name) {
      steps.add('$name in ${manager.currentId}');
      return Future<void>.delayed(
        Duration.zero,
        () => steps.add('$name done'),
      );
    }

    await runInTestTransaction(
      beans,
      () => step('test'),
      before: [() => step('before one'), () => step('before two')],
      after: [() => step('after one'), () => step('after two')],
    );
    expect(steps, [
      'before one in 1',
      'before one done',
      'before two in 1',
      'before two done',
      'test in 1',
      'test done',
      'after one in 1',
      'after one done',
      'after two in 1',
      'after two done',
    ]);
    // Everything happened between the begin and the rollback.
    expect(manager.calls, ['begin 1', 'rollback 1']);
    expect(manager.current, isNull);
  });

  test('code that joins the transaction does not begin another', () async {
    final template = TransactionTemplate(manager);
    await runInTestTransaction(beans, () async {
      await template.execute((status) async {
        expect(status.isNewTransaction, isFalse);
        expect(manager.currentId, 1);
      });
    });
    expect(manager.calls, ['begin 1', 'rollback 1']);
  });

  group('a failing test', () {
    test('is thrown after the rollback, even with rollback: false', () async {
      var after = false;
      await expectLater(
        runInTestTransaction(
          beans,
          () => throw 'boom',
          rollback: false,
          after: [() => after = true],
        ),
        throwsA('boom'),
      );
      expect(after, isTrue);
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test('keeps its stack trace', () async {
      Future<void> fail() async => throw StateError('here');
      StackTrace? trace;
      try {
        await runInTestTransaction(beans, fail);
      } on StateError catch (error, stackTrace) {
        expect(error.message, 'here');
        trace = stackTrace;
      }
      expect(trace.toString(), contains('fail'));
    });

    test('a failing @BeforeEach skips the test and the later ones, but not '
        'the @AfterEach methods', () async {
      final steps = <String>[];
      await expectLater(
        runInTestTransaction(
          beans,
          () => steps.add('test'),
          before: [
            () => steps.add('before one'),
            () => throw 'no database',
            () => steps.add('before three'),
          ],
          after: [() => steps.add('after')],
        ),
        throwsA('no database'),
      );
      expect(steps, ['before one', 'after']);
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test('a failing @AfterEach does not stop the others, and the first '
        'failure is the one thrown; the others are logged', () async {
      final steps = <String>[];
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      addTearDown(stop);
      await expectLater(
        runInTestTransaction(
          beans,
          () => throw 'test failed',
          after: [
            () => throw 'cleanup failed',
            () => steps.add('second after'),
          ],
        ),
        throwsA('test failed'),
      );
      expect(steps, ['second after']);
      expect(
        records
            .where((r) => r.level == SpringLogLevel.warning)
            .map(
              (r) => r.error,
            ),
        ['cleanup failed'],
      );
    });

    test('a failing @AfterEach fails a passing test', () async {
      await expectLater(
        runInTestTransaction(beans, () {}, after: [() => throw 'cleanup']),
        throwsA('cleanup'),
      );
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test("the test's error wins over the one of the rollback", () async {
      manager.failRollback = 'disk gone';
      await expectLater(
        runInTestTransaction(beans, () => throw 'test failed'),
        throwsA('test failed'),
      );
    });
  });

  group('the end of the transaction', () {
    test('a rollback that fails fails the test', () async {
      manager.failRollback = StateError('cannot roll back');
      await expectLater(
        runInTestTransaction(beans, () {}),
        throwsA(
          isA<TransactionSystemException>().having(
            (e) => e.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );
    });

    test('a commit that fails fails the test', () async {
      manager.failCommit = StateError('constraint');
      await expectLater(
        runInTestTransaction(beans, () {}, rollback: false),
        throwsA(isA<TransactionSystemException>()),
      );
    });

    test('a participant that failed makes a committing test fail, as in '
        'Spring, and a rolling back one pass', () async {
      final template = TransactionTemplate(manager);
      Future<void> failingParticipant() async {
        await expectLater(
          template.execute<void>((status) => throw 'constraint'),
          throwsA('constraint'),
        );
      }

      await runInTestTransaction(beans, failingParticipant);
      await expectLater(
        runInTestTransaction(beans, failingParticipant, rollback: false),
        throwsA(isA<UnexpectedRollbackException>()),
      );
    });

    test('work started in the test and not awaited cannot use the ended '
        'transaction', () async {
      late Future<void> late_;
      await runInTestTransaction(beans, () {
        late_ = Future<void>.delayed(Duration.zero, () {
          manager.current;
        });
      });
      await expectLater(
        late_,
        throwsA(isA<IllegalTransactionStateException>()),
      );
    });
  });

  group('several transaction managers', () {
    late RecordingTransactionManager second;
    late DefaultListableBeanFactory many;

    setUp(() {
      second = RecordingTransactionManager();
      many = _beans(manager)
        ..registerSingleton(
          'archiveTransactionManager',
          second,
          types: const [PlatformTransactionManager],
        );
    });

    test('each has a transaction, rolled back together', () async {
      await runInTestTransaction(many, () {
        // A repository joins the transaction of its own manager.
        expect(manager.currentId, 1);
        expect(second.currentId, 1);
      });
      expect(manager.calls, ['begin 1', 'rollback 1']);
      expect(second.calls, ['begin 1', 'rollback 1']);
    });

    test('and committed together', () async {
      await runInTestTransaction(many, () {}, rollback: false);
      expect(manager.calls, ['begin 1', 'commit 1']);
      expect(second.calls, ['begin 1', 'commit 1']);
    });

    test('a failing test rolls all of them back', () async {
      await expectLater(
        runInTestTransaction(many, () => throw 'boom', rollback: false),
        throwsA('boom'),
      );
      expect(manager.calls, ['begin 1', 'rollback 1']);
      expect(second.calls, ['begin 1', 'rollback 1']);
    });

    test('a commit that fails rolls back the ones not committed yet', () async {
      // The last begun ends first.
      second.failCommit = StateError('constraint');
      await expectLater(
        runInTestTransaction(many, () {}, rollback: false),
        throwsA(isA<TransactionSystemException>()),
      );
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });

    test(
      'transactionManager names the only one that gets a transaction',
      () async {
        await runInTestTransaction(many, () {
          expect(manager.current, isNull);
          expect(second.currentId, 1);
        }, transactionManager: 'archiveTransactionManager');
        expect(manager.calls, isEmpty);
        expect(second.calls, ['begin 1', 'rollback 1']);
        await runInTestTransaction(
          many,
          () {},
          rollback: false,
          transactionManager: 'archiveTransactionManager',
        );
        expect(second.calls, [
          'begin 1',
          'rollback 1',
          'begin 2',
          'commit 2',
        ]);
        expect(manager.calls, isEmpty);
      },
    );

    test('an empty transactionManager means all of them', () async {
      await runInTestTransaction(many, () {}, transactionManager: '');
      expect(manager.calls, ['begin 1', 'rollback 1']);
      expect(second.calls, ['begin 1', 'rollback 1']);
    });

    test('a transactionManager no bean has fails and names it', () {
      expect(
        () => runInTestTransaction(many, () {}, transactionManager: 'nope'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("@DataTest(transactionManager: 'nope')"),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
    });

    test('the managers of the repositories are included', () async {
      final factory = RepositoryFactory(
        mappingContext: testContext(),
        converter: EntityConverter(),
      );
      final notes = factory.operations<Book, int>('BookRepository');
      many.registerSingleton(
        'repositoryFactory',
        factory,
        types: const [RepositoryFactory],
      );
      expect(factory.transactionManagers, hasLength(1));
      await runInTestTransaction(many, () async {
        await notes.save(Book(title: 'Dune'));
        expect(await notes.count(), 1);
      });
      // Rolled back with the others.
      expect(await notes.count(), 0);
      expect(manager.calls, ['begin 1', 'rollback 1']);
    });
  });

  test('a context without a transaction manager fails clearly', () {
    expect(
      () => runInTestTransaction(DefaultListableBeanFactory(), () {}),
      throwsA(isA<NoSuchBeanDefinitionException>()),
    );
  });
}
