/// A runnable tour of every spring_core_dart feature: each section starts
/// a context (or uses the shared one), exercises one area and prints what
/// actually happened.
library;

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/external/legacy_config.dart';
import 'package:spring_core_dart_example/src/aop/aspects.dart';
import 'package:spring_core_dart_example/src/app.dart';
import 'package:spring_core_dart_example/src/catalog/catalog.dart';
import 'package:spring_core_dart_example/src/config/shop_config.dart';
import 'package:spring_core_dart_example/src/events/orders.dart';
import 'package:spring_core_dart_example/src/extension/extension_points.dart';
import 'package:spring_core_dart_example/src/payments/payments.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';
import 'package:spring_core_dart_example/src/ui/screen.dart';
import 'package:spring_core_dart_example/src/validation/forms.dart';

export 'package:spring_core_dart_example/src/app.dart';

/// Starts the shop: command-line arguments, `config/application*.properties`
/// (Spring Boot config data), the custom `basket` scope, then refresh.
///
/// [systemEnvironment] replaces the process environment (tests); by default
/// the real OS environment variables are used.
ConfigurableApplicationContext startShop(
  List<String> args, {
  Map<String, String>? systemEnvironment,
}) {
  final environment = StandardEnvironment(systemEnvironment: systemEnvironment)
    ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
  ConfigDataEnvironment(environment).processAndApplySync();
  final context = AnnotationConfigApplicationContext([
    shopBeans,
  ], environment: environment);
  context.beanFactory.registerScope('basket', SimpleMapScope());
  context.refresh();
  return context;
}

/// Names of the tour sections, in order.
const tourSections = [
  'config',
  'beans',
  'lifecycle',
  'extensions',
  'events',
  'messages',
  'spel',
  'validation',
  'aop',
  'hierarchy',
  'failures',
  'shutdown',
];

/// Runs the tour ([section] = one section only) and writes to [out].
Future<void> runTour(
  List<String> args, {
  String? section,
  void Function(String line) out = print,
  Map<String, String>? systemEnvironment,
}) async {
  tourLog.clear();
  final context = startShop(args, systemEnvironment: systemEnvironment);
  // What the beans recorded while the context started (lifecycle order).
  final startup = [...tourLog];
  tourLog.clear();
  final tour = _Tour(context, out, startup);
  for (final name in tourSections) {
    if (section == null || section == name) {
      out('');
      out('=== $name ===');
      await tour.run(name);
      for (final line in tourLog) {
        out('  · $line');
      }
      tourLog.clear();
    }
  }
  if (context.isActive) {
    context.close();
  }
}

class _Tour {
  _Tour(this.context, this.out, this.startup);

  final ConfigurableApplicationContext context;
  final void Function(String line) out;
  final List<String> startup;

  void show(String label, Object? value) => out('  $label: $value');

  Future<void> run(String name) async => switch (name) {
    'config' => config(),
    'beans' => beans(),
    'lifecycle' => lifecycle(),
    'extensions' => extensions(),
    'events' => events(),
    'messages' => messages(),
    'spel' => spel(),
    'validation' => validation(),
    'aop' => await aop(),
    'hierarchy' => hierarchy(),
    'failures' => failures(),
    'shutdown' => shutdown(),
    _ => throw ArgumentError('unknown section $name'),
  };

