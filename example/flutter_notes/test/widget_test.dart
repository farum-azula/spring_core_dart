// The screen and the API share the Notes bean: what one adds, the other
// shows. In memory (springBootTest + MockMvc, no socket), then over real
// HTTP to a server on a free port, and the app started by
// SpringApplicationWidget as `flutter run` does.
//
// Real requests go to the context of springBootTest: it starts outside the
// fake clock of testWidgets, so its server answers while the test waits in
// tester.runAsync.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_notes/main.spring.dart';
import 'package:flutter_notes/src/api/local_api.dart';
import 'package:flutter_notes/src/notes/notes_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

void main() {
  group('springBootTest (MockMvc)', () {
    final app = springBootTest(springApplication);

    setUp(app.markDirty); // fresh notes for every test

    Future<void> showPage(WidgetTester tester) => tester.pumpWidget(
      SpringScope(
        applicationContext: app.context,
        child: const SpringApp(home: NotesPage()),
      ),
    );

    testWidgets('a note posted to the API shows on the screen', (tester) async {
      await showPage(tester);
      expect(find.text('No notes yet'), findsOneWidget);

      await tester.runAsync(
        () => app.mockMvc
            .post('/api/notes', json: {'text': 'Buy milk'})
            .andExpect(
              status: 201,
              headers: {'location': '/api/notes/1'},
              json: containsPair('text', 'Buy milk'),
            ),
      );
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('a note added on the screen is at GET /api/notes', (
      tester,
    ) async {
      await showPage(tester);

      await tester.enterText(find.byKey(const Key('note-text')), 'Call Ada');
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();
      expect(find.text('Call Ada'), findsOneWidget);

      await tester.runAsync(
        () => app.mockMvc
            .get('/api/notes')
            .andExpect(status: 200, json: [containsPair('text', 'Call Ada')]),
      );
      await tester.runAsync(
        () => app.mockMvc
            .get('/api/notes/1')
            .andExpect(status: 200, json: containsPair('id', 1)),
      );
    });

    testWidgets('DELETE removes the note from the screen', (tester) async {
      await showPage(tester);
      await tester.enterText(find.byKey(const Key('note-text')), 'Old');
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();

      await tester.runAsync(
        () => app.mockMvc.delete('/api/notes/1').andExpect(status: 204),
      );
      await tester.pump();

      expect(find.text('Old'), findsNothing);
      expect(find.text('No notes yet'), findsOneWidget);
    });

    test('errors are ProblemDetails', () async {
      await app.mockMvc
          .post('/api/notes', json: {'text': ' '})
          .andExpect(status: 400, contentType: 'application/problem+json');
      await app.mockMvc
          .get('/api/notes/7')
          .andExpect(status: 404, json: containsPair('detail', 'No note 7'));
    });
  });

  group('a real server (WebEnvironment.randomPort)', () {
    final app = springBootTest(
      springApplication,
      webEnvironment: WebEnvironment.randomPort,
    );

    testWidgets('the screen and HTTP requests share the notes', (tester) async {
      await tester.pumpWidget(
        SpringScope(
          applicationContext: app.context,
          child: const SpringApp(home: NotesPage()),
        ),
      );
      final url = 'http://127.0.0.1:${app.localServerPort}/api/notes';
      expect(find.text('GET $url'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('note-text')), 'From the UI');
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();

      final (created, listed) = (await tester.runAsync(() async {
        final client = HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealNetwork(),
        );
        try {
          final post = await client.postUrl(Uri.parse(url));
          post.headers.contentType = ContentType.json;
          post.write(jsonEncode({'text': 'From curl'}));
          final created = await post.close();
          await created.drain<void>();

          final get = await (await client.getUrl(Uri.parse(url))).close();
          final listed = jsonDecode(await get.transform(utf8.decoder).join());
          return (created.statusCode, listed as List<Object?>);
        } finally {
          client.close(force: true);
        }
      }))!;
      await tester.pump();

      expect(created, 201);
      expect(
        [for (final note in listed) (note! as Map)['text']],
        ['From curl', 'From the UI'],
      );
      expect(find.text('From curl'), findsOneWidget);
    });
  });

  testWidgets('SpringApplicationWidget starts the server', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        args: const ['--server.port=0'], // a free port
        home: const NotesPage(),
      ),
    );
    await tester.pumpAndSettle();
    final context = SpringScope.of(
      tester.element(find.byType(Scaffold)),
    ) as ConfigurableApplicationContext;
    final api = context.getBean<LocalApi>();

    // The socket opens asynchronously: wait for the server's address.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && api.url == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(api.url, matches(RegExp(r'^http://127\.0\.0\.1:\d+/api/notes$')));
    expect(find.text('GET ${api.url}'), findsOneWidget);

    // Closes the context: the server closes its socket (real I/O) while
    // the timeouts of the shutdown run on the test's fake clock, so let
    // both go on until the context is closed.
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 100 && context.isActive; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(context.isActive, isFalse);
  });
}

/// flutter_test answers every `HttpClient` request with a 400 and makes no
/// network call; the test talks to the app's own server on 127.0.0.1, so it
/// takes dart:io's client.
final class _RealNetwork extends HttpOverrides {}
