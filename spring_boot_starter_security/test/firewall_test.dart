// StrictHttpFirewall on its own, with request paths as a server might hand
// them over without normalizing them. dart:io and MockMvc resolve `.`,
// `..` and `%2E` before the application (Uri.parse, RFC 3986), so these
// checks are a second line there; another server (or a decorator changing
// the path) must still be refused.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

/// A request whose [path] is exactly the given text.
final class _RawPathRequest extends ServerHttpRequestDecorator {
  _RawPathRequest(this.path)
    : super(MockServerHttpRequest(HttpMethod.get, '/'));

  @override
  final String path;
}

/// A request whose target is exactly [uri], whatever its path says.
final class _RawUriRequest extends ServerHttpRequestDecorator {
  _RawUriRequest(this.uri) : super(MockServerHttpRequest(HttpMethod.get, '/'));

  @override
  final Uri uri;
}

void main() {
  final firewall = StrictHttpFirewall();

  group('raw paths', () {
    for (final path in [
      '/api/./admin',
      '/api/../admin',
      '/public/..',
      '/api/admin%2E',
      '/api/%2e%2e/admin',
      '/api/admin;x',
      '/api%2Fadmin',
      r'/api\admin',
      '/api/admin%25',
      '/api//admin',
      '/api/admin%00',
      '/api/admin%0A',
      '/api/ admin',
      '/api/über',
      '/api/\u0007',
      '/api/\u007f',
      '/api/x\u0020',
    ]) {
      test('$path is refused', () {
        expect(
          () => firewall.check(_RawPathRequest(path)),
          throwsA(isA<RequestRejectedException>()),
        );
      });
    }

    test('clean paths pass', () {
      for (final path in [
        '/',
        '/api/admin',
        '/a-b_c.d~e/%41',
        '/x/{y}',
        '/a!b',
        '/~',
        '/!',
      ]) {
        firewall.check(_RawPathRequest(path));
      }
    });
  });

  group('each allowance lets only its own form through', () {
    test('allowUrlEncodedPeriod', () {
      final relaxed = StrictHttpFirewall(allowUrlEncodedPeriod: true)
        ..check(_RawPathRequest('/api/v1%2E2'));
      // A `.` segment is still not normalized.
      expect(
        () => relaxed.check(_RawPathRequest('/api/./admin')),
        throwsA(isA<RequestRejectedException>()),
      );
      expect(
        () => relaxed.check(_RawPathRequest('/api;x')),
        throwsA(isA<RequestRejectedException>()),
      );
    });

    test('allowSemicolon', () {
      final relaxed = StrictHttpFirewall(allowSemicolon: true)
        ..check(_RawPathRequest('/api;x'));
      expect(
        () => relaxed.check(_RawPathRequest('/api%2Fx')),
        throwsA(isA<RequestRejectedException>()),
      );
    });

    test('allowUrlEncodedSlash, allowBackSlash, allowUrlEncodedPercent', () {
      StrictHttpFirewall(allowUrlEncodedSlash: true)
          .check(_RawPathRequest('/api%2Fx'));
      StrictHttpFirewall(allowBackSlash: true)
          .check(_RawPathRequest('/api%5Cx'));
      StrictHttpFirewall(allowUrlEncodedPercent: true)
          .check(_RawPathRequest('/api%25x'));
    });

    test('allowedMethods replaces the list', () {
      final getOnly = StrictHttpFirewall(allowedMethods: {HttpMethod.get})
        ..check(MockServerHttpRequest(HttpMethod.get, '/'));
      expect(
        () => getOnly.check(MockServerHttpRequest(HttpMethod.post, '/')),
        throwsA(isA<RequestRejectedException>()),
      );
    });
  });

  group('headers', () {
    test('a name with a space or a control character is refused', () {
      for (final name in ['bad name', 'x\u0001', 'café']) {
        final request = MockServerHttpRequest(HttpMethod.get, '/')
          ..headers.set(name, 'v');
        expect(
          () => firewall.check(request),
          throwsA(isA<RequestRejectedException>()),
          reason: name,
        );
      }
    });

    test('a name of the whole printable range passes', () {
      final request = MockServerHttpRequest(HttpMethod.get, '/')
        ..headers.set('!x~', 'v');
      firewall.check(request);
    });

    test('values: tabs and spaces pass, control characters and line '
        'separators do not', () {
      final ok = MockServerHttpRequest(HttpMethod.get, '/')
        ..headers.set('x-a', 'a b\tc');
      firewall.check(ok);
      for (final value in [
        'a\nb',
        'a\rb',
        'a\u0000',
        'a\u001f',
        'a\u007f',
        'a\u2028',
        'a\u2029',
      ]) {
        final request = MockServerHttpRequest(HttpMethod.get, '/')
          ..headers.set('x-a', value);
        expect(
          () => firewall.check(request),
          throwsA(isA<RequestRejectedException>()),
          reason: value.codeUnits.toString(),
        );
      }
    });
  });

  group('the request target', () {
    test('a network-path reference (//host/path) is not a path', () {
      expect(
        () => firewall.check(_RawUriRequest(Uri.parse('//evil.example/admin'))),
        throwsA(
          isA<RequestRejectedException>().having(
            (e) => e.reason,
            'reason',
            contains('//evil.example'),
          ),
        ),
      );
    });

    test('an absolute URI with a scheme passes (the path is checked)', () {
      firewall.check(_RawUriRequest(Uri.parse('https://example.org/api/x')));
      expect(
        () => firewall.check(
          _RawUriRequest(Uri.parse('https://example.org/api;x')),
        ),
        throwsA(isA<RequestRejectedException>()),
      );
    });
  });
}
