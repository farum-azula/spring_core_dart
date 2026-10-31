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

  group("BeanOverride.named with the fake's types", () {
    // The real mailer is also an Auditable; the fake is not.
    final module = BeanModule('audited', [
      BeanDefinition<AuditedMailer>(
        name: 'auditedMailer',
        types: const [AuditedMailer, Mailer, Auditable],
        create: (_) => AuditedMailer(),
      ),
    ]);
    final runner = const ApplicationContextRunner().withUserConfiguration(
      module,
    );

    test('registers it under those types only', () {
      final fake = FakeMailer();
      runner
          .withInitializer(
            ApplicationContextInitializer.of(
              (context) => context.addBeanFactoryPostProcessor(
                BeanOverrideProcessor([
                  BeanOverride.named(
                    fake,
                    name: 'auditedMailer',
                    types: const [FakeMailer, Mailer],
                  ),
                ]),
              ),
            ),
          )
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context.getBean<Mailer>(), same(fake));
            expect(context.getBeanNamesForType<Auditable>(), isEmpty);
            expect(context.getBeanNamesForType<AuditedMailer>(), isEmpty);
            expect(context.getBeanNamesForType<FakeMailer>(), [
              'auditedMailer',
            ]);
          });
    });

    test("without types it keeps the bean's interfaces, the fake's or not", () {
      runner
          .withInitializer(
            ApplicationContextInitializer.of(
              (context) => context.addBeanFactoryPostProcessor(
                BeanOverrideProcessor([
                  BeanOverride.named(FakeMailer(), name: 'auditedMailer'),
                ]),
              ),
            ),
          )
          .run((context) {
            expect(context.getBeanNamesForType<Auditable>(), [
              'auditedMailer',
            ]);
            expect(() => context.getBean<Auditable>(), throwsA(anything));
          });
    });
  });

  // `@Bean Mailer mailer() => smtp ? SmtpMailer() : LogMailer();` is
  // registered under its declared type only, which is also its bean type.
  // Without the fake's types (a `@TestBean(name:)` field whose value is no
  // constructor call) the override dropped that type, and nothing could
  // inject the fake as a Mailer. Spring registers a @TestBean override
  // under the field's type, the T the generated code infers.
  group("BeanOverride.named adds T, the field's type", () {
    final module = BeanModule('declared', [
      BeanDefinition<Mailer>(
        name: 'mailer',
        types: const [Mailer],
        create: (_) => SmtpMailer(),
      ),
    ]);

    void run(
      BeanOverride<Object> override,
      void Function(AssertableApplicationContext context) check,
    ) => const ApplicationContextRunner()
        .withUserConfiguration(module)
        .withInitializer(
          ApplicationContextInitializer.of(
            (context) => context.addBeanFactoryPostProcessor(
              BeanOverrideProcessor([override]),
            ),
          ),
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          check(context);
        });

    test('replacing a bean registered under its declared type only', () {
      final fake = FakeMailer();
      run(
        BeanOverride<Mailer>.named(fake, name: 'mailer'),
        (context) => expect(context.getBean<Mailer>(), same(fake)),
      );
    });

    test("with the fake's types too", () {
      final fake = FakeMailer();
      run(
        BeanOverride<Mailer>.named(
          fake,
          name: 'mailer',
          types: const [FakeMailer],
        ),
        (context) {
          expect(context.getBean<Mailer>(), same(fake));
          expect(context.getBean<FakeMailer>(), same(fake));
        },
      );
    });

    test('also when T is the real class, which the fake extends', () {
      final fake = _FakeSmtpMailer();
      run(
        BeanOverride<SmtpMailer>.named(fake, name: 'mailer'),
        (context) => expect(context.getBean<SmtpMailer>(), same(fake)),
      );
    });

    test('but not Object, which every bean is', () {
      run(BeanOverride<Object>.named(FakeMailer(), name: 'mailer'), (context) {
        expect(context.getBeanNamesForType<Mailer>(), isEmpty);
        expect(context.getBeanNamesForType<FakeMailer>(), ['mailer']);
      });
    });
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

abstract interface class Auditable {
  List<String> get audit;
}

class AuditedMailer implements Mailer, Auditable {
  @override
  String get kind => 'audited';

  @override
  List<String> get audit => const [];
}

class _FakeSmtpMailer extends SmtpMailer {}
