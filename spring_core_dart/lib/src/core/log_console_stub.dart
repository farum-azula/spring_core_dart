/// Whether standard output is a terminal that shows ANSI colours, which
/// decides the default of `printLogHandlerColours`: never on the web,
/// where `print` writes to the browser's console.
bool get consoleSupportsAnsi => false;

/// Writes one line of `printLogHandler`: with `print`, the browser's
/// console.
// The browser's console is the console of the web.
// ignore: avoid_print
void writeConsoleLine(String line) => print(line);
