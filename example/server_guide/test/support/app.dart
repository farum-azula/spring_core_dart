// What the tests share: the application with the test profile, and a
// client that keeps cookies like the Flutter app does.
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

import '../../bin/main.spring.dart';

/// The whole application (`dev` sample data, `test` settings from
/// test/resources/application-test.properties), once for the tests of
/// the calling `main` or `group`.
SpringBootTestContext neonBooks({
  List<String> profiles = const ['dev', 'test'],
  Map<String, Object?> properties = const {},
  Map<String, String> systemEnvironment = const {},
  List<BeanOverride<Object>> overrides = const [],
  WebEnvironment webEnvironment = WebEnvironment.mock,
}) => springBootTest(
  springApplication,
  profiles: profiles,
  properties: properties,
  systemEnvironment: systemEnvironment,
  overrides: overrides,
  webEnvironment: webEnvironment,
);

/// A client of the API as the Flutter app is one: it keeps the cookies
/// the server sets (`JSESSIONID`, `XSRF-TOKEN`) and sends the CSRF token
/// back in `X-XSRF-TOKEN` on POST, PUT and DELETE (Spring's single-page
/// app recipe). Through MockMvc: the real filters, no socket.
final class ApiClient {
  ApiClient(this.mvc);

  final MockMvc mvc;
  final cookies = <String, String>{};

  String? get csrfToken => cookies['XSRF-TOKEN'];
  String? get sessionId => cookies['JSESSIONID'];

  /// Sends a request; [json] as the body, [form] as a url-encoded form.
  Future<MvcResult> send(
    HttpMethod method,
    String path, {
    Object? json,
    Map<String, String>? form,
    Map<String, String> headers = const {},
    bool withCsrf = true,
  }) async {
    final builder = MockRequestBuilder(method, path)
      ..headers.addAll(headers)
      ..cookies.addAll(cookies);
    if (withCsrf && method != HttpMethod.get && csrfToken != null) {
      builder.headers['X-XSRF-TOKEN'] = csrfToken!;
    }
    if (json != null) {
      builder.json(json);
    } else if (form != null) {
      builder
        ..headers[HttpHeaders.contentTypeHeader] =
            MediaType.applicationFormUrlencoded
        ..content(Uri(queryParameters: form).query);
    }
    final result = await mvc.perform(builder).andReturn();
    for (final cookie in result.response.cookies) {
      if (cookie.value.isEmpty) {
        cookies.remove(cookie.name);
      } else {
        cookies[cookie.name] = cookie.value;
      }
    }
    return result;
  }

  Future<MvcResult> get(
    String path, {
    Map<String, String> headers = const {},
  }) => send(HttpMethod.get, path, headers: headers);

  /// What the app does: fetch anything first (the CSRF cookie comes
  /// with every response), post the login form, then read `/api/me` (the
  /// token changes at login; the new cookie comes with this response).
  Future<int> login(String username, String password) async {
    if (csrfToken == null) {
      await get('/api/books');
    }
    final login = await send(
      HttpMethod.post,
      '/api/login',
      form: {'username': username, 'password': password},
    );
    if (login.response.statusCode == HttpStatus.noContent) {
      await get('/api/me');
    }
    return login.response.statusCode;
  }
}

/// The JSON body of [result].
Object? jsonOf(MvcResult result) => jsonDecode(result.response.bodyText);
