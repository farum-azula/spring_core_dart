// Starts the test application on a free port and sends requests to it with
// dart:io's HttpClient; the same application for springBootTest.
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'app/app.dart';

/// The application context runner of the test app.
ApplicationContextRunner webRunner([List<String> properties = const []]) =>
    const ApplicationContextRunner()
        .withUserConfiguration(webTestBeans)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues([
          'spring.test.web-environment=random-port',
          'server.address=127.0.0.1',
          'logging.level.root=warn',
          ...properties,
        ]);

/// A response read whole.
final class Reply {
  Reply(this.status, this.headers, this.body);

  final int status;
  final io.HttpHeaders headers;
  final String body;

  Object? get json => jsonDecode(body);

  @override
  String toString() => '$status $body';
}

/// Sends requests to the server of [context].
final class Client {
  Client(this.port);

  static Future<Client> of(ApplicationContext context) async {
    final server = await context.getBean<WebServerStartStopLifecycle>().started;
    return Client(server!.port);
  }

  final int port;
  final _http = io.HttpClient();

  Uri uri(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<Reply> send(
    String method,
    String path, {
    Object? json,
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await _http.openUrl(method, uri(path));
    headers.forEach(request.headers.set);
    if (json != null) {
      request.headers.contentType = io.ContentType.json;
      request.write(jsonEncode(json));
    } else if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return Reply(response.statusCode, response.headers, text);
  }

  Future<Reply> get(String path, {Map<String, String> headers = const {}}) =>
      send('GET', path, headers: headers);

  Future<io.HttpClientResponse> open(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final request = await _http.getUrl(uri(path));
    headers.forEach(request.headers.set);
    return request.close();
  }

  void close() => _http.close(force: true);
}

/// The test application for springBootTest.
final testApplication = SpringApplication(
  [webTestBeans],
  autoConfigurations: [
    springBootAutoConfiguration,
    springBootStarterLoggingAutoConfiguration,
    springBootStarterWebAutoConfiguration,
    springBootStarterWebsocketAutoConfiguration,
  ],
);