  // Environment, config files, profiles and conditions.
  void config() {
    final env = context.environment;
    show('active profiles', env.activeProfiles);
    show('app.name', env.getProperty('app.name'));
    show(
      'payment.mode (application-dev.properties)',
      env.getProperty('payment.mode'),
    );
    show(
      'support.email (spring.config.import)',
      env.getProperty('support.email'),
    );
    show('log.level (on-profile=!prod document)', env.getProperty('log.level'));
    show(
      'legacy.greeting (@PropertySource via @Import)',
      env.getProperty('legacy.greeting'),
    );
    show(
      'prod.secret (@PropertySource of a prod-only class)',
      env.getProperty('prod.secret'),
    );
    show(
      'placeholder with default',
      env.resolvePlaceholders(r'${missing.key:fallback}'),
    );
    show(r'db.user (${DB_USER:books})', env.getProperty('db.user'));
    show(
      r'db.password (${DB_PASSWORD:changeme})',
      env.getProperty('db.password'),
    );
    show(
      'db.connection (placeholders inside the file)',
      env.getProperty('db.connection'),
    );
    show(
      'shop.motto (env SHOP_MOTTO, relaxed name)',
      env.getProperty('shop.motto'),
    );
    show('typed property', env.getPropertyAs<int>('catalog.page-size'));
    show(
      'gateway (@Profile dev)',
      context.getBean<Checkout>().gateway.charge(9.99),
    );
    show(
      'backup (@Qualifier)',
      context.getBean<Checkout>().backup.charge(9.99),
    );
    show(
      'DebugToolbar (dev-tools & !prod)',
      context.containsBean('debugToolbar'),
    );
    show(
      'Recommendations (condition on property)',
      context.containsBean('recommendations'),
    );
    show(
      'WeekendSale (@Conditional never)',
      context.containsBean('weekendSale'),
    );

    final prod = startShop([
      '--spring.profiles.active=prod',
    ], systemEnvironment: const {});
    out('  -- same beans, --spring.profiles.active=prod --');
    show('active profiles', prod.environment.activeProfiles);
    show('payment.mode', prod.environment.getProperty('payment.mode'));
    show('log.level (!prod guard)', prod.environment.getProperty('log.level'));
    show('prod.secret', prod.environment.getProperty('prod.secret'));
    show(
      'gateway (@Profile prod)',
      prod.getBean<Checkout>().gateway.charge(9.99),
    );
    show('DebugToolbar', prod.containsBean('debugToolbar'));
    prod.close();
    tourLog.clear(); // the second context's own lifecycle noise
  }

  // Declaring beans and injection.
  void beans() {
    final catalog = context.getBean<CatalogService>();
    show('first page (@Value page-size=2)', catalog.firstPage());
    show('currency (@Value)', catalog.currency);
    show('retries (Dart default kept)', catalog.retries);
    show('discount (@Primary composite of the others)', catalog.discount.name);
    show('price of Leaves of Grass', catalog.priceOf(catalog.books.find('3')!));
    show('plugins (no beans: empty list)', catalog.plugins);
    show('deliveryTime (Duration from "2d")', catalog.deliveryTime);
    show('tags (List from "a,b,c")', catalog.tags);
    show('banner (SpEL + placeholder)', catalog.banner);
    show(
      'motto (optional @Value: null unless SHOP_MOTTO is set)',
      catalog.motto,
    );
    show('clock (setter injection)', catalog.clock.runtimeType);
    show('wire (method injection)', catalog.wiredWith);
    show('Map<String, Discount>', context.getBeansOfType<Discount>().keys);
    show('prototype ids', [
      context.getBean<IdGenerator>().id,
      context.getBean<IdGenerator>().id,
    ]);
    show(
      'alias "idGenerator"',
      context.getBeanByName('idGenerator').runtimeType,
    );
    show(
      'lazy pool created yet?',
      context.beanFactory.containsSingleton('pool'),
    );
    show(
      'pool open (initMethod connect)',
      context.getBean<ConnectionPool>().open,
    );
    show(
      'search index (@Bean product with @PostConstruct)',
      context.getBean<SearchIndex>().size,
    );
    show('legacy bean (@Import)', context.getBean<LegacyGreeter>().greeting);

    final screen = CatalogScreen();
    context.autowireCapableBeanFactory.autowireBean(screen);
    show(
      '@Configurable screen',
      '${screen.title}, page ${screen.catalog.pageSize}',
    );
  }

