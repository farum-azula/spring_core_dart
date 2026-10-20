import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/spring_core_dart_example.dart';
import 'package:test/test.dart';

ConfigurableApplicationContext start({
  Map<String, Object?> properties = const {'feature.audit': 'true'},
  List<String> profiles = const [],
}) {
  final environment = StandardEnvironment(systemEnvironment: {})
    ..propertySources.addFirst(MapPropertySource('test', properties));
  if (profiles.isNotEmpty) {
    environment.setActiveProfiles(profiles);
  }
  return ApplicationContext.run([exampleBeans], environment: environment);
}

void main() {
  late ConfigurableApplicationContext context;

  setUp(() {
    creationLog.clear();
    context = start();
  });

  tearDown(() => context.close());

  test('eager singletons at refresh, lazy ones on first use', () {
    expect(
      creationLog,
      containsAll(['englishGreeter', 'appSettings', 'greetingService']),
    );
    expect(creationLog, isNot(contains('report')));
    final report = context.getBean<Report>();
    expect(report.userCount, 3);
    expect(context.getBean<Report>(), same(report));
  });

  test('primary, qualifiers, @Named, @Order collections', () {
    expect(context.getBean<Greeter>(), isA<EnglishGreeter>());
    expect(context.getBean<Greeter>(qualifier: 'fr'), isA<FrenchGreeter>());
    expect(context.getBean<Greeter>(qualifier: 'pirate'), isA<PirateGreeter>());
    expect(context.beanFactory.getBeanDefinition('pirate').description, 'Arr');
    final service = context.getBean<GreetingService>();
    expect(service.all, [
      isA<FrenchGreeter>(),
      isA<EnglishGreeter>(),
      isA<PirateGreeter>(),
    ]);
    expect(service.byName.keys, ['french', 'englishGreeter', 'pirate']);
    expect(service.unique, hasLength(3));
    expect(service.pirate, isA<EnglishGreeter>(), reason: '@Primary first');
  });

  test('constructor, field, setter, method and value injection', () {
    final service = context.getBean<GreetingService>();
    expect(service.greeter, isA<EnglishGreeter>());
    expect(service.french, isA<FrenchGreeter>());
    expect(service.frenchByName, same(service.french));
    expect(service.missing, isNull);
    expect(service.ticket, isNot(same(service.secondTicket)));
    expect(service.initializedWith, same(context.beanFactory));
    expect(service.title, 'NEON Harness');
    expect(service.tags, ['fast', 'local']);
    expect(service.optionalValue, isNull);
    expect(service.maxGreetings, 2);
    expect(service.greetAll(), 'Hello, Ada; Hello, Linus');
    expect(creationLog, contains('greetingService:postConstruct'));
  });

  test('ObjectProvider defers creation', () {
    final service = context.getBean<GreetingService>();
    expect(creationLog, isNot(contains('report')));
    expect(service.reports.getObject().userCount, 3);
    expect(creationLog, contains('report'));
  });

  test('generic types are matched by full type', () {
    expect(context.getBean<Store<User>>(), isA<UserStore>());
    expect(context.findBean<Store<String>>(), isNull);
  });

  test('configuration: @Bean methods, aliases, init and inferred destroy', () {
    expect(context.getBean<AppSettings>().title, 'NEON Harness');
    final banner = context.getBean<Banner>(qualifier: 'banner');
    expect(banner.text, 'Hello, NEON Harness');
    expect(context.getBean<Banner>(), isNot(same(banner)));
    expect(context.getBean<IdGenerator>().next(), 1);
    expect(context.getBean<IdGenerator>().next(), 2);
    final connection = context.getBean<Connection>();
    expect(connection.open, isTrue);
    expect(
      creationLog.indexOf('connection:connect'),
      lessThan(creationLog.indexOf('migrations')),
      reason: '@DependsOn',
    );
    expect(context.getBean<LegacyService>().name, 'legacy', reason: '@Import');
    context.close();
    expect(connection.open, isFalse);
    expect(creationLog, contains('greetingService:preDestroy'));
  });

  test('FactoryBean products', () {
    expect(context.getBean<Pool>().size, 4);
    expect(context.getBean<Pool>(), same(context.getBean<Pool>()));
    expect(context.getBeanByName('&pool'), isA<PoolFactory>());
    expect(creationLog.where((e) => e == 'pool:getObject'), hasLength(1));
  });

  test(
    'events: payloads, returned events, conditions, interfaces, classes',
    () {
      expect(creationLog, contains('shipping:context'), reason: 'refreshed');
      creationLog.clear();
      context.getBean<OrderService>()
        ..place(1, 10)
        ..place(2, 500);
      expect(creationLog, [
        'shipping:1',
        'audit:1',
        'big:2',
        'shipping:2',
        'audit:2',
      ]);
    },
  );

  test('conditions and profiles', () {
    expect(context.containsBean('auditFeature'), isTrue);
    expect(context.containsBean('neverRegistered'), isFalse);
    expect(context.getBean<Clock>().now(), 'system', reason: '@Fallback');
    final testContext = start(properties: {}, profiles: ['test']);
    expect(testContext.containsBean('auditFeature'), isFalse);
    expect(testContext.getBean<Clock>().now(), 'fixed');
    testContext.close();
  });

  test('@Configurable objects are injected with autowireBean', () {
    final state = ScreenState();
    context.autowireCapableBeanFactory.autowireBean(state);
    expect(state.greeter, isA<EnglishGreeter>());
    expect(state.title, 'NEON Harness');
  });

  test('SpEL reads @Introspected beans in @Value', () {
    expect(context.getBean<Headline>().text, 'NEON HARNESS');
  });

  group('data binding and validation', () {
    late BeanValidator validator;
    setUp(
      () => validator = BeanValidator(
        introspector: context.getBean<BeanIntrospector>(),
      ),
    );

    DataBinder binder(SignupForm form) => DataBinder(
      form,
      objectName: 'signup',
      introspector: context.getBean<BeanIntrospector>(),
    )..validators.add(validator);

    test('binds, converts and validates', () {
      final form = SignupForm();
      final dataBinder = binder(form)
        ..bind({
          'name': 'Ada',
          'email': 'ada@example.com',
          'age': '36',
          'password': 'x',
          'confirmPassword': 'x',
          'address.city': 'London',
          'address.zip': '12345',
        })
        ..validate();
      expect(dataBinder.bindingResult.hasErrors, isFalse);
      expect(form.age, 36);
      expect(form.address.city, 'London');
      expect(dataBinder.close()['signup'], same(form));
    });

    test('reports type mismatches, constraints, nested and class errors', () {
      final form = SignupForm()..previous = [Address()];
      final dataBinder = binder(form)
        ..bind({
          'name': '   ',
          'email': 'not-an-email',
          'age': 'old',
          'password': 'a',
          'confirmPassword': 'b',
          'address.zip': '12',
        })
        ..validate();
      final result = dataBinder.bindingResult;
      expect(result.fieldError('age')!.codes.first, 'typeMismatch.signup.age');
      expect(result.fieldError('age')!.code, 'typeMismatch');
      expect(result.getFieldValue('age'), 'old', reason: 'rejected input kept');
      expect(result.fieldError('name')!.codes, [
        'NotBlank.signup.name',
        'NotBlank.name',
        'NotBlank.String',
        'NotBlank',
      ]);
      expect(
        result.fieldError('email')!.defaultMessage,
        'must be a well-formed email address',
      );
      expect(
        result.fieldError('address.city')!.defaultMessage,
        'must not be blank',
      );
      expect(
        result.fieldError('address.zip')!.defaultMessage,
        'must be 5 digits',
      );
      expect(result.fieldError('previous[0].city'), isNotNull);
      expect(result.globalError!.codes.first, 'PasswordsMatch.signup');
      expect(() => dataBinder.close(), throwsA(isA<BindException>()));

      final messages = StaticMessageSource()
        ..addMessage('NotBlank', '', '{0} is required')
        ..addMessage('signup.name', '', 'Your name');
      expect(
        messages.getMessageFromResolvable(result.fieldError('name')!),
        'Your name is required',
      );
    });

    test('groups and the Jakarta-style API', () {
      final form = SignupForm()
        ..name = 'Ada'
        ..email = 'a@b.c'
        ..age = 20
        ..address.city = 'Oslo';
      expect(validator.validateObject(form), isEmpty);
      expect(
        validator.validateObject(form, groups: [OnUpdate]).single.propertyPath,
        'id',
      );
      expect(
        validator.validateValue(SignupForm, 'age', 3).single.message,
        'must be greater than or equal to 18',
      );
      expect(validator.validateProperty(form, 'name'), isEmpty);
    });

    test('introspection metadata', () {
      final introspection = context.getBean<BeanIntrospector>().forType(
        SignupForm,
      )!;
      expect(introspection.getProperty('email')!.nullable, isTrue);
      expect(introspection.getProperty('age')!.type, int);
      expect(
        introspection.getMethod('greet')!.invoke(SignupForm()..name = 'Ada', [
          'Hi',
        ]),
        'Hi Ada',
      );
      expect(introspection.instantiate(), isA<SignupForm>());
      expect(introspection.annotations.single, isA<PasswordsMatch>());
    });
  });

  group('AOP', () {
    setUp(adviceLog.clear);

    test('aspects advise proxied beans in order', () {
      final calculator = context.getBean<Calculator>();
      expect(calculator, isA<Advised>());
      expect(AopUtils.getTarget(calculator), isA<SimpleCalculator>());
      expect(calculator.add(1, 2), 3);
      expect(adviceLog, [
        'audit:before add[1, 2]',
        'audit:returned add=3',
        'audit:after',
      ]);
    });

    test('around advice can change arguments', () {
      final calculator = context.getBean<Calculator>();
      expect(calculator.multiply(3, 4), 30);
      expect(adviceLog, [
        'audit:before multiply[3, 4]',
        'timing:start execution(Calculator.multiply(..))',
        'timing:end',
        'audit:returned multiply=30',
        'audit:after',
      ]);
    });

    test('after throwing filters by error type; errors propagate', () {
      final calculator = context.getBean<Calculator>();
      expect(() => calculator.divide(1, 0), throwsA(isA<UnsupportedError>()));
      // Like Spring, the order of two advices of the same kind in one aspect
      // is not defined.
      expect(adviceLog.first, 'audit:before divide[1, 0]');
      expect(
        adviceLog.sublist(1, 3),
        unorderedEquals([
          'audit:unsupported',
          'audit:failed IntegerDivisionByZeroException',
        ]),
      );
      expect(adviceLog.last, 'audit:after');
    });

    test('async methods are advised when the future completes', () async {
      final calculator = context.getBean<Calculator>();
      final future = calculator.slowAdd(2, 3);
      expect(adviceLog, ['audit:before slowAdd[2, 3]']);
      expect(await future, 5);
      expect(adviceLog, [
        'audit:before slowAdd[2, 3]',
        'audit:async=5',
        'audit:after',
      ]);
    });

    test('advisor beans and bean() pointcuts', () {
      expect(context.getBean<Shouter>().shout('hey'), 'HEY');
      expect(
        context.getBean<Greeter>().greet('Ada'),
        'Hello, Ada',
        reason: 'not advised',
      );
      expect(context.getBean<Greeter>(), isNot(isA<Advised>()));
    });
  });
}
