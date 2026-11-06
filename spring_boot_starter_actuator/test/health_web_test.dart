// /actuator/health over HTTP: Spring Boot's JSON, the HTTP status of the
// health, show-details and show-components, the status order and HTTP
// mapping, the groups and the Kubernetes probes with their additional
// paths, and the indicators the starter declares.
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/beans.dart';
import 'support.dart';

/// Leaves the disk out: its numbers change from run to run.
const _noDisk = 'management.health.diskspace.enabled=false';

const _order = 'fatal,down,out-of-service,unknown,up';

void main() {
  test('UP with the components and their details', () async {
    await withActuator(
      (mvc, context) async {
        final result = await mvc.get('/actuator/health');
        expect(result.response.statusCode, 200);
        expect(jsonOf(result), {
          'status': 'UP',
          'components': {
            'inbox': {
              'status': 'UP',
              'details': {'pending': 3},
            },
            'ping': {'status': 'UP'},
          },
        });
      },
      properties: [_noDisk, 'management.endpoint.health.show-details=always'],
    );
  });

  test('DOWN and OUT_OF_SERVICE answer 503', () async {
    await withActuator(
      (mvc, context) async {
        final state = context.getBean<InboxState>()..status = Status.down;
        final down = await mvc.get('/actuator/health');
        expect(down.response.statusCode, 503);
        expect(jsonOf(down), {'status': 'DOWN'});
        state.status = Status.outOfService;
        expect((await mvc.get('/actuator/health')).response.statusCode, 503);
        state.status = Status.unknown; // ping is UP
        expect(jsonOf(await mvc.get('/actuator/health')), {'status': 'UP'});
      },
      properties: [_noDisk],
    );
  });

  test('an indicator that throws is DOWN with the error', () async {
    await withActuator(
      (mvc, context) async {
        context.getBean<InboxState>().failure = const FormatException('bad');
        final result = await mvc.get('/actuator/health/inbox');
        expect(result.response.statusCode, 503);
        expect(jsonOf(result), {
          'status': 'DOWN',
          'details': {'error': 'FormatException: FormatException: bad'},
        });
      },
      properties: [_noDisk, 'management.endpoint.health.show-details=always'],
    );
  });

  test('show-components without the details', () async {
    await withActuator(
      (mvc, context) async {
        expect(jsonOf(await mvc.get('/actuator/health')), {
          'status': 'UP',
          'components': {
            'inbox': {'status': 'UP'},
            'ping': {'status': 'UP'},
          },
        });
        expect(jsonOf(await mvc.get('/actuator/health/inbox')), {
          'status': 'UP',
        });
      },
      properties: [
        _noDisk,
        'management.endpoint.health.show-components=always',
      ],
    );
  });

  test('never by default: the status alone, components not found', () async {
    await withActuator((mvc, context) async {
      expect(jsonOf(await mvc.get('/actuator/health')), {'status': 'UP'});
      expect((await mvc.get('/actuator/health/ping')).response.statusCode, 404);
    });
  });

  test('a status order and an HTTP mapping of the application', () async {
    await withActuator(
      (mvc, context) async {
        context.getBean<InboxState>().status = const Status('FATAL');
        final result = await mvc.get('/actuator/health');
        expect(result.response.statusCode, 500);
        expect(jsonOf(result), {'status': 'FATAL'});
      },
      properties: [
        _noDisk,
        'management.endpoint.health.status.order=$_order',
        'management.endpoint.health.status.http-mapping.fatal=500',
      ],
    );
  });

  test('the disk space with its details', () async {
    await withActuator(
      (mvc, context) async {
        final disk =
            jsonOf(await mvc.get('/actuator/health/diskSpace'))! as Map;
        expect(disk['status'], 'UP');
        expect((disk['details']! as Map).keys, [
          'total',
          'free',
          'threshold',
          'path',
          'exists',
        ]);
        expect((disk['details']! as Map)['threshold'], 1024);
      },
      properties: [
        'management.endpoint.health.show-details=always',
        'management.health.diskspace.threshold=1KB',
      ],
    );
  }, testOn: 'mac-os || linux');

  test('management.health.<name>.enabled and defaults.enabled', () async {
    await withActuator(
      (mvc, context) async {
        expect(
          context.getBean<HealthContributorRegistry>().names,
          ['inbox'],
        );
      },
      properties: ['management.health.defaults.enabled=false'],
    );
    await withActuator(
      (mvc, context) async {
        expect(context, doesNotHaveBean<PingHealthIndicator>());
        expect(context, hasSingleBean<DiskSpaceHealthIndicator>());
      },
      properties: ['management.health.ping.enabled=false'],
    );
  });

  group('groups', () {
    final groups = [
      _noDisk,
      'management.endpoint.health.group.core.include=ping',
      'management.endpoint.health.group.core.show-details=always',
      'management.endpoint.health.group.app.include=*',
      'management.endpoint.health.group.app.exclude=ping',
      'management.endpoint.health.group.app.status.http-mapping.down=500',
    ];

    test('listed in the root, each at its path with its rules', () async {
      await withActuator((mvc, context) async {
        expect(jsonOf(await mvc.get('/actuator/health')), {
          'status': 'UP',
          'groups': ['app', 'core'],
        });
        expect(jsonOf(await mvc.get('/actuator/health/core')), {
          'status': 'UP',
          'components': {
            'ping': {'status': 'UP'},
          },
        });
        context.getBean<InboxState>().status = Status.down;
        final app = await mvc.get('/actuator/health/app');
        expect(app.response.statusCode, 500);
        expect(jsonOf(app), {'status': 'DOWN'});
        expect(
          (await mvc.get('/actuator/health/core/ping')).response.statusCode,
          200,
        );
        expect(
          (await mvc.get('/actuator/health/core/inbox')).response.statusCode,
          404,
        );
        expect(
          (await mvc.get('/actuator/health/other')).response.statusCode,
          404,
        );
      }, properties: groups);
    });

    test(
      'a group naming a contributor that does not exist stops the start',
      () async {
        await actuatorRunner([
          'management.endpoint.health.group.bad.include=nothing',
        ]).runAsync((context) async {
          expect(
            '${context.startupFailure}',
            contains(
              "Included health contributor 'nothing' in group 'bad' does "
              'not exist',
            ),
          );
        });
        await actuatorRunner([
          'management.endpoint.health.group.bad.include=nothing',
          'management.endpoint.health.validate-group-membership=false',
        ]).runAsync((context) async {
          expect(context.startupFailure, isNull);
        });
      },
    );

    test('an additional path on the main server', () async {
      await withActuator(
        (mvc, context) async {
          final result = await mvc.get('/healthz');
          expect(result.response.statusCode, 200);
          expect(jsonOf(result), {
            'status': 'UP',
            'components': {
              'ping': {'status': 'UP'},
            },
          });
        },
        properties: [
          ...groups,
          'management.endpoint.health.group.core.additional-path=server:/healthz',
        ],
      );
    });
  });

  group('probes', () {
    test('liveness and readiness from the availability', () async {
      await withActuator(
        (mvc, context) async {
          // No SpringApplication here: the states are published by hand.
          AvailabilityChangeEvent.publish(
            context.context,
            LivenessState.correct,
          );
          AvailabilityChangeEvent.publish(
            context.context,
            ReadinessState.acceptingTraffic,
          );
          expect(jsonOf(await mvc.get('/actuator/health')), {
            'status': 'UP',
            'groups': ['liveness', 'readiness'],
          });
          expect(jsonOf(await mvc.get('/actuator/health/liveness')), {
            'status': 'UP',
          });
          expect(
            (await mvc.get('/actuator/health/readiness')).response.statusCode,
            200,
          );
          AvailabilityChangeEvent.publish(
            context.context,
            ReadinessState.refusingTraffic,
          );
          final readiness = await mvc.get('/actuator/health/readiness');
          expect(readiness.response.statusCode, 503);
          expect(jsonOf(readiness), {'status': 'OUT_OF_SERVICE'});
          AvailabilityChangeEvent.publish(
            context.context,
            LivenessState.broken,
          );
          expect(
            (await mvc.get('/actuator/health/liveness')).response.statusCode,
            503,
          );
          // The whole report has them too.
          expect((await mvc.get('/actuator/health')).response.statusCode, 503);
          // No paths without add-additional-paths.
          expect((await mvc.get('/livez')).response.statusCode, 404);
        },
        properties: [_noDisk, 'management.endpoint.health.probes.enabled=true'],
      );
    });

    test('/livez and /readyz with add-additional-paths', () async {
      await withActuator(
        (mvc, context) async {
          AvailabilityChangeEvent.publish(
            context.context,
            LivenessState.correct,
          );
          expect((await mvc.get('/livez')).response.statusCode, 200);
          expect((await mvc.get('/readyz')).response.statusCode, 503);
        },
        properties: [
          _noDisk,
          'management.endpoint.health.probes.enabled=true',
          'management.endpoint.health.probes.add-additional-paths=true',
        ],
      );
    });

    test('on Kubernetes without the property', () async {
      await withActuator(
        (mvc, context) async {
          expect(context, hasSingleBean<LivenessStateHealthIndicator>());
          expect(context, hasSingleBean<ReadinessStateHealthIndicator>());
        },
        properties: [_noDisk, 'spring.main.cloud-platform=kubernetes'],
      );
      await withActuator((mvc, context) async {
        expect(context, doesNotHaveBean<LivenessStateHealthIndicator>());
        expect(
          jsonOf(await mvc.get('/actuator/health')),
          isNot(contains('groups')),
        );
      }, properties: [_noDisk]);
    });

    test(
      'a group of the application wins over the probe of its name',
      () async {
        await withActuator(
          (mvc, context) async {
            AvailabilityChangeEvent.publish(
              context.context,
              LivenessState.broken,
            );
            expect(
              (await mvc.get('/actuator/health/liveness')).response.statusCode,
              200,
            );
          },
          properties: [
            _noDisk,
            'management.endpoint.health.probes.enabled=true',
            'management.endpoint.health.group.liveness.include=ping',
          ],
        );
      },
    );
  });
}
