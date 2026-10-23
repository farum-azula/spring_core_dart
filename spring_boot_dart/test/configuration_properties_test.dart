import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

// ---- generated ----
// What spring_core_dart_generator writes for the classes below (the
// introspections carry the full TypeInfo of every property and constructor
// parameter).

enum Mode { fast, extraSafe }

class Server {
  String host = '';
  int port = 0;
}

/// A nested value object (constructor binding inside a map).
class Backend {
  const Backend(this.url, {this.weight = 1});
  final String url;
  final int weight;
}

class AppProperties {
  List<String> hosts = [];
  Set<int> ports = {};
  List<Duration> timeouts = [];
  Map<String, String> headers = {'x-default': 'kept'};
  List<Server> servers = [];
  Map<String, Backend> backends = {};
  Map<String, List<String>> groups = {};
  Mode mode = Mode.fast;
  int maxSize = 10;
  Server primary = Server();
  final List<String> readOnlyTags = [];
}

final serverIntrospection = BeanIntrospection<Server>(
  properties: [
    BeanProperty<Server>(
      'host',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.host,
      set: (b, v) => b.host = v! as String,
    ),
    BeanProperty<Server>(
      'port',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.port,
      set: (b, v) => b.port = v! as int,
    ),
  ],
  instantiate: Server.new,
);

