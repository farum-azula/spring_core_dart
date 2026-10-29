// The login window of the platform (ASWebAuthenticationSession on iOS and
// macOS, a Custom Tab on Android) against a stand-in provider: a server
// in the app on 127.0.0.1 whose authorization endpoint redirects at once
// to the app's redirect URI, as a provider does after the user logged in.
//   flutter test integration_test/authorization_window_test.dart -d <device>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the login window returns the redirect with the code', (_) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final query = request.uri.queryParameters;
      final redirect = Uri.parse(query['redirect_uri']!).replace(
        queryParameters: {'code': 'code-1', 'state': query['state']!},
      );
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '$redirect');
      await request.response.close();
    });

    // Ephemeral: iOS asks "wants to use ... to sign in" otherwise.
    const window = PlatformAuthorizationWindow(preferEphemeralSession: true);
    final result = await window.authorize(
      redirectUri: Uri.parse('books.neon.app:/oauth2/callback'),
      authorizationUri: (redirectUri) => Uri.http(
        '127.0.0.1:${server.port}',
        '/authorize',
        {'redirect_uri': '$redirectUri', 'state': 'state-1'},
      ),
    );

    expect(result.scheme, 'books.neon.app');
    expect(result.path, '/oauth2/callback');
    expect(result.queryParameters, {'code': 'code-1', 'state': 'state-1'});
  });
}
