import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/isolates/isolate_scaler.dart';
import 'package:spring_boot_starter_web/src/web_server_lifecycle.dart';

/// The pool of the web server's isolates; see the `dart:io` one. Where no
/// isolate can be started (a browser, which has no server either) there
/// is none.
abstract interface class ServerIsolatePool
    implements
        IsolateScaler,
        IsolateLoadSource,
        SmartLifecycle,
        AsyncStartup,
        PrimaryIsolateHandler {
  /// Asks every isolate for its load and reports.
  Future<void> refresh();
}

/// The pool's side in an isolate it started; see the `dart:io` one.
abstract interface class ServerIsolateWorker
    implements SmartLifecycle, IsolateScaler {}

/// Whether this isolate was started by a pool: never here.
bool get isServerIsolate => false;

/// Never: this platform has no isolates to start.
ServerIsolatePool createServerIsolatePool({
  required ServerIsolatesSettings settings,
  required WebServerStartStopLifecycle lifecycle,
  required IsolateReports reports,
  required IsolateLoadSampler sampler,
  PrimaryIsolate? Function()? primary,
  ApplicationLaunch? launch,
  IsolateScalingPolicy? policy,
  Iterable<IsolateLocalState> Function()? localState,
}) => throw UnsupportedError('No isolates on this platform');

/// Never: this platform has no isolates to start.
ServerIsolateWorker createServerIsolateWorker({
  required WebServerStartStopLifecycle lifecycle,
  required IsolateLoads loads,
  required IsolateReports reports,
}) => throw UnsupportedError('No isolates on this platform');
