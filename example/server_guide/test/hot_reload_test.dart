// Hot reload in a debug run: the generated reloadApplication keeps the
// running context while the generated code is unchanged. The fingerprint
// it compares and reloadApplication are in bin/spring_gen/main.spring.debug.dart,
// which the application refers to only in debug builds; a
// release build (dart compile exe) leaves it out.
@TestOn('vm')
library;

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import '../bin/spring_gen/main.spring.dart';

const Map<String, Object?> _properties = {
  'server.port': 0,
  'spring.main.banner-mode': 'off',
  'logging.console.enabled': false,
  'neon.stock.restock-initial-delay': '1h',
};

void main() {
  test('a debug run has the fingerprint of the generated code', () {
    expect(springApplication.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('reloadApplication keeps the context while the code is unchanged, '
      'and restarts it when the fingerprint changed', () async {
    final context = await springApplication.runAsync(
      const [],
      properties: _properties,
    );
    expect(reloadApplication(context), same(context));
    expect(await reloadApplicationAsync(context), same(context));
    final changed = SpringApplication(
      springApplication.modules,
      autoConfigurations: springApplication.autoConfigurations,
      autoConfigurationMetadata: springApplication.autoConfigurationMetadata,
      fingerprint: 'changed',
    );
    final restarted = await changed.reloadAsync(context);
    addTearDown(restarted.closeAsync);
    expect(restarted, isNot(same(context)));
    expect(context.isActive, isFalse);
    expect(restarted.isActive, isTrue);
  });
}
