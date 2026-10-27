// What the generated code of test classes calls: field injection helpers
// of SpringBootTestContext and BeanOverride.named (@TestBean(name: ...)).
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final fake = FakeMailer();
  final app = springBootTest(
    SpringApplication([appModule()]),
    properties: {'greeting.prefix': 'Hey', 'shop.size': '3'},
    overrides: [BeanOverride.named(fake, name: 'smtpMailer')],
  );

  test('findBean: the bean, or null when there is none', () {
    expect(app.findBean<Greeter>(), isA<RealGreeter>());
    expect(app.findBean<URLService>(), isNull);
  });

  test('getBeans: every bean of a type, a qualifier narrows them', () {
    expect(app.getBeans<Mailer>(), hasLength(2));
    expect(app.getBeans<Mailer>(qualifier: 'primaryMail'), [same(fake)]);
    expect(app.getBeans<URLService>(), isEmpty);
  });

  test('value and optionalValue convert like @Value', () {
    expect(app.value<int>(r'${shop.size}'), 3);
    expect(app.value<String>(r'${shop.missing:none}'), 'none');
    expect(app.optionalValue<String>(r'${shop.missing}'), isNull);
    expect(() => app.value<String>(r'${shop.missing}'), throwsA(anything));
  });

  test('BeanOverride.named keeps the types, name and qualifiers', () {
    expect(app.getBeanByName('smtpMailer'), same(fake));
    expect(app.getBean<Mailer>(qualifier: 'primaryMail'), same(fake));
    expect(app.getBean<Notifier>().notify('Ada'), 'fake: Hey, Ada');
  });

  test("BeanOverride.named drops the real class and adds the fake's", () {
    // The fake is not an SmtpMailer: nothing answers to that class now.
    expect(app.findBean<SmtpMailer>(), isNull);
    expect(app.getBeans<SmtpMailer>(), isEmpty);
    expect(app.getBean<FakeMailer>(), same(fake));
  });

  group('BeanOverride.named without such a bean', () {
    final added = springBootTest(
      SpringApplication([appModule()]),
      overrides: [BeanOverride.named(URLService(), name: 'urls')],
    );

    test('registers it under the name with its runtime type', () {
      expect(added.getBeanByName('urls'), isA<URLService>());
      expect(added.getBean<URLService>(), isA<URLService>());
    });
  });
}
