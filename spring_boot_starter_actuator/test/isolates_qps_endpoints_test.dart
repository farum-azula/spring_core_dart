// The `isolates` endpoint (the task manager as JSON) and the `qps`
// endpoint of the web starter's debug feature.
import 'package:spring_boot_starter_actuator/spring_auto_configuration.dart';
import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('isolates', () {
    test('not exposed by default', () async {
      await withActuator((mvc, context) async {
        expect((await mvc.get('/actuator/isolates')).response.statusCode, 404);
      });
    });

    test('the rows of the task manager; measuring starts with it', () async {
      await withActuator(
        (mvc, context) async {
          final first = await mvc.get('/actuator/isolates');
          expect(first.response.statusCode, 200);
          final body = jsonOf(first)! as Map<String, Object?>;
          expect(body['isolate'], 'main');
          final rows = (body['isolates']! as List).cast<Map<String, Object?>>();
          final main = rows.singleWhere((row) => row['name'] == 'main');
          expect(main['kind'], 'main');
          expect(main['memory'], greaterThan(0));
          // The sampler was started by this read.
          final sampler = context.getBean<IsolateLoadSampler>();
          expect(sampler.isRunning, isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final again = jsonOf(await mvc.get('/actuator/isolates'))! as Map;
          final measured = (again['isolates'] as List)
              .cast<Map<String, Object?>>()
              .singleWhere((row) => row['name'] == 'main');
          expect(measured['busy'], isA<num>());
          expect(measured['lagMicros'], isA<int>());
        },
        properties: ['management.endpoints.web.exposure.include=isolates'],
      );
    });

    test('what the application tracks is a row too', () async {
      await withActuator(
        (mvc, context) async {
          final loads = context.getBean<IsolateLoads>();
          final work = loads.track(
            'report',
            Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          final body = jsonOf(await mvc.get('/actuator/isolates'))! as Map;
          expect(
            (body['isolates'] as List).map((row) => (row as Map)['name']),
            contains('report'),
          );
          await work;
        },
        properties: ['management.endpoints.web.exposure.include=isolates'],
      );
    });
  });

  group('qps', () {
    const exposed = [
      'management.endpoints.web.exposure.include=qps',
      'spring.web.debug.qps.log-interval=1h',
    ];

    test('absent without the debug feature', () async {
      await withActuator((mvc, context) async {
        expect((await mvc.get('/actuator/qps')).response.statusCode, 404);
        expect(context.containsBean('qpsEndpoint'), isFalse);
      }, properties: exposed);
    });

    test('the last window, and the window ended now', () async {
      await withActuator(
        (mvc, context) async {
          final none = await mvc.get('/actuator/qps');
          expect(none.response.statusCode, 200);
          expect(jsonOf(none), isEmpty);
          for (var i = 0; i < 4; i++) {
            await mvc.get('/actuator/qps');
          }
          final now = jsonOf(await mvc.get('/actuator/qps/now'))! as Map;
          // The five reads before it; itself is still in flight.
          expect(now['requests'], 5);
          expect(now['errors'], 0);
          expect(now['active'], 1);
          // The endpoint asks the first isolate's RequestRates.
          expect(context.getBean<QpsEndpoint>().primary, isA<PrimaryIsolate>());
          expect(now['p99Micros'], isA<int>());
          expect((now['isolates'] as Map).keys, ['main']);
          // The last window is that one now.
          final last = jsonOf(await mvc.get('/actuator/qps'))! as Map;
          expect(last['requests'], 5);
          expect(
            (await mvc.get('/actuator/qps/yesterday')).response.statusCode,
            404,
          );
        },
        properties: exposed,
        setUp: (runner) => runner
            .withAutoConfiguration(
              springBootStarterWebDebugQpsAutoConfiguration,
            )
            .withAutoConfiguration(
              springBootStarterActuatorQpsAutoConfiguration,
            ),
      );
    });
  });
}
