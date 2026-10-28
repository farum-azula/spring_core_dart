import 'dart:io';

/// The version of the running Dart VM (`3.9.0`, without the build
/// details), for the startup line.
String? dartVersion() => Platform.version.split(' ').first;

/// The id of this process, shown as `with PID 42` in the startup line.
int? processId() => pid;
