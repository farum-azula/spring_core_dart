// Containers need Docker's socket, which only dart:io has: this library
// stands in for them on the web (`dart.library.js_interop`), where there is
// nothing to export.
