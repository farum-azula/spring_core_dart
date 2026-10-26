/// The process id (`${PID}`): unknown here.
int? get processId => null;

/// The name of the current isolate (`%thread`): always `main` here.
String get isolateName => 'main';

/// Whether the console shows ANSI colours: in a Flutter web app's debug or
/// profile build (the browser's DevTools console and `flutter run` show
/// them), not otherwise.
bool get stdoutSupportsAnsi =>
    const bool.fromEnvironment('dart.library.ui') &&
    !const bool.fromEnvironment('dart.vm.product');
