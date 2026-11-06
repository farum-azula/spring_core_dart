import 'dart:io' as io;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/static_resource_path.dart';

/// Whether static resources can be read from directories here: `true`
/// where `dart:io` exists.
///
/// Internal: the static resources pick this file or the stub by a
/// conditional import, so the starter's main library still compiles for
/// the browser.
const bool staticFilesSupported = true;

/// The absolute path of the directory [path] with every symbolic link
/// resolved, or `null` when it is not an existing directory.
String? canonicalDirectory(String path) {
  try {
    if (io.FileSystemEntity.typeSync(path) !=
        io.FileSystemEntityType.directory) {
      return null;
    }
    return io.Directory(path).resolveSymbolicLinksSync();
  } on io.FileSystemException {
    return null;
  }
}

/// The regular file at [segments] (already checked, decoded) under the
/// directory [base] (a [canonicalDirectory]), or `null`.
///
/// Fail closed: the path is resolved with every symbolic link, and the
/// file is refused when the resolved path leaves [base], when one of its
/// segments under [base] is not allowed (a link to a dot file), or when
/// it is not a regular file (a directory, a pipe, a device). The resource
/// reads the resolved path.
FileSystemResource? findStaticFile(String base, List<String> segments) {
  if (segments.isEmpty || segments.any((s) => s.isEmpty)) {
    return null;
  }
  final separator = io.Platform.pathSeparator;
  final candidate = [base, ...segments].join(separator);
  try {
    if (io.FileSystemEntity.typeSync(candidate) !=
        io.FileSystemEntityType.file) {
      return null;
    }
    final real = io.File(candidate).resolveSymbolicLinksSync();
    final prefix = base.endsWith(separator) ? base : '$base$separator';
    final windows = io.Platform.isWindows;
    final inside = windows
        ? real.toLowerCase().startsWith(prefix.toLowerCase())
        : real.startsWith(prefix);
    if (!inside) {
      return null;
    }
    final relative = real.substring(prefix.length).split(separator);
    for (final (index, segment) in relative.indexed) {
      if (!isAllowedStaticSegment(segment, first: index == 0)) {
        return null;
      }
    }
    if (io.FileSystemEntity.typeSync(real, followLinks: false) !=
        io.FileSystemEntityType.file) {
      return null;
    }
    return FileSystemResource(real);
  } on io.FileSystemException {
    return null;
  }
}
