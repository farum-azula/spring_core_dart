// The info endpoint and its contributors: Spring Boot's
// build-info.properties and git.properties, the info.* properties, the
// operating system and the Dart version, in Spring Boot's JSON.
import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:test/test.dart';

Map<String, Object?> contributed(InfoContributor contributor) {
  final builder = InfoBuilder();
  // The contributors tested here answer at once.
  // ignore: discarded_futures
  contributor.contribute(builder);
  return builder.build().details;
}

final class Fixed implements InfoContributor {
  Fixed(this.details);

  final Map<String, Object?> details;

  @override
  Future<void> contribute(InfoBuilder builder) async =>
      builder.withDetails(details);
}

void main() {
  group('times', () {
    test("written as Java's Instant.toString", () {
      expect(
        InfoProperties.instantText(DateTime.utc(2026, 11, 5, 9, 12, 44)),
        '2026-11-05T09:12:44Z',
      );
      expect(
        InfoProperties.instantText(DateTime.utc(2026, 11, 5, 9, 12, 44, 120)),
        '2026-11-05T09:12:44.120Z',
      );
      expect(
        InfoProperties.instantText(
          DateTime.utc(2026, 11, 5, 9, 12, 44, 120, 5),
        ),
        '2026-11-05T09:12:44.120005Z',
      );
    });

    test('read from ISO-8601 or milliseconds', () {
      expect(
        InfoProperties.parseInstant('2026-11-05T10:12:44+0100'),
        DateTime.utc(2026, 11, 5, 9, 12, 44),
      );
      expect(
        InfoProperties.parseInstant('1700000000000'),
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(InfoProperties.parseInstant('soon'), isNull);
      expect(InfoProperties.parseInstant(null), isNull);
    });
  });

  group('build', () {
    final properties = BuildProperties({
      'group': 'com.example',
      'artifact': 'shop',
      'name': 'Shop',
      'version': '1.4.0',
      'time': '2026-11-05T09:12:44.000Z',
      'dart.version': '3.13.7',
    });

    test('the typed values of BuildProperties', () {
      expect(properties.name, 'Shop');
      expect(properties.version, '1.4.0');
      expect(properties.group, 'com.example');
      expect(properties.artifact, 'shop');
      expect(properties.time, DateTime.utc(2026, 11, 5, 9, 12, 44));
    });

    test('the build contributor nests the keys and writes the time', () {
      expect(contributed(BuildInfoContributor(properties)), {
        'build': {
          'group': 'com.example',
          'artifact': 'shop',
          'name': 'Shop',
          'version': '1.4.0',
          'time': '2026-11-05T09:12:44Z',
          'dart': {'version': '3.13.7'},
        },
      });
    });

    test('loaded from a properties file without the build. prefix', () async {
      final resource = ByteArrayResource.fromString(
        'build.name=Shop\nbuild.version=2.0.0\nother=ignored\n',
      );
      final loaded = await BuildProperties.load(resource);
      expect(loaded.name, 'Shop');
      expect(loaded.version, '2.0.0');
      expect(loaded.get('other'), isNull);
      expect(BuildProperties.loadSync(resource).version, '2.0.0');
    });
  });

  group('git', () {
    final properties = GitProperties({
      'branch': 'main',
      'commit.id': '4faa522d0c1e9a6b8f',
      'commit.time': '1762333331',
      'commit.message.short': 'Fix the thing',
      'commit.user.name': 'Ada',
    });

    test('the short id is the abbreviation or 7 characters', () {
      expect(properties.shortCommitId, '4faa522');
      expect(
        GitProperties({
          'commit.id': 'abcdef0123',
          'commit.id.abbrev': 'abcd',
        }).shortCommitId,
        'abcd',
      );
      expect(GitProperties({'commit.id': 'abc'}).shortCommitId, 'abc');
    });

    test('times in seconds are read as such', () {
      expect(
        properties.commitTime,
        DateTime.fromMillisecondsSinceEpoch(1762333331000, isUtc: true),
      );
    });

    test('simple mode: branch, short id and time', () {
      expect(contributed(GitInfoContributor(properties)), {
        'git': {
          'branch': 'main',
          'commit': {'id': '4faa522', 'time': '2025-11-05T09:02:11Z'},
        },
      });
    });

    test('full mode: every key, nested', () {
      final full = contributed(
        GitInfoContributor(properties, mode: InfoPropertiesMode.full),
      );
      expect(full, {
        'git': {
          'branch': 'main',
          'commit': {
            'id': '4faa522d0c1e9a6b8f',
            'time': '2025-11-05T09:02:11Z',
            'message': {'short': 'Fix the thing'},
            'user': {'name': 'Ada'},
          },
        },
      });
    });

    test('no git information: no git detail', () {
      expect(contributed(GitInfoContributor(GitProperties({}))), isEmpty);
    });
  });

  test('nestedInfo keeps a value that is also a prefix under full', () {
    expect(
      nestedInfo([
        const MapEntry('commit.id', 'abc'),
        const MapEntry('commit.id.abbrev', 'a'),
      ]),
      {
        'commit': {
          'id': {'full': 'abc', 'abbrev': 'a'},
        },
      },
    );
    expect(
      nestedInfo([
        const MapEntry('commit.id.abbrev', 'a'),
        const MapEntry('commit.id', 'abc'),
      ]),
      {
        'commit': {
          'id': {'abbrev': 'a', 'full': 'abc'},
        },
      },
    );
  });

  test('env: the info.* properties without the prefix, nested', () {
    final environment = StandardEnvironment()
      ..propertySources.addFirst(
        const MapPropertySource('test', {
          'info.app.name': 'Shop',
          'info.app.owner': r'${owner}',
          'owner': 'team-books',
          'info.region': 'eu',
          'information': 'not mine',
        }),
      );
    expect(contributed(EnvironmentInfoContributor(environment)), {
      'app': {'name': 'Shop', 'owner': 'team-books'},
      'region': 'eu',
    });
  });

  test('os and dart describe the running platform', () {
    final os = contributed(OsInfoContributor())['os']! as Map;
    expect(os.keys, ['name', 'version', 'arch']);
    final dart = contributed(DartInfoContributor())['dart']! as Map;
    expect(dart['version'], matches(RegExp(r'^\d+\.\d+\.\d+')));
    expect((dart['runtime']! as Map)['name'], 'Dart VM');
  }, testOn: 'vm');

  test('the endpoint merges the contributors in order', () async {
    final endpoint = InfoEndpoint([
      Fixed({'a': 1, 'b': 1}),
      Fixed({'b': 2}),
    ]);
    expect(await endpoint.info(), {'a': 1, 'b': 2});
    expect(await InfoEndpoint(const []).info(), isEmpty);
  });
}
