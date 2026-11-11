import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_exchange.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.edge');

/// Where the application runs, and the one thing a function does
/// differently from a server: work after the answer (the bean
/// `edgeRuntime`).
///
/// A platform may stop an instance as soon as its response is sent, so a
/// `Future` nobody waits for (an audit record, a mail) can be cut.
/// [waitUntil] tells the platform to keep the instance until it ends:
///
/// ```dart
/// @RestController()
/// class OrdersController {
///   OrdersController(this.runtime, this.mail);
///   final EdgeRuntime runtime;
///   final Mail mail;
///
///   @PostMapping('/orders')
///   Order place(@RequestBody() Order order) {
///     runtime.waitUntil(mail.confirm(order)); // after the response
///     return order;
///   }
/// }
/// ```
///
/// - Supabase Edge Functions: `EdgeRuntime.waitUntil`.
/// - Cloudflare Workers: `ctx.waitUntil`.
/// - AWS Lambda: the invocation ends when the work did; with a buffered
///   response the client gets the answer then, with a streamed one
///   before.
/// - On a server (the same application run with `dart run`): the work
///   just runs.
///
/// Spring (Java): no counterpart; Spring Cloud Function leaves it to the
/// platform's SDK.
final class EdgeRuntime {
  /// The runtime named [platform] (`spring.edge.runtime`); `null` on a
  /// server.
  const EdgeRuntime(this.platform);

  /// `supabase`, `cloudflare`, `aws`; `null` when the application runs as
  /// an ordinary server.
  final String? platform;

  /// Whether the application runs as a function.
  bool get isFunction => platform != null;

  /// Keeps the instance until [work] ends, after the response of the
  /// current request went out. A failure of [work] is logged, never
  /// thrown. Outside a request, and on a server, [work] runs as any
  /// `Future` does.
  void waitUntil(Future<void> work) {
    final guarded = work.catchError((Object error, StackTrace stackTrace) {
      _log.error(
        'Work after the response failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
    final context =
        RequestContextHolder.currentRequest?.attributes[fetchContextAttribute];
    if (context case FetchContext(:final waitUntil?)) {
      waitUntil(guarded);
    } else {
      unawaited(guarded);
    }
  }
}
