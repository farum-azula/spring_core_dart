// Starts a test application (the shared controllers and one security
// configuration) and calls it through MockMvc: the same dispatcher, filters
// and security chain a real server uses, without a socket.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/web/web.dart';

/// The runner of the controllers with [configuration] (a security module).
ApplicationContextRunner securityRunner(
  BeanModule? configuration, [
  List<String> properties = const [],
]) {
  var runner = const ApplicationContextRunner()
      .withUserConfiguration(securityWebBeans)
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebAutoConfiguration)
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(springBootStarterSecurityAutoConfiguration)
      .withPropertyValues([
        'spring.test.web-environment=mock',
        'logging.level.root=warn',
        ...properties,
      ]);
  if (configuration != null) {
    runner = runner.withUserConfiguration(configuration);
  }
  return runner;
}

/// Runs [body] with a started application of [configuration].
Future<void> withApp(
  BeanModule? configuration,
  Future<void> Function(MockMvc mvc, ApplicationContext context) body, {
  List<String> properties = const [],
}) => securityRunner(configuration, properties).runAsync((started) async {
  final failure = started.startupFailure;
  if (failure != null) {
    fail('The application failed to start: $failure');
  }
  await body(MockMvc.of(started.context), started.context);
});

/// A request to [path] with [headers] and [processors].
MockRequestBuilder request(
  HttpMethod method,
  String path, {
  Map<String, String> headers = const {},
  List<RequestPostProcessor> processors = const [],
  String? body,
  String? contentType,
}) {
  final builder = MockRequestBuilder(method, path)..headers.addAll(headers);
  if (body != null) {
    builder.content(body);
  }
  if (contentType != null) {
    builder.headers['content-type'] = contentType;
  }
  processors.forEach(builder.with_);
  return builder;
}

/// `Authorization: Basic` for [user] / [password].
Map<String, String> basic(String user, String password) => {
  'authorization': 'Basic ${base64.encode(utf8.encode('$user:$password'))}',
};

/// The status of a response.
extension ResultStatus on MvcResult {
  /// The status code.
  int get status => response.statusCode;

  /// A header.
  String? header(String name) => response.headers[name];
}

/// A browser over MockMvc: keeps cookies, sends them back.
final class Browser {
  /// A browser calling [mvc].
  Browser(this.mvc);

  /// The application.
  final MockMvc mvc;

  /// The cookies it holds.
  final cookies = <String, String>{};

  /// Performs a request with the cookies; stores the cookies set.
  Future<MvcResult> send(
    HttpMethod method,
    String path, {
    Map<String, String> headers = const {},
    Map<String, String>? form,
    String accept = 'text/html',
  }) async {
    final builder = MockRequestBuilder(method, path)
      ..headers['accept'] = accept
      ..headers.addAll(headers);
    if (cookies.isNotEmpty) {
      builder.headers['cookie'] = [
        for (final MapEntry(:key, :value) in cookies.entries) '$key=$value',
      ].join('; ');
    }
    if (form != null) {
      builder
        ..headers['content-type'] = 'application/x-www-form-urlencoded'
        ..content(
          [
            for (final MapEntry(:key, :value) in form.entries)
              [
                Uri.encodeQueryComponent(key),
                Uri.encodeQueryComponent(value),
              ].join('='),
          ].join('&'),
        );
    }
    final result = await mvc.perform(builder);
    for (final cookie in result.response.cookies) {
      if (cookie.maxAge == Duration.zero) {
        cookies.remove(cookie.name);
      } else {
        cookies[cookie.name] = cookie.value;
      }
    }
    return result;
  }

  /// GET [path].
  Future<MvcResult> get(String path, {String accept = 'text/html'}) =>
      send(HttpMethod.get, path, accept: accept);

  /// The hidden `_csrf` field of [html].
  static String csrfField(String html) =>
      RegExp('name="_csrf" type="hidden" value="([^"]+)"')
          .firstMatch(html)![1]!;
}
