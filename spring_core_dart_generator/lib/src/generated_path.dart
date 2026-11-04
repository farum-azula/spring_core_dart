import 'package:build/build.dart';

/// The folder next to a source root that holds its generated files.
const generatedFolder = 'spring_gen';

/// The source roots whose `.dart` files may get a generated file.
const generatedRoots = ['lib', 'bin', 'test', 'example'];

/// The generated file of the source [path]: it goes into `spring_gen/` of
/// its source root and mirrors the rest of the path. For example
/// `lib/src/shop/cart.dart` gives `lib/spring_gen/src/shop/cart.spring.dart`.
String generatedPath(String path) {
  final slash = path.indexOf('/');
  final root = path.substring(0, slash);
  final rest = path.substring(slash + 1, path.length - '.dart'.length);
  return '$root/$generatedFolder/$rest.spring.dart';
}

/// [generatedPath] of an asset.
AssetId generatedId(AssetId source) =>
    AssetId(source.package, generatedPath(source.path));

/// Whether [path] is in a root that gets generated files.
bool hasGeneratedRoot(String path) =>
    generatedRoots.any((root) => path.startsWith('$root/'));
