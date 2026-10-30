/// Whether standard output is a terminal that shows ANSI colours, which
/// decides the default of `printLogHandlerColours`: never on the web,
/// where `print` writes to the browser's console.
bool get consoleSupportsAnsi => false;
