/// Always an empty map: a web page has no environment variables.
///
/// Internal: a conditional import picks this file where `dart:io` is
/// missing; the `dart:io` variant returns `Platform.environment`.
Map<String, String> platformEnvironment() => const {};

/// Always `''`: without `dart:io` the system locale is unknown.
///
/// Internal: `Locales.systemLocale` reads it; the `dart:io` variant
/// returns `Platform.localeName`.
String platformLocaleName() => '';
