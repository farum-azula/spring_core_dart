import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Flags {
  bool on = true;

  bool isOn() => on;
}

class Plain {
  bool on = true;
}

class Marker {}

final flagsIntrospection = Introspection<Flags>(
  properties: [
    IntrospectedProperty<Flags>(
      'on',
      type: bool,
      typeInfo: const ClassType<bool>(),
      get: (flags) => flags.on,
    ),
  ],
  methods: [
    IntrospectedMethod<Flags>(
      'isOn',
      invoke: (flags, arguments) => flags.isOn(),
    ),
  ],
  instantiate: Flags.new,
);

BeanDefinition<Flags> flags() =>
    BeanDefinition<Flags>(name: 'flags', create: (_) => Flags());

BeanDefinition<Marker> marker(String name, String expression) =>
    BeanDefinition<Marker>(
      name: name,
      conditions: [ConditionalOnExpression(expression)],
      create: (_) => Marker(),
    );

class SelectsModule implements ImportSelector {
  const SelectsModule(this.module);

  final BeanModule module;

  @override
  List<BeanModule> selectImports() => [module];
}

void main() {
  ConfigurableApplicationContext run(List<BeanModule> modules) {
    final context = SpringApplication(
      modules,
      bannerMode: BannerMode.off,
      out: (_) {},
    ).run(const [], systemEnvironment: const {});
    addTearDown(() {
      if (context.isActive) {
        context.close();
      }
    });
    return context;
  }

  group('@ConditionalOnExpression on an @Introspected bean', () {
    test('reads a property and calls a method of an earlier bean', () {
      final context = run([
        BeanModule(
          'app',
          [
            flags(),
            marker('byProperty', '@flags.on'),
            marker('byMethod', '@flags.isOn()'),
            marker('negated', '!@flags.on'),
          ],
          introspections: [flagsIntrospection],
        ),
      ]);
      expect(context.containsBean('byProperty'), isTrue);
      expect(context.containsBean('byMethod'), isTrue);
      expect(context.containsBean('negated'), isFalse);
    });

    test('sees a description the importing module brings', () {
      final library = BeanModule('library', [
        flags(),
        marker('fromLibrary', '@flags.on'),
      ]);
      final context = run([
        BeanModule(
          'app',
          const [],
          imports: [library],
          introspections: [flagsIntrospection],
        ),
      ]);
      expect(context.containsBean('fromLibrary'), isTrue);
    });

    test('sees the description of a module an ImportSelector brings', () {
      final selected = BeanModule(
        'selected',
        [flags(), marker('fromSelected', '@flags.isOn()')],
        introspections: [flagsIntrospection],
      );
      final context = run([
        BeanModule(
          'app',
          const [],
          registrars: [ImportDeclaration(() => SelectsModule(selected))],
        ),
      ]);
      expect(context.containsBean('fromSelected'), isTrue);
    });

    test('a bean registered later is still not there, as in Spring', () {
      expect(
        () => run([
          BeanModule(
            'app',
            [marker('tooEarly', '@flags.on'), flags()],
            introspections: [flagsIntrospection],
          ),
        ]),
        throwsA(
          predicate<Object>((error) => '$error'.contains("'flags'")),
        ),
      );
    });

    test('a class without a description is still refused', () {
      expect(
        () => run([
          BeanModule('app', [
            BeanDefinition<Plain>(name: 'plain', create: (_) => Plain()),
            marker('undescribed', '@plain.on'),
          ]),
        ]),
        throwsA(predicate<Object>((error) => '$error'.contains('EL1008E'))),
      );
    });
  });
}
