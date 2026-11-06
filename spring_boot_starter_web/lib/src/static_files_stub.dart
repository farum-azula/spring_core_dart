import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Whether static resources can be read from directories here: `false`
/// without `dart:io` (a browser), where only embedded `resources:` files
/// are found.
///
/// Internal: the static resources pick this file or the `dart:io` one by
/// a conditional import.
const bool staticFilesSupported = false;

/// Always `null`: there is no file system here.
String? canonicalDirectory(String path) => null;

/// Always `null`: there is no file system here.
FileSystemResource? findStaticFile(String base, List<String> segments) => null;