  void lifecycle() {
    out('  (the probe was created at refresh; its callbacks in order:)');
    tourLog.addAll(startup);
    context.stop();
    context.start();
  }

  void extensions() {
    final bpp = context.getBean<AuditingPostProcessor>();
    show('beans seen by the custom BPP', bpp.seen.length);
    show(
      'InvoiceService audit trail',
      context.getBean<InvoiceService>().auditTrail,
    );
    show(
      'banner (registered by a registry post-processor)',
      context.getBean<Banner>().text,
    );
    show(
      'salesReport lazy (set by a factory post-processor)',
      context.beanFactory.getBeanDefinition('salesReport').lazy,
    );
    context.getBean<SalesReport>();

    final baskets = context.getBean<BasketService>()..add('Dune');
    show('basket (custom scope)', baskets.items);
    context.beanFactory.getRegisteredScope('basket')!.remove('basket');
    show('basket after the scope ended', baskets.items);
  }

  void events() {
    final orders = context.getBean<OrderService>();
    orders.place(1, 25);
    orders.place(2, 250);
    final seen = <String>[];
    final registration = context.addListener<OrderPlaced>(
      (order) => seen.add('lambda listener: order ${order.id}'),
    );
    orders.place(3, 10);
    registration.remove();
    orders.place(4, 10);
    tourLog.addAll(seen);
  }

  void messages() {
    show('en', context.getMessage('greeting', args: ['NEON Books']));
    show(
      'ru',
      context.getMessage('greeting', args: ['NEON Books'], locale: 'ru'),
    );
    show(
      'de_AT (falls back to de)',
      context.getMessage('greeting', args: ['NEON Books'], locale: 'de_AT'),
    );
    for (final count in [0, 1, 7]) {
      show('choice $count', context.getMessage('cart.items', args: [count]));
    }
    show(
      'default message',
      context.getMessage('missing', defaultMessage: 'n/a'),
    );
  }

  void spel() {
    final parser = SpelExpressionParser();
    final introspector = context.getBean<BeanIntrospector>();
    final books = context.getBean<BookRepository>().findAll();
    final evaluation = StandardEvaluationContext(books.first)
      ..propertyAccessors.insert(0, IntrospectionPropertyAccessor(introspector))
      ..setVariable('books', books)
      ..registerFunction('vat', (num price) => price * 1.2);
    Object? eval(String expression) =>
        parser.parseExpression(expression).getValue(evaluation);

    show('title.toUpperCase()', eval('title.toUpperCase()'));
    show('7 / 2, 7.0 / 2, -7 % 3', [
      eval('7 / 2'),
      eval('7.0 / 2'),
      eval('-7 % 3'),
    ]);
    show(
      '#books.?[price > 10].![title]',
      eval('#books.?[price > 10].![title]'),
    );
    show('#books.^[price < 10]?.title', eval('#books.^[price < 10]?.title'));
    show('#vat(price)', eval('#vat(price)'));
    show("title matches 'D.*'", eval("title matches 'D.*'"));
    show('safe navigation null?.x', eval('null?.length'));
    show('Elvis', eval("'' ?: 'empty'"));
    show('T(Math).max(3, 9)', eval('T(Math).max(3, 9)'));
    show(
      'template',
      parser
          .parseExpression('Total: #{price * 2} EUR', ParserContext.template)
          .getValue(evaluation),
    );
    final restricted = SimpleEvaluationContext.forReadOnlyDataBinding()
        .withRootObject({'name': 'Ada'})
        .build();
    show(
      'SimpleEvaluationContext',
      parser.parseExpression("name").getValue(restricted),
    );
  }

