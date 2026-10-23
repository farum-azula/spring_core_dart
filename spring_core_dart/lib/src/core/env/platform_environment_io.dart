import 'dart:io';

/// The process environment variables (`Platform.environment`).
///
/// Internal: selected by a conditional import in `StandardEnvironment`
/// when `dart:io` is available.
Map<String, String> platformEnvironment() => Platform.environment;

/// The locale of the process (`Platform.localeName`, e.g. `en_US.UTF-8`).
///
/// Internal: used by `Locales.systemLocale`.
String platformLocaleName() => Platform.localeName;
