// Endpoints for the regression tests of the review before 0.5.0 that no
// advice of the tests answers.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/plain')
class PlainController {
  @GetMapping('/bad-header')
  ResponseEntity<String> badHeader() =>
      ResponseEntity.status(HttpStatus.ok).header('X-Name', ['café']).body('x');

  @PostMapping('/text')
  String text(@RequestBody() String body) => '${body.length}';
}
