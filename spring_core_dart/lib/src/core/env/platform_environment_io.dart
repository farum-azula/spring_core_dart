import 'dart:io';

/// The process environment variables (`Platform.environment`).
///
/// Internal: selected by a conditional import in `StandardEnvironment`
/// when `dart:io` is available.
Map<String, String> platformEnvironment() => Platform.environment;
