// The generator writes the page loader of the theme's splash into
// web/index.html when build_runner runs (builder spring_flutter_page_loader).
// This checks that the page has the block, made from this app's splash.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/index.html has the page loader of the splash', () {
    final page = File('web/index.html').readAsStringSync();
    expect(page, contains('<!-- spring:loader:start -->'));
    expect(page, contains('<!-- spring:loader:end -->'));
    expect(page, contains('id="spring-loader"'));
    expect(page, contains('data-kind="bar"'));
    expect(page, contains('<div class="sl-title">NEON Books</div>'));
    // The hand-off the Flutter splash calls, and the app's own script after.
    expect(page, contains('springLoaderHandOff'));
    expect(
      page.indexOf('<!-- spring:loader:end -->'),
      lessThan(page.indexOf('flutter_bootstrap.js')),
    );
  });
}
