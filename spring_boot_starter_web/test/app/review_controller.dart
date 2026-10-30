// Endpoints for the regression tests of the review before 0.5.0.
import 'dart:async';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Marks the controllers [ReviewThirdErrors] advises.
class ReviewApi {
  const ReviewApi();
}

@RestController()
@RequestMapping('/api/review')
@ReviewApi()
class ReviewController {
  // No origins of its own: the global ones (https://shop.example) stay.
  @CrossOrigin(methods: ['PUT'])
  @PutMapping('/cors')
  String cors() => 'ok';

  @GetMapping('/format')
  String format() => throw const FormatException('bad');

  @GetMapping('/argument')
  String argument() => throw ArgumentError('bad');

  @GetMapping('/unsupported')
  String unsupported() => throw UnsupportedError('bad');

  @GetMapping('/entity-events')
  ResponseEntity<EventStream<String>> entityEvents() =>
      ResponseEntity.status(HttpStatus.accepted)
          .header('X-Stream', ['on'])
          .body(EventStream.fromIterable(['a', 'b']));

  @GetMapping('/entity-emitter')
  ResponseEntity<SseEmitter> entityEmitter() {
    final emitter = SseEmitter();
    Timer.run(() async {
      await emitter.send('x');
      emitter.complete();
    });
    return ResponseEntity.status(HttpStatus.ok)
        .header('X-Emitter', ['on'])
        .body(emitter);
  }
}

/// First in order, for every exception of [ReviewController].
@RestControllerAdvice.of(assignableTypes: [ReviewController])
@Order(1)
class ReviewFirstErrors {
  @ExceptionHandler()
  ResponseEntity<String> any(Exception error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('first');
}

/// More specific, but later in order; for the controllers of this file.
@RestControllerAdvice.of(
  basePackages: ['asset:spring_boot_starter_web/test/app/review_controller'],
)
@Order(2)
class ReviewSecondErrors {
  @ExceptionHandler()
  ResponseEntity<String> format(FormatException error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('second');

  @ExceptionHandler()
  ResponseEntity<String> argument(ArgumentError error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('second');
}

/// For the controllers marked `@ReviewApi()` only.
@RestControllerAdvice.of(annotations: [ReviewApi])
@Order(3)
class ReviewThirdErrors {
  @ExceptionHandler()
  ResponseEntity<String> unsupported(UnsupportedError error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('third');
}
