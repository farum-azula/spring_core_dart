import 'dart:async';
import 'dart:io';

/// Marks the errors of [socket]'s `done` future as handled.
///
/// A socket that was written to completes `done` with the error that ended
/// it (`Connection reset by peer`, a broken pipe) in addition to the error
/// its stream reports. A `done` nobody listens to turns that into an
/// uncaught error of whatever zone created the socket, and `package:test`
/// fails the test that happens to be running. Call this right after
/// connecting, for every socket that is written to; the errors themselves
/// are for the stream's `onError`, or for the code that reads the reply.
void ignoreDoneErrors(Socket socket) {
  unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
}
