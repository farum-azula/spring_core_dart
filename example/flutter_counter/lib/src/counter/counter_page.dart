import 'package:flutter/material.dart';
import 'package:flutter_counter/src/about/about_page.dart';
import 'package:flutter_counter/src/about/app_assets.dart';
import 'package:flutter_counter/src/counter/counter.dart';
import 'package:flutter_counter/src/counter/counter_properties.dart';
import 'package:flutter_counter/src/counter/counter_value.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The home page of the template. Stateless: the count is the `Counter`
/// bean.
///
/// The page only calls `counter.increment`, so a tap does not rebuild it:
/// a Spring widget listens to a `@ChangeNotifierComponent` bean only when
/// its build reads the bean's state, as [CounterValue] does.
class CounterPage
    extends SpringStatelessWidget<(CounterProperties, AppAssets, Counter)> {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (properties, assets, counter) = beans;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(properties.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
            tooltip: context.message('about.open'),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // An image asset injected into the AppAssets bean.
            Image(image: assets.logoImage, height: 96),
            const SizedBox(height: 16),
            Text(context.message('counter.pushed')),
            const CounterValue(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        tooltip: context.message('counter.increment'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
