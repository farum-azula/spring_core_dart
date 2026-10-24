// `@ConfigurationProperties` on a `@Bean` method (Spring Boot's binding of
// third-party classes): the returned class gets introspection metadata
// and the method's annotations reach the bean definition.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _config = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/src/pool.dart';

@Configuration()
class PoolConfig {
  @Bean()
  @ConfigurationProperties('pool')
  @Validated()
  Pool pool() => Pool();
}
''';

// A plain class, as if from a library: no annotations of its own.
const _pool = '''
class Pool {
  String url = '';
  int size = 1;
}
''';

void main() {
  test('the returned class is introspected and the definition carries '
      'the annotations', () async {
    final sources = {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/config.dart': _config,
      'pkg|lib/src/pool.dart': _pool,
    };
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    await readerWriter.testing.loadIsolateSources();
    final result = await testBuilder(
      SpringBuilder(),
      sources,
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.errors, isEmpty);
    final output = result.readerWriter.testing.readString(
      result.outputs.single,
    );
    final compact = output
        .replaceAll(RegExp(r'\b_i\d+\.'), '')
        .replaceAll(RegExp(r'\s'), '');
    expect(compact, contains('BeanIntrospection<Pool>('));
    expect(compact, contains("BeanProperty<Pool>(r'url'"));
    expect(compact, contains("ConfigurationProperties(r'pool')"));
    expect(compact, contains('Validated('));

    final errors = await resolveSources<List<String>>(
      {...sources, 'pkg|lib/src/beans.spring.dart': output},
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId('pkg', 'lib/src/beans.spring.dart'),
        );
        final errors = await library.session.getErrors(
          library.firstFragment.source.fullName,
        );
        return [
          if (errors case ErrorsResult(:final diagnostics))
            for (final diagnostic in diagnostics)
              if (diagnostic.severity == Severity.error) diagnostic.message,
        ];
      },
      rootPackage: 'pkg',
      resolverFor: 'pkg|lib/src/beans.spring.dart',
      readAllSourcesFromFilesystem: true,
    );
    expect(errors, isEmpty);
  });
}