final backendIntrospection = BeanIntrospection<Backend>(
  properties: [
    BeanProperty<Backend>(
      'url',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.url,
    ),
    BeanProperty<Backend>(
      'weight',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.weight,
    ),
  ],
  constructor: BeanConstructor<Backend>(
    parameters: const [
      BeanParameter('url', type: ClassType<String>(), isRequired: true),
      BeanParameter('weight', type: ClassType<int>(), symbol: #weight),
    ],
    create: (positional, named) =>
        Function.apply(Backend.new, positional, named) as Backend,
  ),
);

BeanProperty<AppProperties> _app<T>(
  String name,
  TypeInfo<T> typeInfo,
  Object? Function(AppProperties) get, [
  void Function(AppProperties, T)? set,
]) => BeanProperty<AppProperties>(
  name,
  type: typeInfo.type,
  typeInfo: typeInfo,
  get: get,
  set: set == null ? null : (b, v) => set(b, v as T),
);

final appIntrospection = BeanIntrospection<AppProperties>(
  annotations: const [ConfigurationProperties('app')],
  properties: [
    _app(
      'hosts',
      const ListType<String>(ClassType<String>()),
      (b) => b.hosts,
      (b, v) => b.hosts = v,
    ),
    _app(
      'ports',
      const SetType<int>(ClassType<int>()),
      (b) => b.ports,
      (b, v) => b.ports = v,
    ),
    _app(
      'timeouts',
      const ListType<Duration>(ClassType<Duration>()),
      (b) => b.timeouts,
      (b, v) => b.timeouts = v,
    ),
    _app(
      'headers',
      const MapType<String, String>(ClassType<String>(), ClassType<String>()),
      (b) => b.headers,
      (b, v) => b.headers = v,
    ),
    _app(
      'servers',
      const ListType<Server>(ClassType<Server>()),
      (b) => b.servers,
      (b, v) => b.servers = v,
    ),
    _app(
      'backends',
      const MapType<String, Backend>(ClassType<String>(), ClassType<Backend>()),
      (b) => b.backends,
      (b, v) => b.backends = v,
    ),
    _app(
      'groups',
      const MapType<String, List<String>>(
        ClassType<String>(),
        ListType<String>(ClassType<String>()),
      ),
      (b) => b.groups,
      (b, v) => b.groups = v,
    ),
    _app(
      'mode',
      const EnumType<Mode>(Mode.values),
      (b) => b.mode,
      (b, v) => b.mode = v,
    ),
    _app(
      'maxSize',
      const ClassType<int>(),
      (b) => b.maxSize,
      (b, v) => b.maxSize = v,
    ),
    _app(
      'primary',
      const ClassType<Server>(),
      (b) => b.primary,
      (b, v) => b.primary = v,
    ),
    _app(
      'readOnlyTags',
      const ListType<String>(ClassType<String>()),
      (b) => b.readOnlyTags,
    ),
  ],
  instantiate: AppProperties.new,
);

/// Constructor binding: final fields, Dart defaults and `@DefaultValue`.
class PoolProperties {
  const PoolProperties(
    this.url, {
    required this.maxSize,
    required this.tags,
    this.timeout = const Duration(seconds: 5),
    this.owner,
    required this.endpoint,
    required this.replicas,
  });

  final String url;
  final int maxSize;
  final List<String> tags;
  final Duration timeout;
  final String? owner;
  final Endpoint endpoint;
  final List<Endpoint> replicas;
}

/// A nested value object.
class Endpoint {
  const Endpoint({this.host = 'localhost', this.port = 80});
  final String host;
  final int port;
}

final endpointIntrospection = BeanIntrospection<Endpoint>(
  properties: [
    BeanProperty<Endpoint>(
      'host',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.host,
    ),
    BeanProperty<Endpoint>(
      'port',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.port,
    ),
  ],
  constructor: BeanConstructor<Endpoint>(
    parameters: const [
      BeanParameter('host', type: ClassType<String>(), symbol: #host),
      BeanParameter('port', type: ClassType<int>(), symbol: #port),
    ],
    create: (positional, named) =>
        Function.apply(Endpoint.new, positional, named) as Endpoint,
  ),
);

final poolIntrospection = BeanIntrospection<PoolProperties>(
  annotations: const [ConfigurationProperties('pool'), Validated()],
  properties: [
    BeanProperty<PoolProperties>(
      'url',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.url,
      annotations: const [NotBlank()],
    ),
    BeanProperty<PoolProperties>(
      'maxSize',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.maxSize,
      annotations: const [Max(100)],
    ),
  ],
  constructor: BeanConstructor<PoolProperties>(
    parameters: const [
      BeanParameter('url', type: ClassType<String>(), isRequired: true),
      BeanParameter(
        'maxSize',
        type: ClassType<int>(),
        symbol: #maxSize,
        isRequired: true,
        annotations: [DefaultValue('10')],
      ),
      BeanParameter(
        'tags',
        type: ListType<String>(ClassType<String>()),
        symbol: #tags,
        isRequired: true,
        annotations: [
          DefaultValue(['a', 'b']),
        ],
      ),
      BeanParameter('timeout', type: ClassType<Duration>(), symbol: #timeout),
      BeanParameter(
        'owner',
        type: ClassType<String>(nullable: true),
        symbol: #owner,
      ),
      BeanParameter(
        'endpoint',
        type: ClassType<Endpoint>(),
        symbol: #endpoint,
        isRequired: true,
      ),
      BeanParameter(
        'replicas',
        type: ListType<Endpoint>(ClassType<Endpoint>()),
        symbol: #replicas,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(PoolProperties.new, positional, named) as PoolProperties,
  ),
);

BeanModule module() => BeanModule(
  'app',
  [
    BeanDefinition<AppProperties>(
      name: 'appProperties',
      create: (_) => AppProperties(),
    ),
    BeanDefinition<PoolProperties>(
      name: 'poolProperties',
      create: (r) => ConstructorBound.from<PoolProperties>(r, 'poolProperties'),
    ),
  ],
  introspections: [
    appIntrospection,
    serverIntrospection,
    backendIntrospection,
    poolIntrospection,
    endpointIntrospection,
  ],
);
// ---- end of generated ----

void main() {
  ConfigurableApplicationContext run({
    List<String> args = const [],
    Map<String, String> env = const {},
    Map<String, Object?> properties = const {},
    ResourceLoader? resourceLoader,
  }) {
    final context =
        SpringApplication(
          [module()],
          resourceLoader: resourceLoader,
          out: (_) {},
        ).run(
          ['--pool.url=jdbc:x', ...args],
          systemEnvironment: env,
          properties: properties,
        );
    addTearDown(context.close);
    return context;
  }

  // The ConfigurationPropertiesBindException behind a failed start.
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

  test('String, num and bool beans pass through (no Expando key)', () {
    final context = SpringApplication([
      module(),
      BeanModule('values', [
        BeanDefinition<String>(name: 'text', create: (_) => 'hello'),
        BeanDefinition<int>(name: 'count', create: (_) => 3),
      ]),
    ], out: (_) {}).run(['--pool.url=jdbc:x']);
    addTearDown(context.close);
    expect(context.getBean<String>(), 'hello');
    expect(context.getBean<int>(), 3);
  });

  group('JavaBean binding', () {
    test('comma lists, indexed lists and environment variable indexes', () {
      final app = run(
        args: [
          '--app.hosts=a, b',
          '--app.ports[0]=80',
          '--app.ports[1]=443',
          '--app.timeouts=5s,PT1M',
        ],
      ).getBean<AppProperties>();
      expect(app.hosts, ['a', 'b']);
      expect(app.ports, {80, 443});
      // Elements are converted through the conversion service.
      expect(app.timeouts, const [Duration(seconds: 5), Duration(minutes: 1)]);

      final fromEnv = run(env: {'APP_HOSTS_0_': 'x', 'APP_HOSTS_1_': 'y'})
          .getBean<AppProperties>();
      expect(fromEnv.hosts, ['x', 'y']);
    });

    test('a list from a higher-precedence source replaces the whole list', () {
      final app = run(
        args: ['--app.hosts[0]=cli'],
        env: {'APP_HOSTS_0_': 'env-0', 'APP_HOSTS_1_': 'env-1'},
      ).getBean<AppProperties>();
      expect(app.hosts, ['cli']); // not [cli, env-1]

      // A comma list replaces indexed elements of a lower source, too.
      final comma = run(
        args: ['--app.servers[0].host=cli'],
        properties: {'app.hosts': 'p,q'},
        env: {'APP_HOSTS_0_': 'env-0', 'APP_HOSTS_1_': 'env-1'},
      ).getBean<AppProperties>();
      expect(comma.hosts, ['p', 'q']);
    });

    test('lists and maps of nested objects', () {
      final app = run(
        properties: {
          'app.servers[0].host': 'a',
          'app.servers[0].port': '80',
          'app.servers[1].host': 'b',
          'app.backends.eu.url': 'https://eu.example',
          'app.backends.eu.weight': 3,
          'app.backends.us.url': 'https://us.example',
          'app.groups.admins[0]': 'ada',
          'app.groups.admins[1]': 'bob',
          'app.groups.users': 'carl,dora',
        },
      ).getBean<AppProperties>();
      expect(
        [for (final s in app.servers) '${s.host}:${s.port}'],
        ['a:80', 'b:0'],
      );
      expect(app.backends.keys, ['eu', 'us']);
      expect(app.backends['eu']!.url, 'https://eu.example');
      expect(app.backends['eu']!.weight, 3);
      expect(app.backends['us']!.weight, 1); // Dart default
      expect(app.groups, {
        'admins': ['ada', 'bob'],
        'users': ['carl', 'dora'],
      });
    });

    test('map keys keep their form; entries merge across sources', () {
      final app = run(
        args: [
          '--app.headers.X-Shop=1',
          '--app.headers[x.y]=2',
          '--app.headers.a.b=3',
        ],
        properties: {'app.headers.X-Shop': 'inline'},
        env: {'APP_HEADERS_FROMENV': '4'},
      ).getBean<AppProperties>();
      expect(app.headers, {
        'x-default': 'kept', // the default entry stays (merged)
        'X-Shop': 'inline', // as written; the higher source wins per key
        'x.y': '2', // brackets keep the dots
        'a.b': '3', // a scalar value takes the rest of the name
        'fromenv': '4',
      });
    });

    test('YAML lists bind like indexed keys', () {
      const yaml = '''
app:
  hosts:
    - one
    - two
  servers:
    - host: a
      port: 80
    - host: b
  backends:
    eu:
      url: https://eu.example
''';
      final loader = DefaultResourceLoader(
        protocolResolvers: [
          FunctionProtocolResolver(
            (location, _) => location == 'classpath:/application.yml'
                ? ByteArrayResource.fromString(yaml, description: 'yml')
                : null,
          ),
        ],
      );
      final app = run(resourceLoader: loader).getBean<AppProperties>();
      expect(app.hosts, ['one', 'two']);
      expect(
        [for (final s in app.servers) '${s.host}:${s.port}'],
        ['a:80', 'b:0'],
      );
      expect(app.backends['eu']!.url, 'https://eu.example');
    });

    test('relaxed names: the first property source wins, in any form', () {
      // Command line (camelCase) beats the environment variable ...
      expect(
        run(
          args: ['--app.maxSize=1'],
          env: {'APP_MAXSIZE': '2'},
        ).getBean<AppProperties>().maxSize,
        1,
      );
      // ... underscores work too, and so does the variable alone.
      expect(
        run(args: ['--app.max_size=3']).getBean<AppProperties>().maxSize,
        3,
      );
      expect(
        run(env: {'APP_MAXSIZE': '4'}).getBean<AppProperties>().maxSize,
        4,
      );
    });

    test('nested objects, lenient enums and read-only lists', () {
      final app = run(
        args: [
          '--app.primary.host=main',
          '--app.mode=EXTRA_SAFE',
          '--app.read-only-tags=t1,t2',
        ],
      ).getBean<AppProperties>();
      expect(app.primary.host, 'main');
      expect(app.mode, Mode.extraSafe);
      expect(app.readOnlyTags, ['t1', 't2']);
    });

    test('list indexes must start at 0 without gaps', () {
      final error = failure(() => run(args: ['--app.hosts[1]=x']));
      expect(
        error.errors.single,
        contains('The elements [app.hosts[1]] were left unbound'),
      );
    });

    test('conversion failures name the property and the value', () {
      final error = failure(
        () => run(
          args: [
            '--app.max-size=lots',
            '--app.ports[0]=x',
            '--app.backends.eu.url=u',
            '--app.backends.eu.weight=heavy',
          ],
        ),
      );
      expect(error.prefix, 'app');
      expect(error.beanName, 'appProperties');
      expect(error.errors, [
        'app.ports[0]: failed to convert to int (was "x")',
        'app.backends.eu.weight: failed to convert to int (was "heavy")',
        'app.max-size: failed to convert to int (was "lots")',
      ]);
    });
  });

  group('constructor binding', () {
    test('parameters from properties, defaults otherwise', () {
      final pool = run(args: ['--pool.endpoint.port=5432'])
          .getBean<PoolProperties>();
      expect(pool.url, 'jdbc:x');
      expect(pool.maxSize, 10); // @DefaultValue('10')
      expect(pool.tags, ['a', 'b']); // @DefaultValue(['a', 'b'])
      expect(pool.timeout, const Duration(seconds: 5)); // Dart default
      expect(pool.owner, isNull); // nullable without a value
      expect(pool.endpoint.host, 'localhost'); // nested value object
      expect(pool.endpoint.port, 5432);
      expect(pool.replicas, isEmpty);
    });

    test('given values win over defaults; collections of value objects', () {
      final pool = run(
        args: [
          '--pool.max-size=20',
          '--pool.tags[0]=x',
          '--pool.timeout=1m',
          '--pool.owner=ops',
          '--pool.replicas[0].host=r1',
          '--pool.replicas[1].port=81',
        ],
      ).getBean<PoolProperties>();
      expect(pool.maxSize, 20);
      expect(pool.tags, ['x']);
      expect(pool.timeout, const Duration(minutes: 1));
      expect(pool.owner, 'ops');
      expect(pool.endpoint.port, 80); // created with its defaults
      expect(
        [for (final r in pool.replicas) '${r.host}:${r.port}'],
        ['r1:80', 'localhost:81'],
      );
    });

    test('validated after construction (@Validated)', () {
      final error = failure(() => run(args: ['--pool.max-size=500']));
      expect(
        error.errors.single,
        startsWith('pool.max-size: must be less than or equal to 100'),
      );
    });

    test('a required parameter without a value or default fails the start, '
        'naming the property', () {
      final lines = <String>[];
      final error = failure(
        () => SpringApplication([
          module(),
        ], out: lines.add).run(const [], systemEnvironment: const {}),
      );
      expect(error.beanName, 'poolProperties');
      expect(
        error.errors.single,
        "pool.url: no value bound for the required constructor parameter 'url' "
        'of PoolProperties (set the property, give the parameter a '
        '@DefaultValue or a default, or make it nullable)',
      );
      expect(
        lines.join('\n'),
        contains("Binding to target properties under 'pool' failed"),
      );
    });

    test('works without SpringApplication too', () {
      final environment = StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(
          MapPropertySource('test', {'pool.url': 'jdbc:y'}),
        );
      final context = AnnotationConfigApplicationContext([
        module(),
      ], environment: environment)..refresh();
      addTearDown(context.close);
      expect(context.getBean<PoolProperties>().url, 'jdbc:y');
    });
  });

  test('Binder binds a typed value from the environment', () {
    final environment = StandardEnvironment(
      systemEnvironment: {'APP_HOSTS_0_': 'a', 'APP_HOSTS_1_': 'b'},
    );
    final binder = Binder.get(environment);
    expect(
      binder
          .bind('app.hosts', const ListType<String>(ClassType<String>()))
          .get(),
      ['a', 'b'],
    );
    final missing = binder.bind('app.port', const ClassType<int>());
    expect(missing.isBound, isFalse);
    expect(missing.orElse(8080), 8080);
  });
}
