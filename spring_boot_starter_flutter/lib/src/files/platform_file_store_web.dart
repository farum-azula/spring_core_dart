import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/indexed_db_file_store.dart';

/// A store in the browser's IndexedDB.
FileStore createFileStore() => IndexedDbFileStore();
