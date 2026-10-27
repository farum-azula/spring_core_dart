import 'dart:isolate';

/// Runs [work] on another isolate (password hashing: hundreds of
/// milliseconds of CPU that must not stop the server's event loop); on the
/// caller's isolate if [work] cannot be sent there.
Future<T> offload<T>(T Function() work) async {
  try {
    return await Isolate.run(work);
  } on ArgumentError {
    return work(); // captures something an isolate cannot receive
  }
}
