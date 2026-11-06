// The health model and endpoint without HTTP: statuses, their
// aggregation and HTTP mapping as in Spring Boot, the contributors, the
// groups, who sees the details, and the JSON of Spring Boot's
// /actuator/health.
import 'dart:io';

import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:test/test.dart';

/// A principal for the security contexts.
final class User implements Principal {
  User(this.name, [this.roles = const []]);

  @override
  final String name;
  final List<String> roles;
}

/// The roles of [User]s.
final class UserRoles implements PrincipalRoleChecker {
  @override
  bool isUserInRole(Principal principal, String role) =>
      principal is User && principal.roles.contains(role);
}

final class Fixed extends HealthIndicator {
  Fixed(this.status, [this.details = const {}]);

  final Status status;
  final Map<String, Object?> details;
  int calls = 0;

  @override
  Health health() {
    calls++;
    return Health.withStatus(status).withDetails(details).build();
  }
}

final class Throwing extends HealthIndicator {
  @override
  Health health() => throw StateError('broken');
}

final class Checked extends AbstractHealthIndicator {
  Checked(this.check);

  final void Function(HealthBuilder builder) check;

  @override
  void doHealthCheck(HealthBuilder builder) => check(builder);
}

SecurityContext user([List<String> roles = const []]) =>
    SecurityContext.of(User('ada', roles), roles: UserRoles());

HealthEndpointWebExtension web(
  Map<String, HealthContributor> contributors, {
  HealthEndpointGroup? primary,
  Map<String, HealthEndpointGroup> groups = const {},
}) => HealthEndpointWebExtension(
  DefaultHealthContributorRegistry(contributors),
  HealthEndpointGroups.of(
    primary ?? SimpleHealthEndpointGroup(showDetailsMode: Show.always),
    groups,
  ),
);

Future<(int, Object?)> get(
  HealthEndpointWebExtension extension, [
  List<String> path = const [],
  SecurityContext security = SecurityContext.none,
  ApiVersion version = ApiVersion.v3,
]) async {
  final response = await extension.healthForPath(version, security, path);
  return (
    response.status,
    switch (response.body) {
      final HealthDescriptor body => body.toJson(),
      _ => null,
    },
  );
}

/// Matches a [get] result of [status] and [body].
Matcher reply(int status, Object? body) => isA<(int, Object?)>()
    .having((r) => r.$1, 'status', status)
    .having((r) => r.$2, 'body', body);

