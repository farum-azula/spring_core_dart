import 'dart:io';

/// The Dart version (`3.9.0`), for the startup line.
String? dartVersion() => Platform.version.split(' ').first;

/// The process id, for the startup line.
int? processId() => pid;
