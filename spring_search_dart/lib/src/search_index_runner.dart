import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/config/search_properties.dart';
import 'package:spring_search_dart/src/search_service.dart';

/// Builds the indexes of [search] when the application starts, as
/// `spring.search.indexing` says: `start` waits for them (a Flutter app
/// builds them behind its splash), `background` starts them and goes on
/// (the default language first, the app running meanwhile);
/// `first-search` leaves them to the first search.
final class SearchIndexRunner implements ApplicationRunner {
  /// The runner of [search], building as [indexing] says.
  const SearchIndexRunner(this.search, this.indexing);

  /// The service whose indexes are built.
  final SearchService search;

  /// When they are built.
  final SearchIndexing indexing;

  @override
  Future<void> run(ApplicationArguments args) async {
    switch (indexing) {
      case SearchIndexing.start:
        await search.prepare();
      case SearchIndexing.background:
        unawaited(search.prepare());
      case SearchIndexing.firstSearch:
        break;
    }
  }
}
