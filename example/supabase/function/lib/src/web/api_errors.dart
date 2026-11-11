import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

@RestControllerAdvice()
class ApiErrors {
  @ExceptionHandler()
  ProblemDetail denied(PermissionDeniedDataAccessException error) =>
      ProblemDetail.forStatusAndDetail(
        HttpStatus.forbidden,
        'The project does not allow this',
      );
}
