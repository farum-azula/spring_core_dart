/// Environment variables are not available on this platform (web), so the
/// map is empty.
///
/// Internal: selected by a conditional import in `StandardEnvironment`; the
/// `dart:io` variant returns `Platform.environment`.
Map<String, String> platformEnvironment() => const {};

/// The platform locale is not known here (web): `''`.
///
/// Internal: used by `Locales.systemLocale`; the `dart:io` variant returns
/// `Platform.localeName`.
String platformLocaleName() => '';
