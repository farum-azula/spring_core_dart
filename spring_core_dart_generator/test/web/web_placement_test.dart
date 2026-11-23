// Where the web annotations may go (WebGeneration.placements): a mapping
// outside a controller, a request value off a handler, @ResponseStatus on
// an exception class, a rate limit outside a controller fail the build.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      'a mapping on a @Component that is no controller': (
        "@Component() class Api { @GetMapping('/x') String x() => ''; }",
        [
          '@GetMapping on Api.x: Api is no @RestController (or @Controller)',
          'Add @RestController() to Api',
        ],
      ),
      'a mapping on a getter': (
        "@RestController() class G { @GetMapping('/g') String get g => ''; }",
        ['@GetMapping on the getter G.g: it goes on a method'],
      ),
      'a request value on a method that is no handler': (
        '@RestController() class C { String helper(@PathVariable() String id) '
            "=> ''; }",
        ['@PathVariable on parameter id of C.helper'],
      ),
      'an @ExceptionHandler in a service': (
        "@Service() class Svc { @ExceptionHandler([StateError]) String "
            "h(StateError e) => ''; }",
        [
          '@ExceptionHandler on Svc.h: Svc is no @RestController or '
              '@RestControllerAdvice',
        ],
      ),
      '@ResponseStatus on an exception class': (
        '@ResponseStatus(HttpStatus.notFound) class BookNotFound implements '
            'Exception {}',
        [
          '@ResponseStatus on class BookNotFound',
          'Throw ResponseStatusException(status) instead',
        ],
      ),
      '@ResponseStatus on a method that is no handler': (
        '@RestController() class C { @ResponseStatus(HttpStatus.created) '
            'void m() {} }',
        ['@ResponseStatus on C.m: it sets the status of a handler'],
      ),
      'a rate limit outside a controller': (
        "@Component() class Jobs { @RateLimiter('10/1m') void run() {} }",
        ['@RateLimiter on Jobs.run: Jobs is no @RestController'],
      ),
    });
  });

  placedCase('in their places they build', '''
@RestController()
@RequestMapping('/books')
@CrossOrigin()
@ResponseStatus(HttpStatus.ok)
class Books {
  @GetMapping('/{id}')
  @RateLimiter('10/1m')
  String one(@PathVariable() String id, @RequestParam() String? q) => id;

  @PostMapping('')
  @ResponseStatus(HttpStatus.created)
  String create(@RequestBody() String body) => body;
}

@RestControllerAdvice()
class Errors {
  @ExceptionHandler([StateError])
  String handle(StateError e) => '';
}

abstract class BaseApi {
  @GetMapping('/base')
  String base() => '';
}

@RestController()
class Derived extends BaseApi {}
''');

  group('what only a server reads', () {
    misplacedCases({
      '@CrossOrigin on an HTTP client': (
        "@CrossOrigin() @FeignClient('svc', url: 'http://x') abstract "
            "interface class Api { @GetMapping('/x') Future<String> x(); }",
        ['@CrossOrigin on class Api: it applies to the routes of a server'],
      ),
      '@RateLimiter on a method of an HTTP client': (
        "@FeignClient('svc', url: 'http://x') abstract interface class Api "
            "{ @GetMapping('/x') @RateLimiter('10/1s') Future<void> x(); }",
        ['@RateLimiter on Api.x: it applies to the routes of a server'],
      ),
      '@ResponseStatus on a method of an HTTP client': (
        "@FeignClient('svc', url: 'http://x') abstract interface class Api "
            "{ @GetMapping('/x') @ResponseStatus(HttpStatus.created) "
            'Future<void> x(); }',
        ['@ResponseStatus on Api.x: it sets the status a server'],
      ),
      '@RateLimiter in a mixin of a class that is no controller': (
        "mixin M { @RateLimiter('10/1s') void m() {} } "
            '@Component() class A with M {}',
        ['@RateLimiter on M.m: M is no @RestController'],
      ),
      '@RateLimiter on an interface no controller implements': (
        "abstract interface class I { @RateLimiter('10/1s') void m(); } "
            '@Component() class A implements I { @override void m() {} }',
        ['@RateLimiter on I.m: I is no @RestController'],
      ),
    });
  });

  placedCase('a rate limit in a base of a controller', '''
mixin Limited { @RateLimiter('10/1s') @GetMapping('/m') String m() => ''; }
@RestController() class Api with Limited {}
''');
}
