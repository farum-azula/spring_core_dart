// Endpoints of the rate limiter's tests: @RateLimiter on a class and on
// methods, and plain ones for the rules of the configuration.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/limited')
@RateLimiter('50/1m', name: 'limited', key: 'ip')
class LimitedController {
  // Two a minute for each user (by address without one).
  @GetMapping('/annotated')
  @RateLimiter('2/1m')
  String annotated() => 'annotated';

  // One a minute for each API key.
  @GetMapping('/by-header')
  @RateLimiter('1/1m', key: "#{headers['x-api-key']}")
  String byHeader() => 'by-header';

  // One a minute for each authenticated user, by an expression.
  @GetMapping('/by-user')
  @RateLimiter('1/1m', key: '#{authentication.name}')
  String byUser(ServerHttpRequest request) =>
      request.principal?.name ?? 'nobody';

  // The limit from the configuration.
  @GetMapping('/placeholder')
  @RateLimiter(r'${limited.placeholder:1/1h}', burst: 3)
  String placeholder() => 'placeholder';

  // Counts the bodies it was given: a refused request's is not read.
  @PostMapping('/echo')
  String echo(@RequestBody() String body) => body;

  @GetMapping('/plain')
  String plain(ServerHttpRequest request) =>
      request.principal?.name ?? 'nobody';
}
