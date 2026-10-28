// What runs the application, for the startup line.

/// The Flutter version, for the `Starting ... using Flutter ...` line.
///
/// The Flutter tool passes it to every Flutter build as
/// `--dart-define=FLUTTER_VERSION=...`; it is empty outside Flutter.
const flutterVersionDefine = String.fromEnvironment('FLUTTER_VERSION');

/// The Dart version the Flutter tool passes together with
/// [flutterVersionDefine]; empty outside Flutter. On the web it is the
/// only way to know the Dart version.
const flutterDartVersionDefine = String.fromEnvironment('FLUTTER_DART_VERSION');

/// What the startup line says the application runs on: `Dart 3.13.5`, or
/// `Flutter 3.47.7 (Dart 3.13.5)` in a Flutter app.
///
/// [dart] is the running VM's version (null without `dart:io`). [flutter]
/// and [flutterDart] are what the Flutter tool passed (empty outside
/// Flutter); only the version number of [flutterDart] is used, and only
/// when [dart] is null. Returns null when nothing is known, as in a web
/// build outside Flutter.
String? runtimeDescription({
  required String? dart,
  required String flutter,
  required String flutterDart,
}) {
  // `3.13.5 (build 3.13.5-...)`: the version alone.
  final fromFlutter = flutterDart.trim().split(' ').first;
  final dartVersion = dart ?? (fromFlutter.isEmpty ? null : fromFlutter);
  if (flutter.isNotEmpty) {
    return dartVersion == null
        ? 'Flutter $flutter'
        : 'Flutter $flutter (Dart $dartVersion)';
  }
  return dartVersion == null ? null : 'Dart $dartVersion';
}
