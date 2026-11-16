import 'package:spring_core_dart/src/core/io/resource.dart';

/// A resource that knows the version of its content: a file downloaded
/// and kept, whose digest says which content it holds now.
///
/// A resource is equal to another by its type and its address, as in
/// Spring, so a result a cache made from a file that changed at the same
/// address would stay; with `spring.cache.resource-version` a cache key
/// made of such a resource is its address and its [version], and a new
/// content is a new key.
abstract interface class VersionedResource implements Resource {
  /// The version of the content held now (a digest of it), `null` while
  /// none is held.
  String? get version;
}
