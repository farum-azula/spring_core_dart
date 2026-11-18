// What the main builder rejects, naming the fix.
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('rejects', () {
    final cases = <String, (String, String)>{
      'abstract imported class': (
        '@Configuration() @Import([A]) class C {} abstract class A {}',
        'must not be abstract',
      ),
      'private bean class': ('@Component() class _A {}', 'must be public'),
      'final injected field': (
        '@Component() class A { @Autowired() final A? a = null; }',
        'must be settable',
      ),
      'private injected field': (
        '@Component() class A { @Autowired() A? _a; }',
        'must be public',
      ),
      'private injected setter': (
        '@Component() class A { @Autowired() set _a(A? v) {} }',
        'must be public',
      ),
      'private autowired method': (
        '@Component() class A { @Autowired() void _m() {} }',
        'must be public',
      ),
      'async autowired method': (
        '@Component() class A { @Autowired() Future<void> m() async {} }',
        'must not be async',
      ),
      'several @Autowired constructors': (
        '@Component() class A { @Autowired() A.one(); @Autowired() A.two(); }',
        'Only one constructor may be @Autowired',
      ),
      'private @Autowired constructor': (
        '@Component() class A { @Autowired() A._(); A.x(); A.y(); }',
        'must be public',
      ),
      'ambiguous constructors': (
        '@Component() class A { A.one(); A.two(); }',
        'Cannot choose a constructor',
      ),
      'async @Bean method': (
        'class B {} @Configuration() class C { @Bean() Future<B> b() async => '
            'B(); }',
        'must not be async',
      ),
      'void @Bean method': (
        '@Configuration() class C { @Bean() void b() {} }',
        'must return a class, function or record type',
      ),
      'private @Bean method': (
        'class B {} @Configuration() class C { @Bean() B _b() => B(); }',
        'must be public',
      ),
      'generic @Bean method': (
        '@Configuration() class C { @Bean() List<T> b<T>() => []; }',
        'Generic @Bean method',
      ),
      'missing initMethod': (
        "class B {} @Configuration() class C { @Bean(initMethod: 'nope') B b() "
            '=> B(); }',
        "initMethod 'nope'",
      ),
      'missing destroyMethod': (
        "class B {} @Configuration() class C { @Bean(destroyMethod: 'nope') B "
            'b() => B(); }',
        "destroyMethod 'nope'",
      ),
      // A single function-typed dependency is injected by its type.
      'collection of functions': (
        '@Component() class A { A(List<void Function()> f); }',
        'only class types can be injected',
      ),
      'future dependency': (
        '@Component() class A { A(Future<int> f); }',
        'Cannot inject a Future',
      ),
      'nullable collection element': (
        '@Component() class A { A(List<A?> all); }',
        'must not be nullable',
      ),
      'map without String keys': (
        '@Component() class A { A(Map<int, A> all); }',
        'String keys',
      ),
      'lifecycle method with arguments': (
        '@Component() class A { @PostConstruct() void init(int x) {} }',
        'without required parameters',
      ),
      'async lifecycle method of a @Configurable': (
        '@Configurable() class A { @PreDestroy() Future<void> close() async {} '
            '}',
        'must not be async',
      ),
      'listener with two parameters': (
        '@Component() class A { @EventListener() void on(A a, A b) {} }',
        'at most one parameter',
      ),
      'listener without event type': (
        '@Component() class A { @EventListener() void on() {} }',
        'needs an event parameter',
      ),
      'private listener': (
        '@Component() class A { @EventListener() void _on(A a) {} }',
        'must be public',
      ),
      'bad conditional type': (
        '@Component() @Conditional([String]) class A {}',
        'must implement Condition',
      ),
      'condition with arguments': (
        'class C implements Condition { C(this.x); final int x; @override bool '
            'matches(ConditionContext c) => true; }\n'
            '@Component() @Conditional([C]) class A {}',
        'no-argument constructor',
      ),
      'import of a non-class': (
        '@Component() @Import([dynamic]) class A {}',
        'class types only',
      ),
      'property source factory with arguments': (
        'class F { F(this.x); final int x; }\n'
            "@Component() @PropertySource(['a'], factory: F) class A {}",
        'no-argument constructor',
      ),
      'private configurable': ('@Configurable() class _S {}', 'must be public'),
      'private introspected': ('@Introspected() class _S {}', 'must be public'),
      'static advice': (
        "@Aspect() @Component() class A { @Before('x()') static void b() {} }",
        'public instance method',
      ),
      'named advice parameter': (
        "@Aspect() @Component() class A { @Before('x()') void b({JoinPoint? "
            'jp}) {} }',
        'positional parameters',
      ),
      'unexpected advice parameter': (
        "@Aspect() @Component() class A { @Before('execution(* *(..))') void "
            'b(String s) {} }',
        'Unexpected parameter s of @Before',
      ),
      'around without proceeding join point': (
        "@Aspect() @Component() class A { @Around('x()') Object? b(JoinPoint "
            'jp) => null; }',
        'needs a ProceedingJoinPoint',
      ),
      'proceeding join point outside around': (
        "@Aspect() @Component() class A { @Before('x()') void "
            'b(ProceedingJoinPoint jp) {} }',
        'Only @Around advice',
      ),
      'generic configurable': (
        '@Configurable() class S<T> {}',
        'Generic @Configurable',
      ),
      'duplicate bean names': (
        "@Component('same') class A {}\n@Component('same') class B {}",
        "Bean name 'same' is used by both",
      ),
      'alias clash': (
        "class B {}\n@Configuration() class C { @Bean(aliases: ['c']) B b() => "
            'B(); }',
        "Bean name 'c' is used by both",
      ),
      'lazy nullable': (
        'abstract interface class G {}\n'
            '@Component() class S { S(@Lazy() this.g); final G? g; }',
        'a lazy dependency cannot be nullable',
      ),
      'lazy collection': (
        'abstract interface class G {}\n'
            '@Component() class S { S(@Lazy() this.g); final List<G> g; }',
        'only a single bean can be injected lazily',
      ),
      'lazy value': (
        "@Component() class S { S(@Lazy() @Value('x') this.v); final String v; "
            '}',
        'only beans can be injected lazily',
      ),
      'lazy class with private members': (
        'class P { int _n = 0; }\n'
            '@Component() class S { S(@Lazy() this.p); final P p; }',
        'the lazy proxy must implement P',
      ),
      'lazy generic type': (
        'abstract interface class Repo<T> {}\n'
            '@Component() class S { S(@Lazy() this.r); final Repo<int> r; }',
        'generic types (Repo<...>) cannot be injected lazily',
      ),
      'lazy SDK type': (
        '@Component() class S { S(@Lazy() this.s); final StringBuffer s; }',
        'the lazy proxy must implement StringBuffer',
      ),
      'private constant condition': (
        'class _P implements Condition { const _P(); @override bool '
            'matches(ConditionContext c) => true; }\n'
            '@Component() @_P() class A {}',
        'private constant',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }

    test('two @ComponentScan in one file', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';
@ComponentScan() final BeanModule a = BeanModule('a', []);
@ComponentScan() final BeanModule b = BeanModule('b', []);
''',
      });
      expect(result.errors.join(), contains('Only one @ComponentScan'));
    });

    test('invalid @ComponentScan variable names', () async {
      for (final name in [r'$x', '_x']) {
        final result = await buildPackage({
          'lib/src/beans.dart':
              "import 'package:spring_core_dart/spring_core_dart.dart';\n"
              "@ComponentScan() final BeanModule $name = BeanModule('x', []);",
        });
        expect(result.errors.join(), contains('must be public'), reason: name);
      }
    });
  });

  group('private declarations fail the build, naming the fix', () {
    const uri = 'declared in package:pkg/src/service.dart';
    final cases = <String, (String, String)>{
      'constructor parameter type': (
        'class _Dep {} @Component() class A { A(_Dep d); }',
        'Constructor parameter d of A',
      ),
      'the message names the type, its library and the fix': (
        'class _Dep {} @Component() class A { A(_Dep d); }',
        'has the private type _Dep ($uri), which the generated module '
            'cannot reference: make _Dep public.',
      ),
      'type argument': (
        'class _Dep {} @Component() class A { A(List<_Dep> d); }',
        'has the private type _Dep',
      ),
      '@Bean return type (lite mode)': (
        'class _Pool {} @Configuration(proxyBeanMethods: false) class C { '
            '@Bean() _Pool pool() => _Pool(); }',
        '@Bean method C.pool returns the private type _Pool ($uri), which '
            'the generated module cannot reference: make _Pool public, or '
            'declare a public supertype as the return type.',
      ),
      '@Bean parameter (full mode)': (
        'class _P {} @Configuration() class C { @Bean() Object o(_P? p) => 1; '
            '}',
        'Parameter p of @Bean method C.o has the private type _P',
      ),
      'injected field': (
        'class _Dep {} @Component() class A { @Autowired() late _Dep d; }',
        'Field d of A has the private type _Dep',
      ),
      '@Autowired method parameter': (
        'class _Dep {} @Component() class A { '
            '@Autowired() void wire(_Dep d) {} }',
        'Parameter d of method A.wire has the private type _Dep',
      ),
      'event type': (
        'class _Evt {} @Component() class A { '
            '@EventListener() void on(_Evt e) {} }',
        'Method A.on listens to the private type _Evt',
      ),
      'private function as a default value': (
        'int _zero() => 0; @Component() class A { '
            r'A({@Value(r"${f}") Object f = _zero}); }',
        'The default value of constructor parameter f of A uses the private '
            '_zero ($uri), which the generated module cannot reference: make '
            'it public, or declare the parameter without a default.',
      ),
      'private class as a default value': (
        'class _Opts { const _Opts(); } @Component() class A { '
            r'A({@Value(r"${o}") Object o = const _Opts()}); }',
        'uses the private _Opts ($uri)',
      ),
      'private constructor as a default value': (
        'class Opts { const Opts._(); } @Component() class A { '
            r'A({@Value(r"${o}") Object o = const Opts._()}); }',
        'uses the private Opts._ ($uri)',
      ),
      'private bean class': (
        '@Component() class _A {}',
        'Bean class _A must be public: the generated module cannot reference '
            'a private class of package:pkg/src/service.dart. Make it public, '
            'or move it out of the scanned directory.',
      ),
    };
    for (final MapEntry(key: name, value: (source, message)) in cases.entries) {
      test(name, () => expectBuildError(source, message));
    }
  });
}
