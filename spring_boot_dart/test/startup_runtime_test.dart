// The runtime in the startup line: the VM's Dart version, or the Flutter
// version the Flutter tool passes to every Flutter build.
import 'package:spring_boot_dart/src/startup_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('a Dart program: the VM version', () {
    expect(
      runtimeDescription(dart: '3.13.5', flutter: '', flutterDart: ''),
      'Dart 3.13.5',
    );
  });

  test('a Flutter app: Flutter and its Dart', () {
    expect(
      runtimeDescription(dart: '3.13.5', flutter: '3.47.7', flutterDart: ''),
      'Flutter 3.47.7 (Dart 3.13.5)',
    );
  });

  test('a Flutter web app: the Dart version from the Flutter tool', () {
    expect(
      runtimeDescription(
        dart: null,
        flutter: '3.47.7',
        flutterDart: '3.13.5 (build 3.13.5)',
      ),
      'Flutter 3.47.7 (Dart 3.13.5)',
    );
  });

  test('nothing known: no runtime in the line', () {
    expect(
      runtimeDescription(dart: null, flutter: '', flutterDart: ''),
      isNull,
    );
  });
}
