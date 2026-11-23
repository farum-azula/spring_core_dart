// Where the container's annotations are read: definition annotations on
// the bean's own class, stereotypes on a class, injection on what the
// container passes; elsewhere the build fails, naming what to change.
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/placements.dart';
import '../support/spring_builder.dart';

void main() {
  group('definition annotations are read on the bean itself', () {
    misplacedCases({
      'on a constructor, with its class named': (
        '@Component() class Orders { @Transactional() Orders(); }',
        ['@Transactional on the constructor Orders', 'service.dart'],
      ),
      'on a class that is no bean': (
        '@Primary() class Plain { String name = ""; }',
        ['@Primary on class Plain, which is no bean'],
      ),
      'on an abstract base, which a bean does not inherit': (
        '@Scope("prototype") abstract class Base {} '
            '@Component() class Impl extends Base {}',
        ['@Scope on abstract class Base'],
      ),
      '@Order on an abstract base': (
        '@Order(1) abstract class Base {} '
            '@Component() class Impl extends Base {}',
        ['@Order on abstract class Base'],
      ),
      'a condition on a class that is no bean': (
        "@ConditionalOnProperty('x.y') class Plain {}",
        ['@ConditionalOnProperty on class Plain, which is no bean'],
      ),
      '@Import on the result of a @Bean method': (
        'class Dep {} @Import([Dep]) class Made {} '
            '@Configuration() class Config { @Bean() Made made() => Made(); }',
        ['@Import on class Made, which is no bean'],
      ),
      '@Aspect on an abstract base': (
        '@Aspect() abstract class Base {} '
            '@Component() class Impl extends Base {}',
        ['@Aspect on Base: an aspect must be a bean'],
      ),
      '@Configurable on an abstract class': (
        '@Configurable() abstract class Base {}',
        ['@Configurable on class Base: the container finds'],
      ),
    });
  });

  group('stereotypes and scan roots', () {
    misplacedCases({
      '@Component on a method': (
        '@Component() class A { @Component() void m() {} }',
        ['@Component on A.m: it belongs on a class'],
      ),
      '@Service on a top-level function': (
        '@Service() void run() {}',
        ['@Service on run, in the top level'],
      ),
      '@Configuration on a @Bean method': (
        'class P {} @Configuration() class C '
            '{ @Bean() @Configuration() P p() => P(); }',
        ['@Configuration on C.p: it belongs on a class'],
      ),
      '@Configuration on a repository': (
        '@Table() class Book { @Id() int? id; } '
            '@Configuration() abstract interface class Books '
            'implements CrudRepository<Book, int> {}',
        ['@Configuration on class Books: the build writes'],
      ),
      '@ComponentScan on a top-level function': (
        '@ComponentScan() void scanHere() {}',
        ['@ComponentScan on scanHere, in the top level'],
      ),
      '@ComponentScan on a mixin': (
        '@ComponentScan() mixin M {}',
        ['@ComponentScan on mixin M: a scan root is'],
      ),
    });
  });

  group('injection points', () {
    misplacedCases({
      '@Value on a field of a class that is no bean': (
        r"class Plain { @Value(r'${x:1}') late String x; }",
        ['@Value on the field Plain.x, and Plain is no bean'],
      ),
      '@Value on a static field': (
        r"@Component() class A { @Value(r'${x:1}') static late String x; }",
        ['@Value on the field A.x: a static member'],
      ),
      '@Value at the top level': (
        r"@Value(r'${x:1}') late String x;",
        ['@Value on x, in the top level'],
      ),
      '@Value on a parameter nothing passes': (
        r"@Component() class A { void m(@Value(r'${x:1}') String x) {} }",
        ['@Value on parameter x of A.m: only the parameters'],
      ),
      '@Qualifier on a parameter nothing passes': (
        '@Component() class D {} @Component() class A '
            "{ void m(@Qualifier('d') D d) {} }",
        ['@Qualifier on parameter d of A.m: only the parameters'],
      ),
      '@Lazy on a constructor of a class that is no bean': (
        '@Component() class D {} class Plain { Plain(@Lazy() D d); }',
        ['@Lazy on parameter d of the constructor Plain, and Plain'],
      ),
      '@Autowired on a repository method': (
        '@Table() class Book { @Id() int? id; String title = ""; } '
            'abstract interface class Books '
            'implements CrudRepository<Book, int> { '
            '@Autowired() Future<List<Book>> findByTitle(String title); }',
        ['@Autowired on Books.findByTitle: the build writes'],
      ),
      '@Lookup on a class that is no component': (
        '@Component() class D {} class Plain { @Lookup() D d() => throw 0; }',
        ['@Lookup on Plain.d: the container implements it'],
      ),
      '@Pointcut outside an aspect': (
        "@Component() class A { @Pointcut('execution(* *(..))') void p() {} }",
        ['@Pointcut on A.p: A is no @Aspect class'],
      ),
    });
  });

  group('validation and JSON', () {
    misplacedCases({
      '@Validated on a getter of a class without it': (
        '@Component() class A { @Validated() int get n => 1; }',
        ['@Validated on the getter A.n: method validation'],
      ),
      '@Validated on a parameter of a plain method': (
        '@Component() class A { void m(@Validated() int x) {} }',
        ['@Validated on parameter x of A.m: method validation'],
      ),
      '@Validated in a mixin of a class without it': (
        'mixin M { @Validated() void m(@NotBlank() String s) {} } '
            '@Component() class A with M {}',
        ['@Validated on the method M.m: method validation'],
      ),
      '@Valid on a String': (
        "@Introspected() class A { @Valid() String d = ''; }",
        ['@Valid on the field A.d: @Valid checks'],
      ),
      '@ConfigurationProperties with nothing to bind': (
        "@ConfigurationProperties(prefix: 'p') "
            "class P { final String name = ''; }",
        ['@ConfigurationProperties on class P: it has nothing to bind'],
      ),
      '@JsonProperty on a method': (
        "@Introspected() class A { String y = ''; "
            "@JsonProperty('n') void m() {} }",
        ['@JsonProperty on A.m: the ObjectMapper reads'],
      ),
      '@JsonAlias on a getter without a setter': (
        "@Introspected() class A { @JsonAlias(['a']) String get g => ''; }",
        ['@JsonAlias on the getter A.g: an alias'],
      ),
      '@JsonNaming on a mixin': (
        '@JsonNaming(PropertyNamingStrategy.snakeCase) mixin M {}',
        ['@JsonNaming on mixin M: the ObjectMapper reads'],
      ),
      '@Resource on a method without a parameter': (
        "import 'package:spring_core_dart/jakarta.dart' as jk;\n"
            '@Component() class A { @jk.Resource() void m() {} }',
        ['@Resource on A.m: it injects the one parameter'],
      ),
    });
  });

  placedCase('what the runtime reads through a base keeps building', '''
@Transactional() abstract class TxBase { void save() {} }
@Component() class Orders extends TxBase {}
@PreAuthorize('true') abstract class Secured2 { void wipe() {} }
@Component() class Vault extends Secured2 {}
@Observed() abstract class Watched { void run() {} }
@Component() class Job extends Watched {}
@Validated() abstract class Checked { void put(@NotBlank() String s) {} }
@Component() class Form extends Checked {}
''');

  placedCase('an abstract @Component with @Lookup methods', '''
@Component() class Dep {}
@Component() abstract class Maker { @Lookup() Dep dep(); }
''');

  placedCase('an annotation composes by extending another', '''
class MainOne extends Primary { const MainOne(); }
class DevOnly extends Profile { const DevOnly() : super(const ['dev']); }
class Each extends Scope { const Each() : super('prototype'); }
@MainOne() @DevOnly() @Each() @Component() class UsesThem {}
''');

  group('an annotation passes nothing on to the classes it marks', () {
    misplacedCases({
      '@Primary on an annotation class': (
        '@Primary() class MainOne { const MainOne(); } '
            '@MainOne() @Component() class UsesIt {}',
        ['@Primary on class MainOne', 'class MainOne extends Primary'],
      ),
      '@Profile on an annotation class': (
        "@Profile(['dev']) class DevOnly { const DevOnly(); } "
            '@DevOnly() @Component() class UsesIt {}',
        ['@Profile on class DevOnly', 'class DevOnly extends Profile'],
      ),
    });
  });

  placedCase('the result of a @Bean method keeps its method annotations', '''
@Order(3) class Made { @Transactional() void save() {} @Cacheable('c') int n() => 1; }
@Configuration() class Config { @Bean() Made made() => Made(); }
''');

  placedCase(
    'injection annotations on the parameters the container passes',
    r'''
@Component() class Dep {}
@Component() class A {
  A(@Value(r'${x:1}') String x, @Qualifier('dep') Dep d, @Lazy() Dep e);
  @Value(r'${y:2}') late String y;
  @Autowired() void wire(@Qualifier('dep') Dep d, @Value(r'${z:3}') String z) {}
}
abstract class Base { Base(@Value(r'${b:1}') String b); }
@Component() class Sub extends Base { Sub(super.b); }
class Made { Made(this.d); final Dep d; }
@Configuration() class Config {
  @Bean() Made made(@Qualifier('dep') @Lazy() Dep d, @Value(r'${m:1}') String m) => Made(d);
}
''',
  );

  placedCase('@Configurable on a class the container does not create', r'''
@Component() class Dep {}
@Configurable() class Plain { @Autowired() late Dep dep; @Value(r'${x:1}') late String x; }
''');

  placedCase('@Value in an @Introspected class is listed metadata', '''
@Introspected() class Form { @Value('nick') String? nick; }
''');

  placedCase('a qualifier or a stereotype on a generated bean', '''
@Table() class Book { @Id() int? id; String title = ''; }
@Qualifier('books') @Repository() abstract interface class Books
    implements CrudRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}
@Qualifier('api') @FeignClient('svc', url: 'http://x')
abstract interface class Api { @GetMapping('/x') Future<String> x(); }
''');

  test('@Order on an exported class another package may return', () async {
    final result = await buildPackage({
      'lib/pkg.dart': "export 'src/service.dart';",
      'lib/src/beans.dart': scanRoot,
      'lib/src/service.dart':
          "$starterImports@Order(1) class Exported { String name = ''; }",
    }, proxyMode: ProxyMode.all);
    expect(result.errors, isEmpty);
  });
}
