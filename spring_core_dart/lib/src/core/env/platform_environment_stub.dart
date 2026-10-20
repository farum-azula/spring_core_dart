/// Environment variables are not available on this platform (web), so the
/// map is empty.
///
/// Internal: selected by a conditional import in `StandardEnvironment`; the
/// `dart:io` variant returns `Platform.environment`.
Map<String, String> platformEnvironment() => const {};
