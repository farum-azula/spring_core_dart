import 'dart:io';

import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

// Spring Boot 4 behaviour: binding (env vars, @Name, units, handlers),
// @ConfigurationProperties on @Bean methods, validation, conditions and
// their report, EnvironmentPostProcessor, messages, exit codes, banner.

class Server {
  String host = '';
  int port = 0;
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

/// A "third-party" class bound through a `@Bean` method.
class Pool {
  String url = '';
  int size = 1;
}

final poolIntrospection = BeanIntrospection<Pool>(
  properties: [
    BeanProperty<Pool>(
      'url',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.url,
      set: (b, v) => b.url = v! as String,
    ),
    BeanProperty<Pool>(
      'size',
      type: int,
      typeInfo: const ClassType<int>(),
      annotations: const [Min(1)],
      get: (b) => b.size,
      set: (b, v) => b.size = v! as int,
    ),
  ],
  instantiate: Pool.new,
);

/// Validates itself (Boot's self-validating properties).
class Modes implements Validator {
  String mode = 'a';

  @override
  bool supports(Object target) => target is Modes;

  @override
  void validate(Object target, Errors errors) {
    if ((target as Modes).mode != 'a' && target.mode != 'b') {
      errors.rejectValue('mode', 'mode', defaultMessage: 'must be a or b');
    }
  }
}

final modesIntrospection = BeanIntrospection<Modes>(
  annotations: const [ConfigurationProperties('modes')],
  properties: [
    BeanProperty<Modes>(
      'mode',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.mode,
      set: (b, v) => b.mode = v! as String,
    ),
  ],
  instantiate: Modes.new,
);

/// The `configurationPropertiesValidator` bean.
class JdbcUrls implements Validator {
  const JdbcUrls();

  @override
  bool supports(Object target) => target is Pool;

  @override
  void validate(Object target, Errors errors) {
    if (!(target as Pool).url.startsWith('jdbc:')) {
      errors.rejectValue('url', 'jdbc', defaultMessage: 'must be a JDBC url');
    }
  }
}

class Units {
  Duration timeout = Duration.zero;
  List<Duration> retries = [];
  DataSize buffer = const DataSize.ofBytes(0);
  String importFrom = '';
}

final unitsIntrospection = BeanIntrospection<Units>(
  properties: [
    BeanProperty<Units>(
      'timeout',
      type: Duration,
      typeInfo: const ClassType<Duration>(),
      annotations: const [DurationUnit(ChronoUnit.seconds)],
      get: (b) => b.timeout,
      set: (b, v) => b.timeout = v! as Duration,
    ),
    BeanProperty<Units>(
      'retries',
      type: List<Duration>,
      typeInfo: const ListType<Duration>(ClassType<Duration>()),
      annotations: const [DurationUnit(ChronoUnit.minutes)],
      get: (b) => b.retries,
      set: (b, v) => b.retries = v! as List<Duration>,
    ),
    BeanProperty<Units>(
      'buffer',
      type: DataSize,
      typeInfo: const ClassType<DataSize>(),
      annotations: const [DataSizeUnit(DataUnit.megabytes)],
      get: (b) => b.buffer,
      set: (b, v) => b.buffer = v! as DataSize,
    ),
    BeanProperty<Units>(
      'importFrom',
      type: String,
      typeInfo: const ClassType<String>(),
      annotations: const [Name('import')],
      get: (b) => b.importFrom,
      set: (b, v) => b.importFrom = v! as String,
    ),
  ],
  instantiate: Units.new,
);

/// Constructor binding with `@Name`.
class Renamed {
  const Renamed(this.value);
  final String value;
}

final renamedIntrospection = BeanIntrospection<Renamed>(
  properties: [
    BeanProperty<Renamed>(
      'value',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.value,
    ),
  ],
  constructor: BeanConstructor<Renamed>(
    parameters: const [
      BeanParameter(
        'value',
        type: ClassType<String>(),
        isRequired: true,
        annotations: [Name('default')],
      ),
    ],
    create: (positional, named) => Renamed(positional.single! as String),
  ),
);

abstract interface class Greeter {}

class Hello implements Greeter {}

class Marker {}

class Recording extends BindHandler {
  Recording({this.ignoreFailures = false});

