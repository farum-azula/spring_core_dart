import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Tells the `SearchService` its documents changed: the next search reads
/// the `SearchDocumentSource`s again and builds a new index.
///
/// ```dart
/// await books.save(book);
/// events.publishEvent(SearchIndexInvalidatedEvent(this));
/// ```
final class SearchIndexInvalidatedEvent extends ApplicationEvent {
  /// The event of [source].
  SearchIndexInvalidatedEvent(super.source);

  @override
  String get eventName => 'SearchIndexInvalidatedEvent';
}
