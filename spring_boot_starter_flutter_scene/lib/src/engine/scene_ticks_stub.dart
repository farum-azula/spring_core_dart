import 'dart:async';

/// Calls [beat] every [period] until the returned function is called.
void Function() startSceneTicks(Duration period, void Function() beat) =>
    Timer.periodic(period, (_) => beat()).cancel;