void main() {
  group('Status and Health', () {
    test('statuses compare by code; the description is shown', () {
      expect(const Status('UP', 'fine'), Status.up);
      expect(Status.outOfService.code, 'OUT_OF_SERVICE');
      expect(
        Health.withStatus(const Status('FATAL', 'disk gone')).build().toJson(),
        {'status': 'FATAL', 'description': 'disk gone'},
      );
    });

    test('the builder keeps the details in order; no details, no key', () {
      final health = Health.up().withDetail('b', 1).withDetails({
        'a': 2,
        'c': null,
      }).build();
      expect(health.toJson(), {
        'status': 'UP',
        'details': {'b': 1, 'a': 2, 'c': null},
      });
      expect(health.details.keys, ['b', 'a', 'c']);
      expect(Health.down().build().toJson(), {'status': 'DOWN'});
      expect(health.withoutDetails().toJson(), {'status': 'UP'});
    });

    test('down(error) and withException write the error as Boot does', () {
      final health = HealthBuilder().down(StateError('no db')).build();
      expect(health.status, Status.down);
      expect(health.details['error'], 'StateError: Bad state: no db');
      expect(
        Health.unknown().statusCode('FATAL').build().status.code,
        'FATAL',
      );
    });

    test('a composite sorts its components; version 2 says details', () {
      final composite = CompositeHealthDescriptor(Status.up, {
        'ping': Health.up().build(),
        'db': Health.up().build(),
        'Zeta': Health.down().build(),
      });
      expect((composite.toJson()['components']! as Map).keys, [
        'Zeta',
        'db',
        'ping',
      ]);
      expect(
        CompositeHealthDescriptor(Status.up, {
          'db': Health.up().build(),
        }, apiVersion: ApiVersion.v2).toJson(),
        {
          'status': 'UP',
          'details': {
            'db': {'status': 'UP'},
          },
        },
      );
      expect(CompositeHealthDescriptor(Status.up, null).toJson(), {
        'status': 'UP',
      });
    });

    test('the system health lists its groups, sorted', () {
      expect(
        SystemHealthDescriptor(
          Status.up,
          null,
          groups: ['readiness', 'liveness'],
        ).toJson(),
        {
          'status': 'UP',
          'groups': ['liveness', 'readiness'],
        },
      );
    });
  });

  group('SimpleStatusAggregator', () {
    const aggregator = StatusAggregator.defaults;

    test("Spring Boot's order: DOWN, OUT_OF_SERVICE, UP, UNKNOWN", () {
      expect(
        aggregator.getAggregateStatus([Status.up, Status.down]),
        Status.down,
      );
      expect(
        aggregator.getAggregateStatus([Status.up, Status.outOfService]),
        Status.outOfService,
      );
      expect(
        aggregator.getAggregateStatus([Status.unknown, Status.up]),
        Status.up,
      );
      expect(aggregator.getAggregateStatus([]), Status.unknown);
    });

    test('statuses not in the order are left out', () {
      expect(
        aggregator.getAggregateStatus([const Status('FATAL'), Status.up]),
        Status.up,
      );
      expect(
        aggregator.getAggregateStatus([const Status('FATAL')]),
        Status.unknown,
      );
    });

    test('a custom order compares uniform codes', () {
      final custom = SimpleStatusAggregator.of([
        'fatal',
        'down',
        'out-of-service',
        'unknown',
        'up',
      ]);
      expect(
        custom.getAggregateStatus([Status.down, const Status('FATAL')]),
        const Status('FATAL'),
      );
      expect(
        custom.getAggregateStatus([Status.up, Status.unknown]),
        Status.unknown,
      );
      expect(SimpleStatusAggregator.of([]).order, [
        'DOWN',
        'OUT_OF_SERVICE',
        'UP',
        'UNKNOWN',
      ]);
    });
  });

  group('SimpleHttpCodeStatusMapper', () {
    test('DOWN and OUT_OF_SERVICE are 503 by default', () {
      const mapper = HttpCodeStatusMapper.defaults;
      expect(mapper.getStatusCode(Status.down), 503);
      expect(mapper.getStatusCode(Status.outOfService), 503);
      expect(mapper.getStatusCode(Status.up), 200);
      expect(mapper.getStatusCode(Status.unknown), 200);
    });

    test('a mapping replaces the defaults, as in Spring Boot', () {
      const mapper = SimpleHttpCodeStatusMapper({'fatal': 500, 'down': 502});
      expect(mapper.getStatusCode(const Status('FATAL')), 500);
      expect(mapper.getStatusCode(Status.down), 502);
      expect(mapper.getStatusCode(Status.outOfService), 200);
    });
  });

  group('contributors', () {
    test('bean names lose the suffix, in any case', () {
      expect(healthContributorName('diskSpaceHealthIndicator'), 'diskSpace');
      expect(healthContributorName('dbHealthContributor'), 'db');
      expect(healthContributorName('inboxhealthindicator'), 'inbox');
      expect(healthContributorName('healthIndicator'), 'healthIndicator');
      expect(healthContributorName('queue'), 'queue');
    });

    test('the registry refuses a name twice and unregisters', () {
      final registry = DefaultHealthContributorRegistry({
        'ping': Fixed(Status.up),
      });
      expect(
        () => registry.registerContributor('ping', Fixed(Status.up)),
        throwsStateError,
      );
      expect(
        () => registry.registerContributor(' ', Fixed(Status.up)),
        throwsArgumentError,
      );
      registry.registerContributor('db', Fixed(Status.down));
      expect(registry.names, ['ping', 'db']);
      expect(registry.unregisterContributor('db'), isA<Fixed>());
      expect(registry.getContributor('db'), isNull);
    });

    test(
      'an AbstractHealthIndicator that throws is DOWN with the error',
      () async {
        final health = await Checked((_) => throw const FormatException('x'))
            .health();
        expect(health.status, Status.down);
        expect(health.details['error'], 'FormatException: FormatException: x');
        final ok = await Checked((b) => b.up().withDetail('n', 1)).health();
        expect(ok.toJson(), {
          'status': 'UP',
          'details': {'n': 1},
        });
      },
    );

    test('ping is always UP', () {
      expect(PingHealthIndicator().health().status, Status.up);
    });
  });

  group('availability indicators', () {
    test('liveness: CORRECT is UP, BROKEN is DOWN', () {
      final availability = ApplicationAvailabilityBean();
      final indicator = LivenessStateHealthIndicator(availability);
      expect(indicator.health().status, Status.down);
      availability.onApplicationEvent(
        AvailabilityChangeEvent(Object(), LivenessState.correct),
      );
      expect(indicator.health().status, Status.up);
    });

    test('readiness: ACCEPTING is UP, REFUSING is OUT_OF_SERVICE', () {
      final availability = ApplicationAvailabilityBean();
      final indicator = ReadinessStateHealthIndicator(availability);
      expect(indicator.health().status, Status.outOfService);
      availability.onApplicationEvent(
        AvailabilityChangeEvent(Object(), ReadinessState.acceptingTraffic),
      );
      expect(indicator.health().status, Status.up);
    });
  });

  group('DiskSpaceHealthIndicator', () {
    DiskSpaceReader reader(int free) =>
        (path) async => DiskSpace(
          path: '/srv/$path',
          total: 1000,
          free: free,
          exists: true,
        );

    test("UP above the threshold, with Spring Boot's details", () async {
      final health = await DiskSpaceHealthIndicator(
        threshold: const DataSize.ofBytes(100),
        reader: reader(500),
      ).health();
      expect(health.toJson(), {
        'status': 'UP',
        'details': {
          'total': 1000,
          'free': 500,
          'threshold': 100,
          'path': '/srv/.',
          'exists': true,
        },
      });
    });

    test('DOWN below the threshold', () async {
      final health = await DiskSpaceHealthIndicator(
        threshold: const DataSize.ofBytes(600),
        reader: reader(500),
      ).health();
      expect(health.status, Status.down);
      expect(health.details['free'], 500);
    });

    test('UNKNOWN when the space cannot be measured', () async {
      final none = await DiskSpaceHealthIndicator(
        reader: (_) async => null,
      ).health();
      expect(none.status, Status.unknown);
      final failed = await DiskSpaceHealthIndicator(
        reader: (_) async => throw const FileSystemException('denied'),
      ).health();
      expect(failed.status, Status.unknown);
      expect(failed.details['error'], contains('denied'));
    });

    test('the default threshold is 10 MB', () {
      expect(DiskSpaceHealthIndicator().threshold.toBytes(), 10485760);
    });

    test('the file system of this machine', () async {
      final health = await DiskSpaceHealthIndicator().health();
      expect(health.status, isNot(Status.down));
      if (!Platform.isWindows) {
        expect(health.details['total'], greaterThan(0));
        expect(health.details['exists'], isTrue);
        expect(health.details['path'], endsWith('/.'));
      }
    }, testOn: 'mac-os || linux');

    test('a path that does not exist has no space', () async {
      final health = await DiskSpaceHealthIndicator(
        path: '/no/such/path/here',
      ).health();
      expect(health.status, Status.down);
      expect(health.details['exists'], isFalse);
      expect(health.details['free'], 0);
    }, testOn: 'mac-os || linux');
  });

  group('groups', () {
    test('include and exclude, with * and composite parts', () {
      final group = SimpleHealthEndpointGroup(
        include: ['db', 'ping'],
        exclude: ['db/reporting'],
      );
      expect(group.isMember('db'), isTrue);
      expect(group.isMember('db/primary'), isTrue);
      expect(group.isMember('db/reporting'), isFalse);
      expect(group.isMember('diskSpace'), isFalse);
      expect(SimpleHealthEndpointGroup().isMember('anything'), isTrue);
      expect(
        SimpleHealthEndpointGroup(
          include: ['*'],
          exclude: ['ping'],
        ).isMember('ping'),
        isFalse,
      );
      // A part included alone makes its composite reachable.
      final part = SimpleHealthEndpointGroup(include: ['db/primary']);
      expect(part.isMember('db'), isTrue);
      expect(part.isMember('db/primary'), isTrue);
      expect(part.isMember('db/reporting'), isFalse);
    });

    test('show: never, always, when-authorized with and without roles', () {
      expect(Show.never.isShown(user(), const []), isFalse);
      expect(Show.always.isShown(SecurityContext.none, const []), isTrue);
      expect(
        Show.whenAuthorized.isShown(SecurityContext.none, const []),
        isFalse,
      );
      expect(Show.whenAuthorized.isShown(user(), const []), isTrue);
      expect(Show.whenAuthorized.isShown(user(), ['ADMIN']), isFalse);
      expect(Show.whenAuthorized.isShown(user(['ADMIN']), ['ADMIN']), isTrue);
    });

    test('show-components falls back to show-details', () {
      final group = SimpleHealthEndpointGroup(
        showDetailsMode: Show.whenAuthorized,
      );
      expect(group.showComponents(SecurityContext.none), isFalse);
      expect(group.showComponents(user()), isTrue);
      final components = SimpleHealthEndpointGroup(
        showComponentsMode: Show.always,
      );
      expect(components.showComponents(SecurityContext.none), isTrue);
      expect(components.showDetails(SecurityContext.none), isFalse);
    });
  });

  group('HealthEndpointWebExtension', () {
    final contributors = <String, HealthContributor>{
      'ping': Fixed(Status.up),
      'disk': Fixed(Status.up, {'free': 5}),
      'db': CompositeHealthContributor.fromMap({
        'primary': Fixed(Status.up, {'database': 'SQLite'}),
        'reporting': Fixed(Status.down),
      }),
    };

    test('the whole report with details and components', () async {
      final (status, body) = await get(web(contributors));
      expect(status, 503);
      expect(body, {
        'status': 'DOWN',
        'components': {
          'db': {
            'status': 'DOWN',
            'components': {
              'primary': {
                'status': 'UP',
                'details': {'database': 'SQLite'},
              },
              'reporting': {'status': 'DOWN'},
            },
          },
          'disk': {
            'status': 'UP',
            'details': {'free': 5},
          },
          'ping': {'status': 'UP'},
        },
      });
    });

    test('show-details=never: the status alone', () async {
      final (status, body) = await get(
        web(contributors, primary: SimpleHealthEndpointGroup()),
      );
      expect(status, 503);
      expect(body, {'status': 'DOWN'});
    });

    test('components without details', () async {
      final (_, body) = await get(
        web({
          'disk': Fixed(Status.up, {'free': 5}),
        }, primary: SimpleHealthEndpointGroup(showComponentsMode: Show.always)),
      );
      expect(body, {
        'status': 'UP',
        'components': {
          'disk': {'status': 'UP'},
        },
      });
    });

    test('when-authorized: details for a user with the role', () async {
      final extension = web(
        {
          'ping': Fixed(Status.up, {'n': 1}),
        },
        primary: SimpleHealthEndpointGroup(
          showDetailsMode: Show.whenAuthorized,
          roles: const ['ADMIN'],
        ),
      );
      expect((await get(extension)).$2, {'status': 'UP'});
      expect((await get(extension, const [], user())).$2, {'status': 'UP'});
      expect((await get(extension, const [], user(['ADMIN']))).$2, {
        'status': 'UP',
        'components': {
          'ping': {
            'status': 'UP',
            'details': {'n': 1},
          },
        },
      });
    });

    test('a component and a part of a composite by path', () async {
      final extension = web(contributors);
      expect(
        await get(extension, ['disk']),
        reply(
          200,
          {
            'status': 'UP',
            'details': {'free': 5},
          },
        ),
      );
      expect(
        await get(extension, ['db', 'reporting']),
        reply(
          503,
          {'status': 'DOWN'},
        ),
      );
      expect((await get(extension, ['nothing'])).$1, 404);
      expect((await get(extension, ['disk', 'deeper'])).$1, 404);
    });

    test('no components shown: paths are not found', () async {
      final extension = web(
        contributors,
        primary: SimpleHealthEndpointGroup(),
      );
      expect((await get(extension, ['disk'])).$1, 404);
      expect((await get(extension)).$1, 503);
    });

    test('groups: their members, their rules, listed in the root', () async {
      final extension = web(
        contributors,
        groups: {
          'core': SimpleHealthEndpointGroup(
            include: ['ping', 'disk'],
            showDetailsMode: Show.always,
          ),
          'custom': SimpleHealthEndpointGroup(
            include: ['db'],
            httpCodeStatusMapper: const SimpleHttpCodeStatusMapper({
              'down': 500,
            }),
          ),
        },
      );
      final (_, root) = await get(extension);
      expect((root! as Map)['groups'], ['core', 'custom']);
      expect(
        await get(extension, ['core']),
        reply(
          200,
          {
            'status': 'UP',
            'components': {
              'disk': {
                'status': 'UP',
                'details': {'free': 5},
              },
              'ping': {'status': 'UP'},
            },
          },
        ),
      );
      expect(await get(extension, ['custom']), reply(500, {'status': 'DOWN'}));
      // A member through its group; a non-member is not found there.
      expect((await get(extension, ['core', 'ping'])).$1, 200);
      expect((await get(extension, ['core', 'db'])).$1, 404);
    });

    test('a group without members is not found', () async {
      final extension = web(
        contributors,
        groups: {
          'none': SimpleHealthEndpointGroup(include: ['missing']),
        },
      );
      expect((await get(extension, ['none'])).$1, 404);
    });

    test('no contributor at all: UP', () async {
      expect(await get(web({})), reply(200, {'status': 'UP'}));
    });

    test('an indicator that throws is DOWN with the error', () async {
      final (status, body) = await get(web({'bad': Throwing()}));
      expect(status, 503);
      expect(body, {
        'status': 'DOWN',
        'components': {
          'bad': {
            'status': 'DOWN',
            'details': {'error': 'StateError: Bad state: broken'},
          },
        },
      });
    });

    test('version 2 of the JSON puts the components under details', () async {
      final (_, body) = await get(
        web({'ping': Fixed(Status.up)}),
        const [],
        SecurityContext.none,
        ApiVersion.v2,
      );
      expect(body, {
        'status': 'UP',
        'details': {
          'ping': {'status': 'UP'},
        },
      });
    });

    test('the endpoint itself shows everything', () async {
      final endpoint = HealthEndpoint(
        DefaultHealthContributorRegistry({
          'ping': Fixed(Status.up, {'n': 1}),
        }),
        HealthEndpointGroups.of(SimpleHealthEndpointGroup(), {}),
      );
      expect((await endpoint.health())!.toJson(), {
        'status': 'UP',
        'components': {
          'ping': {
            'status': 'UP',
            'details': {'n': 1},
          },
        },
      });
      expect((await endpoint.healthForPath(['ping']))!.status, Status.up);
      expect(await endpoint.healthForPath(['nope']), isNull);
    });

    test('each request asks the indicators again', () async {
      final indicator = Fixed(Status.up);
      final extension = web({'ping': indicator});
      await get(extension);
      await get(extension);
      expect(indicator.calls, 2);
    });
  });
}
