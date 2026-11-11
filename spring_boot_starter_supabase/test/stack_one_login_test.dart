@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, one login for everything: after one sign-in a repository, a
// bucket, a function and a Realtime subscription all act as that user,
// and after the logout as nobody.
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'stack_support.dart';

void main() {
  group('one login for everything', skip: Stack.skip, () {
    late StackApp app;

    setUpAll(() async {
      Stack.require();
      app = await StackApp.start();
    });

    tearDownAll(() => app.close());

    test('a repository, Storage, a function and Realtime act as the user '
        'who signed in, and as nobody after the logout', () async {
      await app.run(() async {
        final user = await app.createUser();
        final listId = Stack.unique('l');
        final avatar = Uint8List.fromList([1, 2, 3, 4]);
        expect(app.credentials.caller, const SupabaseCaller.anon());

        // One sign-in.
        await app.auth.signInWithPassword(
          email: user.email,
          password: user.password,
        );
        expect(app.credentials.caller, SupabaseCaller.user(user.id));
        expect(
          SecurityContextHolder.getContext().authentication?.name,
          user.id,
        );

        // Realtime first: its subscription takes a moment.
        final changes = Recorder(app.todos.changesByListId(listId));
        final rows = <Todo>[];
        try {
          // The repository: the row is the user's, by the database's own
          // auth.uid().
          final saved = await app.todos.save(
            Todo(title: 'mine', listId: listId),
          );
          rows.add(saved);
          final owner = await app.credentials.asServiceRole(
            () => app.rest(
              HttpMethod.get,
              '/todos',
              query: {'id': 'eq.${saved.id}', 'select': 'owner'},
            ),
          );
          expect(owner.bodyText, contains(user.id));

          // Storage: the folder of the policy is the user's id.
          await app.avatars.put(avatar);
          expect(
            await app.storage.downloadBytes(
              'avatars',
              '${user.id}/avatar.png',
            ),
            avatar,
          );

          // A function: the token it got is the user's.
          final stats = await app.functions.stats('now');
          expect(stats['user'], user.id);
          expect(stats['verified'], user.id);

          // Realtime: only a user who may read the rows gets them.
          final change = await changes.provoke(
            (n) async => rows.add(
              await app.todos.save(Todo(title: 'probe $n', listId: listId)),
            ),
            (change) => change.kind == RowChangeKind.insert,
            what: "a change of the user's rows",
          );
          expect(change.row?.listId, listId);
          expect(changes.errors, isEmpty);
        } finally {
          await changes.cancel();
          if (app.auth.isLoggedIn) {
            await app.todos.deleteAllById([for (final row in rows) row.id!]);
            await app.avatars.remove(user.id);
          }
        }

        // One logout.
        await app.auth.logout();
        expect(app.credentials.caller, const SupabaseCaller.anon());
        expect(SecurityContextHolder.getContext().authentication, isNull);
        await expectLater(
          app.todos.findAll(),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
        expect(await app.avatars.bytesOrNull(user.id), isNull);
        final stats = await app.functions.stats('now');
        expect(stats['user'], isNull);
        expect(stats['role'], 'anon');
      });
    });
  });
}
