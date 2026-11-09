// The generator runs it in an app's package (`dart run
// spring_search_dart:search_index <request.json> <response.json>`): it
// reads the pages and the spring.search.* settings of the request and writes
// the index file of each language into the response, by language.
import 'dart:convert';
import 'dart:io';

import 'package:spring_search_dart/src/index/search_index_writer.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run spring_search_dart:search_index '
      '<request.json> <response.json>',
    );
    exitCode = 64;
    return;
  }
  final request =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>;
  final files = await SearchIndexWriter.build(
    texts: (request['texts']! as Map).cast<String, String>(),
    markdown: [
      for (final entry in request['markdown']! as List)
        (
          location: (entry as Map)['location']! as String,
          exclude: [for (final e in entry['exclude']! as List) e as String],
          link: entry['link']! as String,
        ),
    ],
    analyzers: (request['analyzers'] as Map? ?? const {})
        .cast<String, String>(),
    defaultLanguage: request['defaultLanguage'] as String? ?? 'en',
  );
  File(args[1]).writeAsStringSync(jsonEncode(files));
}
