// Errors as RFC 9457 problems (chapter 3): `application/problem+json`
// from @ExceptionHandler methods of a @RestControllerAdvice, for every
// controller.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show FeignException;
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestControllerAdvice()
@Log()
class ApiErrors {
  ApiErrors(this.messages);

  final MessageSource messages;

  /// 404 `{"type": "about:blank", "title": "Not Found", "status": 404,
  /// "detail": "No book 978...", "instance": "/api/books/978...", "isbn":
  /// "978..."}`. The exception type comes from the parameter.
  @ExceptionHandler()
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail bookNotFound(BookNotFoundException error) =>
      ProblemDetail.forStatusAndDetail(
          HttpStatus.notFound,
          'No book ${error.isbn}',
        )
        ..title = 'Book not found'
        ..setProperty('isbn', error.isbn);

  @ExceptionHandler()
  @ResponseStatus(HttpStatus.conflict)
  ProblemDetail emptyBasket(EmptyBasketException error) =>
      ProblemDetail.forStatusAndDetail(
        HttpStatus.conflict,
        'The basket is empty',
      );

  /// `StateError`s of the services (a book that exists already).
  @ExceptionHandler()
  ResponseEntity<ProblemDetail> conflict(StateError error) =>
      ResponseEntity.status(HttpStatus.conflict).body(
        ProblemDetail.forStatusAndDetail(HttpStatus.conflict, error.message),
      );

  /// The supplier failed: 502, with the details in the log only.
  @ExceptionHandler()
  @ResponseStatus(HttpStatus.badGateway)
  ProblemDetail supplierFailed(FeignException error) {
    log.warning('supplier call failed: $error');
    return ProblemDetail.forStatusAndDetail(
      HttpStatus.badGateway,
      'The supplier is not available',
    );
  }

  /// `@Valid` failures: 400 with the field errors, their messages from
  /// messages*.properties in the language the client asks for
  /// (`Accept-Language: ja`): `{"errors": [{"field": "isbn", "message":
  /// "...", "rejectedValue": "12"}]}`.
  @ExceptionHandler()
  ProblemDetail invalid(
    MethodArgumentNotValidException error,
    ServerHttpRequest request,
  ) {
    final locale = request.headers['Accept-Language']
        ?.split(RegExp('[,;]'))
        .first
        .trim();
    final result = error.bindingResult;
    return ProblemDetail.forStatusAndDetail(
      HttpStatus.badRequest,
      'Invalid request content.',
    )..setProperty('errors', [
      for (final field in result.fieldErrors())
        {
          'field': field.field,
          'message': messages.getMessageFromResolvable(field, locale: locale),
          'rejectedValue': switch (field.rejectedValue) {
            null || String() || num() || bool() => field.rejectedValue,
            final other => '$other',
          },
        },
      for (final global in result.globalErrors)
        {
          'object': global.objectName,
          'message': messages.getMessageFromResolvable(global, locale: locale),
        },
    ]);
  }
}
