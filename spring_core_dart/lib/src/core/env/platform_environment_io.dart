import 'dart:io';

/// The environment variables of the running process
/// (`Platform.environment`).
///
/// Internal: a conditional import picks this file where `dart:io` exists,
/// so `StandardEnvironment` can read the variables without breaking web
/// builds.
Map<String, String> platformEnvironment() => Platform.environment;

/// The locale of the process as the operating system reports it
/// (`Platform.localeName`, for example `en_US.UTF-8`).
///
/// Internal: `Locales.systemLocale` reads it.
String platformLocaleName() => Platform.localeName;
