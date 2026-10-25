// NEON Books: a runnable tour of every spring_core_dart feature.
//
//   dart run bin/main.dart                      # every section
//   dart run bin/main.dart --section=aop        # one section
//   dart run bin/main.dart --app.name=Demo      # any property override
import 'package:spring_core_dart_example/tour.dart';

Future<void> main(List<String> args) async {
  final section = args
      .where((a) => a.startsWith('--section='))
      .map((a) => a.substring('--section='.length))
      .firstOrNull;
  await runTour([
    for (final a in args)
      if (!a.startsWith('--section=')) a,
  ], section: section);
}
