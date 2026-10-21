import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class MyMessages extends StaticMessageSource {}

void main() {
  ClasspathResources.registerAll(const {
    'i18n/messages.properties': EmbeddedResource.text('hello=Hello {0}'),
    'i18n/messages_ru.properties': EmbeddedResource.text('hello=Привет {0}'),
  });

  ConfigurableApplicationContext run(
    List<BeanModule> modules,
    List<String> args,
  ) => SpringApplication(
    modules,
    autoConfigurations: [springBootAutoConfiguration],
    out: (_) {},
  ).run(args, systemEnvironment: const {});

  test('MessageSourceAutoConfiguration reads spring.messages.basename', () {
    final context = run([], ['--spring.messages.basename=i18n/messages']);
    expect(context.getMessage('hello', args: ['Ada']), 'Hello Ada');
    expect(
      context.getMessage('hello', args: ['Ada'], locale: 'ru'),
      'Привет Ada',
    );
    expect(context.getBean<MessageSource>(), isA<PropertiesMessageSource>());
    context.close();
  });

  test('backs off without a bundle or with an application messageSource', () {
    final none = run([], ['--spring.messages.basename=missing']);
    // The context's own empty DelegatingMessageSource.
    expect(none.getBeanByName('messageSource'), isA<DelegatingMessageSource>());
    none.close();

    final custom = run(
      [
        BeanModule('app', [
          BeanDefinition<MyMessages>(
            name: 'messageSource',
            types: const [MyMessages, MessageSource],
            create: (_) => MyMessages(),
          ),
        ]),
      ],
      ['--spring.messages.basename=i18n/messages'],
    );
    expect(custom.getBeanByName('messageSource'), isA<MyMessages>());
    custom.close();
  });
}
