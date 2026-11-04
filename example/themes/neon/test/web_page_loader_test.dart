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
    expect(page, contains('data-kind="neongate"'));
    // The fill phase's min-duration, for the script: it starts after the
    // panels came in (2 s) and takes 2.5 s at least.
    expect(page, contains('data-fill-at="2000" data-fill-min="2500"'));
    // The gate is CSS and SVG (no image), the number in the package's font,
    // and the page has no title or image of its own.
    expect(page, contains('class="ng-box"'));
    expect(page, contains('--gate-color:'));
    expect(page, contains('--edge-accent:'));
    expect(page, contains('--phases-enter-duration:2000ms'));
    expect(page, contains('--phases-fill-min-duration:2500ms'));
    expect(page, contains('JetBrainsMono-SemiBold.ttf'));
    expect(page, isNot(contains('ns-title')));
    expect(page, isNot(contains('sl-logo"')));
    expect(page, isNot(contains('<img')));
    // The hand-off the Flutter splash calls, and the app's own script after.
    expect(page, contains('springLoaderHandOff'));
    expect(
      page.indexOf('<!-- spring:loader:end -->'),
      lessThan(page.indexOf('flutter_bootstrap.js')),
    );
  });
}
