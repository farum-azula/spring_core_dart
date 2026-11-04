import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

void main() {
  final app = springBootTest(springApplication);
  test('boots', () {
    expect(
      app.context.getBean<SpringThemes>().names,
      containsAll(['light', 'dark', 'ocean', 'neon']),
    );
  });
}
