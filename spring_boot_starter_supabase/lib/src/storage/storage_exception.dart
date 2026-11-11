import 'package:spring_boot_starter_supabase/src/supabase_exception.dart';

/// A call to Supabase Storage that failed.
///
/// ```dart
/// try {
///   await storage.upload('avatars', 'u1.png', bytes);
/// } on StorageObjectAlreadyExistsException {
///   // upload(..., upsert: true) would have replaced it
/// }
/// ```
class StorageException extends SupabaseException {
  /// A failure of Storage with [message].
  StorageException(super.message, {super.statusCode, super.code, super.cause});

  @override
  String toString() => describe('StorageException');
}

/// The object or the bucket does not exist, or the caller may not see it
/// (Storage does not tell the two apart).
class StorageObjectNotFoundException extends StorageException {
  /// Nothing at the place asked for.
  StorageObjectNotFoundException(
    super.message, {
    super.statusCode,
    super.code,
  });

  @override
  String toString() => describe('StorageObjectNotFoundException');
}

/// There is an object (or a bucket) at that place already.
class StorageObjectAlreadyExistsException extends StorageException {
  /// The place is taken.
  StorageObjectAlreadyExistsException(
    super.message, {
    super.statusCode,
    super.code,
  });

  @override
  String toString() => describe('StorageObjectAlreadyExistsException');
}

/// The caller may not do this: a policy of row-level security on
/// `storage.objects` refused it, or the token was not accepted.
class StoragePermissionDeniedException extends StorageException {
  /// Refused.
  StoragePermissionDeniedException(
    super.message, {
    super.statusCode,
    super.code,
  });

  @override
  String toString() => describe('StoragePermissionDeniedException');
}

/// The object is larger than the bucket or the project allows.
class StorageObjectTooLargeException extends StorageException {
  /// Too large.
  StorageObjectTooLargeException(
    super.message, {
    super.statusCode,
    super.code,
  });

  @override
  String toString() => describe('StorageObjectTooLargeException');
}
