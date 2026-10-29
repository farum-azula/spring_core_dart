// Chapter 7, "Login & roles": the Login screen, the user in Spring
// Security's SecurityContextHolder, @PreAuthorize on the app's services,
// the Admin screen for admins only, logout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/admin/admin_service.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/app/home_page.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_security_core/testing.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

Authentication? get current =>
    SecurityContextHolder.getContext().authentication;

void main() {
  final server = FakeServer();
  final app = springBootTest(springApplication, overrides: server.overrides);

  setUp(() {
    app.markDirty();
    server.http.reset();
    server.answerCatalog();
  });
  tearDown(SecurityContextHolder.clearContext);

  testWidgets('a wrong password: a message, nobody logged in', (tester) async {
    server.http
      ..when(HttpMethod.get, '/api/me').respond(401)
      ..when(HttpMethod.post, '/api/login').respond(401);
    await showPage(tester, app.context, const HomePage());

    await logIn(tester, 'ada', 'wrong');

    expect(find.text('Wrong user name or password'), findsOneWidget);
    expect(current, isNull);
  });

  testWidgets('a USER: in the SecurityContextHolder, no Admin screen', (
    tester,
  ) async {
    server.answerLogin('ada');
    await showPage(tester, app.context, const HomePage());

    await logIn(tester, 'ada', 'ada-secret');

    expect(find.text('ada'), findsOneWidget); // the app bar's account button
    expect(current, isA<UsernamePasswordAuthenticationToken>());
    expect(current!.name, 'ada');
    expect(current!.authorities.map((a) => a.authority), ['ROLE_USER']);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('an ADMIN gets the Admin screen', (tester) async {
    server.answerLogin('root', roles: ['USER', 'ADMIN']);
    await showPage(tester, app.context, const HomePage());

    await logIn(tester, 'root', 'root-secret');
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.byIcon(Icons.admin_panel_settings), findsWidgets);
  });

  test('@PreAuthorize: a USER cannot even send an admin request', () async {
    server.answerLogin('ada');
    await withMockUser(() async {
      await expectLater(
        app.getBean<AdminService>().addBook(NewBook()),
        throwsA(isA<AccessDeniedException>()),
      );
    }, username: 'ada');
    expect(
      server.http.requests.where((request) => request.url.path == '/api/books'),
      isEmpty,
    );
  });

  test('@PreAuthorize: orders need a login', () async {
    await expectLater(
      app.getBean<OrderService>().orders(),
      throwsA(isA<AuthenticationCredentialsNotFoundException>()),
    );
  });

  testWidgets('logout: the server, the context and the cookies', (
    tester,
  ) async {
    server.answerLogin('ada');
    await showPage(tester, app.context, const HomePage());
    await logIn(tester, 'ada', 'ada-secret');

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(current, isNull);
    expect(app.getBean<CookieJar>().header, isNull);
    expect(server.http.lastRequest.url.path, '/api/logout');
    expect(find.widgetWithText(TextButton, 'Log in'), findsOneWidget);
  });
}
