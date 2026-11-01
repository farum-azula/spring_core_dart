import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

// What the dispatcher and the response writer share about
// `server.request-timeout`; not exported.

/// The answer's detail: it says that the request did not complete in time,
/// not the limit or what the handler was doing.
const requestTimeoutDetail = 'The request did not complete in time.';

/// How close to its end a `RequestDeadline` must be for an error to count
/// as the timeout: the timers of the server and of a Feign call that
/// share one end can fire a few milliseconds apart.
const requestDeadlineSlack = Duration(milliseconds: 10);

/// The 503 the request ends with when its deadline passed.
AsyncRequestTimeoutException requestTimeoutError() =>
    AsyncRequestTimeoutException(requestTimeoutDetail);

/// Whether [error] ends the request that runs now because of its
/// deadline: the deadline's own exception, or any error once the deadline
/// is (all but) over.
bool endsAtRequestDeadline(Object error) =>
    error is RequestDeadlineExceededException ||
    (RequestDeadline.current?.remaining ?? const Duration(days: 1)) <=
        requestDeadlineSlack;
