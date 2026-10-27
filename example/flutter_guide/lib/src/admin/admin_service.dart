import 'dart:typed_data';

import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/admin_client.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// The admin's actions. `@PreAuthorize` checks the role of the user in the
/// `SecurityContextHolder` before each call (an `AccessDeniedException`
/// otherwise), like on a server; here it keeps a USER from even sending
/// the request. The server checks again: this is the app being helpful,
/// not the protection.
@Service()
@Log(topic: 'neon.admin')
class AdminService {
  AdminService(this._admin, this._catalog);

  final AdminClient _admin;
  final CatalogService _catalog;

  /// Adds [book]; a 400 from the server throws `FeignBadRequest` with the
  /// field errors in its ProblemDetail (see `fieldErrorsOf`).
  @PreAuthorize("hasRole('ADMIN')")
  Future<Book> addBook(NewBook book) async {
    final response = await _admin.addBook(book);
    log.info(
      'book added',
      fields: {'isbn': book.isbn, 'location': response.headers.location},
    );
    _catalog.refresh();
    return response.body ?? Book(isbn: book.isbn, title: book.title);
  }

  /// Uploads [png] as the cover of [isbn] (`multipart/form-data`).
  @PreAuthorize("hasRole('ADMIN')")
  Future<void> uploadCover(String isbn, Uint8List png) async {
    await _admin.uploadCover(
      isbn,
      InMemoryMultipartFile(
        'file',
        png,
        originalFilename: '$isbn.png',
        contentType: 'image/png',
      ),
    );
    _catalog.coverChanged(isbn);
  }

  @PreAuthorize("hasRole('ADMIN')")
  Future<void> deleteBook(String isbn) async {
    await _admin.deleteBook(isbn);
    _catalog.refresh();
  }

  /// The server's last log lines, as text.
  @PreAuthorize("hasRole('ADMIN')")
  Future<List<String>> serverLogs() async => [
    for (final line in await _admin.serverLogs())
      switch (line) {
        {'message': final Object message} => '$message',
        _ => '$line',
      },
  ];
}
