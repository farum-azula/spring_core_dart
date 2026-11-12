// The factories of the starters: constants a module lists, found by type
// before any bean exists and as a bean afterwards.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

abstract interface class Design {
  String get name;
}

final class Plain implements Design {
  const Plain(this.name);

  @override
  final String name;
}

final class First implements Design, Ordered {
  const First();

  @override
  String get name => 'first';

  @override
  int get order => -10;
}

final class Other {
  const Other();
}

void main() {
  test('factories are found by type, by Ordered and then in the order of '
      'the modules', () {
    const factories = SpringFactories([
      Plain('ocean'),
      Other(),
      Plain('forest'),
      First(),
    ]);
    expect(
      [for (final design in factories.load<Design>()) design.name],
      [
        'first',
        'ocean',
        'forest',
      ],
    );
    expect(factories.load<Other>(), hasLength(1));
    expect(factories.load<String>(), isEmpty);
    expect(const SpringFactories().load<Design>(), isEmpty);
  });

  test('the application has the factories of its modules before it runs, '
      'and the context has them as the springFactories bean', () {
    final ocean = BeanModule('ocean', []);
    final forest = BeanModule('forest', []);
    final bare = BeanModule('bare', []);
    final application = SpringApplication(
      [BeanModule('application', [])],
      autoConfigurations: [ocean, bare, forest],
      autoConfigurationMetadata: {
        ocean: const AutoConfigurationModule(factories: [Plain('ocean')]),
        forest: const AutoConfigurationModule(
          order: 5,
          factories: [Plain('forest'), Other()],
        ),
      },
      bannerMode: BannerMode.off,
    );
    expect(
      [for (final design in application.factories.load<Design>()) design.name],
      ['ocean', 'forest'],
    );

    final context = application.run(const []);
    addTearDown(context.close);
    final bean = context.getBean<SpringFactories>();
    expect(context.containsBean('springFactories'), isTrue);
    expect(
      [for (final design in bean.load<Design>()) design.name],
      ['ocean', 'forest'],
    );
  });

  test('a module of the map that is not in the application adds nothing', () {
    final ocean = BeanModule('ocean', []);
    final application = SpringApplication(
      [BeanModule('application', [])],
      autoConfigurationMetadata: {
        ocean: const AutoConfigurationModule(factories: [Plain('ocean')]),
      },
      bannerMode: BannerMode.off,
    );
    expect(application.factories.load<Design>(), isEmpty);
  });
}
