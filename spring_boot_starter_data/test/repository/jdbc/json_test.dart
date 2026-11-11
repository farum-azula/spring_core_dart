// JSON columns (@Json): the converter's trees, and the same aggregate on the
// memory store, SQLite and PostgreSQL: the round trip, what each database
// keeps, the schema the starter creates and validates, @Query methods that
// read and filter JSON, and what is refused.
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../../postgres/support.dart' show postgresServerSkip, usePostgresServer;
import 'support.dart';

UserProfile _ada() => UserProfile(
  name: 'ada',
  settings: Settings(
    theme: 'dark',
    fontSize: 14,
    layout: Layout(columns: 2, pinned: ['inbox', 'todo']),
  ),
  raw: {
    'tags': ['a', 'b'],
    'depth': {'n': 1, 'ok': true},
    'ratio': 1.5,
  },
  addresses: [
    Address(street: 'Oak St', city: 'Ely'),
    Address(street: 'Elm St'),
  ],
);

Matcher _mapping(String text) => throwsA(
  isA<MappingException>().having((e) => e.message, 'message', contains(text)),
);

Matcher _usage(String text) => throwsA(
  isA<InvalidDataAccessApiUsageException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void _expectAda(UserProfile? read) {
  expect(read, isNotNull);
  expect(read!.settings.theme, 'dark');
  expect(read.settings.fontSize, 14);
  expect(read.settings.layout!.columns, 2);
  expect(read.settings.layout!.pinned, ['inbox', 'todo']);
  expect(read.raw, {
    'tags': ['a', 'b'],
    'depth': {'n': 1, 'ok': true},
    'ratio': 1.5,
  });
  expect([for (final a in read.addresses!) a.street], ['Oak St', 'Elm St']);
  expect([for (final a in read.addresses!) a.city], ['Ely', null]);
}

void main() {
  setUpAll(() => SpringLog.handler = (_) {});

  group('converter', () {
    test('uses the ObjectMapper bean of the application, else one of its '
        'own', () async {
      final mapper = ObjectMapper();
      await const ApplicationContextRunner()
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .withUserConfiguration(
            BeanModule('json', [
              BeanDefinition<ObjectMapper>(
                name: 'objectMapper',
                create: (_) => mapper,
              ),
            ]),
          )
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            expect(context.getBean<EntityConverter>().mapper, same(mapper));
          });
      await withJdbc((j) {
        expect(j.context.getBean<EntityConverter>().mapper, isNotNull);
      });
    });

    test('write: a class, nested, as a tree; a list of classes; a map; '
        'null stays null', () {
      return withJdbc((j) {
        final converter = j.context.getBean<EntityConverter>();
        final entity = j.entity<UserProfile>();
        final row = converter.write(entity, _ada());
        final settings = row['settings']! as Map<String, Object?>;
        expect(settings['theme'], 'dark');
        expect(settings['fontSize'], 14);
        expect(settings['layout'], {
          'columns': 2,
          'pinned': ['inbox', 'todo'],
        });
        final addresses = row['addresses']! as List<Object?>;
        expect((addresses[0]! as Map<String, Object?>)['street'], 'Oak St');
        expect((addresses[1]! as Map<String, Object?>)['city'], isNull);
        expect(row['raw'], {
          'tags': ['a', 'b'],
          'depth': {'n': 1, 'ok': true},
          'ratio': 1.5,
        });
        expect(row['name'], 'ada');
        final none = converter.write(
          entity,
          UserProfile(
            name: 'bob',
            settings: Settings(theme: 'light'),
          ),
        );
        expect(none['addresses'], isNull);
        expect(none.containsKey('addresses'), isTrue);
      });
    });

    test('read: from the tree and from JSON text, sharing nothing', () {
      return withJdbc((j) {
        final converter = j.context.getBean<EntityConverter>();
        final entity = j.entity<UserProfile>();
        final row = converter.write(entity, _ada());
        final read = converter.read(entity, row);
        _expectAda(read);
        read.raw['added'] = 1;
        (read.raw['tags']! as List<Object?>).add('c');
        expect(
          (row['raw']! as Map<String, Object?>).containsKey('added'),
          isFalse,
        );
        expect((row['raw']! as Map<String, Object?>)['tags'], ['a', 'b']);
        final text = converter.read(entity, {
          'id': 1,
          'name': 'ada',
          'settings': '{"theme":"dark","fontSize":9}',
          'raw': '{"a":[1,2]}',
          'addresses': '[{"street":"Oak St"}]',
        });
        expect(text.settings.fontSize, 9);
        expect(text.raw, {
          'a': [1, 2],
        });
        expect(text.addresses!.single.street, 'Oak St');
        expect(
          converter.read(entity, {
            'name': 'n',
            'settings': {'theme': 't'},
            'raw': <String, Object?>{},
            'addresses': null,
          }).addresses,
          isNull,
        );
      });
    });

    test('a stored value that does not fit: a MappingException naming the '
        'property, without the value', () {
      return withJdbc((j) {
        final converter = j.context.getBean<EntityConverter>();
        final entity = j.entity<UserProfile>();
        Object? read(Object? settings, {Object? addresses}) => converter.read(
          entity,
          {
            'name': 'n',
            'settings': settings,
            'raw': <String, Object?>{},
            'addresses': addresses,
          },
        );
        for (final bad in <Object>[
          {'theme': 't', 'fontSize': 'big-4711'},
          <Object?>[1, 2],
          4711,
          'secret-4711',
          '{"fontSize": "big-4711", "theme": "t"}',
          <String, Object?>{},
        ]) {
          expect(
            () => read(bad),
            throwsA(
              isA<MappingException>()
                  .having(
                    (e) => e.message,
                    'message',
                    contains(
                      'UserProfile.settings: the stored JSON cannot be read',
                    ),
                  )
                  .having((e) => e.message, 'message', isNot(contains('4711'))),
            ),
            reason: '$bad',
          );
        }
        expect(
          () => read(
            {'theme': 't'},
            addresses: [
              {'street': 'a'},
              {'city': 'no street'},
            ],
          ),
          _mapping('UserProfile.addresses: the stored JSON cannot be read'),
        );
        expect(() => read(null), _mapping('UserProfile.settings is null'));
      });
    });
  });

  group('memory', () {
    test(
      'keeps the tree: saved, read, updated, detached from the instance',
      () {
        return withJdbc((j) async {
          final profiles = j.memoryProfiles;
          final ada = _ada();
          final saved = await profiles.save(ada);
          ada.settings.theme = 'changed after the save';
          ada.raw['later'] = true;
          _expectAda(await profiles.findById(saved.id!));
          final read = (await profiles.findByName('ada')).single;
          read.settings.fontSize = 20;
          read.addresses = null;
          await profiles.save(read);
          final again = (await profiles.findById(saved.id!))!;
          expect(again.settings.fontSize, 20);
          expect(again.addresses, isNull);
        });
      },
    );

    test('a condition or an order on a @Json property is refused', () {
      return withJdbc((j) {
        _refusals(j, const []);
      });
    });
  });

  for (final db in const ['sqlite', 'postgres']) {
    group(
      db,
      () {
        if (db == 'postgres') {
          usePostgresServer();
        }
        _suite(postgres: db == 'postgres');
      },
      skip: db == 'postgres' ? postgresServerSkip : null,
      tags: db == 'postgres' ? 'postgres' : null,
    );
  }
}

