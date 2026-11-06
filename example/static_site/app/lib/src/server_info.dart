import 'dart:convert';

import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// The network: the browser's `fetch` on the web. Tests replace this bean
/// with a `MockHttpTransport`.
@Configuration()
class NetworkConfig {
  @Bean()
  HttpTransport httpTransport() => platformHttpTransport();
}

/// What the server says about itself (`GET /api/info`).
final class ServerInfo {
  const ServerInfo({required this.name, required this.time});

  ServerInfo.fromJson(Map<String, Object?> json)
    : name = json['name']! as String,
      time = DateTime.parse(json['time']! as String);

  final String name;
  final DateTime time;
}

/// Asks the server the page came from: `/api/info` on the page's own
/// origin, so the site and its API need no CORS and no address in the
/// configuration.
@Service()
class ServerInfoClient {
  ServerInfoClient(this._transport);

  final HttpTransport _transport;

  Future<ServerInfo> fetch() async {
    final response = await _transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.base.resolve('/api/info'),
        headers: HttpHeaders({'Accept': 'application/json'}),
        timeout: const Duration(seconds: 10),
      ),
    );
    if (response.statusCode != 200) {
      throw StateError('GET /api/info answered ${response.statusCode}');
    }
    return ServerInfo.fromJson(
      jsonDecode(response.bodyText) as Map<String, Object?>,
    );
  }
}
