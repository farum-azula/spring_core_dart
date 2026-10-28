/// Runs [work] on the caller's event loop: on the web there are no
/// isolates to move it to.
Future<T> offload<T>(T Function() work) async => work();
