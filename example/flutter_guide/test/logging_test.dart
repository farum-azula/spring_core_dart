// Chapter 10, "Logging": the app logs through SpringLog (@Log), the
// LogBuffer bean keeps the lines in memory, the Logs screen shows them
// filtered by level.
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/logs/logs_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'support/app.dart';
import 'support/fake_server.dart';

void main() {
  final server = FakeServer();
  final app = springBootTest(springApplication, overrides: server.overrides);

  setUp(() {
    app.markDirty();
    server.http.reset();
    server.answerCatalog();
  });

  test('logging.* properties: levels per logger, fields', () {
    final logging = app.getBean<LoggingSystem>();
    expect(logging.rootLevel, SpringLogLevel.info);
    expect(
      const SpringLog('neon.catalog').isEnabled(SpringLogLevel.debug),
      isTrue,
    );
    expect(
      const SpringLog('spring_core_dart').isEnabled(SpringLogLevel.debug),
      isFalse,
    );
  });

  testWidgets('the Logs screen: the buffer, filtered by level', (tester) async {
    final buffer = app.getBean<LogBuffer>()..clear();
    const SpringLog('neon.test').info('an info line');
    const SpringLog('neon.test').warning('a warning line');
    const SpringLog('neon.test').debug('a debug line');

    await showPage(tester, app.context, const LogsPage());
    await tester.pumpAndSettle();
    expect(find.text('an info line'), findsOneWidget);
    expect(find.text('a warning line'), findsOneWidget);
    expect(find.text('a debug line'), findsNothing); // Info and up

    await tester.tap(find.text('Warning'));
    await tester.pumpAndSettle();
    expect(find.text('an info line'), findsNothing);
    expect(find.text('a warning line'), findsOneWidget);

    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    expect(find.text('a debug line'), findsOneWidget);

    // New lines show up as they are logged.
    const SpringLog('neon.test').error('an error line');
    await tester.pumpAndSettle();
    expect(find.text('an error line'), findsOneWidget);
    expect(buffer.counts[SpringLogLevel.error], 1);
  });
}
