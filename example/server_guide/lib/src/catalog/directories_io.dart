import 'dart:io';

/// Creates [path] and its parents.
void createDirectories(String path) =>
    Directory(path).createSync(recursive: true);
