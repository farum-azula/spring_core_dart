// Where the method security annotations and the security web arguments
// may go (SecurityGeneration.placements): where no proxy runs them the
// method would run unchecked, for anyone, so the build fails.
import 'package:build/build.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/placements.dart';
import '../support/spring_builder.dart';

void main() {
  test('this on a client: the interface is described', () async {
    final result = await buildPackage({
      'lib/src/beans.dart': scanRoot,
      'lib/src/service.dart':
          "${starterImports}@FeignClient('svc', url: 'http://x') "
          'abstract interface class Api { '
          "@PreAuthorize('this.ping() != null') @GetMapping('/a') "
          "Future<String> a(); @GetMapping('/p') Future<String> ping(); }",
    }, proxyMode: ProxyMode.all);
    expect(result.errors, isEmpty);
    expect(
      result.readerWriter.testing.readString(
        AssetId('pkg', 'lib/spring_gen/src/beans.spring.introspection.dart'),
      ),
      contains(RegExp(r'Introspection<(\w+\.)?Api>')),
    );
  });

  group('misplaced', () {
    misplacedCases({
      'on a private method': (
        "@Service() class Admin { @PreAuthorize('false') void _wipe() {} "
            'void call() => _wipe(); }',
        [
          '@PreAuthorize on Admin._wipe: a private member',
          'the method would run unchecked, for anyone',
        ],
      ),
      'on a method of a @Configuration class': (
        "@Configuration() class Admin { @PreAuthorize('hasRole(\"ADMIN\")') "
            'void wipe() {} }',
        ['@PreAuthorize on Admin.wipe, a @Configuration class'],
      ),
      'on a @Bean method': (
        'class Vault {}\n'
            "@Configuration() class C { @Bean() @Secured(['ADMIN']) Vault "
            'vault() => Vault(); }',
        ['@Secured on the @Bean method C.vault'],
      ),
      'on a field': (
        "@Service() class S { @PostAuthorize('true') int count = 0; }",
        ['@PostAuthorize on the field S.count'],
      ),
      'on an operator (MS-2)': (
        "@Service() class S { @PreAuthorize('true') int operator [](int i) "
            '=> i; }',
        ['@PreAuthorize on the operator S.[]'],
      ),
      'on a class that is no bean': (
        "@PreAuthorize('true') class Plain { void run() {} }",
        ['@PreAuthorize on class Plain, and Plain is no bean'],
      ),
      'a principal off a handler': (
        '@Service() class S { void run(@AuthenticationPrincipal() Object? '
            'me) {} }',
        ['@AuthenticationPrincipal on parameter me of S.run: only a handler'],
      ),
    });
  });

  placedCase('in their places they build', '''
@Service()
@PreAuthorize('isAuthenticated()')
class Orders {
  @PreAuthorize("hasRole('ADMIN')")
  void wipe() {}

  @PostFilter('true')
  List<String> all() => [];
}

@RestController()
class Me {
  @GetMapping('/me')
  String me(@AuthenticationPrincipal() Object? principal) => '';
}
''');
}
