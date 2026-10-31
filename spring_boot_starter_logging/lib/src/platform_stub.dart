/// The id of this process, for `${PID}` in log patterns: always `null`
/// on the web, which has no process id.
int? get processId => null;

/// The name of the current isolate, for `%thread`: always `main` on the
/// web.
String get isolateName => 'main';

/// Whether the console can show ANSI colours; this decides
/// `spring.output.ansi.enabled=detect`. On the web it is true only in a
/// Flutter app's debug or profile build, whose output the browser's
/// DevTools console and `flutter run` show with colours.
bool get stdoutSupportsAnsi =>
    const bool.fromEnvironment('dart.library.ui') &&
    !const bool.fromEnvironment('dart.vm.product');

/// Where the console's lines go: `print`, the browser's console.
void Function(String line) consoleOut({bool stderr = false}) => print;
