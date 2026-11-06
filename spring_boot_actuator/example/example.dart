// The actuator's endpoints without a server: a health report of three
// indicators and the info of a build, as Spring Boot writes them. An
// application gets the same endpoints over HTTP (/actuator/health) from
// spring_boot_starter_actuator, which declares them as beans.
//
//   dart run example/example.dart
import 'dart:convert';

import 'package:spring_boot_actuator/spring_boot_actuator.dart';

const _log = SpringLog('example');

/// A queue that is `DOWN` when too many messages wait.
class QueueHealthIndicator extends AbstractHealthIndicator {
  QueueHealthIndicator(this.waiting);

  final int waiting;

  @override
  void doHealthCheck(HealthBuilder builder) =>
      (waiting < 100 ? builder.up() : builder.down()).withDetail(
        'waiting',
        waiting,
      );
}

Future<void> main() async {
  final registry = DefaultHealthContributorRegistry({
    'ping': PingHealthIndicator(),
    'diskSpace': DiskSpaceHealthIndicator(),
    'queue': QueueHealthIndicator(250),
  });
  // Who sees what: everybody sees the components and their details.
  final groups = HealthEndpointGroups.of(
    SimpleHealthEndpointGroup(showDetailsMode: Show.always),
    {
      'core': SimpleHealthEndpointGroup(include: ['ping', 'diskSpace']),
    },
  );
  final health = HealthEndpointWebExtension(registry, groups);
  final report = await health.health(ApiVersion.v3, SecurityContext.none);
  // 503 {"status":"DOWN","components":{...},"groups":["core"]}
  _log.info('${report.status} ${jsonEncode(report.body?.toJson())}');

  final core = await health.healthForPath(
    ApiVersion.v3,
    SecurityContext.none,
    ['core'],
  );
  // 200 {"status":"UP"}
  _log.info('${core.status} ${jsonEncode(core.body?.toJson())}');

  final info = InfoEndpoint([
    BuildInfoContributor(
      BuildProperties({
        'name': 'shop',
        'version': '1.4.0',
        'time': '2026-11-05T09:12:44Z',
      }),
    ),
  ]);
  // {"build":{"name":"shop","version":"1.4.0","time":"2026-11-05T09:12:44Z"}}
  _log.info(jsonEncode(await info.info()));
}
