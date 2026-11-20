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

// The generated files other than a module's library follow the
// framework's convention `<name>.spring.<kind>.dart`. Not `.spring.dart`:
// that is the generated file of a source of the same name (`lib/theme.dart`
// gives `lib/spring_gen/theme.spring.dart`), which the build would refuse as
// written twice.

/// The ending of the typed keys written beside a generated library
/// (`theme.spring.keys.dart`, `messages.spring.keys.dart`).
const generatedKeysExtension = '.spring.keys.dart';

/// The ending of the classes of JSON Schemas
/// (`json_schemas.spring.classes.dart`).
const generatedClassesExtension = '.spring.classes.dart';

/// The ending of a module's descriptions, written beside its
/// `.spring.dart` (`lib/spring_gen/src/app.spring.introspection.dart`): a
/// library with the descriptions of the classes the module uses.
const introspectionExtension = '.spring.introspection.dart';

/// The ending of the binding of a module's `@ConfigurationProperties`
/// classes (`lib/spring_gen/src/app.spring.properties.dart`): a library
/// with the descriptions only their binder uses.
const propertiesExtension = '.spring.properties.dart';

/// The ending of a module's proxies
/// (`lib/spring_gen/src/app.spring.proxies.dart`): a part of its
/// `.spring.dart` with the AOP proxy classes and the lazy-resolution
/// proxies.
const proxiesExtension = '.spring.proxies.dart';

/// The ending of what only debug and profile builds of an application use
/// (`bin/spring_gen/main.spring.debug.dart`): a part of the
/// `@SpringBootApplication`'s `.spring.dart` with the fingerprint of the
/// generated code and the hot-reload functions, which the library refers to
/// only under `!dart.vm.product`, so a release build leaves it out.
const debugExtension = '.spring.debug.dart';

/// The ending of the values of the `--dart-define`s an application may
/// read (`bin/spring_gen/main.spring.env.dart`): a part of the
/// `@SpringBootApplication`'s `.spring.dart` with one constant map, a
/// `String.fromEnvironment` for each property and environment variable the
/// application reads, which its `springApplication` passes as
/// `dartDefines`.
const environmentExtension = '.spring.env.dart';

/// The endings of the parts of an application's library that the builder
/// fills itself (not the module's emitter), in the order the build lists
/// them.
const List<String> applicationPartExtensions = [
  debugExtension,
  environmentExtension,
];

/// The endings of the files a module's library has beside it, in the
/// order the build lists them ([moduleFileId]).
const List<String> moduleFileExtensions = [
  introspectionExtension,
  propertiesExtension,
  proxiesExtension,
  ...applicationPartExtensions,
];

/// The file of [module], a generated `.spring.dart`, that ends with
/// [extension] (one of [moduleFileExtensions]), beside it:
/// `lib/spring_gen/src/app.spring.dart` gives
/// `lib/spring_gen/src/app.spring.introspection.dart`.
AssetId moduleFileId(AssetId module, String extension) => AssetId(
  module.package,
  '${module.path.substring(0, module.path.length - '.spring.dart'.length)}'
  '$extension',
);

/// Whether [path] is a file the generator writes: never a source to read
/// beans, keys or tests from.
bool isGeneratedSource(String path) =>
    path.endsWith('.spring.dart') ||
    path.endsWith(generatedKeysExtension) ||
    path.endsWith(generatedClassesExtension) ||
    moduleFileExtensions.any(path.endsWith);
