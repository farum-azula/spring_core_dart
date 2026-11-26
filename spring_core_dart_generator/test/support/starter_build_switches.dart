// The build switches of the starters' auto-configuration modules as the
// starters write them, for stubs that carry the real switches.
import 'dart:io';

import 'package:test/test.dart';

/// The auto-configuration of [package], from the generator's folder or the
/// repository's root (the workspace run).
String starterSource(String package) {
  for (final base in ['..', '.']) {
    final file = File('$base/$package/lib/spring_auto_configuration.dart');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('$package not found');
}

/// The `build:` argument of the module [module] of [package] as the
/// starter writes it, nested switches included.
String starterBuildSwitch(
  String module, {
  String package = 'spring_boot_starter_flutter',
}) {
  final source = starterSource(package);
  final declaration = RegExp(
    'final BeanModule\\s+$module\\b',
  ).firstMatch(source);
  expect(declaration, isNotNull, reason: '$module in $package');
  final annotation = source.lastIndexOf(
    '@AutoConfigurationModule(',
    declaration!.start,
  );
  final build = source.indexOf('build:', annotation);
  expect(
    build > annotation && build < declaration.start,
    isTrue,
    reason: '$module has a build switch',
  );
  final start = source.indexOf('AutoConfigurationBuild', build);
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    switch (source[i]) {
      case '(':
        depth++;
      case ')':
        depth--;
        if (depth == 0) {
          return source.substring(start, i + 1);
        }
    }
  }
  throw StateError('unbalanced build switch of $module');
}
