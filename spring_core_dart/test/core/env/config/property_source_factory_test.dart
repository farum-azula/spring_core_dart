import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  final memory = InMemoryProtocolResolver('mem:', {
    'a.properties': 'key=a\nonly.a=1',
    'b.properties': 'key=b\nonly.b=2',
    'c.properties': 'key=c',
  });
  late StandardEnvironment env;
  late PropertySourceProcessor processor;

  setUp(() {
    env = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(
        const MapPropertySource('base', {'dir': 'mem:'}),
      );
    processor = PropertySourceProcessor(
      env,
      DefaultResourceLoader(protocolResolvers: [memory]),
    );
  });

  List<String> names() => [for (final s in env.propertySources) s.name];

  test('later locations win; placeholders in locations', () {
    processor
      ..processPropertySource([r'${dir}a.properties'])
      ..processPropertySource(['mem:b.properties', 'mem:c.properties']);
    expect(env.getProperty('key'), 'c');
    expect(env.getProperty('only.a'), '1');
    expect(env.getProperty('only.b'), '2');
    // Like Spring: @PropertySource sources sit below the OS environment.
    expect(names(), [
      'base',
      'systemEnvironment',
      'resource [mem:c.properties]',
      'resource [mem:b.properties]',
      'resource [mem:a.properties]',
    ]);
  });

  test('missing resources', () {
    expect(
      () => processor.processPropertySource(['mem:none.properties']),
      throwsA(
        isA<PropertySourceNotFoundException>().having(
          (e) => e.toString(),
          'text',
          contains('mem:none.properties'),
        ),
      ),
    );
    processor.processPropertySource([
      'mem:none.properties',
      r'${undefined}/x.properties',
    ], ignoreResourceNotFound: true);
    expect(names(), ['base', 'systemEnvironment']);
    expect(
      () => processor.processPropertySource([r'${undefined}/x.properties']),
      throwsA(isA<PlaceholderResolutionException>()),
    );
  });

  test('same name merges into a composite, newest first', () {
    processor
      ..processPropertySource(['mem:a.properties'], name: 'shared')
      ..processPropertySource(['mem:b.properties'], name: 'shared')
      ..processPropertySource(['mem:c.properties'], name: 'shared');
    final shared = env.propertySources.get('shared');
    expect(shared, isA<CompositePropertySource>());
    expect(env.getProperty('key'), 'c');
    expect(env.getProperty('only.a'), '1');
  });

  test('custom factory', () {
    processor.processPropertySource([
      'mem:a.properties',
    ], factory: const _UpperCaseFactory());
    expect(env.getProperty('KEY'), 'a');
  });

  test('a same-named source from elsewhere is replaced, not merged', () {
    env.propertySources.addLast(
      const MapPropertySource('shared', {'key': 'old', 'only.old': 'x'}),
    );
    processor.processPropertySource(['mem:a.properties'], name: 'shared');
    final shared = env.propertySources.get('shared');
    expect(shared, isNot(isA<CompositePropertySource>()));
    expect(env.getProperty('key'), 'a');
    expect(env.getProperty('only.old'), isNull);
    // A second call extends the processor's own source.
    processor.processPropertySource(['mem:b.properties'], name: 'shared');
    expect(env.propertySources.get('shared'), isA<CompositePropertySource>());
    expect(env.getProperty('only.a'), '1');
  });

  test('previous source removed: next one goes last', () {
    processor.processPropertySource(['mem:a.properties']);
    env.propertySources.remove(env.propertySources.elementAt(1).name);
    processor.processPropertySource(['mem:b.properties']);
    expect(env.getProperty('key'), 'b');
  });
}

class _UpperCaseFactory implements PropertySourceFactory {
  const _UpperCaseFactory();

  @override
  AbstractPropertySource<Object> createPropertySource(
    String? name,
    EncodedResource resource,
  ) {
    final source = ResourcePropertySource.fromResource(resource.resource);
    return MapPropertySource(name ?? source.name, {
      for (final key in source.propertyNames)
        key.toUpperCase(): source.getProperty(key),
    });
  }
}
