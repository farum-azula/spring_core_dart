import 'package:flutter/material.dart';
import 'package:flutter_counter/src/counter/counter_page.dart';
import 'package:flutter_counter/src/counter/counter_properties.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The app; below `SpringApplicationWidget`, so every widget reaches the beans.
class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Any bean by type, without a generated getter.
    final properties = context.bean<CounterProperties>();
    return MaterialApp(
      title: properties.title,
      // The banner would cover the app bar's About button.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        // Japanese glyphs: the system's fonts on devices; in tests (which
        // see no system fonts) the cut-down font of test/fonts/.
        fontFamilyFallback: const ['Noto Sans JP'],
      ),
      // English and Japanese texts (lib/resources/messages*.properties).
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ja')],
      home: const CounterPage(),
    );
  }
}
