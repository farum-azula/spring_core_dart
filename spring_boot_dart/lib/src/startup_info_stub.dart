/// The version of the running Dart VM: always null here, because it can
/// only be read through `dart:io` (not available on the web).
String? dartVersion() => null;

/// The id of this process: always null here, because it can only be
/// read through `dart:io` (not available on the web).
int? processId() => null;
