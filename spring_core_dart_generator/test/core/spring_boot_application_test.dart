// `@SpringBootApplication`: what an application's module scans, embeds
// and declares.
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  test('lib/resources files are embedded as classpath resources', () async {
    final output = await generateModule(
      '@Component() class A {}',
      extra: {
        'lib/resources/application.properties': "app.name='NEON' \$x\nb=2",
        'lib/resources/img/logo.bin': const [0xff, 0xfe, 0x00],
      },
    );
    expect(
      output,
      contains("r'application.properties':EmbeddedResource.text("),
    );
    expect(output, contains("r'img/logo.bin':EmbeddedResource.base64("));
  });

  group('@SpringBootApplication', () {
    test(
      'scans lib/ and the directory of main, declares runApplication',
      () async {
        final result = await buildPackage({
          'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);

@Component()
class CliRunner {}
''',
          'lib/src/deep/service.dart': '$coreImport@Service() class Deep {}',
          'lib/props.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
@ConfigurationProperties('db')
class DbProps { String url = ''; }
''',
        });
        expect(result.errors, isEmpty);
        final output = normalize(
          result.readerWriter.testing.readString(result.outputs.single),
        );
        expect(result.outputs.single.path, 'bin/spring_gen/main.spring.dart');
        // lib/spring_auto_configuration.dart of the dependencies is
        // discovered, listed by package (SpringApplication sorts them).
        expect(
          output,
          contains('autoConfigurations:[springBootAutoConfiguration,'),
        );
        // Every starter of the workspace is discovered.
        for (final starter in [
          'springBootStarterLoggingAutoConfiguration',
          'springBootStarterSchedulingAutoConfiguration',
          'springBootStarterCacheAutoConfiguration',
        ]) {
          expect(output, contains(starter));
        }
        expect(
          output,
          hasCode(
            'runApplicationAsync(List<String> args) '
            '=> '
            'springApplication.runAsync(args, hotReload: () => '
            'springApplication)',
          ),
        );
        expect(output, hasCode("BeanDefinition<CliRunner>(name: r'cliRunner'"));
        expect(output, hasCode("name: r'deep'"));
        // @ConfigurationProperties: a bean plus introspection metadata.
        expect(output, hasCode("name: r'dbProps'"));
        expect(output, hasCode('BeanIntrospection<'));
        expect(output, contains("ConfigurationProperties(r'db')"));
        // Getters, so a hot reload sees the beans of the new code.
        expect(
          output,
          hasCode(r"BeanModule get $application => BeanModule(r'application'"),
        );
        expect(output, hasCode('SpringApplication get springApplication =>'));
        expect(output, matches(RegExp("fingerprint:'[0-9a-f]{8}'")));
        expect(
          output,
          hasCode(
            'runApplication(List<String> args) => '
            'springApplication.run(args, hotReload: () => springApplication);',
          ),
        );
        expect(
          output,
          hasCode(
            'reloadApplication(ConfigurableApplicationContext running, '
            '{bool runners = true}) => '
            'springApplication.reload(running, runners: runners);',
          ),
        );
        expect(
          output,
          hasCode(
            'reloadApplicationAsync(ConfigurableApplicationContext '
            'running, {bool runners = true}) => '
            'springApplication.reloadAsync(running, runners: runners);',
          ),
        );
      },
    );

    test(
      'the same digits earlier in the file are not the fingerprint',
      () async {
        final result = await buildPackage({
          'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
          'lib/resources/application.properties':
              'app.tenant=00000000-0000-0000-0000-000000000000\n',
        });
        expect(result.errors, isEmpty);
        final output = result.readerWriter.testing.readString(
          result.outputs.single,
        );
        expect(output, contains('00000000-0000-0000-0000-000000000000'));
        expect(output, isNot(contains("fingerprint: '00000000'")));
        expect(output, matches(RegExp("fingerprint: '[0-9a-f]{8}'")));
      },
    );

    test('the fingerprint is stable and changes with the beans', () async {
      Future<String> fingerprint(String beans) async {
        final result = await buildPackage({
          'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
          'lib/beans.dart': '$coreImport$beans',
        });
        expect(result.errors, isEmpty);
        return RegExp("fingerprint: '([0-9a-f]{8})'")
            .firstMatch(
              result.readerWriter.testing.readString(result.outputs.single),
            )!
            .group(1)!;
      }

      const one = '@Service() class A {}';
      final first = await fingerprint(one);
      expect(await fingerprint(one), first); // same code, same fingerprint
      expect(
        await fingerprint('$one\n@Service() class B {}'), // a new bean
        isNot(first),
      );
      expect(
        await fingerprint(
          r"@Service() class A { A(@Value(r'${x:1}') this.x); final String x; "
          '}',
        ),
        isNot(first), // a changed injection point
      );
    });
  });
}
