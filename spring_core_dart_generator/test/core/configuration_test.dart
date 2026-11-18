// `@Configuration` classes: full mode, `@Bean` types inferred from the
// method body, `@ConfigurationProperties` constructor binding.
import 'package:spring_core_dart_generator/src/core/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('@ConfigurationProperties constructor binding', () {
    const boot = "import 'package:spring_boot_dart/spring_boot_dart.dart';\n";

    test('the only constructor with parameters is bound from properties, '
        'not beans', () async {
      const db = '''
@ConfigurationProperties('db')
class DbProperties {
  const DbProperties(
    this.url, {
    @DefaultValue('10') required this.maxSize,
    this.hosts = const [],
    this.owner,
  });
  final String url;
  final int maxSize;
  final List<String> hosts;
  final String? owner;
}
''';
      final output = await generateModule(
        '',
        extra: {'lib/src/db.dart': boot + db},
      );
      // Spring Boot's ConstructorBound: no String / int / List beans.
      expect(
        output,
        matches(
          RegExp(
            r'create:\(r\)=>ConstructorBound\.from<DbProperties>'
            r"\(r,r'dbProperties'\)",
          ),
        ),
      );
      expect(output, isNot(contains('Dependency(')));
      // The introspection carries the same constructor, with @DefaultValue.
      expect(output, contains("DefaultValue(r'10')"));
      expect(output, contains('BeanConstructor<'));
      expect(await compileErrors({'lib/src/db.dart': boot + db}), isEmpty);
    });

    test('a named single constructor is the bound one', () async {
      final output = await generateModule(
        '',
        extra: {
          'lib/src/mail.dart':
              '''
$boot
@ConfigurationProperties('mail')
class MailProperties {
  MailProperties.of(this.host, [this.port = 25]);
  final String host;
  final int port;
}
''',
        },
      );
      expect(output, contains('ConstructorBound.from<'));
      // Called directly, an absent optional argument getting its default.
      expect(
        output,
        contains(
          'MailProperties.of((positional[0]asString),'
          'positional.argumentOr(1,25))',
        ),
      );
    });

    test('mutable classes keep the no-argument constructor', () async {
      final output = await generateModule(
        '',
        extra: {
          'lib/src/shop.dart':
              '''
$boot
@ConfigurationProperties('shop')
class ShopProperties {
  String name = '';
}
''',
        },
      );
      expect(output, contains('ShopProperties()'));
      expect(output, isNot(contains('ConstructorBound')));
    });
  });

  group('full-mode @Configuration', () {
    const source = """
class Calculator {}
class Pricing { Pricing(this.calculator); final Calculator calculator; }
class Id {}

@Configuration()
class AppConfig {
  AppConfig.named(this.prefix, [this.count = 2]);
  final Calculator prefix;
  final int count;

  @Bean()
  Calculator calculator() => Calculator();

  @Bean()
  Pricing pricing(Calculator calc, {int n = 3,
      Duration d = const Duration(seconds: 1)}) => Pricing(calculator());

  @Bean()
  @Scope(ScopeType.prototype)
  Id id([String? tag]) => Id();

  @Bean()
  @Qualifier('nullable')
  Pricing other(Calculator? calc) => Pricing(calc ?? calculator());

  @Bean()
  static Calculator shared() => Calculator();
}

base class Seed {}

@Configuration()
base class BaseConfig {
  BaseConfig({@Value('x') required this.name, this.size = 1});
  final String name;
  final int size;
  @Bean() Seed seed() => Seed();
}
""";

    test("a generated subclass returns the container's beans", () async {
      final output = await generateModule(source);
      // The subclass forwards the constructor arguments (super parameters
      // keep types and defaults); a `base` class gets a `final` subclass.
      expect(
        output,
        hasCode(
          r'class _$AppConfigConfiguration extends AppConfig { '
          r'_$AppConfigConfiguration(this._$beanFactory, super.p0, '
          '[super.p1]) : super.named();',
        ),
      );
      expect(
        output,
        hasCode(
          r'final class _$BaseConfigConfiguration extends BaseConfig { '
          r'_$BaseConfigConfiguration(this._$beanFactory, '
          '{required super.name, super.size});',
        ),
      );
      // Inter-bean calls get the bean of the container.
      expect(
        output,
        hasCode(
          '@override Calculator calculator() => '
          r"(this._$beanFactory.getBeanByName(r'calculator') as Calculator);",
        ),
      );
      // Arguments of an inter-bean call are used when that call creates
      // the bean (Spring's getBean(name, args)) ...
      expect(
        output,
        hasCode(
          // Defaulted parameters left out are resolved like the container
          // does (see aop_and_bean_types_test.dart).
          r'Pricing pricing(Calculator calc, {Object? n = const _$Absent(), '
          r'Object? d = const _$Absent()}) { '
          r'final _$args = <Object?>[calc, n, d]; '
          r"this._$arguments[r'pricing'] = _$args;",
        ),
      );
      expect(
        output,
        hasCode(
          r"final _$args = this._$arguments.remove(r'pricing'); "
          r'if (_$args != null) {return super.pricing( '
          r'(_$args[0] as Calculator), n: _$args[1] is _$Absent ? ',
        ),
      );
      // ... but not for a singleton when one is null (Spring: "stubbed
      // null arguments just for reference purposes"); a prototype keeps
      // them.
      expect(
        output,
        hasCode(
          r'if (!_$args.contains(null)) '
          r"{this._$arguments[r'other'] = _$args;}",
        ),
      );
      expect(
        output,
        hasCode(
          r'Id id([String? tag]) {final _$args = <Object?>[tag]; '
          r"this._$arguments[r'id'] = _$args;",
        ),
      );
      // The container creates the configuration through the subclass and
      // the beans through `_$method(r)`.
      expect(
        output,
        hasCode(
          r'create: (r) => _$AppConfigConfiguration(r, '
          "r.dependency<Calculator>(name: r'prefix'), ",
        ),
      );
      expect(
        output,
        hasCode(
          "create: (r) => (r.dependency<AppConfig>(qualifier: r'appConfig') "
          r'as _$AppConfigConfiguration)._$calculator(r)',
        ),
      );
      // Static @Bean methods are not intercepted.
      expect(output, hasCode('create: (r) => AppConfig.shared()'));
      expect(output, isNot(contains(r'_$shared')));
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('lite mode: proxyBeanMethods false, @Component, imported classes, '
        '@AutoConfiguration', () async {
      final output = await generateModule('''
import 'package:spring_boot_dart/spring_boot_dart.dart';
class Calculator {}

@Configuration(proxyBeanMethods: false)
class Lite { @Bean() Calculator a() => Calculator(); }

@Component()
class WithBeans { @Bean() Calculator b() => Calculator(); }

@AutoConfiguration()
class Auto { @Bean() Calculator c() => Calculator(); }

class Plain { @Bean() Calculator d() => Calculator(); }

@Component()
@Import([Plain])
class Importer {}
''');
      expect(output, isNot(contains('Configurationextends')));
      for (final (owner, method) in [
        ('Lite', 'a'),
        ('WithBeans', 'b'),
        ('Auto', 'c'),
        ('Plain', 'd'),
      ]) {
        final name = owner[0].toLowerCase() + owner.substring(1);
        expect(
          output,
          hasCode("r.dependency<$owner>(qualifier: r'$name').$method()"),
        );
      }
    });

    test('FactoryBean @Bean methods return the factory itself', () async {
      final output = await generateModule('''
class Client {}
class ClientFactory implements FactoryBean<Client> {
  @override Client getObject() => Client();
  @override bool get isSingleton => true;
  @override Type get objectType => Client;
}

@Configuration()
class Config { @Bean() ClientFactory client() => ClientFactory(); }
''');
      expect(
        output,
        hasCode(
          r"(this._$beanFactory.getBeanByName(r'&client') as ClientFactory)",
        ),
      );
    });

    test('rejects what cannot be subclassed, naming the fix', () async {
      for (final (source, message) in [
        (
          '@Configuration() final class C { @Bean() Object o() => 1; }',
          'remove `final`',
        ),
        (
          '@Configuration() interface class C { @Bean() Object o() => 1; }',
          'remove `interface`',
        ),
        (
          '@Configuration() class C { C._(); factory C() => C._(); '
              '@Bean() Object o() => 1; }',
          'add a public generative constructor',
        ),
      ]) {
        final result = await buildPackage({
          'lib/src/beans.dart': scanRoot,
          'lib/src/service.dart': '$coreImport$source',
        });
        expect(result.succeeded, isFalse, reason: source);
        expect(
          result.errors.join('\n'),
          allOf(contains(message), contains('proxyBeanMethods: false')),
          reason: source,
        );
      }
      // Lite mode builds, and so does a class without instance @Bean
      // methods (nothing to intercept: no subclass).
      await generateModule(
        '@Configuration(proxyBeanMethods: false) '
        'final class C { @Bean() Object o() => 1; }',
      );
      final output = await generateModule(
        '@Configuration() final class C { @Bean() static Object o() => 1; }',
      );
      expect(output, isNot(contains('Configurationextends')));
      expect(output, hasCode('create: (r) => C()'));
    });
  });

  group('@Bean types inferred from the method body', () {
    const source = """
abstract interface class DataSource {}
class HikariDataSource implements DataSource {
  void close() {}
}
abstract interface class Store<T> {}
class MemoryStore<T> implements Store<T> {}
abstract class Shape {}
class Circle extends Shape {}
class Square extends Shape {}
class Plain {}
class _Hidden implements DataSource {}

@Configuration()
class Config {
  @Bean() DataSource dataSource() => HikariDataSource();
  @Bean() Store<Object> store() => MemoryStore<String>();
  @Bean() Object shape(@Value('true') bool round) {
    if (round) {
      return Circle();
    }
    final square = Square();
    return square;
  }
  @Bean() Plain plain() => Plain();
  @Bean() Plain failing() => throw StateError('no');
  @Bean() Object closure() {
    final make = () { return 1; };
    make();
    return Plain();
  }
  @Bean() DataSource hidden() => _Hidden();
  @Bean() static DataSource shared() => HikariDataSource();
}
""";

    test(
      'the concrete class with full type arguments, plus supertypes',
      () async {
        final output = await generateModule(source);
        expect(
          output,
          hasCode(
            "BeanDefinition<HikariDataSource>(name: r'dataSource', "
            "source: r'package:pkg/src/service.dart#Config.dataSource', "
            'types: const [HikariDataSource, DataSource],',
          ),
        );
        // The call is cast to the inferred type; the destroy method of the
        // concrete class is inferred.
        expect(
          output,
          hasCode(
            "create: (r) => ((r.dependency<Config>(qualifier: r'config') "
            r'as _$ConfigConfiguration)._$dataSource(r) as HikariDataSource), '
            'destroyMethod: (bean) {bean.close();}',
          ),
        );
        expect(
          output,
          hasCode('create: (r) => (Config.shared() as HikariDataSource)'),
        );
        // The override keeps the declared signature.
        expect(output, hasCode('@override DataSource dataSource() =>'));
        expect(
          output,
          hasCode(
            "BeanDefinition<MemoryStore<String>>(name: r'store', "
            "source: r'package:pkg/src/service.dart#Config.store', "
            'types: const [MemoryStore<String>, Store<String>, '
            'MemoryStore<dynamic>, Store<dynamic>, Store<Object>],',
          ),
        );
        // Several returns: the common supertype.
        expect(output, hasCode("BeanDefinition<Shape>(name: r'shape',"));
        // Same as declared, `throw`, closures, private classes: unchanged.
        for (final name in ['plain', 'failing', 'closure']) {
          expect(output, hasCode("BeanDefinition<Plain>(name: r'$name',"));
        }
        expect(output, hasCode("BeanDefinition<DataSource>(name: r'hidden',"));
      },
    );

    test('AOP proxies see the concrete class', () async {
      final output = await generateModule('''
abstract interface class Api { void run(); }
class Impl implements Api {
  @override void run() {}
  void extra() {}
}

@Configuration(proxyBeanMethods: false)
class Config { @Bean() Api api() => Impl(); }
''', proxyMode: ProxyMode.all);
      expect(
        output,
        contains(r'class_$Config$ApiProxywithAdvisedWrapperimplementsImpl,Api'),
      );
      expect(output, hasCode("MethodSignature.of(r'extra',"));
      expect(output, hasCode("AopTarget(r'Impl',"));
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });
}
