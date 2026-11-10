// Tells which isolate answered, for the tests of the server's pool of
// isolates.
import 'dart:isolate';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/isolate')
class IsolateController {
  IsolateController(this.isolate, this.primary, this.scaler);

  final IsolateInfo isolate;
  final PrimaryIsolate primary;

  // There only with a pool, and then in every isolate of it.
  final ObjectProvider<IsolateScaler> scaler;

  // The pool as the isolate that answers sees it, and that isolate.
  @GetMapping('/pool')
  String pool() {
    final scaler = this.scaler.getIfAvailable();
    return '${isolate.name} ${scaler?.count} ${scaler?.min} ${scaler?.max}';
  }

  // Scales from whichever isolate takes the request.
  @GetMapping('/scale')
  Future<String> scale(@RequestParam() int to) async =>
      '${isolate.name} ${await scaler.getIfAvailable()!.scaleTo(to)}';

  // Asks the first isolate for every isolate's load: the names.
  @GetMapping('/loads')
  Future<String> loads() async {
    final rows = (await primary.ask(IsolateLoadsHandler.handlerId))! as List;
    return '${isolate.name}: '
        '${rows.map((row) => (row as Map)['name']).join(',')}';
  }

  // Asks the first isolate for something nobody answers.
  @GetMapping('/ask-unknown')
  Future<String> askUnknown() async {
    try {
      await primary.ask('no.such.handler');
      return 'answered';
    } on Object catch (error) {
      return '${isolate.name}: ${error.runtimeType}';
    }
  }

  @GetMapping('/name')
  String name() => isolate.name;

  // Answers after [ms], the isolate free meanwhile.
  @GetMapping('/slow')
  Future<String> slow(@RequestParam() int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return isolate.name;
  }

  // Computes for [ms]: the isolate does nothing else.
  @GetMapping('/spin')
  String spin(@RequestParam() int ms) {
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < ms) {}
    return isolate.name;
  }

  // Ends the isolate at once, as a crash would; the first one answers
  // instead (the tests run in it).
  @GetMapping('/exit')
  void exit() {
    if (!isolate.primary) {
      Isolate.exit();
    }
  }
}
