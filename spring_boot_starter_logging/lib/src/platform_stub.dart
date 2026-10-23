/// The process id (`${PID}`): unknown here.
int? get processId => null;

/// The name of the current isolate (`%thread`): always `main` here.
String get isolateName => 'main';

/// Whether standard output understands ANSI colours: never here.
bool get stdoutSupportsAnsi => false;
