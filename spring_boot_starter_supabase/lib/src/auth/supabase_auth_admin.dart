import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/auth/supabase_auth_exception.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_user.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The admin API of Supabase Auth (the bean `supabaseAuthAdmin`): creates,
/// reads, changes and deletes the project's users, as the service role.
///
/// Every call is made with `spring.supabase.service-role-key`, which
/// passes every rule of the project: it belongs on a server (and in
/// tests). Without the key a call fails with a [StateError] before any
/// request.
///
/// ```dart
/// final user = await admin.createUser(
///   email: 'ada@example.com',
///   password: password,
///   emailConfirm: true,
///   appMetadata: {'roles': ['editor']},
/// );
/// await admin.updateUser(user.id, appMetadata: {'roles': ['admin']});
/// await admin.deleteUser(user.id);
/// ```
///
/// Roles belong in `appMetadata` (`roles`): only this API writes it, and
/// it is what `SupabaseAuth` and a server read them from.
final class SupabaseAuthAdmin {
  /// The admin API of the project of [http]; [errors] turns Auth's
  /// errors into exceptions.
  SupabaseAuthAdmin({required this.http, SupabaseAuthErrors? errors})
    : errors = errors ?? SupabaseAuthErrors();

  /// The project.
  final SupabaseHttp http;

  /// What turns Auth's errors into exceptions.
  final SupabaseAuthErrors errors;

  static final _uuid = RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// Creates a user with an [email] or a [phone].
  ///
  /// With [emailConfirm] (or [phoneConfirm]) the address counts as
  /// confirmed and the user can sign in at once; without it Auth sends
  /// nothing either, so confirm here or invite the user. [appMetadata] is
  /// what the project says about the user (`roles`), [userMetadata] what
  /// the user may change themselves.
  ///
  /// Throws an `AuthenticationException` with Auth's error code
  /// (`email_exists`, `weak_password`, ...) when Auth refuses.
  Future<SupabaseUser> createUser({
    String? email,
    String? phone,
    String? password,
    bool emailConfirm = false,
    bool phoneConfirm = false,
    Map<String, Object?>? appMetadata,
    Map<String, Object?>? userMetadata,
  }) async {
    if ((email == null || email.trim().isEmpty) &&
        (phone == null || phone.trim().isEmpty)) {
      throw ArgumentError('createUser needs an email or a phone');
    }
    return _user(
      await _send(
        HttpMethod.post,
        '/admin/users',
        json: {
          'email': ?email?.trim(),
          'phone': ?phone?.trim(),
          'password': ?password,
          if (emailConfirm) 'email_confirm': true,
          if (phoneConfirm) 'phone_confirm': true,
          'app_metadata': ?appMetadata,
          'user_metadata': ?userMetadata,
        },
        secrets: [password],
      ),
    );
  }

  /// The user with [id], or `null` when there is none.
  Future<SupabaseUser?> user(String id) async {
    try {
      return _user(await _send(HttpMethod.get, '/admin/users/${_id(id)}'));
    } on SupabaseUserNotFoundException {
      return null;
    }
  }

  /// One page of the project's users: [perPage] of them, [page] counted
  /// from 1.
  Future<List<SupabaseUser>> users({int page = 1, int perPage = 50}) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'starts at 1');
    }
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'must be positive');
    }
    final json = await _send(
      HttpMethod.get,
      '/admin/users',
      query: [MapEntry('page', '$page'), MapEntry('per_page', '$perPage')],
    );
    return [
      if (json['users'] case final List<Object?> users)
        for (final user in users) ?SupabaseUser.fromJson(user),
    ];
  }

  /// Changes the user with [id]: only what is given. [appMetadata] and
  /// [userMetadata] are merged into what the user has (a key with the
  /// value `null` is removed); [banDuration] bans the user for that long
  /// (`'24h'`; `'none'` lifts a ban).
  ///
  /// Throws a [SupabaseUserNotFoundException] when there is no such
  /// user.
  Future<SupabaseUser> updateUser(
    String id, {
    String? email,
    String? phone,
    String? password,
    bool? emailConfirm,
    bool? phoneConfirm,
    Map<String, Object?>? appMetadata,
    Map<String, Object?>? userMetadata,
    String? banDuration,
  }) async => _user(
    await _send(
      HttpMethod.put,
      '/admin/users/${_id(id)}',
      json: {
        'email': ?email?.trim(),
        'phone': ?phone?.trim(),
        'password': ?password,
        'email_confirm': ?emailConfirm,
        'phone_confirm': ?phoneConfirm,
        'app_metadata': ?appMetadata,
        'user_metadata': ?userMetadata,
        'ban_duration': ?banDuration,
      },
      secrets: [password],
    ),
  );

  /// Deletes the user with [id], with their sessions. With [softDelete]
  /// the row stays, emptied, for what refers to it.
  ///
  /// Throws a [SupabaseUserNotFoundException] when there is no such
  /// user.
  Future<void> deleteUser(String id, {bool softDelete = false}) async {
    await _send(
      HttpMethod.delete,
      '/admin/users/${_id(id)}',
      json: {'should_soft_delete': softDelete},
    );
  }

  // A user id is a UUID: nothing else becomes a part of the path.
  static String _id(String id) => _uuid.hasMatch(id)
      ? id
      : throw ArgumentError.value(id, 'id', 'is not the id of a user (UUID)');

  SupabaseUser _user(Map<String, Object?> json) =>
      SupabaseUser.fromJson(json) ??
      (throw SupabaseAuthenticationException(
        'Supabase Auth answered without a user',
      ));

  Future<Map<String, Object?>> _send(
    HttpMethod method,
    String path, {
    Iterable<MapEntry<String, String>> query = const [],
    Object? json,
    Iterable<String?> secrets = const [],
  }) => http.credentials.asServiceRole(() async {
    // Inside asServiceRole: the service role key.
    final key = http.credentials.apiKey;
    final response = await http.send(
      SupabaseService.auth,
      method,
      path,
      query: query,
      json: json,
      bearer: key,
    );
    if (!response.isSuccess) {
      // Should the answer repeat a secret, it never reaches a message.
      throw errors.translate(
        errors.read(response, secrets: [...secrets, key]),
      );
    }
    if (response.bodyBytes.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final json = jsonDecode(response.bodyText);
      return json is Map<String, Object?> ? json : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  });
}
