import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/local_file_store.dart';
import 'package:spring_boot_starter_flutter/src/app_directories.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories_io.dart'
    as native;

/// A store on the app's directories: `support` (kept), `cache` (the system
/// may clear it) and `documents` (the user sees it).
FileStore createFileStore() => LocalFileStore(
  directory: (place) async {
    if (!native.hasPlatform) {
      throw StateError(
        'The app has no directories here: no implementation of '
        'path_provider is registered (a widget test needs a '
        'PathProviderPlatform of its own, or a FileStore bean).',
      );
    }
    return switch (place) {
      FilePlace.support => await readAppSupportDirectory(),
      FilePlace.cache => await readAppCacheDirectory(),
      FilePlace.documents => await readAppDocumentsDirectory(),
    };
  },
);
