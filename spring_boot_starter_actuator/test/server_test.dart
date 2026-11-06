// The endpoints on a real server (dart:io), as a load balancer and
// Kubernetes ask them.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:test/test.dart';

import 'app/beans.dart';
import 'support.dart';

void main() {
  test('/actuator/health and the probes over HTTP', () async {
    await actuatorRunner([
      'spring.test.web-environment=random-port',
      'server.address=127.0.0.1',
      'management.endpoint.health.probes.enabled=true',
      'management.endpoint.health.probes.add-additional-paths=true',
      'management.health.diskspace.enabled=false',
    ]).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final server = await context
          .getBean<WebServerStartStopLifecycle>()
          .started;
      final client = io.HttpClient();
      addTearDown(client.close);
      Future<(int, String?, Object?)> get(String path) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server!.port}$path'),
        );
        final response = await request.close();
        final text = await utf8.decodeStream(response);
        return (
          response.statusCode,
          response.headers.contentType?.mimeType,
          text.isEmpty ? null : jsonDecode(text),
        );
      }

      AvailabilityChangeEvent.publish(context.context, LivenessState.correct);
      AvailabilityChangeEvent.publish(
        context.context,
        ReadinessState.acceptingTraffic,
      );
      final (status, type, body) = await get('/actuator/health');
      expect(status, 200);
      expect(type, 'application/vnd.spring-boot.actuator.v3+json');
      expect(body, {
        'status': 'UP',
        'groups': ['liveness', 'readiness'],
      });
      expect((await get('/livez')).$1, 200);
      expect((await get('/readyz')).$1, 200);
      context.getBean<InboxState>().status = Status.down;
      expect((await get('/actuator/health')).$1, 503);
      // The probes do not include the application's indicators.
      expect((await get('/readyz')).$1, 200);
      AvailabilityChangeEvent.publish(
        context.context,
        ReadinessState.refusingTraffic,
      );
      expect((await get('/readyz')).$3, {'status': 'OUT_OF_SERVICE'});
      expect((await get('/actuator/info')).$1, 404);
    });
  });
}
