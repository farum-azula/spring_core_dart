// What a RestClient call costs on top of the bare HttpTransport: a GET of
// a URI template with one variable whose JSON answer is read into a map,
// the same with the template without variables, and a POST of a JSON
// body, against the same call written by hand on the transport as the
// family's code does it today (the URL built, a status check, the JSON
// written and read with the same ObjectMapper). The transport answers at
// once, so only the client's own work is measured. Not part of the tests; run
// with
//   dart run benchmark/rest_client_benchmark.dart
//   dart compile exe benchmark/rest_client_benchmark.dart -o /tmp/rc && /tmp/rc
//
// November 2026, Apple M5, AOT, microseconds per call (medians of 5 runs
// of 200 000 calls), bare / RestClient:
//   GET, template with a variable: 1.54 / 1.85 (+0.31)
//   GET, template without one:     1.48 / 1.63 (+0.15)
//   POST, a JSON body:             2.16 / 2.37 (+0.21)
// The ObjectMapper reading the map is most of either (0.62 us, against
// 0.14 us for jsonDecode alone).

import 'dart:convert';
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _json = MapType<String, Object?>(ClassType<String>(), DynamicType());

final class _Instant implements HttpTransport {
  _Instant(this.body);

  final List<int> body;
  final _headers = HttpHeaders({'Content-Type': 'application/json'});

  @override
  Future<HttpResponse> send(HttpRequest request) async =>
      HttpResponse(200, headers: _headers, body: body, request: request);

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnsupportedError('not measured');

  @override
  void close() {}
}

Future<double> _perCall(Future<void> Function(int i) call, int count) async {
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    await call(i);
  }
  return watch.elapsedMicroseconds / count;
}

Future<double> _median(Future<void> Function(int i) call, int count) async {
  await _perCall(call, count ~/ 4);
  final runs = [for (var r = 0; r < 5; r++) await _perCall(call, count)]
    ..sort();
  return runs[2];
}

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 200000 : int.parse(args.first);
  final transport = _Instant(utf8.encode('{"isbn":"1","title":"Dune"}'));
  const base = 'https://api.neon.books/v1';
  final rest = RestClient.builder().baseUrl(base).transport(transport).build();
  final payload = {'isbn': '1', 'title': 'Dune'};
  final mapper = ObjectMapper();

  Future<void> bareGet(int i) async {
    final response = await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('$base/books/${Uri.encodeComponent('$i')}'),
      ),
    );
    if (!response.isSuccess) {
      throw StateError('${response.statusCode}');
    }
    mapper.readValue(response.bodyText, _json);
  }

  Future<void> bareConstant(int i) async {
    final response = await transport.send(
      HttpRequest(method: HttpMethod.get, url: Uri.parse('$base/books')),
    );
    if (!response.isSuccess) {
      throw StateError('${response.statusCode}');
    }
    mapper.readValue(response.bodyText, _json);
  }

  Future<void> barePost(int i) async {
    final response = await transport.send(
      HttpRequest(
        method: HttpMethod.post,
        url: Uri.parse('$base/books'),
        headers: HttpHeaders({'Content-Type': 'application/json'}),
        body: utf8.encode(mapper.writeValueAsString(payload)),
      ),
    );
    if (!response.isSuccess) {
      throw StateError('${response.statusCode}');
    }
    mapper.readValue(response.bodyText, _json);
  }

  Future<void> restGet(int i) =>
      rest.get().uri('/books/{isbn}', [i]).retrieve().body(_json);

  Future<void> restConstant(int i) =>
      rest.get().uri('/books').retrieve().body(_json);

  Future<void> restPost(int i) =>
      rest.post().uri('/books').body(payload).retrieve().body(_json);

  final results = {
    'GET, template with a variable': (
      await _median(bareGet, count),
      await _median(restGet, count),
    ),
    'GET, template without one': (
      await _median(bareConstant, count),
      await _median(restConstant, count),
    ),
    'POST, a JSON body': (
      await _median(barePost, count),
      await _median(restPost, count),
    ),
  };
  for (final MapEntry(key: name, value: (bare, client)) in results.entries) {
    stdout.writeln(
      '$name: bare ${bare.toStringAsFixed(2)} us, '
      'RestClient ${client.toStringAsFixed(2)} us '
      '(+${(client - bare).toStringAsFixed(2)} us)',
    );
  }
}
