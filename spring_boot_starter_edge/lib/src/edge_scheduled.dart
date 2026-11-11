import 'dart:async';

/// The platform ran the function by its schedule, not for a request: a
/// Cloudflare cron trigger, an Amazon EventBridge schedule.
final class EdgeScheduledEvent {
  /// An event of [platform] at [time], for the schedule [schedule].
  const EdgeScheduledEvent({required this.time, this.schedule, this.platform});

  /// When the platform planned the run.
  final DateTime time;

  /// Which schedule it is: the cron expression of a Cloudflare trigger
  /// (`*/5 * * * *`), the ARN of an EventBridge rule; `null` when the
  /// platform does not say.
  final String? schedule;

  /// `cloudflare`, `aws`.
  final String? platform;

  @override
  String toString() => 'EdgeScheduledEvent(${schedule ?? time})';
}

/// A bean the function calls when the platform runs it by a schedule.
///
/// A timer does not outlive a request in a function, so `@Scheduled`
/// methods do not run between requests; the platform's schedule does
/// their work. Every bean of this type is called for every event, one
/// after the other, and the platform keeps the instance until the last
/// one ended. An error fails the run (the platform records it) after the
/// other handlers ran.
///
/// ```dart
/// @Component()
/// class NightlyReport implements EdgeScheduledHandler {
///   NightlyReport(this.reports);
///   final Reports reports;
///
///   @override
///   Future<void> onScheduled(EdgeScheduledEvent event) async {
///     if (event.schedule == '0 3 * * *') {
///       await reports.send();
///     }
///   }
/// }
/// ```
///
/// - Cloudflare Workers: `[triggers] crons = ["0 3 * * *"]` in
///   `wrangler.toml`; [EdgeScheduledEvent.schedule] is the expression.
/// - AWS Lambda: an EventBridge rule or schedule with the function as its
///   target; the schedule is the rule's ARN.
/// - Supabase: `pg_cron` calls an endpoint of the function over HTTP; that
///   is an ordinary request, not this.
///
/// Spring (Java): `@Scheduled` with an external trigger has no
/// counterpart; Spring Cloud Function maps such an event to a `Consumer`.
abstract interface class EdgeScheduledHandler {
  /// Does the work of [event].
  FutureOr<void> onScheduled(EdgeScheduledEvent event);
}
