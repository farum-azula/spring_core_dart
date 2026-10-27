// What runs the application, for the startup line.

/// The Flutter version the Flutter tool passes to every Flutter build
/// (`--dart-define=FLUTTER_VERSION=...`); empty outside Flutter.
const flutterVersionDefine = String.fromEnvironment('FLUTTER_VERSION');

/// The Dart version the Flutter tool passes with it; empty outside
/// Flutter.
const flutterDartVersionDefine = String.fromEnvironment('FLUTTER_DART_VERSION');

/// `Dart 3.13.5`, or `Flutter 3.47.7 (Dart 3.13.5)` in a Flutter app; null
/// when nothing is known (a web build outside Flutter). [dart] is the
/// running VM's version (null without `dart:io`), [flutter] and
/// [flutterDart] what the Flutter tool passed.
String? runtimeDescription({
  required String? dart,
  String flutter = flutterVersionDefine,
  String flutterDart = flutterDartVersionDefine,
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
