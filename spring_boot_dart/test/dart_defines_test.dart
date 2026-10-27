import 'dart:io';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Settings {
  Settings(this.url, this.size);
  final String url;
  final String size;
}

SpringApplication app({
  Map<String, String> dartDefines = const {},
  List<String> additionalProfiles = const [],
  String fingerprint = 'v1',
}) => SpringApplication(
  [
    BeanModule('application', [
      BeanDefinition<Settings>(
        name: 'settings',
        create: (r) => Settings(
          r.value<String>(r'${api.url:none}'),
          r.value<String>(r'${shop.max-basket-size:0}'),
        ),
      ),
    ]),
  ],
  dartDefines: dartDefines,
  additionalProfiles: additionalProfiles,
  fingerprint: fingerprint,
  out: (_) {},
);

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('scd_defines_');
    File('${dir.path}/application.properties')
        .writeAsStringSync('api.url=from-file\nshop.max-basket-size=1');
    File('${dir.path}/application-prod.properties')
        .writeAsStringSync('api.url=from-prod-file');
    File('${dir.path}/application-mobile.properties')
        .writeAsStringSync('region=mobile\nkind=mobile');
    File('${dir.path}/application-android.properties')
        .writeAsStringSync('kind=android');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> location() => ['--spring.config.location=file:${dir.path}/'];

  test('defines answer exact names, relaxed names and binding', () {
    final context = app(
      dartDefines: const {
        'API_URL': 'https://api.neon.books',
        'SHOP_MAXBASKETSIZE': '3',
        'feature.beta': 'true',
      },
    ).run(location(), systemEnvironment: const {});
    addTearDown(context.close);
    final environment = context.environment;
    expect(environment.getProperty('API_URL'), 'https://api.neon.books');
    expect(environment.getProperty('api.url'), 'https://api.neon.books');
    expect(environment.getProperty('feature.beta'), 'true');
    expect(context.getBean<Settings>().url, 'https://api.neon.books');
    expect(context.getBean<Settings>().size, '3');
    expect(
      Binder.get(environment)
          .bind('shop.max-basket-size', const ClassType<int>())
          .get(),
      3,
    );
    final names = [for (final s in environment.propertySources) s.name];
    expect(
      names.indexOf(SpringApplication.dartDefinesPropertySourceName),
      names.indexOf('commandLineArgs') + 1,
    );
  });

  test('the command line wins over defines; defines win over the OS '
      'environment and config files', () {
    final context = app(dartDefines: const {'API_URL': 'define'}).run(
      [...location(), '--shop.max-basket-size=9'],
      systemEnvironment: const {'API_URL': 'os', 'SHOP_MAXBASKETSIZE': '7'},
    );
    addTearDown(context.close);
    expect(context.getBean<Settings>().url, 'define');
    expect(context.getBean<Settings>().size, '9');

    final cli = app(dartDefines: const {'API_URL': 'define'})
        .run([...location(), '--api.url=cli'], systemEnvironment: const {});
    addTearDown(cli.close);
    expect(cli.getBean<Settings>().url, 'cli');
  });

  test('SPRING_PROFILES_ACTIVE as a define activates profiles', () async {
    final context = await app(
      dartDefines: const {'SPRING_PROFILES_ACTIVE': 'prod'},
    ).runAsync(location(), systemEnvironment: const {});
    addTearDown(context.close);
    expect(context.environment.activeProfiles, ['prod']);
    expect(context.getBean<Settings>().url, 'from-prod-file');
  });

  test('no defines: no property source', () {
    final context = app().run(location(), systemEnvironment: const {});
    addTearDown(context.close);
    expect(
      context.environment.propertySources.containsSource(
        SpringApplication.dartDefinesPropertySourceName,
      ),
      isFalse,
    );
  });

  group('additionalProfiles of run', () {
    test("come after the application's own, before config files are "
        'read; the more specific last wins', () {
      final context = app(additionalProfiles: const ['base']).run(
        location(),
        systemEnvironment: const {},
        additionalProfiles: const ['mobile', 'android'],
      );
      addTearDown(context.close);
      expect(context.environment.activeProfiles, ['base', 'mobile', 'android']);
      expect(context.environment.getProperty('region'), 'mobile');
      expect(context.environment.getProperty('kind'), 'android');
    });

    test('runAsync takes them too, and a reload keeps them', () async {
      final context = await app().runAsync(
        location(),
        systemEnvironment: const {},
        additionalProfiles: const ['mobile', 'android'],
      );
      expect(context.environment.activeProfiles, ['mobile', 'android']);

      final reloaded = await app(fingerprint: 'v2').reloadAsync(context);
      addTearDown(reloaded.close);
      expect(reloaded, isNot(same(context)));
      expect(reloaded.environment.activeProfiles, ['mobile', 'android']);
      expect(reloaded.environment.getProperty('kind'), 'android');

      final again = app(fingerprint: 'v3').reload(reloaded);
      addTearDown(again.close);
      expect(again.environment.activeProfiles, ['mobile', 'android']);
    });
  });
}
