// The classes that describe the web starter's properties are the ones that
// read them: the defaults of a class equal the defaults of the settings the
// server, the sessions and the uploads use, and a value is bound from any
// spelling of its key.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_web/src/config/config.dart';
import 'package:test/test.dart';

ConfigurableEnvironment _environment(Map<String, Object> properties) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', properties));

void main() {
  group('defaults', () {
    test('of server.* are those of ServerProperties', () {
      final bound = ServerProperties.from(ServerSettings());
      const plain = ServerProperties();
      expect(bound.port, plain.port);
      expect(bound.address, plain.address);
      expect(bound.shutdown, plain.shutdown);
      expect(bound.ssl, plain.ssl);
      expect(bound.contextPath, plain.contextPath);
      expect(bound.maxRequestBodySize, plain.maxRequestBodySize);
      expect(bound.compression, plain.compression);
      expect(bound.compressionMimeTypes, plain.compressionMimeTypes);
      expect(
        bound.compressionMinResponseSize,
        plain.compressionMinResponseSize,
      );
      expect(
        bound.webSocketMaxTextMessageSize,
        plain.webSocketMaxTextMessageSize,
      );
      expect(
        bound.webSocketMaxBinaryMessageSize,
        plain.webSocketMaxBinaryMessageSize,
      );
      expect(
        bound.webSocketSendBufferSizeLimit,
        plain.webSocketSendBufferSizeLimit,
      );
      expect(bound.webSocketSendTimeLimit, plain.webSocketSendTimeLimit);
      expect(bound.connectionTimeout, plain.connectionTimeout);
      expect(bound.requestTimeout, plain.requestTimeout);
    });

    test('of server.session.* are those of HttpSessionProperties', () {
      final bound = HttpSessionProperties.from(ServerSessionSettings());
      const plain = HttpSessionProperties();
      expect(bound.timeout, plain.timeout);
      expect(bound.cookieName, plain.cookieName);
      expect(bound.cookiePath, '/');
      expect(bound.cookieDomain, plain.cookieDomain);
      expect(bound.httpOnly, plain.httpOnly);
      expect(bound.secure, plain.secure);
      expect(bound.sameSite, plain.sameSite);
      expect(bound.maxSessions, plain.maxSessions);
    });

    test('of spring.web.multipart.* are those of MultipartProperties', () {
      final bound = MultipartProperties.from(MultipartSettings());
      const plain = MultipartProperties();
      expect(bound.enabled, plain.enabled);
      expect(bound.maxFileSize, plain.maxFileSize);
      expect(bound.maxRequestSize, plain.maxRequestSize);
      expect(bound.maxPartCount, plain.maxPartCount);
      expect(bound.fileSizeThreshold, plain.fileSizeThreshold);
      expect(bound.location, plain.location);
    });
  });

  group('binding', () {
    test('reads server.* in any spelling', () {
      final properties = ServerProperties.of(
        _environment({
          'server.port': '9090',
          'server.contextPath': 'shop/',
          'server.shutdown': 'immediate',
          'server.max-http-request-body-size': '2MB',
          'server.compression.enabled': 'true',
          'server.compression.mime-types': 'Text/HTML, application/json',
          'server.websocket.send-time-limit': '-1',
          'server.connection-timeout': '5s',
          'server.ssl.certificate': 'cert.pem',
          'server.ssl.certificate-private-key': 'key.pem',
          'server.ssl.client-auth': 'need',
        }),
      );
      expect(properties.port, 9090);
      expect(properties.contextPath, '/shop');
      expect(properties.shutdown, Shutdown.immediate);
      expect(properties.maxRequestBodySize, 2 * 1024 * 1024);
      expect(properties.compression, isTrue);
      expect(properties.compressionMimeTypes, [
        'text/html',
        'application/json',
      ]);
      expect(properties.webSocketSendTimeLimit, isNull);
      expect(properties.connectionTimeout, const Duration(seconds: 5));
      expect(properties.ssl?.clientAuth, ClientAuth.need);
    });

    test('a certificate needs its private key', () {
      expect(
        () => ServerProperties.of(
          _environment({'server.ssl.certificate': 'cert.pem'}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'server.ssl.certificate needs server.ssl.certificate-private-key',
          ),
        ),
      );
    });

    test('a value that does not fit fails, naming the property', () {
      for (final property in [
        'server.port=abc',
        'server.shutdown=never',
        'server.ssl.client-auth=sometimes',
        'server.session.cookie.same-site=wild',
        'server.forward-headers-strategy=always',
      ]) {
        final parts = property.split('=');
        expect(
          () => bindServerSettings(_environment({parts[0]: parts[1]})),
          throwsA(
            isA<Object>().having(
              (e) => '$e',
              'message',
              contains(parts[0]),
            ),
          ),
          reason: property,
        );
      }
    });

    test('the session timeout without a unit is seconds', () {
      final properties = HttpSessionProperties.of(
        _environment({'server.session.timeout': '90'}),
      );
      expect(properties.timeout, const Duration(seconds: 90));
    });

    test('reads spring.web.multipart.*', () {
      final properties = MultipartProperties.of(
        _environment({
          'spring.web.multipart.max-file-size': '-1',
          'spring.web.multipart.max-part-count': '7',
          'spring.web.multipart.enabled': 'false',
          'spring.web.multipart.location': ' ',
        }),
      );
      expect(properties.maxFileSize, -1);
      expect(properties.maxPartCount, 7);
      expect(properties.enabled, isFalse);
      expect(properties.location, isNull);
    });
  });
}
