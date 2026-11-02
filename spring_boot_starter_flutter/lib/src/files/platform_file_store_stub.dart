import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/memory_file_store.dart';

// Neither dart:io nor dart:js_interop: files in memory.

/// A store in memory.
FileStore createFileStore() => InMemoryFileStore();
