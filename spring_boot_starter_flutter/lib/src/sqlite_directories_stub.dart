// Where there is no dart:io (the web): no directories. sqlite_directories.dart
// never asks on the web, so these are not called.

/// Whether the plugin has a platform implementation: none here.
bool get hasPlatform => false;

/// The application support directory: none here.
Future<String> supportPath() => throw UnsupportedError('No app directories');

/// The application cache directory: none here.
Future<String> cachePath() => throw UnsupportedError('No app directories');

/// The application documents directory: none here.
Future<String> documentsPath() => throw UnsupportedError('No app directories');

/// Creates [path]: not here.
void createDirectory(String path) =>
    throw UnsupportedError('No app directories');
