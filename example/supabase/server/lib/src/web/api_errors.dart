// What the project refuses, as statuses of this API
// (`application/problem+json`). The messages of the project stay in the
// log.
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:supabase_example_server/spring_gen/src/app.spring.dart';

@RestControllerAdvice()
@Log()
class ApiErrors {
  /// The second title of a pair (`TodoLists.addPair`).
  @ExceptionHandler()
  ProblemDetail invalid(ArgumentError error) =>
      ProblemDetail.forStatusAndDetail(
        HttpStatus.badRequest,
        '${error.name}: ${error.message}',
      );

  /// The database refused the statement for this caller (a policy, a
  /// privilege).
  @ExceptionHandler()
  ProblemDetail denied(PermissionDeniedDataAccessException error) =>
      ProblemDetail.forStatusAndDetail(
        HttpStatus.forbidden,
        'The project does not allow this',
      );

  /// The row changed since it was read (`@Version`).
  @ExceptionHandler()
  ProblemDetail changed(OptimisticLockingFailureException error) =>
      ProblemDetail.forStatusAndDetail(
        HttpStatus.conflict,
        'The todo was changed by someone else',
      );

  /// No such object in a bucket, or not for this caller.
  @ExceptionHandler()
  ProblemDetail noObject(StorageObjectNotFoundException error) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No such file');

  /// An Edge Function answered an error, or did not answer: 502.
  @ExceptionHandler()
  ProblemDetail functionFailed(FeignException error) {
    log.warning('an Edge Function failed: $error');
    return ProblemDetail.forStatusAndDetail(
      HttpStatus.badGateway,
      'The function is not available',
    );
  }
}
