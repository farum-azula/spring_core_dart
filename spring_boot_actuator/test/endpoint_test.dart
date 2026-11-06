// The endpoint model: ids, enablement and exposure from Spring Boot's
// properties, the conditions of the indicators and contributors, the
// discovery of @Endpoint beans (as the generator describes them) and the
// mappings endpoint's JSON.
import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:test/test.dart';

/// An endpoint of the tests, as `@Endpoint(id: 'features')`.
class Features {
  final flags = {'beta': true};

  Map<String, bool> all() => flags;

  bool? one(String name) => flags[name];

  String echo(String text, {int times = 1}) => text * times;

  Object? who(SecurityContext user, ApiVersion version) => {
    'name': user.principal?.name,
    'version': version.name,
  };
}

/// Its web extension.
class FeaturesWeb {
  WebEndpointResponse<Map<String, bool>> all() =>
      const WebEndpointResponse(body: {'web': true}, status: 202);
}

BeanDefinition<Features> features({String id = 'features'}) =>
    BeanDefinition<Features>(
      name: 'featuresEndpoint',
      annotations: [Endpoint(id: id)],
      create: (_) => Features(),
      annotatedMethods: [
        BeanMethod<Features>(
          'all',
          invoke: (bean, _) => bean.all(),
          annotations: const [ReadOperation()],
        ),
        BeanMethod<Features>(
          'one',
          invoke: (bean, arguments) => bean.one(arguments.single! as String),
          parameters: const [
            BeanParameter(
              'name',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [Selector()],
            ),
          ],
          annotations: const [ReadOperation()],
        ),
        // Not an operation.
        BeanMethod<Features>('other', invoke: (bean, _) => null),
      ],
    );

