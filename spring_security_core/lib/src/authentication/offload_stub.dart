/// No isolates (the web): [work] runs on the caller's event loop.
Future<T> offload<T>(T Function() work) async => work();
