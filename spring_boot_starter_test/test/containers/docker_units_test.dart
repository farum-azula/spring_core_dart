// What the containers need that does not need a Docker daemon: the tar
// archives, the endpoint, the configuration, the answers' parsing, the
// modules' properties.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

class _Properties implements DynamicPropertyRegistry {
  final Map<String, Object? Function()> suppliers = {};

  @override
  void add(String name, Object? Function() valueSupplier) =>
      suppliers[name] = valueSupplier;

  Map<String, Object?> get values => {
    for (final e in suppliers.entries) e.key: e.value(),
  };
}

// A PostgresContainer that says it is started, with fixed ports.
class _StartedPostgres extends PostgresContainer {
  _StartedPostgres() : super('postgres:17');

  @override
  String get host => 'db.test';

  @override
  int mappedPort(int port) => 55432;
}

class _StartedKeycloak extends KeycloakContainer {
  _StartedKeycloak() : super('keycloak:test');

  @override
  String get host => 'sso.test';

  @override
  int mappedPort(int port) => 58080;
}

String _field(Uint8List header, int offset, int length) {
  final end = header.indexOf(0, offset);
  return utf8.decode(
    header.sublist(
      offset,
      end == -1 || end > offset + length ? offset + length : end,
    ),
  );
}

void main() {
  group('tarArchive', () {
    test('writes ustar headers with the size, mode and a valid checksum', () {
      final tar = tarArchive(
        [
          TarFile('/etc/app/config.json', utf8.encode('{"a":1}')),
          TarFile('run.sh', utf8.encode('echo'), mode: 0x1ED),
        ],
        modified: DateTime.utc(2026),
      );
      // Two files of one block each, plus their headers, plus the end.
      expect(tar.length, 512 * 4 + 1024);
      expect(_field(tar, 0, 100), 'etc/app/config.json');
      expect(_field(tar, 100, 8), '0000644');
      expect(int.parse(_field(tar, 124, 12), radix: 8), 7);
      expect(_field(tar, 257, 6), 'ustar');
      expect(utf8.decode(tar.sublist(512, 519)), '{"a":1}');
      expect(_field(tar, 512 * 2, 100), 'run.sh');
      expect(_field(tar, 512 * 2 + 100, 8), '0000755');
      // The checksum counts the checksum field as eight spaces.
      for (final start in [0, 1024]) {
        final header = Uint8List.fromList(tar.sublist(start, start + 512));
        final stored = int.parse(_field(header, 148, 8).trim(), radix: 8);
        header.fillRange(148, 156, 32);
        expect(stored, header.fold<int>(0, (a, b) => a + b));
      }
      expect(tar.sublist(tar.length - 1024), everyElement(0));
    });

    test('splits a long path into prefix and name', () {
      final directory = List.filled(8, 'x' * 20).join('/'); // 167 characters
      final tar = tarArchive([
        TarFile('$directory/file.txt', const [1]),
      ]);
      // 155 characters of prefix at most, and the rest is the name.
      final prefix = _field(tar, 345, 155);
      expect(prefix.length, lessThanOrEqualTo(155));
      expect('$prefix/${_field(tar, 0, 100)}', '$directory/file.txt');
    });

    test('rejects a path that cannot be split', () {
      expect(
        () => tarArchive([TarFile('x' * 120, const [])]),
        throwsArgumentError,
      );
    });

    test('pads the content to whole blocks', () {
      final tar = tarArchive([TarFile('a', Uint8List(513))]);
      expect(tar.length, 512 + 1024 + 1024);
    });
  });

  group('DockerEndpoint', skip: Platform.isWindows ? 'Unix sockets' : null, () {
    late Directory temp;
    late ServerSocket socket;
    late String path;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('docker-endpoint');
      path = '${temp.path}/docker.sock';
      socket = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
    });

    tearDown(() async {
      await socket.close();
      await temp.delete(recursive: true);
    });

    test('DOCKER_HOST with unix:// names the socket', () {
      final endpoint = DockerEndpoint.resolve(
        environment: {'DOCKER_HOST': 'unix://$path'},
      );
      expect(endpoint?.socketPath, path);
      expect(endpoint?.containerHost, '127.0.0.1');
      expect(endpoint?.publishIp, '127.0.0.1');
    });

    test('DOCKER_HOST with a missing socket says so', () {
      final environment = {'DOCKER_HOST': 'unix://$path.missing'};
      expect(DockerEndpoint.resolve(environment: environment), isNull);
      expect(
        DockerEndpoint.unavailableReason(environment: environment),
        contains('there is no socket'),
      );
    });

    test('the usual sockets are looked at without DOCKER_HOST', () {
      // Colima's socket, in a home directory of its own.
      Directory('${temp.path}/.colima/default').createSync(recursive: true);
      final colima = '${temp.path}/.colima/default/docker.sock';
      File(path).renameSync(colima); // a socket moves as a file
      final candidates = DockerEndpoint.candidateSockets({'HOME': temp.path});
      expect(
        candidates,
        containsAllInOrder([
          '/var/run/docker.sock',
          '${temp.path}/.docker/run/docker.sock',
          colima,
        ]),
      );
    });

    test('tcp:// gives the host and a default port', () {
      final endpoint = DockerEndpoint.resolve(
        environment: {'DOCKER_HOST': 'tcp://docker.internal'},
      );
      expect(endpoint?.host, 'docker.internal');
      expect(endpoint?.port, 2375);
      expect(endpoint?.containerHost, 'docker.internal');
      expect(endpoint?.publishIp, isEmpty);
      expect(
        DockerEndpoint.resolve(
          environment: {'DOCKER_HOST': 'tcp://10.0.0.5:2376'},
        )?.port,
        2376,
      );
    });

    test('other schemes are refused with the supported ones', () {
      expect(
        DockerEndpoint.unavailableReason(
          environment: {'DOCKER_HOST': 'ssh://me@box'},
        ),
        allOf(contains('not supported'), contains('unix:///path')),
      );
    });
  });

  group('DockerClient', () {
    test('parseImage splits the tag and keeps registry ports', () {
      expect(DockerClient.parseImage('postgres'), ('postgres', 'latest'));
      expect(DockerClient.parseImage('postgres:17'), ('postgres', '17'));
      expect(
        DockerClient.parseImage('quay.io/keycloak/keycloak:26.8'),
        ('quay.io/keycloak/keycloak', '26.8'),
      );
      expect(
        DockerClient.parseImage('localhost:5000/team/app'),
        ('localhost:5000/team/app', 'latest'),
      );
      expect(
        DockerClient.parseImage('redis@sha256:abc'),
        ('redis@sha256:abc', null),
      );
    });

    test('a missing daemon is a DockerUnavailableException', () async {
      await expectLater(
        DockerClient.connect(
          environment: {'DOCKER_HOST': 'tcp://127.0.0.1:1'}, // nothing there
        ),
        throwsA(
          isA<DockerUnavailableException>().having(
            (e) => e.message,
            'message',
            contains(
              'Cannot connect to the Docker daemon at tcp://127.0.0.1:1',
            ),
          ),
        ),
      );
    });

    test('the create request holds what the config says', () {
      const config = DockerContainerConfig(
        image: 'postgres:17',
        environment: {'A': 'b'},
        command: ['postgres', '-c', 'fsync=off'],
        exposedPorts: [5432],
        labels: {'x': 'y'},
        binds: ['/h:/c:ro'],
        autoRemove: true,
        publishIp: '127.0.0.1',
        healthCheck: (
          test: ['CMD-SHELL', 'pg_isready'],
          interval: Duration(seconds: 2),
          timeout: Duration(seconds: 3),
          retries: 4,
        ),
      );
      expect(config.toJson(), {
        'Image': 'postgres:17',
        'Env': ['A=b'],
        'Cmd': ['postgres', '-c', 'fsync=off'],
        'ExposedPorts': {'5432/tcp': <String, Object?>{}},
        'Labels': {'x': 'y'},
        'Healthcheck': {
          'Test': ['CMD-SHELL', 'pg_isready'],
          'Interval': 2000000000,
          'Timeout': 3000000000,
          'Retries': 4,
        },
        'HostConfig': {
          'PortBindings': {
            '5432/tcp': [
              {'HostIp': '127.0.0.1', 'HostPort': ''},
            ],
          },
          'Binds': ['/h:/c:ro'],
          'AutoRemove': true,
        },
      });
    });

    test('an inspect answer gives the state, the health and the ports', () {
      final state = DockerContainerState.fromJson({
        'Id': 'abc',
        'State': {
          'Running': true,
          'Status': 'running',
          'ExitCode': 0,
          'Health': {'Status': 'healthy'},
        },
        'Config': {
          'Labels': {'a': 'b'},
        },
        'NetworkSettings': {
          'Ports': {
            '5432/tcp': [
              {'HostIp': '127.0.0.1', 'HostPort': '55001'},
              {'HostIp': '::1', 'HostPort': '55002'},
            ],
            '8080/tcp': null,
          },
        },
      });
      expect(state.running, isTrue);
      expect(state.health, 'healthy');
      expect(state.labels, {'a': 'b'});
      expect(state.mappedPort(5432), 55001);
      expect(state.mappedPort(8080), isNull);
    });
  });

  group('GenericContainer', () {
    test('mappedPort and baseUrl need a started container', () {
      final container = GenericContainer('redis:7').withExposedPorts([6379]);
      expect(container.isStarted, isFalse);
      expect(
        () => container.mappedPort(6379),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not started'),
          ),
        ),
      );
      expect(() => container.containerId, throwsStateError);
    });

    test('stop of a container that never started does nothing', () async {
      await GenericContainer('redis:7').stop();
    });

    test('withCopyFile fails at start for a file that is not there', () {
      expect(
        () => GenericContainer('redis:7').withCopyFile('nope.txt', '/x'),
        returnsNormally, // read at start
      );
      expect(
        () => KeycloakContainer().withRealmImport('missing-realm.json'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('no such file'),
          ),
        ),
      );
    });
  });

  group('PostgresContainer', () {
    test("has test/test/test and the image's environment", () {
      final postgres = PostgresContainer();
      expect(postgres.image, 'postgres:17-alpine');
      expect(postgres.databaseName, 'test');
      expect(postgres.username, 'test');
      expect(postgres.password, 'test');
      expect(postgres.exposedPorts, [5432]);
    });

    test('the URLs are in the form of the data starter', () {
      final postgres = _StartedPostgres()
        ..withDatabaseName('shop')
        ..withUsername('me@work')
        ..withPassword('p:w/d');
      expect(postgres.jdbcUrl, 'postgresql://db.test:55432/shop');
      expect(
        postgres.url,
        'postgresql://me%40work:p%3Aw%2Fd@db.test:55432/shop',
      );
      expect(Uri.parse(postgres.url).userInfo, 'me%40work:p%3Aw%2Fd');
    });

    test('its service connection sets spring.datasource.*', () {
      final postgres = _StartedPostgres()
        ..withDatabaseName('shop')
        ..withUsername('me')
        ..withPassword('secret');
      expect(postgres.connectionProperties, {
        'spring.datasource.url': 'postgresql://db.test:55432/shop',
        'spring.datasource.username': 'me',
        'spring.datasource.password': 'secret',
      });
    });
  });

  group('KeycloakContainer', () {
    test('its service connection sets the issuer URIs', () {
      final keycloak = _StartedKeycloak().withProviderId('sso');
      expect(keycloak.issuerUri, 'http://sso.test:58080/realms/master');
      expect(keycloak.connectionProperties, {
        'spring.security.oauth2.resourceserver.jwt.issuer-uri':
            'http://sso.test:58080/realms/master',
        'spring.security.oauth2.client.provider.sso.issuer-uri':
            'http://sso.test:58080/realms/master',
      });
    });

    test('a realm import names the realm and the wait', () {
      final temp = Directory.systemTemp.createTempSync('realm');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/neon-realm.json')
        ..writeAsStringSync('{"realm": "neon", "enabled": true}');
      final keycloak = _StartedKeycloak().withRealmImport(file.path);
      expect(keycloak.realm, 'neon');
      expect(keycloak.issuerUri, 'http://sso.test:58080/realms/neon');
      expect(keycloak.adminUsername, 'admin');
    });
  });

  group('TestContainers', () {
    test('registers the connection properties as suppliers', () {
      final properties = _Properties();
      TestContainers(
        {'T.postgres': _StartedPostgres(), 'T.redis': GenericContainer('r')},
        serviceConnections: {'T.postgres'},
      ).registerConnections(properties);
      expect(properties.values, {
        'spring.datasource.url': 'postgresql://db.test:55432/test',
        'spring.datasource.username': 'test',
        'spring.datasource.password': 'test',
      });
    });

    test(
      'a container that cannot connect is an error that says what to do',
      () {
        expect(
          () => TestContainers(
            {'T.redis': GenericContainer('redis:7')},
            serviceConnections: {'T.redis'},
          ).registerConnections(_Properties()),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('@ServiceConnection on T.redis'),
                contains('@DynamicPropertySource'),
              ),
            ),
          ),
        );
      },
    );

    test('a @Container field that is not a container is an error', () async {
      await expectLater(
        const TestContainers({'T.x': 'nope'}).start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('@Container field T.x must hold a GenericContainer'),
          ),
        ),
      );
    });

    test('skipWithoutDocker: false never skips', () {
      expect(TestContainers.skipReason(skipWithoutDocker: false), isNull);
    });
  });

  group('removing a container, against a fake daemon', () {
    late HttpServer daemon;
    late DockerClient docker;
    var status = 204;
    var message = '';
    // How many inspections still find the container before it is gone.
    var stillThere = 0;

    setUp(() async {
      daemon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) async {
          await request.drain<void>();
          if (request.method == 'GET') {
            final response = request.response;
            if (stillThere > 0) {
              stillThere--;
              response
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({'Id': 'abc', 'State': <String, Object?>{}}),
                );
            } else {
              response.statusCode = 404;
            }
            await response.close();
            return;
          }
          final response = request.response..statusCode = status;
          if (message.isNotEmpty) {
            response
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'message': message}));
          }
          await response.close();
        });
      docker = DockerClient(
        DockerEndpoint.resolve(
          environment: {'DOCKER_HOST': 'tcp://127.0.0.1:${daemon.port}'},
        )!,
      );
    });

    tearDown(() async {
      docker.close();
      await daemon.close(force: true);
    });

    test('a removal already in progress (auto-remove) is not an error', () {
      status = 409;
      message = 'removal of container abc is already in progress';
      expect(docker.removeContainer('abc'), completes);
    });

    test('it returns once the daemon has finished removing', () async {
      status = 409;
      message = 'removal of container abc is already in progress';
      stillThere = 3;
      await docker.removeContainer('abc');
      expect(stillThere, 0);
    });

    test('a container that is gone is not an error', () {
      status = 404;
      message = 'No such container: abc';
      expect(docker.removeContainer('abc'), completes);
    });

    test('another conflict is still an error', () {
      status = 409;
      message = 'You cannot remove a running container abc';
      expect(
        docker.removeContainer('abc'),
        throwsA(isA<DockerException>()),
      );
    });
  });
}
