import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

void main() {
  StandardEnvironment env(
    Map<String, String> system, [
    Map<String, Object?> props = const {},
  ]) =>
      StandardEnvironment(systemEnvironment: system)
        ..propertySources.addFirst(MapPropertySource('cli', props));

  group('CloudPlatform detection, like Boot', () {
    final cases = <Map<String, String>, CloudPlatform>{
      {'VCAP_APPLICATION': '{}'}: CloudPlatform.cloudFoundry,
      {'VCAP_SERVICES': '{}'}: CloudPlatform.cloudFoundry,
      {'DYNO': 'web.1'}: CloudPlatform.heroku,
      {'HC_LANDSCAPE': 'x'}: CloudPlatform.sap,
      {'NOMAD_ALLOC_ID': 'x'}: CloudPlatform.nomad,
      {'KUBERNETES_SERVICE_HOST': '10.0.0.1', 'KUBERNETES_SERVICE_PORT': '443'}:
          CloudPlatform.kubernetes,
      {'ORDERS_SERVICE_HOST': '10.0.0.2', 'ORDERS_SERVICE_PORT': '80'}:
          CloudPlatform.kubernetes,
      {
        'WEBSITE_SITE_NAME': 'a',
        'WEBSITE_INSTANCE_ID': 'b',
        'WEBSITE_RESOURCE_GROUP': 'c',
        'WEBSITE_SKU': 'd',
      }: CloudPlatform.azureAppService,
      {'ECS_CONTAINER_METADATA_URI_V4': 'http://x'}: CloudPlatform.amazonEcs,
    };
    for (final MapEntry(key: system, value: platform) in cases.entries) {
      test('$platform from ${system.keys.join(', ')}', () {
        expect(CloudPlatform.getActive(env(system)), platform);
        expect(platform.isActive(env(system)), isTrue);
      });
    }

    test('nothing detected without the variables', () {
      expect(CloudPlatform.getActive(env({})), isNull);
      expect(
        CloudPlatform.getActive(env({'KUBERNETES_SERVICE_HOST': 'x'})),
        isNull,
        reason: 'the port is needed too',
      );
      expect(
        CloudPlatform.getActive(
          env({'WEBSITE_SITE_NAME': 'a', 'WEBSITE_SKU': 'd'}),
        ),
        isNull,
        reason: 'Azure needs all four variables',
      );
    });

    test('Kubernetes only from the system environment source', () {
      expect(
        CloudPlatform.getActive(
          env({}, {
            'KUBERNETES_SERVICE_HOST': 'x',
            'KUBERNETES_SERVICE_PORT': '1',
          }),
        ),
        isNull,
      );
    });

    test('spring.main.cloud-platform enforces or turns detection off', () {
      expect(
        CloudPlatform.getActive(
          env({}, {'spring.main.cloud-platform': 'CLOUD_FOUNDRY'}),
        ),
        CloudPlatform.cloudFoundry,
      );
      expect(
        CloudPlatform.getActive(
          env({'DYNO': 'web.1'}, {'spring.main.cloud-platform': 'none'}),
        ),
        CloudPlatform.none,
      );
      expect(
        CloudPlatform.heroku.isActive(
          env({'DYNO': 'web.1'}, {'spring.main.cloud-platform': 'none'}),
        ),
        isFalse,
      );
      expect(
        CloudPlatform.parse('azure-app-service'),
        CloudPlatform.azureAppService,
      );
    });
  });

  group('spring.config.activate.on-cloud-platform', () {
    late Directory temp;
    late String root;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('scd_cloud_platform_');
      root = temp.path;
    });
    tearDown(() => temp.deleteSync(recursive: true));

    void write(String content) =>
        File('$root/application.properties').writeAsStringSync(content);

    StandardEnvironment process(
      Map<String, String> system, [
      Map<String, Object?> props = const {},
    ]) {
      final environment = env(system, props);
      ConfigDataEnvironment(
        environment,
        defaultLocations: ['optional:file:$root/'],
      ).processAndApplySync();
      return environment;
    }

    const file = '''
where=local
#---
spring.config.activate.on-cloud-platform=kubernetes
where=k8s
#---
spring.config.activate.on-cloud-platform=heroku
where=heroku
''';

    test('documents of another platform are skipped', () {
      write(file);
      expect(process({}).getProperty('where'), 'local');
      expect(
        process({
          'KUBERNETES_SERVICE_HOST': 'x',
          'KUBERNETES_SERVICE_PORT': '1',
        }).getProperty('where'),
        'k8s',
      );
      expect(process({'DYNO': 'web.1'}).getProperty('where'), 'heroku');
    });

    test('spring.main.cloud-platform on the command line or in a file', () {
      write(file);
      expect(
        process({}, {
          'spring.main.cloud-platform': 'kubernetes',
        }).getProperty('where'),
        'k8s',
      );
      write('spring.main.cloud-platform=heroku\n$file');
      expect(process({}).getProperty('where'), 'heroku');
    });

    test('none matches when no platform is active', () {
      write('''
where=a
#---
spring.config.activate.on-cloud-platform=none
where=none
''');
      expect(process({}).getProperty('where'), 'none');
      expect(process({'DYNO': 'x'}).getProperty('where'), 'a');
    });

    test('combined with on-profile, both must match', () {
      write('''
where=a
#---
spring.config.activate.on-cloud-platform=heroku
spring.config.activate.on-profile=prod
where=heroku-prod
''');
      expect(process({'DYNO': 'x'}).getProperty('where'), 'a');
      expect(
        process(
          {'DYNO': 'x'},
          {'spring.profiles.active': 'prod'},
        ).getProperty('where'),
        'heroku-prod',
      );
      expect(
        process({}, {'spring.profiles.active': 'prod'}).getProperty('where'),
        'a',
      );
    });

    test('a document for a platform may activate profiles', () {
      write('''
#---
spring.config.activate.on-cloud-platform=heroku
spring.profiles.active=cloud
''');
      expect(process({'DYNO': 'x'}).activeProfiles, ['cloud']);
    });

    test('an unknown platform fails', () {
      write('''
#---
spring.config.activate.on-cloud-platform=moon
a=1
''');
      expect(() => process({}), throwsA(isA<ConfigDataLoadException>()));
    });
  });
}