// The run-time refusal, on the store [annotations] select.
void _refusals(Jdbc j, List<Object> annotations) {
  final operations = j.factory.operations<UserProfile, int>(
    'Profiles',
    annotations: annotations,
  );
  const fix =
      "use @Query with the database's JSON operators on a SQL store, or "
      '@Procedure';
  expect(
    () => operations.list(
      const PartTree('findBySettings', [
        OrPart([Part('settings')]),
      ]),
      [Settings(theme: 'dark')],
    ),
    _usage(
      'Profiles.findBySettings: a derived query cannot filter by the @Json '
      'property UserProfile.settings: $fix',
    ),
  );
  expect(
    () => operations.countBy(
      const PartTree('countByRawIsNull', [
        OrPart([Part('raw', PartType.isNull)]),
      ]),
      const [],
    ),
    _usage('cannot filter by the @Json property UserProfile.raw'),
  );
  expect(
    () => operations.findAllSorted(Sort.by(['addresses'])),
    _usage(
      'Profiles.findAllSorted: a derived query cannot sort by the @Json '
      'property UserProfile.addresses: $fix',
    ),
  );
  expect(
    () => operations.findAllPaged(
      PageRequest.of(0, 5, Sort.by(['name', 'settings'])),
    ),
    _usage('cannot sort by the @Json property UserProfile.settings'),
  );
  // A sort often comes from a request (?sort=settings): refused as a
  // property that does not exist is (a 400 in the web starter's answers),
  // and from the Future, not thrown at the call.
  final refused = operations.findAllPaged(
    PageRequest.of(0, 5, Sort.by(['settings'])),
  );
  expect(refused, throwsA(isA<PropertyReferenceException>()));
}

