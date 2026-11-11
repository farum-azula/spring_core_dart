import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// The bucket `avatars` of the project: each user's files are under the
/// folder named after their id, and the policies of the bucket let a user
/// read and write only there.
@StorageBucket('avatars')
abstract interface class Avatars {
  /// An address that reads the caller's avatar for five minutes, without
  /// a token: what a page puts into an `<img>`. `authentication.name` is
  /// the id of the caller (SpEL, as in `@PreAuthorize`).
  @SignedUrl(
    '#{authentication.name}/avatar.png',
    expiresIn: Duration(minutes: 5),
  )
  Future<Uri> link();
}
