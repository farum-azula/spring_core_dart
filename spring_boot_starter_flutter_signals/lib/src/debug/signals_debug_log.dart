import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';

/// Logs the activity of followed state at DEBUG under
/// `spring.flutter.signals.activity`: writes, publications, flushes,
/// drops, computations and effect runs with their time, failures (a
/// refused run too); reads with [reads]. Names only, never a value.
///
/// In the build with the Signals tab (`spring.flutter.signals.debug.enabled`)
/// and attached only with `spring.flutter.signals.debug.log.enabled: true`.
final class SignalsDebugLog implements SignalProbe {
  /// The log; [reads] logs every read too (very many lines).
  SignalsDebugLog({this.reads = false});

  /// Whether reads are logged.
  final bool reads;

  static const _log = SpringLog('spring.flutter.signals.activity');

  void Function()? _detach;

  /// Starts logging.
  void start() => _detach ??= SignalProbes.attach(this);

  /// Stops logging.
  void stop() {
    _detach?.call();
    _detach = null;
  }

  static String _micros(Duration took) => '${took.inMicroseconds}µs';

  @override
  void wrote(ValueMember member) => _log.debug(() => '${member.name} written');

  @override
  void told(ValueMember member) =>
      _log.debug(() => '${member.name} told its readers');

  @override
  void read(SignalMember member) {
    if (reads) {
      _log.debug(() => '${member.name} read');
    }
  }

  @override
  void flushed(SignalQueue queue, int count) =>
      _log.debug(() => "queue '${queue.name}' flushed $count");

  @override
  void dropped(SignalQueue queue, ValueMember member) =>
      _log.debug(() => "queue '${queue.name}' dropped ${member.name}");

  @override
  void computed(ComputedMember member, Duration took, Object? error) =>
      _log.debug(
        () => error == null
            ? '${member.name} computed in ${_micros(took)}'
            : '${member.name} failed with ${error.runtimeType} in '
                  '${_micros(took)}',
      );

  @override
  void ran(EffectFollower effect, Duration took, Object? error) => _log.debug(
    () => error == null
        ? 'effect ${effect.name} ran in ${_micros(took)}'
        : 'effect ${effect.name} failed with ${error.runtimeType} (refused when it '
              'is an access denial) in ${_micros(took)}',
  );

  @override
  void beginReader(Object reader) {}

  @override
  void endReader() {}
}