  final bool ignoreFailures;
  final started = <String>[];
  final failures = <String>[];

  @override
  bool onStart(ConfigurationPropertyName name, TypeInfo<Object?> target) {
    started.add('$name');
    return true;
  }

  @override
  bool onFailure(ConfigurationPropertyName name, String error) {
    failures.add(error);
    return !ignoreFailures;
  }
}

final class Ordered1 implements EnvironmentPostProcessor, Ordered {
  Ordered1(this.importFile, this.log);

  final String importFile;
  final List<String> log;

  @override
  int get order => EnvironmentPostProcessor.configDataOrder - 1;

  @override
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  ) {
    log.add('before: ${environment.getProperty('from.file')}');
    environment.propertySources.addLast(
      MapPropertySource('epp', {
        'spring.config.import': 'file:$importFile',
        'spring.profiles.active': 'extra',
      }),
    );
  }
}

final class After implements EnvironmentPostProcessor {
  After(this.log);

  final List<String> log;

  @override
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  ) => log.add('after: ${environment.getProperty('from.file')}');
}

// A start that fails binding: the bean's creation error wraps it.
Matcher bindFailure(String text) => throwsA(
  isA<BeanCreationException>().having(
    (e) => e.cause,
    'cause',
    isA<ConfigurationPropertiesBindException>().having(
      (e) => e.errors.single,
      'error',
      contains(text),
    ),
  ),
);

