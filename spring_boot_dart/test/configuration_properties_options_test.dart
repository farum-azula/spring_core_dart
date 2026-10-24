import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

// Hand-written introspections, as the generator writes them.

class Endpoint {
  String host = '';
}

class Strict {
  int port = 0;
  List<String> hosts = [];
  Endpoint endpoint = Endpoint();
}

class Lenient {
  int port = 7;
  List<int> ids = [1];
  String name = '';
}

/// Constructor-bound, unknown properties rejected.
class StrictRecord {
  const StrictRecord({this.port = 1});
  final int port;
}

final endpointIntrospection = BeanIntrospection<Endpoint>(
  properties: [
    BeanProperty<Endpoint>(
      'host',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.host,
      set: (b, v) => b.host = v! as String,
    ),
  ],
  instantiate: Endpoint.new,
);

final strictIntrospection = BeanIntrospection<Strict>(
  annotations: const [
    ConfigurationProperties('strict', ignoreUnknownFields: false),
  ],
  properties: [
    BeanProperty<Strict>(
      'port',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.port,
      set: (b, v) => b.port = v! as int,
    ),
    BeanProperty<Strict>(
      'hosts',
      type: List<String>,
      typeInfo: const ListType<String>(ClassType<String>()),
      get: (b) => b.hosts,
      set: (b, v) => b.hosts = v! as List<String>,
    ),
    BeanProperty<Strict>(
      'endpoint',
      type: Endpoint,
      typeInfo: const ClassType<Endpoint>(),
      get: (b) => b.endpoint,
      set: (b, v) => b.endpoint = v! as Endpoint,
    ),
  ],
  instantiate: Strict.new,
);

final lenientIntrospection = BeanIntrospection<Lenient>(
  annotations: const [
    ConfigurationProperties('lenient', ignoreInvalidFields: true),
  ],
  properties: [
    BeanProperty<Lenient>(
      'port',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.port,
      set: (b, v) => b.port = v! as int,
    ),
    BeanProperty<Lenient>(
      'ids',
      type: List<int>,
      typeInfo: const ListType<int>(ClassType<int>()),
      get: (b) => b.ids,
      set: (b, v) => b.ids = v! as List<int>,
    ),
    BeanProperty<Lenient>(
      'name',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.name,
      set: (b, v) => b.name = v! as String,
    ),
  ],
  instantiate: Lenient.new,
);

final strictRecordIntrospection = BeanIntrospection<StrictRecord>(
  annotations: const [
    ConfigurationProperties('record', ignoreUnknownFields: false),
  ],
  properties: [
    BeanProperty<StrictRecord>(
      'port',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.port,
    ),
  ],
  constructor: BeanConstructor<StrictRecord>(
    parameters: const [
      BeanParameter('port', type: ClassType<int>(), symbol: #port),
    ],
    create: (positional, named) =>
        Function.apply(StrictRecord.new, positional, named) as StrictRecord,
  ),
);

void main() {
  ConfigurableApplicationContext run(
    List<String> args, {
    Map<String, String> env = const {},
  }) {
    final context = SpringApplication(
      [
        BeanModule(
          'app',
          [
            BeanDefinition<Strict>(name: 'strict', create: (_) => Strict()),
            BeanDefinition<Lenient>(name: 'lenient', create: (_) => Lenient()),
            BeanDefinition<StrictRecord>(
              name: 'record',
              create: (r) => ConstructorBound.from<StrictRecord>(r, 'record'),
            ),
          ],
          introspections: [
            endpointIntrospection,
            strictIntrospection,
            lenientIntrospection,
            strictRecordIntrospection,
          ],
        ),
      ],
      bannerMode: BannerMode.off,
      out: (_) {},
    ).run(args, systemEnvironment: env);
    addTearDown(context.close);
    return context;
  }

  ConfigurationPropertiesBindException failure(void Function() body) {
    try {
      body();
    } catch (error) {
      Object? cause = error;
      while (cause is BeansException) {
        cause = cause.cause;
      }
      if (cause is ConfigurationPropertiesBindException) {
        return cause;
      }
      fail('expected a ConfigurationPropertiesBindException, got $error');
    }
    fail('expected a failure');
  }

  group('ignoreUnknownFields: false', () {
    test('known properties bind', () {
      final strict = run([
        '--strict.port=80',
        '--strict.hosts[0]=a',
        '--strict.endpoint.host=h',
        '--record.port=5',
      ]).getBean<Strict>();
      expect(strict.port, 80);
      expect(strict.hosts, ['a']);
      expect(strict.endpoint.host, 'h');
    });

    test('an unknown property fails the start, like Boot', () {
      final error = failure(
        () => run(['--strict.port=80', '--strict.prot=81', '--strict.x.y=1']),
      );
      expect(error.beanName, 'strict');
      expect(
        error.errors.single,
        'The elements [strict.prot, strict.x.y] were left unbound.',
      );
    });

    test('also for constructor binding', () {
      final error = failure(() => run(['--record.unknown=1']));
      expect(error.errors.single, contains('[record.unknown]'));
    });

    test('OS environment variables and overridden list elements are fine', () {
      final strict = run(
        ['--strict.hosts=x,y'],
        env: {'STRICT_UNKNOWN': '1', 'STRICT_HOSTS_0_': 'z'},
      ).getBean<Strict>();
      expect(strict.hosts, ['x', 'y']);
    });

    test('the default (true) ignores unknown properties', () {
      expect(run(['--lenient.unknown=1']).getBean<Lenient>().port, 7);
    });
  });

  group('ignoreInvalidFields: true', () {
    test('values that cannot be converted keep the defaults', () {
      final lenient = run([
        '--lenient.port=eighty',
        '--lenient.ids=1,x',
        '--lenient.name=n',
      ]).getBean<Lenient>();
      expect(lenient.port, 7);
      expect(lenient.ids, [1]);
      expect(lenient.name, 'n');
    });

    test('the default (false) fails', () {
      final error = failure(() => run(['--strict.port=eighty']));
      expect(error.errors.single, contains('strict.port'));
    });
  });
}
