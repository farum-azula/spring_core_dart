import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final logs = captureLogs(level: SpringLogLevel.debug);
  const log = SpringLog('neon.checkout.payment');

  test('captures records of the current test', () {
    log
      ..debug('basket checked')
      ..warning('slow payment', fields: {'ms': 3000});
    const SpringLog('other').info('elsewhere');
    expect(logs.messages, ['basket checked', 'slow payment', 'elsewhere']);
    expect(logs.atLevel(SpringLogLevel.warning).single.fields, {'ms': 3000});
    expect(logs.ofLogger('neon.checkout'), hasLength(2));
    expect(logs.text, contains('WARNING [neon.checkout.payment] slow payment'));
  });

  test('starts empty in every test', () {
    expect(logs.records, isEmpty);
    expect(SpringLog.level, SpringLogLevel.debug);
  });

  test('sees logs of beans started by a runner', () {
    const ApplicationContextRunner().withUserConfiguration(appModule()).run((
      context,
    ) {
      context.getBean<Greeter>();
    });
    expect(logs.messages, contains('creating greeter'));
  });
}