void main() {
  BeanIntrospector introspector() => BeanIntrospector()
    ..registerAll([
      serverIntrospection,
      unitsIntrospection,
      renamedIntrospection,
    ]);

  StandardEnvironment environment(
    Map<String, Object?> properties, [
    Map<String, String> system = const {},
  ]) {
    final env = StandardEnvironment(systemEnvironment: system)
      ..propertySources.addFirst(MapPropertySource('test', properties));
    ConfigurationPropertySources.attach(env);
    return env;
  }

  ConfigurableApplicationContext run(
    List<BeanDefinition<Object>> definitions, {
    List<String> args = const [],
    List<BeanIntrospection<Object>> introspections = const [],
    List<BeanModule> autoConfigurations = const [],
    List<EnvironmentPostProcessor> environmentPostProcessors = const [],
    void Function(String line)? out,
  }) {
    final context = SpringApplication(
      [BeanModule('app', definitions, introspections: introspections)],
      autoConfigurations: autoConfigurations,
      environmentPostProcessors: environmentPostProcessors,
      bannerMode: BannerMode.off,
      out: out ?? (_) {},
    ).run(args, systemEnvironment: const {});
    addTearDown(() {
      if (context.isActive) {
        context.close();
      }
    });
    return context;
  }

  group('Binder', () {
    test("env vars bind nested objects under dashed names (Boot's legacy "
        'ancestor check)', () {
      final env = environment({}, {
        'APP_MAIN_SERVER_HOST': 'example.org',
        'APP_MAIN_SERVER_PORT': '8443',
      });
      final server = Binder(
        env,
        introspector: introspector(),
      ).bind('app.main-server', const ClassType<Server>()).get();
      expect(server.host, 'example.org');
      expect(server.port, 8443);
    });

    test('@Name, @DurationUnit and @DataSizeUnit', () {
      final env = environment({
        'units.timeout': '30',
        'units.retries': '1,2',
        'units.buffer': '4',
        'units.import': 'yes',
        'renamed.default': 'kept',
      });
      final binder = Binder(env, introspector: introspector());
      final units = binder.bind('units', const ClassType<Units>()).get();
      expect(units.timeout, const Duration(seconds: 30));
      expect(units.retries, [
        const Duration(minutes: 1),
        const Duration(minutes: 2),
      ]);
      expect(units.buffer, DataSize.ofMegabytes(4));
      expect(units.importFrom, 'yes');
      expect(
        binder.bind('renamed', const ClassType<Renamed>()).get().value,
        'kept',
      );
      // Values with a unit keep it.
      final explicit = Binder(
        environment({'units.timeout': '500ms', 'units.buffer': '2KB'}),
        introspector: introspector(),
      ).bind('units', const ClassType<Units>()).get();
      expect(explicit.timeout, const Duration(milliseconds: 500));
      expect(explicit.buffer.toBytes(), 2048);
    });

    test('BindHandler sees every name and may ignore failures', () {
      final env = environment({'app.port': 'x', 'app.host': 'h'});
      final handler = Recording(ignoreFailures: true);
      final server = Binder(
        env,
        introspector: introspector(),
      ).bind('app', const ClassType<Server>(), handler: handler).get();
      expect(server.host, 'h');
      expect(handler.started, containsAll(['app', 'app.host', 'app.port']));
      expect(handler.failures.single, contains('app.port'));
      expect(
        () => Binder(
          env,
          introspector: introspector(),
        ).bind('app', const ClassType<Server>(), handler: Recording()),
        throwsA(isA<ConfigurationPropertiesBindException>()),
      );
    });

    test('BindResult map / ifBound / orElseGet / orElseThrow', () {
      final binder = Binder(environment({'app.port': '80'}));
      final port = binder.bind('app.port', const ClassType<int>());
      expect(port.map((p) => p + 1).get(), 81);
      final seen = <int>[];
      port.ifBound(seen.add);
      expect(seen, [80]);
      final missing = binder.bind('app.none', const ClassType<int>())
        ..ifBound(seen.add);
      expect(seen, [80]);
      expect(missing.map((p) => p + 1).isBound, isFalse);
      expect(missing.orElseGet(() => 7), 7);
      expect(
        () => missing.orElseThrow(() => StateError('required')),
        throwsStateError,
      );
    });
  });

  group('@ConfigurationProperties', () {
    BeanDefinition<Pool> poolBean({List<Object> annotations = const []}) =>
        BeanDefinition<Pool>(
          name: 'pool',
          annotations: [const ConfigurationProperties('pool'), ...annotations],
          create: (_) => Pool(),
        );

    test('on a @Bean method binds the returned object', () {
      final context = run(
        [poolBean()],
        args: ['--pool.url=jdbc:x', '--pool.size=0'],
        introspections: [poolIntrospection],
      );
      final pool = context.getBean<Pool>();
      expect(pool.url, 'jdbc:x');
      expect(pool.size, 0); // not @Validated: Min(1) not checked
    });

    test('@Validated on the @Bean method checks constraints', () {
      expect(
        () => run(
          [
            poolBean(annotations: const [Validated()]),
          ],
          args: ['--pool.url=jdbc:x', '--pool.size=0'],
          introspections: [poolIntrospection],
        ),
        bindFailure('pool.size'),
      );
    });

    test('the configurationPropertiesValidator bean checks bound objects', () {
      final validator = BeanDefinition<JdbcUrls>(
        name: ConfigurationPropertiesBinder.validatorBeanName,
        types: const [JdbcUrls, Validator],
        create: (_) => const JdbcUrls(),
      );
      expect(
        () => run(
          [poolBean(), validator],
          args: ['--pool.url=http://x'],
          introspections: [poolIntrospection],
        ),
        bindFailure('must be a JDBC url'),
      );
      final ok = run(
        [poolBean(), validator],
        args: ['--pool.url=jdbc:y'],
        introspections: [poolIntrospection],
      );
      expect(ok.getBean<Pool>().url, 'jdbc:y');
    });

    test('a properties class that is a Validator validates itself', () {
      final modes = BeanDefinition<Modes>(
        name: 'modes',
        create: (_) => Modes(),
      );
      expect(
        () => run(
          [modes],
          args: ['--modes.mode=c'],
          introspections: [modesIntrospection],
        ),
        bindFailure('must be a or b'),
      );
      expect(
        run(
          [modes],
          args: ['--modes.mode=b'],
          introspections: [modesIntrospection],
        ).getBean<Modes>().mode,
        'b',
      );
    });
  });

  group('conditions', () {
    final helloA = BeanDefinition<Hello>(
      name: 'helloA',
      types: const [Hello, Greeter],
      create: (_) => Hello(),
    );

    BeanDefinition<Marker> marker(String name, Condition condition) =>
        BeanDefinition<Marker>(
          name: name,
          conditions: [condition],
          create: (_) => Marker(),
        );

    test('@ConditionalOnProperty with prefix and several names', () {
      final context = run(
        [
          marker(
            'both',
            const ConditionalOnProperty.names(['a', 'b'], prefix: 'feat'),
          ),
          marker(
            'onlyA',
            const ConditionalOnProperty(
              'a',
              prefix: 'feat.',
              havingValue: 'on',
            ),
          ),
          marker(
            'missing',
            const ConditionalOnProperty.names(
              ['a', 'c'],
              prefix: 'feat',
              matchIfMissing: true,
            ),
          ),
        ],
        args: ['--feat.a=on', '--feat.b=false'],
      );
      expect(context.containsBean('both'), isFalse);
      expect(context.containsBean('onlyA'), isTrue);
      expect(context.containsBean('missing'), isTrue);
    });

    test('@ConditionalOnBooleanProperty', () {
      final context = run(
        [
          marker('on', const ConditionalOnBooleanProperty('x.enabled')),
          marker(
            'off',
            const ConditionalOnBooleanProperty('x.enabled', havingValue: false),
          ),
          marker(
            'missing',
            const ConditionalOnBooleanProperty('x.other', matchIfMissing: true),
          ),
        ],
        args: ['--x.enabled=TRUE'],
      );
      expect(context.containsBean('on'), isTrue);
      expect(context.containsBean('off'), isFalse);
      expect(context.containsBean('missing'), isTrue);
    });

    test('@ConditionalOnExpression, @ConditionalOnResource, '
        '@ConditionalOnBean by name', () {
      ClasspathResources.registerAll(const {
        'conditions/present.txt': EmbeddedResource.text('x'),
      });
      final context = run(
        [
          helloA,
          marker('big', const ConditionalOnExpression(r'${x.n:0} > 2')),
          marker('small', const ConditionalOnExpression(r'#{${x.n:0} < 2}')),
          marker(
            'resource',
            const ConditionalOnResource(['classpath:conditions/present.txt']),
          ),
          marker(
            'noResource',
            const ConditionalOnResource([
              'classpath:conditions/present.txt',
              'classpath:conditions/absent.txt',
            ]),
          ),
          marker('named', const ConditionalOnBean.named('helloA')),
          marker('unnamed', const ConditionalOnBean.named('nobody')),
        ],
        args: ['--x.n=5'],
      );
      expect(context.containsBean('big'), isTrue);
      expect(context.containsBean('small'), isFalse);
      expect(context.containsBean('resource'), isTrue);
      expect(context.containsBean('noResource'), isFalse);
      expect(context.containsBean('named'), isTrue);
      expect(context.containsBean('unnamed'), isFalse);
    });

    test('@ConditionalOnSingleCandidate', () {
      final single = run([
        helloA,
        marker('single', const ConditionalOnSingleCandidate(Greeter)),
      ]);
      expect(single.containsBean('single'), isTrue);
      final two = run([
        helloA,
        BeanDefinition<Hello>(
          name: 'helloB',
          types: const [Hello, Greeter],
          create: (_) => Hello(),
        ),
        marker('single', const ConditionalOnSingleCandidate(Greeter)),
      ]);
      expect(two.containsBean('single'), isFalse);
      final primary = run([
        helloA,
        BeanDefinition<Hello>(
          name: 'helloB',
          types: const [Hello, Greeter],
          primary: true,
          create: (_) => Hello(),
        ),
        marker('single', const ConditionalOnSingleCandidate(Greeter)),
      ]);
      expect(primary.containsBean('single'), isTrue);
    });

    test('the condition evaluation report, logged for --debug', () {
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.info;
      final logged = <String>[];
      final stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring_boot_dart.ConditionEvaluationReport') {
          logged.add(record.message);
        }
      });
      addTearDown(() {
        stop();
        SpringLog.level = saved;
      });
      final quiet = run([
        marker('flag', const ConditionalOnProperty('x.flag')),
      ]);
      expect(logged, isEmpty);
      final report = ConditionEvaluationReport.of(quiet);
      expect(report.negativeMatches.keys, ['flag']);
      expect(report.positiveMatches, isEmpty);

      run(
        [
          marker('flag', const ConditionalOnProperty('x.flag')),
          marker('other', const ConditionalOnProperty('x.other')),
        ],
        args: ['--debug', '--x.other=on'],
      );
      expect(logged.single, contains('CONDITIONS EVALUATION REPORT'));
      expect(logged.single, contains('Positive matches:'));
      expect(logged.single, contains('   other matched:'));
      expect(
        logged.single,
        contains('@ConditionalOnProperty (x.flag) did not match'),
      );
    });
  });

  test('EnvironmentPostProcessors run around config data by order', () {
    final dir = Directory.systemTemp.createTempSync('boot_epp_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/extra.properties')
      ..writeAsStringSync('from.file=imported');
    File('${dir.path}/extra-extra.properties').writeAsStringSync('p=extra');
    final log = <String>[];
    final context = run(
      const [],
      environmentPostProcessors: [After(log), Ordered1(file.path, log)],
    );
    expect(log, ['before: null', 'after: imported']);
    expect(context.environment.activeProfiles, ['extra']);
    expect(context.environment.getProperty('p'), 'extra');
  });

  group('messages', () {
    setUpAll(
      () => ClasspathResources.registerAll(const {
        'parity/a.properties': EmbeddedResource.text('a=A'),
        'parity/b.properties': EmbeddedResource.text('b=B'),
      }),
    );

    test('spring.messages.basename as a YAML list', () {
      final context = run(
        const [],
        args: [
          '--spring.messages.basename[0]=parity/a',
          '--spring.messages.basename[1]=parity/b',
        ],
        autoConfigurations: [springBootAutoConfiguration],
      );
      expect(context.getMessage('a'), 'A');
      expect(context.getMessage('b'), 'B');
    });

    test('cache-duration 500ms and a case-insensitive '
        'use-code-as-default-message', () {
      final context = run(
        const [],
        args: [
          '--spring.messages.basename=parity/a',
          '--spring.messages.cache-duration=500ms',
          '--spring.messages.use-code-as-default-message=TRUE',
        ],
        autoConfigurations: [springBootAutoConfiguration],
      );
      final source =
          context.getBean<MessageSource>()
              as ReloadableResourceBundleMessageSource;
      expect(source.cacheMillis, 500);
      expect(source.useCodeAsDefaultMessage, isTrue);
      expect(context.getMessage('unknown.code'), 'unknown.code');
    });
  });

  test('JsonMapperBuilderCustomizer beans change the auto-configured '
      'mapper after the properties', () {
    final context = run(
      [
        BeanDefinition<JsonMapperBuilderCustomizer>(
          name: 'snake',
          types: const [JsonMapperBuilderCustomizer],
          create: (_) => JsonMapperBuilderCustomizer.of(
            (builder) => builder.configure(
              SerializationFeature.indentOutput,
              !builder.isEnabled(SerializationFeature.indentOutput),
            ),
          ),
        ),
      ],
      args: ['--spring.jackson.serialization.indent-output=true'],
      autoConfigurations: [springBootAutoConfiguration],
    );
    expect(context.getBean<ObjectMapper>().indentOutput, isFalse);
  });

  test('ApplicationArguments: a lone -- ends the options', () {
    final arguments = ApplicationArguments([
      '--a=1',
      'plain',
      '--',
      '--b=2',
      'x',
    ]);
    expect(arguments.optionNames, {'a'});
    expect(arguments.getOptionValues('a'), ['1']);
    expect(arguments.containsOption('b'), isFalse);
    expect(arguments.nonOptionArgs, ['plain', '--b=2', 'x']);
    expect(() => ApplicationArguments(['--=x']), throwsArgumentError);
  });

  group('failure analysis', () {
    test('BeanDefinitionOverrideException', () {
      final analysis = analyzeFailure(
        BeanDefinitionOverrideException('dataSource', 'app'),
      )!;
      expect(analysis.description, contains("The bean 'dataSource'"));
      expect(
        analysis.action,
        contains('spring.main.allow-bean-definition-overriding=true'),
      );
    });

    test('missing config data and invalid property names', () {
      final lines = <String>[];
      expect(
        () => SpringApplication(
          const [],
          bannerMode: BannerMode.off,
          out: lines.add,
        ).run(['--spring.config.import=file:/no/such/app.properties']),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
      expect(lines.single, contains('APPLICATION FAILED TO START'));
      expect(lines.single, contains("prefix it with 'optional:'"));
      final invalid = analyzeFailure(
        InvalidConfigurationPropertyNameException('app.myName', ['N']),
      )!;
      expect(invalid.description, contains("'app.myName' is not valid"));
      expect(invalid.action, contains('canonical names'));
    });
  });

  group('banner', () {
    test('printed from spring.banner.location, logged in log mode', () {
      ClasspathResources.registerAll(const {
        'parity/banner.txt': EmbeddedResource.text(
          r'Shop ${app.edition} on ${spring-boot.version}',
        ),
      });
      final saved = SpringLog.level;
      SpringLog.level = SpringLogLevel.info;
      final logged = <String>[];
      final stop = SpringLog.listen((record) => logged.add(record.message));
      addTearDown(() {
        stop();
        SpringLog.level = saved;
      });
      final context =
          SpringApplication(
            const [],
            bannerMode: BannerMode.log,
            out: (_) {},
          ).run([
            '--spring.banner.location=classpath:parity/banner.txt',
            '--app.edition=eu',
          ]);
      addTearDown(context.close);
      expect(logged, contains('Shop eu on $springBootVersion'));
    });

    test('spring.main.banner-mode=off prints nothing; invalid modes fail', () {
      final printed = <String>[];
      final banner = _RecordingBanner(printed);
      SpringApplication(
        const [],
        banner: banner,
        out: (_) {},
      ).run(['--spring.main.banner-mode=off']).close();
      expect(printed, isEmpty);
      SpringApplication(
        const [],
        banner: banner,
        bannerMode: BannerMode.log,
        out: (_) {},
      ).run(const []).close();
      expect(printed, ['custom']);
      expect(
        () => SpringApplication(
          const [],
          out: (_) {},
        ).run(['--spring.main.banner-mode=loud']),
        throwsA(isA<ConfigurationPropertiesBindException>()),
      );
    });

    test('the default banner names the version', () {
      final out = <String>[];
      const SpringBootBanner().printBanner(StandardEnvironment(), out.add);
      expect(out.single, contains(':: Spring Boot for Dart ::'));
      expect(out.single, contains('(v$springBootVersion)'));
    });
  });
}

final class _RecordingBanner implements Banner {
  _RecordingBanner(this.printed);

  final List<String> printed;

  @override
  void printBanner(Environment environment, void Function(String text) out) =>
      printed.add('custom');
}
