// The server with a small build of its own (test/web/: an index.html, a
// main.dart.js and its .br, a .wasm), in place of ../app/build/web/.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../../bin/spring_gen/main.spring.dart';

/// The whole server, its files from [web], for the tests of the calling
/// `main` or `group`.
SpringBootTestContext staticSite({
  String web = 'file:test/web/',
  WebEnvironment webEnvironment = WebEnvironment.mock,
}) => springBootTest(
  springApplication,
  properties: {'spring.web.resources.static-locations': web},
  webEnvironment: webEnvironment,
);
