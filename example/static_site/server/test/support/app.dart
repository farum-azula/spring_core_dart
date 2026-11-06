// The server with a small build of its own (test/web/: an index.html, a
// main.dart.js and its .br, a .wasm), in place of ../app/build/web/.
import 'dart:isolate';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../../bin/spring_gen/main.spring.dart';

/// [path] inside this package, whatever the working directory: `dart test`
/// runs here and from the workspace root.
String inPackage(String path) => Isolate.resolvePackageUriSync(
  Uri.parse('package:static_site_server/'),
)!.resolve('../$path').toFilePath();

/// The whole server, its files from [web] (a `file:` location), for the
/// tests of the calling `main` or `group`.
SpringBootTestContext staticSite({
  String? web,
  WebEnvironment webEnvironment = WebEnvironment.mock,
}) => springBootTest(
  springApplication,
  properties: {
    'spring.web.resources.static-locations':
        web ?? 'file:${inPackage('test/web/')}',
  },
  webEnvironment: webEnvironment,
);
