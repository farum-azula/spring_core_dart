import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

// `spring.websocket.client.config.*` with Boot's relaxed names, as in an
// environment prepared by SpringApplication.
void main() {
  WebSocketClientConfig config(
    Map<String, Object?> properties, {
    Map<String, String> system = const {},
  }) {
    final environment = StandardEnvironment(systemEnvironment: system)
      ..propertySources.addFirst(MapPropertySource('test', properties));
    ConfigurationPropertySources.attach(environment);
    return WebSocketClientConfig.of(environment, 'feed');
  }

  test('camelCase keys: connectTimeout, reconnect.maxRetries, '
      'defaultRequestHeaders', () {
    final feed = config({
      'spring.websocket.client.config.default.connectTimeout': '2s',
      'spring.websocket.client.config.feed.reconnect.maxRetries': '3',
      'spring.websocket.client.config.feed.reconnect.maxDelay': '1m',
      'spring.websocket.client.config.feed.defaultRequestHeaders.X-Shop':
          'neon',
      'spring.websocket.client.config.default.default_request_headers.X-Trace':
          't',
    });
    expect(feed.connectTimeout, const Duration(seconds: 2));
    expect(feed.reconnect.maxRetries, 3);
    expect(feed.reconnect.maxDelay, const Duration(minutes: 1));
    expect(feed.defaultRequestHeaders, {
      'X-Trace': ['t'],
      'X-Shop': ['neon'],
    });
  });

  test('default-request-headers lists: X: a,b and X[0], X[1] are two '
      'values', () {
    final feed = config({
      'spring.websocket.client.config.feed.default-request-headers.X-Tags':
          'a,b',
      'spring.websocket.client.config.feed.default-request-headers.X-List[0]':
          'one',
      'spring.websocket.client.config.feed.default-request-headers.X-List[1]':
          'two',
    });
    expect(feed.defaultRequestHeaders, {
      'X-Tags': ['a', 'b'],
      'X-List': ['one', 'two'],
    });
  });

  test('environment variables, below the other sources', () {
    final feed = config(
      {'spring.websocket.client.config.feed.connectTimeout': '1s'},
      system: {
        'SPRING_WEBSOCKET_CLIENT_CONFIG_FEED_CONNECTTIMEOUT': '9s',
        'SPRING_WEBSOCKET_CLIENT_CONFIG_FEED_RECONNECT_MAXRETRIES': '5',
      },
    );
    expect(feed.connectTimeout, const Duration(seconds: 1));
    expect(feed.reconnect.maxRetries, 5);
  });
}
