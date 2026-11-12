import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart'
    show FeignException, StorageException, SupabaseAuth;
import 'package:supabase_example_app/src/profile/avatars.dart';
import 'package:supabase_example_app/src/profile/functions.dart';

/// The beans of [ProfileCard].
typedef ProfileCardBeans = (
  SupabaseAuth,
  Avatars,
  AvatarPainter,
  Functions,
);

/// Who is signed in: their avatar from Storage (and a button that draws
/// and uploads a new one), their address, and a button that calls an Edge
/// Function.
class ProfileCard extends SpringStatefulWidget<ProfileCardBeans> {
  const ProfileCard({super.key});

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends SpringState<ProfileCard, ProfileCardBeans> {
  static final _random = Random();

  late Future<Uint8List?> _avatar = _load();

  String get _email => beans.$1.user?.email ?? '';

  /// The avatar in the bucket; none also when Storage cannot be asked.
  Future<Uint8List?> _load() async {
    try {
      return await beans.$2.mine();
    } on StorageException {
      return null;
    }
  }

  void _say(ScaffoldMessengerState messenger, String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _newAvatar() async {
    final (_, avatars, painter, _) = beans;
    final messenger = ScaffoldMessenger.of(context);
    final color = Colors.primaries[_random.nextInt(Colors.primaries.length)];
    final letter = _email.isEmpty ? '?' : _email[0].toUpperCase();
    try {
      final png = await painter.paint(letter, color);
      await avatars.put(png);
      if (mounted) {
        setState(() {
          _avatar = Future.value(png);
        });
      }
    } on StorageException catch (error) {
      _say(messenger, 'Not uploaded: ${error.runtimeType}');
    }
  }

  Future<void> _invite() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await beans.$4.sendInvite(
        const Invite(email: 'friend@example.com'),
      );
      _say(messenger, 'Invited: ${result.id}');
    } on FeignException catch (error) {
      _say(messenger, 'The function failed (${error.status})');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          FutureBuilder(
            future: _avatar,
            builder: (context, avatar) => CircleAvatar(
              key: const Key('avatar'),
              radius: 28,
              foregroundImage: switch (avatar.data) {
                final bytes? => MemoryImage(bytes),
                null => null,
              },
              child: const Icon(Icons.person),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_email, overflow: TextOverflow.ellipsis)),
          IconButton(
            key: const Key('avatar-new'),
            onPressed: _newAvatar,
            tooltip: 'New avatar',
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            key: const Key('invite'),
            onPressed: _invite,
            tooltip: 'Invite a friend',
            icon: const Icon(Icons.person_add_alt),
          ),
        ],
      ),
    ),
  );
}