void _suite({required bool postgres}) {
  Future<void> run(
    Future<void> Function(Jdbc j) body, {
    bool create = true,
  }) => withJdbc(postgres: postgres, (j) async {
    if (create) {
      await SchemaCreator(j.dataSource).create([j.entity<UserProfile>()]);
    }
    await body(j);
  });

  Future<Object?> one(Jdbc j, String sql) =>
      j.jdbc.queryForObject<Object?>(sql);

  test(
    'the schema the starter creates: the column types, and it validates',
    () {
      return run((j) async {
        if (postgres) {
          final types = {
            for (final row in await j.jdbc.queryForMaps(
              'select column_name, data_type from information_schema.columns '
              "where table_name = 'profiles' "
              'and table_schema = current_schema()',
            ))
              row['column_name']: row['data_type'],
          };
          expect(types['settings'], 'jsonb');
          expect(types['raw'], 'json');
          expect(types['addresses'], 'jsonb');
        } else {
          final sql = await one(
            j,
            "select sql from sqlite_master where name = 'profiles'",
          );
          expect(
            sql,
            allOf(
              contains(
                '"settings" TEXT NOT NULL CHECK (json_valid("settings"))',
              ),
              contains('"raw" TEXT NOT NULL CHECK (json_valid("raw"))'),
              contains('"addresses" TEXT CHECK (json_valid("addresses"))'),
            ),
          );
        }
        final report = await SchemaValidator(
          j.dataSource,
        ).validate([j.entity<UserProfile>()]);
        expect(report.problems, isEmpty);
      });
    },
  );

  test('validation reports a column of another type', () {
    return run(create: false, (j) async {
      await j.jdbc.execute(
        postgres
            ? 'create table profiles (id bigint primary key, name text '
                  'not null, settings json not null, raw jsonb not null, '
                  'addresses text)'
            : 'create table profiles (id integer primary key, name text '
                  'not null, settings integer not null, raw text not null, '
                  'addresses json)',
      );
      final report = await SchemaValidator(
        j.dataSource,
      ).validate([j.entity<UserProfile>()]);
      if (postgres) {
        expect(report.problems, hasLength(3));
        expect(
          report.problems,
          containsAll(<Matcher>[
            allOf(
              contains('Column "settings" in table'),
              contains(
                'for UserProfile.settings has the wrong type: expected ',
              ),
              contains('JSONB'),
              contains('found json'),
            ),
            allOf(contains('Column "raw"'), contains('found jsonb')),
            allOf(contains('Column "addresses"'), contains('found text')),
          ]),
        );
      } else {
        expect(report.problems, [
          allOf(
            contains(
              'Column "settings" in table "profiles" for '
              'UserProfile.settings has the wrong type: expected TEXT',
            ),
            contains('found INTEGER'),
          ),
        ]);
      }
    });
  });

  test('saved, read, updated; a null list is a SQL NULL', () {
    return run((j) async {
      final profiles = j.sqlProfiles;
      final saved = await profiles.save(_ada());
      _expectAda(await profiles.findById(saved.id!));
      _expectAda((await profiles.findByName('ada')).single);
      final read = (await profiles.findById(saved.id!))!;
      read.settings
        ..layout = null
        ..theme = 'light';
      read
        ..addresses = null
        ..raw = {'only': null};
      await profiles.save(read);
      final again = (await profiles.findAll()).single;
      expect(again.settings.theme, 'light');
      expect(again.settings.layout, isNull);
      expect(again.addresses, isNull);
      expect(again.raw, {'only': null});
      expect(
        await one(j, 'select count(*) from profiles where addresses is null'),
        1,
      );
      await profiles.saveAll([
        UserProfile(
          name: 'bob',
          settings: Settings(theme: 'dark'),
        ),
        UserProfile(
          name: 'cy',
          settings: Settings(theme: 'dark'),
          addresses: [],
        ),
      ]);
      expect(await profiles.count(), 3);
      expect((await profiles.findByName('cy')).single.addresses, isEmpty);
    });
  });

  test('what the database keeps', () {
    return run((j) async {
      await j.sqlProfiles.save(_ada());
      if (postgres) {
        expect(
          await one(
            j,
            'select jsonb_typeof(settings) || json_typeof(raw) || '
            'jsonb_typeof(addresses) from profiles',
          ),
          'objectobjectarray',
        );
        expect(
          await one(j, "select settings #>> '{layout,pinned,1}' from profiles"),
          'todo',
        );
      } else {
        expect(
          await one(j, 'select typeof(settings) from profiles'),
          'text',
        );
        expect(
          await one(
            j,
            r"select json_extract(settings, '$.layout.pinned[1]') "
            'from profiles',
          ),
          'todo',
        );
        // The created table refuses a text that is no JSON.
        await expectLater(
          j.jdbc.update("update profiles set settings = 'no json'"),
          throwsA(isA<DataAccessException>()),
        );
      }
    });
  });

  test('@Query: the entity with its JSON columns, a filter with a JSON '
      'operator, a class with a @Json property', () {
    return run((j) async {
      final profiles = j.sqlProfiles;
      await profiles.saveAll([
        _ada(),
        UserProfile(
          name: 'bob',
          settings: Settings(theme: 'light'),
        ),
        UserProfile(
          name: 'cy',
          settings: Settings(theme: 'dark', fontSize: 8),
        ),
      ]);
      _expectAda(await profiles.named('ada'));
      expect(await profiles.named('nobody'), isNull);
      expect((await profiles.themed('dark')).map((p) => p.name), ['ada', 'cy']);
      expect((await profiles.themed('light')).single.settings.theme, 'light');
      final cards = await profiles.cards();
      expect(cards.map((c) => c.name), ['ada', 'bob', 'cy']);
      expect(cards.map((c) => c.settings.fontSize), [14, 12, 8]);
      expect(cards.first.settings.layout!.pinned, ['inbox', 'todo']);
    });
  });

  test('a stored value that cannot be read: a MappingException naming the '
      'property', () {
    return run(create: false, (j) async {
      await j.jdbc.execute(
        postgres
            ? 'create table profiles (id bigint primary key, name text, '
                  'settings jsonb, raw json, addresses jsonb)'
            : 'create table profiles (id integer primary key, name text, '
                  'settings text, raw text, addresses text)',
      );
      await j.jdbc.update(
        postgres
            ? "insert into profiles values (1, 'a', '[4711]', '{}', null)"
            : "insert into profiles values (1, 'a', 'secret-4711', '{}', null)",
      );
      await expectLater(
        j.sqlProfiles.findById(1),
        throwsA(
          isA<MappingException>()
              .having(
                (e) => e.message,
                'message',
                contains(
                  postgres
                      ? 'UserProfile.settings: the stored JSON cannot be read'
                      : 'UserProfile.settings: the stored value is not JSON',
                ),
              )
              .having((e) => e.message, 'message', isNot(contains('4711'))),
        ),
      );
      await j.jdbc.update(
        """update profiles set settings = '{"theme": "t"}', """
        """addresses = '{"street": 1}'""",
      );
      await expectLater(
        j.sqlProfiles.named('a'),
        _mapping('UserProfile.addresses: the stored JSON cannot be read as'),
      );
    });
  });

  test('a condition or an order on a @Json property is refused', () {
    return run((j) async {
      _refusals(j, const [UseStore('jdbc')]);
    });
  });
}
