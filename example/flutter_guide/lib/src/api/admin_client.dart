import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// What only an admin may do. The server checks the role again on every
/// call (403 otherwise); the app's `AdminService` checks it first.
@FeignClient('admin', url: r'${api.base-url}', path: '/api')
abstract interface class AdminClient {
  /// `POST /api/books`: `201 Created` with a `Location`, or a 400
  /// ProblemDetail with the field errors of `@Valid`.
  @PostMapping('/books')
  Future<ResponseEntity<Book>> addBook(@RequestBody() NewBook book);

  /// `PUT /api/books/{isbn}/cover`: a `multipart/form-data` upload, the
  /// file in the part `file` (`@RequestPart MultipartFile` on the server).
  @PutMapping('/books/{isbn}/cover')
  Future<void> uploadCover(
    @PathVariable() String isbn,
    @RequestPart('file') MultipartFile file,
  );

  @DeleteMapping('/books/{isbn}')
  Future<void> deleteBook(@PathVariable() String isbn);

  /// `GET /api/admin/logs`: the server's last log lines, as JSON.
  @GetMapping('/admin/logs')
  Future<List<Object?>> serverLogs();
}
