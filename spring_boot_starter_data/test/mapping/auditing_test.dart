import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

class _Auditor implements AuditorAware<String> {
  _Auditor(this.name);
  final FutureOr<String?> name;
  int calls = 0;

  @override
  FutureOr<String?> getCurrentAuditor() {
    calls++;
    return name;
  }
}

void main() {
  late RelationalMappingContext context;
  late EntityConverter converter;
  late PersistentEntity<Book> book;
  final t1 = DateTime.utc(2024);
  final t2 = DateTime.utc(2025);
  setUp(() {
    context = testContext();
    converter = EntityConverter(introspector: context.introspector);
    book = context.getRequiredPersistentEntity<Book>();
  });

  AuditingHandler handler({
    AuditorAware<Object>? auditor,
    DateTime Function()? clock,
    bool setDates = true,
    bool modifyOnCreate = true,
  }) => AuditingHandler(
    converter: converter,
    auditorAware: auditor,
    dateTimeProvider: DateTimeProvider(clock ?? () => t1),
    setDates: setDates,
    modifyOnCreate: modifyOnCreate,
  );

  group('IsNewStrategy', () {
    const strategy = IsNewStrategy();

    test('with an int version: new when 0', () {
      expect(strategy.isNew(book, Book(id: 5, title: 'x')), isTrue);
      expect(
        strategy.isNew(book, Book(title: 'x', version: 1)),
        isFalse,
      );
      expect(
        strategy.isNew(book, Book(id: 5, title: 'x', version: 2)),
        isFalse,
      );
    });

    test('two versions on a class are refused', () {
      final i = BeanIntrospection<_Versioned>(
        className: 'Versioned',
        properties: [
          prop<_Versioned>(
            'v',
            int,
            const ClassType<int>(nullable: true),
            (o) => o.v,
            set: (o, x) => o.v = x as int?,
            annotations: const [Version()],
          ),
          prop<_Versioned>(
            'at',
            DateTime,
            const ClassType<DateTime>(nullable: true),
            (o) => o.at,
            set: (o, x) => o.at = x as DateTime?,
            annotations: const [Version()],
          ),
        ],
      );
      // Two versions are refused: test each alone.
      expect(
        () => RelationalMappingContext(
          introspector: BeanIntrospector(introspections: [i]),
        ).getRequiredPersistentEntity<_Versioned>(),
        throwsA(isA<MappingException>()),
      );
    });

    test('with a DateTime version: new only when null', () {
      final entity = context.fromIntrospection(_dateVersion());
      expect(strategy.isNew(entity, _Stamped()), isTrue);
      expect(strategy.isNew(entity, _Stamped()..at = t1), isFalse);
      // A DateTime is never "0".
      expect(
        strategy.isNew(
          entity,
          _Stamped()..at = DateTime.fromMillisecondsSinceEpoch(0),
        ),
        isFalse,
      );
    });

    test('without a version: new when the id is null', () {
      final item = context
          .getRequiredPersistentEntity<OrderLine>()
          .property('items')!
          .childEntity!;
      expect(strategy.isNew(item, Item(sku: 'a')), isTrue);
      expect(strategy.isNew(item, Item(id: 1, sku: 'a')), isFalse);
    });

    test('with neither id nor version', () {
      final tag = context
          .getRequiredPersistentEntity<OrderLine>()
          .property('tags')!
          .childEntity!;
      expect(
        () => strategy.isNew(tag, Tag('x')),
        throwsA(isA<MappingException>()),
      );
    });
  });

  group('AuditingHandler', () {
    test('markCreated sets all four, modifyOnCreate on', () async {
      final b = Book(title: 'x');
      final out = await handler(auditor: _Auditor('ann')).markCreated(book, b);
      expect(out, same(b));
      expect(b.createdAt, t1);
      expect(b.modifiedAt, t1);
      expect(b.createdBy, 'ann');
      expect(b.modifiedBy, 'ann');
    });

    test('markCreated without modifyOnCreate leaves modified alone', () async {
      final b = Book(title: 'x');
      await handler(
        auditor: _Auditor('ann'),
        modifyOnCreate: false,
      ).markCreated(book, b);
      expect(b.createdAt, t1);
      expect(b.createdBy, 'ann');
      expect(b.modifiedAt, isNull);
      expect(b.modifiedBy, isNull);
    });

    test('markModified keeps created and sets modified', () async {
      final b = Book(title: 'x', createdAt: t1, createdBy: 'ann');
      await handler(
        auditor: _Auditor('bob'),
        clock: () => t2,
      ).markModified(book, b);
      expect(b.createdAt, t1);
      expect(b.createdBy, 'ann');
      expect(b.modifiedAt, t2);
      expect(b.modifiedBy, 'bob');
    });

    test('an asynchronous auditor is awaited', () async {
      final b = Book(title: 'x');
      await handler(
        auditor: _Auditor(Future.delayed(Duration.zero, () => 'late')),
      ).markCreated(book, b);
      expect(b.createdBy, 'late');
    });

    test('no auditor: the dates only', () async {
      final b = Book(title: 'x');
      await handler().markCreated(book, b);
      expect(b.createdAt, t1);
      expect(b.createdBy, isNull);
    });

    test('a null auditor leaves the properties as they are', () async {
      final b = Book(title: 'x', modifiedBy: 'old');
      await handler(auditor: _Auditor(null)).markModified(book, b);
      expect(b.modifiedBy, 'old');
      expect(b.modifiedAt, t1);
    });

    test('setDates false sets only the auditors', () async {
      final b = Book(title: 'x');
      await handler(
        auditor: _Auditor('ann'),
        setDates: false,
      ).markCreated(book, b);
      expect(b.createdAt, isNull);
      expect(b.modifiedAt, isNull);
      expect(b.createdBy, 'ann');
    });

    test('the auditor is asked once per marking', () async {
      final auditor = _Auditor('ann');
      await handler(auditor: auditor).markCreated(book, Book(title: 'x'));
      expect(auditor.calls, 1);
    });

    test('an entity without audit properties is returned as is', () async {
      final item = context
          .getRequiredPersistentEntity<OrderLine>()
          .property('items')!
          .childEntity!;
      final auditor = _Auditor('ann');
      final i = Item(sku: 'a');
      expect(await handler(auditor: auditor).markCreated(item, i), same(i));
      expect(auditor.calls, 0);
    });

    test('final audit properties: a copy is returned', () async {
      final reading = context.getRequiredPersistentEntity<Reading>();
      final r = makeReading(1, 'a');
      final out = await handler().markCreated(reading, r);
      expect(out, isNot(same(r)));
      expect(out.created, t1);
      expect(out.text, 'a');
      expect(r.created, isNull);
    });

    test('the clock defaults to the system time', () {
      final before = DateTime.now();
      final now = const DateTimeProvider().now();
      expect(now.isBefore(before), isFalse);
    });
  });

  test('EnableDataAuditing defaults', () {
    const a = EnableDataAuditing();
    expect(a.auditorAwareRef, '');
    expect(a.dateTimeProviderRef, '');
    expect(a.setDates, isTrue);
    expect(a.modifyOnCreate, isTrue);
  });
}

class _Versioned {
  int? v;
  DateTime? at;
}

class _Stamped {
  DateTime? at;
}

BeanIntrospection<_Stamped> _dateVersion() => BeanIntrospection<_Stamped>(
  className: 'Stamped',
  properties: [
    prop<_Stamped>(
      'at',
      DateTime,
      const ClassType<DateTime>(nullable: true),
      (o) => o.at,
      set: (o, x) => o.at = x as DateTime?,
      annotations: const [Version()],
    ),
  ],
);