  void validation() {
    final introspector = context.getBean<BeanIntrospector>();
    final form = CheckoutForm();
    final binder =
        DataBinder(form, objectName: 'checkout', introspector: introspector)
          ..disallowedFields = ['giftNote']
          ..validators.add(BeanValidator(introspector: introspector))
          ..bind({
            'name': '',
            'email': 'ada@example.com',
            'confirmEmail': 'ada@other.com',
            'quantity': 'lots',
            'address.city': '',
            'address.zip': '123',
            "giftNote": 'sneaky',
          })
          ..validate();
    show('suppressed (disallowedFields)', binder.suppressedFields);
    for (final error in binder.bindingResult.allErrors) {
      final field = error is FieldError ? error.field : '(object)';
      show(field, context.getMessageFromResolvable(error));
    }
    final ru = binder.bindingResult.fieldError('name')!;
    show('name (ru)', context.getMessageFromResolvable(ru, locale: 'ru'));

    final gift = BeanValidator(introspector: introspector)
        .validateObject(CheckoutForm()..email = 'a@b.c', groups: [OnGift]);
    show('group OnGift only', [
      for (final v in gift) '${v.propertyPath}: ${v.message}',
    ]);

    final wrapper = BeanWrapper(form, introspector: introspector)
      ..setPropertyValue('address.city', 'Kyiv');
    show('BeanWrapper address.city', wrapper.getPropertyValue('address.city'));
  }

  Future<void> aop() async {
    final pricing = context.getBean<PricingService>();
    show('quote', pricing.quote('1', 3));
    try {
      pricing.refund('1');
    } on StateError catch (error) {
      show('refund threw', error.message);
    }
    show('reserve (async)', await pricing.reserve('2'));
    show('slogans (advisor bean)', context.getBean<Slogans>().today());
    show('proxy target', AopUtils.getTarget(pricing).runtimeType);
  }

  // Parent and child contexts built from hand-written modules.
  void hierarchy() {
    final parent = AnnotationConfigApplicationContext([
      BeanModule('platform', [
        BeanDefinition<LegacyGreeter>(
          name: 'platformGreeter',
          create: (_) => LegacyGreeter('hello from the parent context'),
        ),
      ]),
    ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
    final heard = <String>[];
    parent.addListener<OrderPlaced>(
      (o) => heard.add('parent heard order ${o.id}'),
    );
    final child = AnnotationConfigApplicationContext(
      [
        BeanModule('feature', [
          BeanDefinition<Banner>(
            name: 'childBanner',
            dependencies: const [Dependency(LegacyGreeter)],
            create: (r) => Banner(r.dependency<LegacyGreeter>().greeting),
          ),
        ]),
      ],
      parent: parent,
      environment: StandardEnvironment(systemEnvironment: {}),
    )..refresh();
    show('child bean using a parent bean', child.getBean<Banner>().text);
    child.publishEvent(const OrderPlaced(42, 1));
    show('event propagated to the parent', heard);
    child.close();
    parent.close();
  }

  // Startup validation reports configuration errors before creating beans.
  void failures() {
    void attempt(String label, List<BeanDefinition<Object>> definitions) {
      final broken = AnnotationConfigApplicationContext([
        BeanModule('broken', definitions),
      ], environment: StandardEnvironment(systemEnvironment: {}));
      try {
        broken.refresh();
        show(label, 'started?!');
      } on BeansException catch (error) {
        show(label, error);
      }
    }

    attempt('missing dependency', [
      BeanDefinition<Banner>(
        name: 'banner',
        dependencies: const [Dependency(LegacyGreeter)],
        create: (r) => Banner(r.dependency<LegacyGreeter>().greeting),
      ),
    ]);
    attempt('cycle', [
      BeanDefinition<Banner>(
        name: 'a',
        dependsOn: const ['b'],
        create: (_) => Banner('a'),
      ),
      BeanDefinition<LegacyGreeter>(
        name: 'b',
        dependsOn: const ['a'],
        create: (_) => LegacyGreeter('b'),
      ),
    ]);
  }

  void shutdown() {
    context.close();
    show('closed', context.isClosed);
  }
}
