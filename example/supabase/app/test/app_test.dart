// The whole app on a project played in memory (test/support/
// fake_project.dart): sign-up and sign-in, the live list, the avatar and
// the Edge Function, each as the signed-in user.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart'
    show HttpMethod, SupabaseAuth, SupabaseCredentials;
import 'package:supabase_example_app/src/account/login_page.dart';
import 'package:supabase_example_app/src/todos/todo_list.dart';

import 'support/app.dart';

void main() {
  late FakeProject project;

  setUp(() => project = FakeProject());

  group('the login', () {
    testWidgets('nobody signed in: the login page, nothing asked of the '
        'database', (tester) async {
      await startApp(tester, project);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(TodoList), findsNothing);
      expect(project.sent(HttpMethod.get, '/rest/v1/'), isEmpty);
      await stopApp(tester);
    });

    testWidgets('sign-in with an email and a password: the user is Spring '
        "Security's, every call carries their token", (tester) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      final context = await startApp(tester, project);

      await fillLogin(tester, 'ada@example.com', 'correct horse');

      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(context.getBean<SupabaseAuth>().user?.id, id);
      expect(
        context.getBean<SupabaseCredentials>().caller.toString(),
        'user:$id',
      );
      final query = project.sent(HttpMethod.get, '/rest/v1/todos').last;
      expect(query.headers['Authorization'], 'Bearer token-of-$id');
      expect(query.headers['apikey'], FakeProject.anonKey);
      expect(
        Uri.decodeFull(query.url.query),
        allOf(contains('list_id=eq.home'), contains('order=id.asc')),
      );
      await stopApp(tester);
    });

    testWidgets('a wrong password: the form says so, nobody is signed '
        'in', (tester) async {
      project.addUser('ada@example.com', 'correct horse');
      final context = await startApp(tester, project);

      await fillLogin(tester, 'ada@example.com', 'wrong');

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(context.getBean<SupabaseAuth>().isLoggedIn, isFalse);
      await stopApp(tester);
    });

    testWidgets('sign-up: a new user is signed in at once', (tester) async {
      final context = await startApp(tester, project);

      await tester.tap(find.byKey(const Key('login-mode')));
      await tester.pump();
      await fillLogin(
        tester,
        'grace@example.com',
        'hopper-1906',
        submit: 'Create account',
      );

      expect(find.byType(TodoList), findsOneWidget);
      expect(
        context.getBean<SupabaseAuth>().user?.id,
        project.idOf('grace@example.com'),
      );
      await stopApp(tester);
    });

    testWidgets('sign-up in a project that confirms addresses: nobody is '
        'signed in yet', (tester) async {
      project.confirmEmail = true;
      await startApp(tester, project);

      await tester.tap(find.byKey(const Key('login-mode')));
      await tester.pump();
      await fillLogin(
        tester,
        'grace@example.com',
        'hopper-1906',
        submit: 'Create account',
      );

      expect(find.byKey(const Key('login-notice')), findsOneWidget);
      expect(find.byType(TodoList), findsNothing);
      await stopApp(tester);
    });

    testWidgets('a password the project finds too short', (tester) async {
      await startApp(tester, project);

      await tester.tap(find.byKey(const Key('login-mode')));
      await tester.pump();
      await fillLogin(
        tester,
        'grace@example.com',
        'abc',
        submit: 'Create account',
      );

      expect(find.textContaining('longer password'), findsOneWidget);
      await stopApp(tester);
    });

    testWidgets('sign-out: back to the login, the connection to Realtime '
        'closed', (tester) async {
      project.addUser('ada@example.com', 'correct horse');
      final context = await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');
      expect(project.openSockets, 1);

      await tester.tap(find.byTooltip('Sign out'));
      await settle(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(context.getBean<SupabaseAuth>().isLoggedIn, isFalse);
      expect(project.sent(HttpMethod.post, '/auth/v1/logout'), hasLength(1));
      expect(project.openSockets, 0);
      await stopApp(tester);
    });
  });

  group('the live list', () {
    Future<String> signIn(WidgetTester tester) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');
      return id;
    }

    testWidgets("the user's todos of the list, and nobody else's", (
      tester,
    ) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      project
        ..addTodo(id, 'Buy milk')
        ..addTodo(id, 'Elsewhere', listId: 'work')
        ..addTodo('someone-else', 'Not hers');
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Elsewhere'), findsNothing);
      expect(find.text('Not hers'), findsNothing);
      await stopApp(tester);
    });

    testWidgets('add: one POST through the repository, the row comes back '
        'through Realtime', (tester) async {
      final id = await signIn(tester);
      expect(find.text('Nothing to do'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('todo-title')), 'Buy milk');
      await tester.tap(find.byKey(const Key('todo-add')));
      await settle(tester);

      expect(find.widgetWithText(CheckboxListTile, 'Buy milk'), findsOneWidget);
      final post = project.sent(HttpMethod.post, '/rest/v1/todos').single;
      expect(
        jsonDecode(utf8.decode(post.body!)),
        allOf(
          containsPair('title', 'Buy milk'),
          containsPair('list_id', 'home'),
          // The database sets the owner (default auth.uid()).
          isNot(contains('owner')),
        ),
      );
      expect(project.todos.single['owner'], id);
      await stopApp(tester);
    });

    testWidgets('a todo written elsewhere shows up by itself', (tester) async {
      final id = await signIn(tester);
      final before = project.sent(HttpMethod.get, '/rest/v1/todos').length;

      project.addTodo(id, 'From the server');
      await settle(tester);

      expect(find.text('From the server'), findsOneWidget);
      // Realtime told; the watched query ran again, once.
      expect(
        project.sent(HttpMethod.get, '/rest/v1/todos'),
        hasLength(before + 1),
      );
      await stopApp(tester);
    });

    testWidgets('tick and delete', (tester) async {
      final id = await signIn(tester);
      project.addTodo(id, 'Buy milk');
      await settle(tester);

      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      expect(project.todos.single['done'], isTrue);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      final patch = project.sent(HttpMethod.patch, '/rest/v1/todos').single;
      expect(patch.url.queryParameters['id'], 'eq.1');

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      expect(project.todos, isEmpty);
      expect(find.text('Nothing to do'), findsOneWidget);
      await stopApp(tester);
    });
  });

  group('the profile', () {
    testWidgets('a new avatar is uploaded into the folder of the user and '
        'shown', (tester) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');
      // None yet: Storage was asked, as the user.
      expect(
        project
            .sent(HttpMethod.get, '/storage/v1/object/authenticated/avatars/')
            .single
            .url
            .path,
        endsWith('/avatars/$id/avatar.png'),
      );
      expect(
        tester
            .widget<CircleAvatar>(find.byKey(const Key('avatar')))
            .foregroundImage,
        isNull,
      );

      await tester.tap(find.byKey(const Key('avatar-new')));
      await settle(tester);

      final upload = project
          .sent(HttpMethod.post, '/storage/v1/object/')
          .single;
      expect(upload.url.path, '/storage/v1/object/avatars/$id/avatar.png');
      expect(upload.headers['Content-Type'], 'image/png');
      expect(upload.headers['x-upsert'], 'true');
      expect(project.avatars['avatars/$id/avatar.png'], onePixelPng);
      expect(
        tester
            .widget<CircleAvatar>(find.byKey(const Key('avatar')))
            .foregroundImage,
        isA<MemoryImage>(),
      );
      await stopApp(tester);
    });

    testWidgets('the avatar of an earlier run is read from the '
        'bucket', (tester) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      project.avatars['avatars/$id/avatar.png'] = onePixelPng;
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');

      expect(
        tester
            .widget<CircleAvatar>(find.byKey(const Key('avatar')))
            .foregroundImage,
        isA<MemoryImage>(),
      );
      await stopApp(tester);
    });

    testWidgets('the Edge Function is called as the user', (tester) async {
      final id = project.addUser('ada@example.com', 'correct horse');
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');

      await tester.tap(find.byKey(const Key('invite')));
      await settle(tester);

      expect(find.text('Invited: $id|friend@example.com'), findsOneWidget);
      final call = project.sent(HttpMethod.post, '/functions/v1/').single;
      expect(call.headers['Authorization'], 'Bearer token-of-$id');
      expect(jsonDecode(utf8.decode(call.body!)), {
        'email': 'friend@example.com',
      });
      await stopApp(tester);
    });

    testWidgets('a function that fails is said, not thrown', (tester) async {
      project
        ..addUser('ada@example.com', 'correct horse')
        ..inviteStatus = 500;
      await startApp(tester, project);
      await fillLogin(tester, 'ada@example.com', 'correct horse');

      await tester.tap(find.byKey(const Key('invite')));
      await settle(tester);

      expect(find.text('The function failed (500)'), findsOneWidget);
      await stopApp(tester);
    });
  });
}
