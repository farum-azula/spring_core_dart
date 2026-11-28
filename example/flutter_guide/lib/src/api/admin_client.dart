import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// What only an admin may do. The server checks the role again on every
/// call (403 otherwise); the app's `AdminService` checks it first.
@HttpExchange('/api')
abstract interface class AdminClient {
  /// `POST /api/books`: `201 Created` with a `Location`, or a 400
  /// ProblemDetail with the field errors of `@Valid`.
  @PostExchange('/books')
  Future<ResponseEntity<Book>> addBook(@RequestBody() NewBook book);

  /// `PUT /api/books/{isbn}/cover`: a `multipart/form-data` upload, the
  /// file in the part `file` (`@RequestPart MultipartFile` on the server).
  @PutExchange.of(
    url: '/books/{isbn}/cover',
    contentType: MediaType.multipartFormData,
  )
  Future<void> uploadCover(
    @PathVariable() String isbn,
    @RequestPart('file') MultipartFile file,
  );

  @DeleteExchange('/books/{isbn}')
  Future<void> deleteBook(@PathVariable() String isbn);

  /// `GET /api/admin/logs`: the server's last log lines, as JSON.
  @GetExchange('/admin/logs')
  Future<List<Object?>> serverLogs();
}
