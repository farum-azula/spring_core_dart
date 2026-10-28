import 'dart:isolate';

/// Runs [work] on a new isolate and returns its result.
///
/// Password hashing takes hundreds of milliseconds of CPU; on another
/// isolate it does not stop the server's other requests. When [work] (or
/// what it captures) cannot be sent to an isolate, the `ArgumentError`
/// that follows makes it run again on the caller's isolate. An
/// `ArgumentError` thrown by [work] itself does the same, so such work
/// runs twice.
Future<T> offload<T>(T Function() work) async {
  try {
    return await Isolate.run(work);
  } on ArgumentError {
    return work(); // captures something an isolate cannot receive
  }
}
