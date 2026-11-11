// The app's beans, without its screen, against the whole of Supabase: the
// Supabase CLI's stack of ../supabase (or a hosted project with the same
// migration and functions), given by SUPABASE_URL and SUPABASE_ANON_KEY;
// skipped without them (../README.md says how to start one).
//
// What test/app_test.dart plays in memory is real here: Auth signs the
// user up, the REST API keeps their rows, Realtime tells the watched query
// about them, Storage keeps the avatar and the Edge Function answers.
@Tags(['supabase-stack'])
library;

import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart'
    show FileStore, InMemoryFileStore;
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show BeanOverride, springBootTest;
import 'package:supabase_example_app/spring_gen/main.spring.dart';
import 'package:supabase_example_app/src/profile/avatars.dart';
import 'package:supabase_example_app/src/profile/functions.dart';
import 'package:supabase_example_app/src/todos/todo.dart';

import 'support/fake_project.dart' show onePixelPng;

/// The value of the variable [name], without the quotes
/// `supabase status -o env` puts around it; `null` when not set.
String? env(String name) {
  var value = io.Platform.environment[name]?.trim();
  if (value == null) {
    return null;
  }
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1);
  }
  return value.isEmpty ? null : value;
}

String unique(String prefix) {
  final random = Random.secure();
  return [
    prefix,
    for (var i = 0; i < 12; i++) random.nextInt(16).toRadixString(16),
  ].join();
}

void main() {
  final url = env('SUPABASE_URL');
  final skip = url == null
      ? 'SUPABASE_URL is not set: this test needs the whole of Supabase '
            '(example/supabase/README.md)'
      : null;

  group('the app against a project', skip: skip, () {
    final listId = unique('list-');
    final app = springBootTest(
      springApplication,
      properties: {
        'spring.supabase.url': url,
        'spring.supabase.anon-key': env('SUPABASE_ANON_KEY'),
        'todos.list': listId,
      },
      // No plugin answers in a test: the session and the files in memory.
      overrides: [
        BeanOverride<SecretStore>(InMemorySecretStore()),
        BeanOverride<FileStore>(InMemoryFileStore()),
      ],
    );
    final email = '${unique('example-app-')}@example.com';
    late SupabaseAuth auth;
    late Todos todos;

    setUpAll(() async {
      // A widget test answers every HTTP request itself; this one calls
      // the project.
      io.HttpOverrides.global = null;
      auth = app.getBean<SupabaseAuth>();
      todos = app.getBean<Todos>();
      await auth.signUp(email: email, password: unique('Pw-'));
      expect(
        auth.isLoggedIn,
        isTrue,
        reason: 'the project confirms addresses: nobody is signed in',
      );
    });

    tearDownAll(() async {
      // A user deletes their own rows and files.
      final id = auth.user!.id;
      for (final todo in await todos.findAll()) {
        await todos.delete(todo);
      }
      await app.getBean<StorageTemplate>().delete('avatars', '$id/avatar.png');
      await auth.logout();
      // The user itself only the admin API deletes, with the key an app
      // never has: the test's own, when the environment gives it.
      final serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY');
      if (serviceRoleKey != null) {
        final properties = SupabaseProperties()
          ..url = url
          ..anonKey = env('SUPABASE_ANON_KEY')
          ..serviceRoleKey = serviceRoleKey;
        await SupabaseAuthAdmin(
          http: SupabaseHttp(
            properties: properties,
            transport: platformHttpTransport(),
            credentials: DefaultSupabaseCredentials(
              properties: properties,
              authentication: () => null,
            ),
          ),
        ).deleteUser(id);
      }
    });

    test('the watched list follows the table: a row added, ticked and '
        'deleted', () async {
      final lists = <List<String>>[];
      final wake = StreamController<void>.broadcast();
      final subscription = todos.watchByListIdOrderByIdAsc(listId).listen((
        list,
      ) {
        lists.add([
          for (final todo in list) '${todo.title}${todo.done ? ' ✓' : ''}',
        ]);
        wake.add(null);
      });
      Future<void> shows(List<String> titles) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (lists.isEmpty || !_same(lists.last, titles)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('the list never showed $titles; it showed $lists');
          }
          await wake.stream.first.timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        }
      }

      await shows([]);
      // Realtime starts to tell a moment after the channel is joined: the
      // first row is written until the list has it.
      final saved = await todos.save(
        Todo(title: 'Buy milk', listId: listId, createdAt: DateTime.now()),
      );
      expect(saved.id, isNotNull);
      for (var attempt = 0; lists.last.isEmpty && attempt < 20; attempt++) {
        await todos.save(saved..title = 'Buy milk');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await shows(['Buy milk']);

      await todos.save(saved..done = true);
      await shows(['Buy milk ✓']);

      await todos.deleteById(saved.id!);
      await shows([]);
      await subscription.cancel();
      await wake.close();
    });

    test("the avatar: uploaded into the user's folder, read back", () async {
      final avatars = app.getBean<Avatars>();
      expect(await avatars.mine(), isNull);

      await avatars.put(onePixelPng);

      expect(await avatars.mine(), onePixelPng);
      expect(
        await app.getBean<StorageTemplate>().exists(
          'avatars',
          '${auth.user!.id}/avatar.png',
        ),
        isTrue,
      );
    });

    test('the Edge Function answers who called', () async {
      final result = await app.getBean<Functions>().sendInvite(
        const Invite(email: 'friend@example.com'),
      );
      expect(result.id, '${auth.user!.id}|friend@example.com');
    });
  });
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