BeanDefinition<Object> echoEndpoint() => BeanDefinition<Features>(
  name: 'echoEndpoint',
  annotations: const [Endpoint(id: 'echo', enableByDefault: false)],
  create: (_) => Features(),
  annotatedMethods: [
    BeanMethod<Features>(
      'echo',
      invoke: (bean, arguments) => bean.echo(arguments.single! as String),
      invokeNamed: (bean, positional, named) => bean.echo(
        positional.single! as String,
        times: named.argumentOr(#times, 1),
      ),
      parameters: const [
        BeanParameter('text', type: ClassType<String>(), isRequired: true),
        BeanParameter(
          'times',
          type: ClassType<int>(),
          symbol: #times,
          hasDefaultValue: true,
          defaultValue: 1,
        ),
      ],
      annotations: const [ReadOperation()],
    ),
    BeanMethod<Features>(
      'who',
      invoke: (bean, arguments) => bean.who(
        arguments[0]! as SecurityContext,
        arguments[1]! as ApiVersion,
      ),
      parameters: const [
        BeanParameter(
          'user',
          type: ClassType<SecurityContext>(),
          isRequired: true,
        ),
        BeanParameter(
          'version',
          type: EnumType<ApiVersion>(ApiVersion.values),
          isRequired: true,
        ),
        BeanParameter(
          'path',
          type: ListType<String>(ClassType<String>()),
          isRequired: true,
          annotations: [Selector(match: SelectorMatch.allRemaining)],
        ),
      ],
      annotations: const [ReadOperation()],
    ),
  ],
);

BeanDefinition<FeaturesWeb> featuresWeb() => BeanDefinition<FeaturesWeb>(
  name: 'featuresWebExtension',
  annotations: const [EndpointWebExtension(endpoint: Features)],
  create: (_) => FeaturesWeb(),
  annotatedMethods: [
    BeanMethod<FeaturesWeb>(
      'all',
      invoke: (bean, _) => bean.all(),
      annotations: const [ReadOperation()],
    ),
  ],
);

final class User implements Principal {
  @override
  String get name => 'ada';
}

Future<AnnotationConfigApplicationContext> contextOf(
  List<BeanDefinition<Object>> beans,
) async {
  final context = AnnotationConfigApplicationContext([
    BeanModule('test', beans),
  ]);
  await context.refreshAsync();
  addTearDown(context.close);
  return context;
}

/// A condition context over some properties.
final class Conditions implements ConditionContext {
  Conditions(Map<String, Object?> properties)
    : environment = StandardEnvironment()
        ..propertySources.addFirst(MapPropertySource('test', properties));

  @override
  final ConfigurableEnvironment environment;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PropertyResolver env(Map<String, Object?> properties) =>
    Conditions(properties).environment;

void main() {
  group('EndpointId', () {
    test('compared without case, dots and dashes', () {
      expect(EndpointId.of('health'), EndpointId.of('Health'));
      expect(EndpointId.of('my-endpoint'), EndpointId.of('myendpoint'));
      expect(EndpointId.of('my.endpoint').toLowerCaseString(), 'myendpoint');
      expect(EndpointId.of('Health').toString(), 'Health');
    });

    test('letters and digits, starting with a letter', () {
      expect(() => EndpointId.of('1st'), throwsArgumentError);
      expect(() => EndpointId.of('a b'), throwsArgumentError);
      expect(() => EndpointId.of(''), throwsArgumentError);
      expect(() => EndpointId.of('a/b'), throwsArgumentError);
    });
  });

  group('isEndpointEnabled', () {
    final health = EndpointId.of('health');

    test("the endpoint's own default", () {
      expect(isEndpointEnabled(env({}), health), isTrue);
      expect(
        isEndpointEnabled(env({}), health, enableByDefault: false),
        isFalse,
      );
    });

    test('management.endpoint.<id>.enabled', () {
      expect(
        isEndpointEnabled(
          env({'management.endpoint.health.enabled': 'false'}),
          health,
        ),
        isFalse,
      );
      expect(
        isEndpointEnabled(
          env({'management.endpoint.health.enabled': 'true'}),
          health,
          enableByDefault: false,
        ),
        isTrue,
      );
    });

    test('management.endpoints.enabled-by-default, below the own key', () {
      expect(
        isEndpointEnabled(
          env({'management.endpoints.enabled-by-default': 'false'}),
          health,
        ),
        isFalse,
      );
      expect(
        isEndpointEnabled(
          env({
            'management.endpoints.enabled-by-default': 'false',
            'management.endpoint.health.enabled': 'true',
          }),
          health,
        ),
        isTrue,
      );
    });

    test('access (Spring Boot 3.4) wins over enabled', () {
      expect(
        isEndpointEnabled(
          env({
            'management.endpoint.health.access': 'none',
            'management.endpoint.health.enabled': 'true',
          }),
          health,
        ),
        isFalse,
      );
      expect(
        isEndpointEnabled(
          env({'management.endpoint.health.access': 'read-only'}),
          health,
          enableByDefault: false,
        ),
        isTrue,
      );
      expect(
        isEndpointEnabled(
          env({'management.endpoints.access.default': 'none'}),
          health,
        ),
        isFalse,
      );
      expect(
        isEndpointEnabled(
          env({
            'management.endpoints.access.default': 'none',
            'management.endpoint.health.access': 'unrestricted',
          }),
          health,
        ),
        isTrue,
      );
      expect(
        () => isEndpointEnabled(
          env({'management.endpoint.health.access': 'sometimes'}),
          health,
        ),
        throwsArgumentError,
      );
    });
  });

  group('IncludeExcludeEndpointFilter', () {
    bool exposed(String id, {List<String>? include, List<String>? exclude}) =>
        IncludeExcludeEndpointFilter(
          include: include ?? const [],
          exclude: exclude ?? const [],
        ).match(EndpointId.of(id));

    test('health alone by default, as Spring Boot over HTTP', () {
      expect(exposed('health'), isTrue);
      expect(exposed('info'), isFalse);
    });

    test('include, * and exclude (which wins)', () {
      expect(exposed('info', include: ['health', 'info']), isTrue);
      expect(exposed('health', include: ['info']), isFalse);
      expect(exposed('mappings', include: ['*']), isTrue);
      expect(exposed('env', include: ['*'], exclude: ['env']), isFalse);
      expect(exposed('health', include: ['*'], exclude: ['*']), isFalse);
      expect(exposed('Health', include: [' health ']), isTrue);
    });
  });

  group('conditions', () {
    test('a health indicator: its own key, then the defaults', () {
      const ping = ConditionalOnEnabledHealthIndicator('ping');
      expect(ping.matches(Conditions({})), isTrue);
      expect(
        ping.matches(Conditions({'management.health.ping.enabled': 'false'})),
        isFalse,
      );
      expect(
        ping.matches(
          Conditions({'management.health.defaults.enabled': 'false'}),
        ),
        isFalse,
      );
      expect(
        ping.matches(
          Conditions({
            'management.health.defaults.enabled': 'false',
            'management.health.ping.enabled': 'true',
          }),
        ),
        isTrue,
      );
    });

    test('an info contributor: on or off by default', () {
      const build = ConditionalOnEnabledInfoContributor('build');
      const env = ConditionalOnEnabledInfoContributor(
        'env',
        enabledByDefault: false,
      );
      expect(build.matches(Conditions({})), isTrue);
      expect(
        build.matches(
          Conditions({'management.info.defaults.enabled': 'false'}),
        ),
        isFalse,
      );
      expect(env.matches(Conditions({})), isFalse);
      expect(
        env.matches(Conditions({'management.info.defaults.enabled': 'true'})),
        isFalse,
      );
      expect(
        env.matches(Conditions({'management.info.env.enabled': 'true'})),
        isTrue,
      );
    });
  });

  group('EndpointDiscoverer', () {
    test('finds the endpoints and their read operations', () async {
      final context = await contextOf([features()]);
      final endpoints = EndpointDiscoverer(context.beanFactory).getEndpoints();
      final endpoint = endpoints.single;
      expect(endpoint.id, EndpointId.of('features'));
      expect(endpoint.beanName, 'featuresEndpoint');
      expect(endpoint.enableByDefault, isTrue);
      expect([for (final op in endpoint.operations) op.name], ['all', 'one']);
      expect(endpoint.operations.last.selectors.single.name, 'name');
      expect(endpoint.operations.first.className, 'Features');
      expect(
        await endpoint.operations.first.invoke(InvocationContext()),
        {'beta': true},
      );
      expect(
        await endpoint.operations.last.invoke(
          InvocationContext(arguments: {'name': 'beta'}),
        ),
        isTrue,
      );
    });

    test('a missing mandatory argument; a default kept; conversion', () async {
      final context = await contextOf([echoEndpoint()]);
      final endpoint = EndpointDiscoverer(context.beanFactory)
          .getEndpoints()
          .single;
      expect(endpoint.enableByDefault, isFalse);
      final echo = endpoint.operations.first;
      expect(
        () => echo.invoke(InvocationContext()),
        throwsA(
          isA<MissingParametersException>().having(
            (e) => e.parameters,
            'parameters',
            ['text'],
          ),
        ),
      );
      expect(
        await echo.invoke(InvocationContext(arguments: {'text': 'ab'})),
        'ab',
      );
      expect(
        await echo.invoke(
          InvocationContext(arguments: {'text': 'ab', 'times': '3'}),
        ),
        'ababab',
      );
      expect(
        () => echo.invoke(
          InvocationContext(arguments: {'text': 'ab', 'times': 'many'}),
        ),
        throwsA(isA<InvalidEndpointRequestException>()),
      );
    });

    test('the user and the API version come from the context', () async {
      final context = await contextOf([echoEndpoint()]);
      final who = EndpointDiscoverer(context.beanFactory)
          .getEndpoints()
          .single
          .operations
          .last;
      expect(who.parameters.where((p) => p.isImplicit), hasLength(2));
      expect(
        await who.invoke(
          InvocationContext(
            securityContext: SecurityContext.of(User()),
            apiVersion: ApiVersion.v2,
            arguments: {
              'path': ['a'],
            },
          ),
        ),
        {'name': 'ada', 'version': 'v2'},
      );
    });

    test('a web extension replaces the operations of its shape', () async {
      final context = await contextOf([features(), featuresWeb()]);
      final endpoint = EndpointDiscoverer(context.beanFactory)
          .getEndpoints()
          .single;
      expect([for (final op in endpoint.operations) op.name], ['one', 'all']);
      final all = await endpoint.operations.last.invoke(InvocationContext());
      expect(all, isA<WebEndpointResponse<Object?>>());
      expect((all! as WebEndpointResponse<Object?>).status, 202);
    });

    test('two endpoints with one id stop the start', () async {
      final context = await contextOf([
        features(),
        BeanDefinition<Features>(
          name: 'other',
          annotations: const [Endpoint(id: 'Features')],
          create: (_) => Features(),
        ),
      ]);
      expect(
        () => EndpointDiscoverer(context.beanFactory).getEndpoints(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("Found two endpoints with the id 'Features'"),
          ),
        ),
      );
    });

    test('an invalid id and an extension of no endpoint', () async {
      final context = await contextOf([
        features(id: '9lives'),
        featuresWeb(),
      ]);
      expect(
        () => EndpointDiscoverer(context.beanFactory).getEndpoints(),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('9lives'))
              .having(
                (e) => e.message,
                'message',
                contains('which is not an endpoint bean'),
              ),
        ),
      );
    });
  });

  group('MappingsEndpoint', () {
    test("Spring Boot's shape, one key per MappingDescriptions", () {
      final endpoint = MappingsEndpoint([_Screens()], contextId: 'shop');
      expect(endpoint.mappings().toJson(), {
        'contexts': {
          'shop': {
            'mappings': {
              'screens': [
                {'path': '/books/{isbn}'},
              ],
            },
            'parentId': null,
          },
        },
      });
      expect(MappingsEndpoint(const []).mappings().toJson(), {
        'contexts': {
          'application': {'mappings': <String, Object?>{}, 'parentId': null},
        },
      });
    });
  });
}

final class _Screens implements MappingDescriptions {
  @override
  String get mappingsName => 'screens';

  @override
  Object? describeMappings() => [
    {'path': '/books/{isbn}'},
  ];
}
