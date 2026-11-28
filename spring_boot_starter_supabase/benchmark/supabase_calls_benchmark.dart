// What the starter's own work costs on its hot path: one select of the
// REST API (a derived query of a repository, two rows read into entities)
// and one call of an Edge Function (a JSON body posted, a JSON answer
// read into a class), each through the beans of the test application, on
// a MockHttpTransport that answers at once. Not part of the tests; run
// with
//   dart run benchmark/supabase_calls_benchmark.dart
//   dart compile exe benchmark/supabase_calls_benchmark.dart -o /tmp/sb && /tmp/sb
//
// November 2026, Apple M5, AOT, microseconds per call (medians of 5 runs
// of 20 000 calls, three runs each), 0.10.0 / 0.10.1:
//   REST select:   7.5-7.8 / 8.5-8.7 (SupabaseHttp on the bare transport,
//                  then on RestClient: its request spec, two interceptors)
//   Edge Function: 5.1-5.5 / 4.3-4.4 (an invocation handler at run time, the
//                  generated RestClient calls of an HTTP service interface)
// Neither runs in a zone of its own unless a deadline of the caller is
// later than its time limit.

import 'dart:io';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../test/app_support.dart';

Map<String, Object?> _row(int id, String title) => {
  'id': id,
  'title': title,
  'list_id': 'l1',
  'done': false,
  'priority': 'low',
  'created_at': '2026-11-10T08:00:00Z',
  'version': 1,
};

void _expect(MockHttpTransport transport) {
  transport.reset();
  transport
      .when(HttpMethod.get, '/rest/v1/todos')
      .respond(200, json: [_row(1, 'Buy milk'), _row(2, 'Bread')]);
  transport
      .when(HttpMethod.post, '/functions/v1/send-invite')
      .respond(200, json: {'id': 'inv-1'});
}

Future<double> _perCall(
  MockHttpTransport transport,
  Future<void> Function() call,
  int count,
) async {
  _expect(transport);
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    await call();
  }
  return watch.elapsedMicroseconds / count;
}

Future<double> _median(
  MockHttpTransport transport,
  Future<void> Function() call,
  int count,
) async {
  await _perCall(transport, call, count ~/ 4);
  final runs = [
    for (var r = 0; r < 5; r++) await _perCall(transport, call, count),
  ]..sort();
  return runs[2];
}

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 20000 : int.parse(args.first);
  final transport = MockHttpTransport();
  _expect(transport);
  await appRunner(transport).runAsync((context) async {
    final failure = context.startupFailure;
    if (failure != null) {
      throw StateError('The application did not start: $failure');
    }
    final todos = context.getBean<Todos>();
    final functions = context.getBean<Functions>();
    final invite = Invite(email: 'a@b.c');

    Future<void> select() async {
      final rows = await todos.findByDoneOrderByCreatedAtDesc(false);
      if (rows.length != 2) {
        throw StateError('${rows.length} rows');
      }
    }

    Future<void> function() async {
      final result = await functions.sendInvite(invite);
      if (result.id != 'inv-1') {
        throw StateError(result.id);
      }
    }

    final selectMicros = await _median(transport, select, count);
    final functionMicros = await _median(transport, function, count);
    stdout
      ..writeln('REST select:   ${selectMicros.toStringAsFixed(2)} us')
      ..writeln('Edge Function: ${functionMicros.toStringAsFixed(2)} us');
  });
}
