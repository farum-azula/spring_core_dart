// Starting the application with the signals, security, data, cache and
// validation beans: no bean is made before the post-processors and so
// skipped by them (Spring's "not eligible for getting processed by all
// BeanPostProcessors").
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'support.dart';

void main() {
  test('no bean is made too early for the post-processors', () async {
    final lines = <String>[];
    final stop = SpringLog.listen((record) {
      final message = record.message;
      if (message.contains('not eligible for getting processed')) {
        lines.add(message);
      }
    });
    addTearDown(stop);
    final app = await startApp([
      '--logging.level.spring_core_dart.context=info',
    ]);
    addTearDown(app.closeAsync);
    expect(lines, isEmpty);
    expect(app.containsBean('defaultValidator'), isTrue);
    expect(app.containsBean('signalRuntime'), isTrue);
  });
}
