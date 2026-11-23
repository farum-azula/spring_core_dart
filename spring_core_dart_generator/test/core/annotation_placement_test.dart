// Where the container's own annotations may go (AnnotationPlacement): an
// annotation in a place where nothing reads it fails the build with what
// to change, instead of being ignored; in its places it works as before,
// and where Spring makes it work (@Order on the class a @Bean method
// returns, a bare @ConditionalOnMissingBean deducing the declared type) it
// works so.
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('advice (@Observed, @Validated) where no proxy runs it', () {
    final cases = <String, (String, List<String>)>{
      'a private method': (
        '@Component() class Orders { @Observed() void _save() {} '
            'void call() => _save(); }',
        [
          '@Observed on Orders._save: a private member is not called',
          'Make it a public instance method',
        ],
      ),
      'a static method': (
        '@Component() class Orders { @Observed() static int count() => 1; }',
        ['@Observed on Orders.count: a static member'],
      ),
      'a class that is no bean': (
        'class Report { @Observed() void run() {} }',
        [
          '@Observed on Report.run, and Report is no bean',
          'Add @Component() to Report',
        ],
      ),
      'the top level, an enum, an extension': (
        '@Observed() void migrate() {}\n'
            'enum Mode { a; @Observed() void on() {} }\n'
            'extension on String { @Observed() void x() {} }',
        [
          '@Observed on migrate, in the top level of',
          '@Observed on on, in the enum Mode',
          '@Observed on x, in the extension on String',
        ],
      ),
      'a constructor': (
        '@Component() class A { @Observed() A(); }',
        ['@Observed on the constructor A: a constructor is not called'],
      ),
      'a field (Java allows methods and types only)': (
        '@Component() class A { @Observed() int count = 0; }',
        [
          '@Observed on the field A.count',
          "Java's @Target allows no field",
        ],
      ),
      'an operator': (
        '@Component() class V { @Observed() int operator [](int i) => i; }',
        ['@Observed on the operator V.[]: a proxy cannot forward an operator'],
      ),
      'a @Bean method': (
        'class Vault {}\n'
            '@Configuration() class C { @Bean() @Observed() Vault vault() => '
            'Vault(); }',
        [
          '@Observed on the @Bean method C.vault',
          'Annotate the returned class or its methods instead',
        ],
      ),
      'a method of a @Configuration class': (
        '@Configuration() class Admin { @Observed() void wipe() {} }',
        [
          '@Observed on Admin.wipe, a @Configuration class',
          'Move the method into a @Service',
        ],
      ),
      'an aspect': (
        '@Aspect() @Component() class Audit { @Observed() void log() {} }',
        ['@Observed on Audit.log, a bean the container does not proxy'],
      ),
      '@Validated on a method of a class without it': (
        '@Service() class Signup { @Validated() void register(String n) {} }',
        [
          '@Validated on the method Signup.register',
          'Add @Validated() to Signup',
        ],
      ),
    };
    for (final MapEntry(key: name, value: (source, messages))
        in cases.entries) {
      test(name, () async {
        final result = await buildPackage({
          'lib/src/beans.dart': scanRoot,
          'lib/src/service.dart': '$coreImport$source',
        }, proxyMode: ProxyMode.all);
        expect(result.succeeded, isFalse);
        final errors = result.errors.join('\n');
        for (final message in messages) {
          expect(errors, contains(message));
        }
      });
    }

    test('a member the subclass proxy cannot override (MS-1)', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        'lib/src/service.dart':
            "${coreImport}import 'package:meta/meta.dart';\n"
            '@Component() class Vault { int _n = 0; '
            '@Observed() @nonVirtual void open() => _n++; }',
      }, proxyMode: ProxyMode.all);
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('The method Vault.open carries advice'),
          contains('it is @nonVirtual'),
        ),
      );
    });

    test('in its places it works: a bean, a base, a @Bean product', () async {
      final output = await generateModule('''
abstract class Base {
  @Observed()
  void run() {}
}

class Plain {
  @Observed()
  void x() {}
}

@Component()
class Good extends Base {
  @Observed()
  int get total => 1;
}

@Configuration()
class Config {
  @Bean()
  Plain plain() => Plain();
}

@Service()
@Validated()
class Signup {
  @Validated()
  void register(@NotBlank() String name) {}
}
''', proxyMode: ProxyMode.all);
      expect(output, contains(r'_$GoodProxy'));
    });
  });

  group('methods the container calls', () {
    final cases = <String, (String, String)>{
      'a listener of a class that is no bean': (
        'class Ev {} class Report { @EventListener() void run(Ev e) {} }',
        '@EventListener on Report.run, and Report is no bean',
      ),
      'a lifecycle method in an enum': (
        'enum Mode { a; @PostConstruct() void on() {} }',
        '@PostConstruct on on, in the enum Mode',
      ),
      'a lifecycle getter': (
        '@Component() class A { @PostConstruct() int get ready => 1; }',
        '@PostConstruct on the getter A.ready: it goes on a method',
      ),
      'a listener setter': (
        'class Ev {} @Component() class A { @EventListener() set on(Ev e) {} }',
        '@EventListener on the setter A.on',
      ),
      'a @BeanMethodAnnotation of the application on a top-level function': (
        '@BeanMethodAnnotation() class Tick { const Tick(); }\n'
            '@Tick() void tick() {}',
        '@Tick on tick, in the top level of',
      ),
      'advice of an aspect in a class that is no aspect': (
        "@Component() class Svc { @Around('execution(* *(..))') Object? "
            'a(ProceedingJoinPoint p) => p.proceed(); }',
        '@Around on Svc.a: Svc is no @Aspect class',
      ),
      '@Aspect without @Component': (
        "@Aspect() class Audit { @Before('execution(* *(..))') void b() {} }",
        '@Aspect on Audit: an aspect must be a bean',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }
  });

  group('injection annotations', () {
    final cases = <String, (String, String)>{
      '@Qualifier on a field without @Autowired': (
        "class E {} @Component() class A { @Qualifier('fast') late E e; }",
        '@Qualifier on the field A.e: only an @Autowired',
      ),
      '@Lazy on a field without @Autowired': (
        '@Component() class A { @Lazy() A? a; }',
        '@Lazy on the field A.a',
      ),
      '@Autowired on a static field': (
        '@Component() class A { @Autowired() static A? a; }',
        '@Autowired on the field A.a: a static member is not injected',
      ),
      '@Autowired on a getter': (
        '@Component() class A { @Autowired() A? get a => null; }',
        '@Autowired on the getter A.a',
      ),
      '@Autowired on a constructor parameter': (
        '@Component() class A { A(@Autowired() Object? o); }',
        'a constructor parameter is injected anyway',
      ),
      '@Autowired on a top-level variable': (
        '@Autowired() Object? shared;',
        '@Autowired on shared, in the top level of',
      ),
      '@Autowired in a class that is no bean': (
        'class E {} class A { @Autowired() late E e; }',
        'and A is no bean',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }

    test('a @Configurable class is injected though it is no bean', () async {
      await generateModule('''
class E {}

@Component()
class EBean extends E {}

@Configurable()
class Form {
  @Autowired()
  late E e;
}
''');
    });
  });

  group('definition annotations', () {
    final cases = <String, (String, String)>{
      '@Primary on a method': (
        '@Component() class P { @Primary() void m() {} }',
        '@Primary on P.m: it belongs on a class or a @Bean method',
      ),
      '@Profile on a method': (
        "@Component() class P { @Profile(['x']) void m() {} }",
        '@Profile on P.m',
      ),
      '@Primary on a mixin': (
        '@Primary() mixin M {}',
        '@Primary on mixin M',
      ),
      '@Order on a plain method': (
        '@Component() class P { @Order(1) void m() {} }',
        '@Order on P.m: it orders a bean',
      ),
      '@Import on a method': (
        '@Component() class P { @Import([P]) void m() {} }',
        '@Import on P.m: it belongs on a class',
      ),
      '@Primary on the class a @Bean method returns': (
        '@Primary() class Pool {}\n'
            '@Configuration() class C { @Bean() Pool pool() => Pool(); }',
        '@Primary on Pool: Pool is the result of the @Bean method C.pool',
      ),
      '@Log on a mixin': ('@Log() mixin L {}', '@Log on mixin L'),
      '@Introspected on an enum': (
        '@Introspected() enum E { a }',
        '@Introspected on enum E',
      ),
      'a stereotype on an abstract class': (
        '@Service() abstract class PaymentService { void pay() {} }',
        '@Service on the abstract class PaymentService: it cannot be created',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }

    test('@Order on the class a @Bean method returns orders the bean, as '
        "Spring's AnnotationAwareOrderComparator does", () async {
      final output = await generateModule('''
@Order(7)
class Pool {}

@Configuration()
class C {
  @Bean()
  Pool pool() => Pool();
}
''');
      expect(output, contains('order:7'));
    });

    test('a bare @ConditionalOnMissingBean() of a @Bean method is written '
        'with the declared return type (FP-1)', () async {
      final output = await generateModule('''
import 'package:spring_boot_dart/spring_boot_dart.dart';

abstract interface class Clock {}

class SystemClock implements Clock {}

@Configuration()
class C {
  @Bean()
  @ConditionalOnMissingBean()
  Clock clock() => SystemClock();
}
''');
      expect(
        output,
        matches(
          RegExp(r'ConditionalOnMissingBean\.where\(types:(const)?\[Clock\]'),
        ),
      );
    });
  });

  group('constraints and JSON annotations nothing reads', () {
    final cases = <String, (String, String)>{
      'a constraint on a parameter of a bean without @Validated': (
        '@Service() class Signup { void register(@NotBlank() String n) {} }',
        'method validation runs on beans with @Validated()',
      ),
      'a constraint on a @ConfigurationProperties class without @Validated': (
        "@ConfigurationProperties(prefix: 'p') class P { @NotBlank() String "
            "name = ''; }",
        'Add @Validated() to P',
      ),
      'a constraint on a static field': (
        "@Introspected() class F { @NotBlank() static String s = ''; }",
        '@NotBlank on the field F.s: a static field is not described',
      ),
      '@JsonCreator on a static method': (
        "@Introspected() class M { String y = ''; @JsonCreator() static M of() "
            '=> M(); }',
        '@JsonCreator on M.of: only a constructor',
      ),
      '@JsonIgnore on a private field': (
        "@Introspected() class X { @JsonIgnore() String _p = ''; String get "
            'p => _p; }',
        '@JsonIgnore on the field X._p',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }
  });

  test('two beans of one name: both declarations are named', () async {
    await expectBuildError(
      'class Pool {}\n'
          '@Configuration() class A { @Bean() Pool plazy() => Pool(); }\n'
          '@Configuration() class B { @Bean() Pool plazy() => Pool(); }',
      'the @Bean method A.plazy of package:pkg/src/service.dart and the '
          '@Bean method B.plazy',
    );
  });
}
