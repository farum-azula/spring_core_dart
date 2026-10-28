/// The plugin's entry on Windows and Linux, named in `pubspec.yaml`.
///
/// Flutter calls [registerWith] at startup. There is nothing to register:
/// on these platforms the token store calls the OS directly from Dart
/// (`dart:ffi`: DPAPI on Windows, libsecret on Linux), so the plugin
/// builds no native code; the entry only declares the platforms
/// supported. Apps never use it.
class SpringBootStarterFlutterDesktop {
  SpringBootStarterFlutterDesktop._();

  /// Called by Flutter's generated plugin registrant; does nothing.
  static void registerWith() {}
}
