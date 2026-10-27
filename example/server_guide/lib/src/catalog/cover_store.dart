// Cover images: uploaded ones in a directory (neon.covers.directory),
// packaged ones on the classpath (lib/resources/covers/). Not a component:
// ShopConfig declares it with a @Bean method (lazy, an alias, an init
// method and an inferred destroy method `close`).
import 'package:neon_books_server/src/catalog/directories.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

class CoverStore {
  CoverStore(this.directory, this._resources);

  /// Where uploaded covers are written.
  final String directory;
  final ResourceLoader _resources;

  /// Whether [open] ran (the `initMethod` of the `@Bean`).
  bool isOpen = false;

  /// The file types accepted, by media type.
  static const extensions = {'image/png': 'png', 'image/jpeg': 'jpg'};

  void open() {
    createDirectories(directory);
    isOpen = true;
  }

  /// Found by name as the destroy method (`close`, `shutdown`, `dispose`).
  void close() => isOpen = false;

  /// The cover of [isbn]: the latest uploaded one, else the packaged
  /// one, else the default cover.
  Resource coverOf(String isbn) {
    final uploaded = [
      for (final extension in extensions.values)
        if (FileSystemResource('$directory/$isbn.$extension') case final file
            when file.exists())
          file,
    ]..sort((a, b) => b.lastModified().compareTo(a.lastModified()));
    if (uploaded.isNotEmpty) {
      return uploaded.first;
    }
    final packaged = _resources.getResource('classpath:covers/$isbn.png');
    return packaged.exists()
        ? packaged
        : _resources.getResource('classpath:covers/default.png');
  }

  /// Keeps [file] as the cover of [isbn] (moved from the upload's
  /// temporary file).
  Future<void> store(String isbn, MultipartFile file) =>
      file.transferTo('$directory/$isbn.${extensions[file.contentType]!}');
}
