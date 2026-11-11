// A small load on a running function: so many clients ask one address
// one request after the other for so long, and the rate, the latencies
// and the statuses are printed.
//
//   dart run tool/function_load.dart http://127.0.0.1:8787/hello
//   dart run tool/function_load.dart <url> --clients 32 --seconds 20 \
//     --bearer <token> --method POST --body '{"title":"x","listId":"y"}'
//
// It measures the function where it runs (a local runtime, a deployed
// function); the server's own load tests are tool/load.dart of the
// repository.

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'dart run tool/function_load.dart <url> [--clients 16] '
      '[--seconds 10] [--bearer <token>] [--method GET] [--body <text>]',
    );
    exit(64);
  }
  final url = Uri.parse(args.first);
  String? option(String name) {
    final at = args.indexOf('--$name');
    return at < 0 || at + 1 >= args.length ? null : args[at + 1];
  }

  final clients = int.parse(option('clients') ?? '16');
  final seconds = int.parse(option('seconds') ?? '10');
  final bearer = option('bearer');
  final method = option('method') ?? 'GET';
  final body = option('body');
  final client = HttpClient()..maxConnectionsPerHost = clients;
  final latencies = <int>[];
  final statuses = <int, int>{};
  var failures = 0;
  final watch = Stopwatch()..start();
  final end = Duration(seconds: seconds);

  Future<void> run() async {
    while (watch.elapsed < end) {
      final started = watch.elapsedMicroseconds;
      try {
        final request = await client.openUrl(method, url);
        if (bearer != null) {
          request.headers.set('authorization', 'Bearer $bearer');
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(body));
        }
        final response = await request.close();
        await response.drain<void>();
        statuses.update(response.statusCode, (n) => n + 1, ifAbsent: () => 1);
        latencies.add(watch.elapsedMicroseconds - started);
      } on Object {
        failures++;
      }
    }
  }

  await Future.wait([for (var i = 0; i < clients; i++) run()]);
  client.close(force: true);
  latencies.sort();
  String at(double share) => latencies.isEmpty
      ? '-'
      : (latencies[((latencies.length - 1) * share).round()] / 1000)
            .toStringAsFixed(1);
  final took = watch.elapsedMilliseconds / 1000;
  print(
    '$method $url: $clients clients, ${took.toStringAsFixed(1)} s\n'
    '  ${(latencies.length / took).toStringAsFixed(0)} requests/s '
    '(${latencies.length} answered, $failures failed)\n'
    '  latency ms: p50 ${at(0.5)}, p95 ${at(0.95)}, p99 ${at(0.99)}, '
    'max ${at(1)}\n'
    '  statuses: $statuses',
  );
}
