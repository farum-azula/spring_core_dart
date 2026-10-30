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

  // A hot restart while a login's window is open: the first login of the
  // new isolate (replaceStale) cancels the replaced one and runs, on
  // Android in the replaced login's window (singleTask: the same
  // activity gets the new page). Before 0.5.0's fix that window cancelled
  // the new login at once.
  testWidgets(
    'a login after a hot restart completes while the old window is open',
    (_) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var waiting = 0;
      server.listen((request) async {
        final query = request.uri.queryParameters;
        if (request.uri.path != '/authorize') {
          request.response.statusCode = HttpStatus.notFound; // favicon.ico
        } else if (query['state'] == 'state-stale') {
          waiting++;
          // The provider's page, where the replaced code's user never
          // finishes.
          request.response
            ..headers.contentType = ContentType.html
            ..write('<html><body>Signing in...</body></html>');
        } else {
          final redirect = Uri.parse(query['redirect_uri']!).replace(
            queryParameters: {'code': 'code-3', 'state': query['state']!},
          );
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '$redirect');
        }
        await request.response.close();
      });
      const window = PlatformAuthorizationWindow(preferEphemeralSession: true);
      Uri page(Uri redirectUri, String state) => Uri.http(
        '127.0.0.1:${server.port}',
        '/authorize',
        {'redirect_uri': '$redirectUri', 'state': state},
      );
      final redirectUri = Uri.parse('books.neon.app:/oauth2/callback');

      final stale = window
          .authorize(
            redirectUri: redirectUri,
            authorizationUri: (redirect) => page(redirect, 'state-stale'),
          )
          .then<Object>((uri) => uri, onError: (Object e) => e);
      while (waiting == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await Future<void>.delayed(const Duration(seconds: 2)); // the page is up

      PlatformAuthorizationWindow.debugResetIsolate(); // a hot restart
      final fresh = await window
          .authorize(
            redirectUri: redirectUri,
            authorizationUri: (redirect) => page(redirect, 'state-fresh'),
          )
          .timeout(const Duration(seconds: 60));
      expect(fresh.queryParameters, {'code': 'code-3', 'state': 'state-fresh'});
      // The replaced login was answered (nobody hears it after a real
      // hot restart).
      expect(await stale, isA<AuthorizationCancelledException>());
    },
    skip: !Platform.isAndroid && !Platform.isIOS,
  );

  // Android: the window destroyed without an answer (a singleTask main
  // activity, a CLEAR_TOP intent, its task removed) ends the login as
  // cancelled; it never waits forever. The host removes the window's task
  // when the test prints its marker:
  //   example/flutter_guide/integration_test/remove_login_task.sh
  testWidgets(
    'Android: a login whose window is destroyed is cancelled',
    (_) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var asked = 0;
      server.listen((request) async {
        final query = request.uri.queryParameters;
        if (request.uri.path != '/authorize') {
          request.response.statusCode = HttpStatus.notFound; // favicon.ico
        } else if (query['state'] == 'state-wait') {
          asked++;
          // The provider's page, where the user never finishes.
          request.response
            ..headers.contentType = ContentType.html
            ..write('<html><body>Signing in...</body></html>');
        } else {
          final redirect = Uri.parse(query['redirect_uri']!).replace(
            queryParameters: {'code': 'code-2', 'state': query['state']!},
          );
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '$redirect');
        }
        await request.response.close();
      });
      const window = PlatformAuthorizationWindow();
      Uri page(Uri redirectUri, String state) => Uri.http(
        '127.0.0.1:${server.port}',
        '/authorize',
        {'redirect_uri': '$redirectUri', 'state': state},
      );
      final redirectUri = Uri.parse('books.neon.app:/oauth2/callback');

      final waiting = window.authorize(
        redirectUri: redirectUri,
        authorizationUri: (redirect) => page(redirect, 'state-wait'),
      );
      // The host waits for the page, then removes the window's task.
      while (asked == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      // ignore: avoid_print
      print('SPRING_TEST_LOGIN_WINDOW_OPEN');
      await expectLater(
        waiting.timeout(const Duration(seconds: 90)),
        throwsA(isA<AuthorizationCancelledException>()),
      );

      // Not left "in progress": the next login runs.
      final next = await window.authorize(
        redirectUri: redirectUri,
        authorizationUri: (redirect) => page(redirect, 'state-2'),
      );
      expect(next.queryParameters, {'code': 'code-2', 'state': 'state-2'});
    },
    skip:
        !Platform.isAndroid ||
        const bool.fromEnvironment('SPRING_TEST_REMOVE_TASK') == false,
  );
}
