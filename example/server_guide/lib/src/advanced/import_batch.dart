// A custom scope, registered by a BeanFactoryPostProcessor (what Spring's
// CustomScopeConfigurer does): one ImportBatch per import, however many
// beans ask for it while the import runs.
import 'package:neon_books_server/src/advanced/advanced_tour.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Runs before any bean is created, with the bean factory itself.
@Component()
@AdvancedTour()
class ImportBatchScope implements BeanFactoryPostProcessor {
  static const name = 'import-batch';

  final _scope = SimpleMapScope();

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      beanFactory.registerScope(name, _scope);

  /// Ends the current batch: the next lookup creates a new one.
  void end() => _scope.remove('importBatch');
}

/// What one import brought in.
@Component()
@Scope(ImportBatchScope.name)
@AdvancedTour()
class ImportBatch {
  final isbns = <String>[];
  final rejected = <String>[];
}

/// Imports books in batches; a singleton that reaches the scoped bean
/// through a provider, so it always sees the current batch.
@Service()
@AdvancedTour()
class CatalogImporter {
  CatalogImporter(this._books, this._batch, this._scope, this._validator);

  final BookRepository _books;
  final ObjectProvider<ImportBatch> _batch;
  final ImportBatchScope _scope;
  final BeanValidator _validator;

  /// Adds [books] that pass the default and the [Catalogued] constraints
  /// (validation groups); the batch's summary.
  ImportBatch import(List<NewBook> books) {
    for (final book in books) {
      final violations = _validator.validateObject(
        book,
        groups: [Default, Catalogued],
      );
      if (violations.isEmpty) {
        _books.save(book.toBook());
        _batch.getObject().isbns.add(book.isbn);
      } else {
        _batch.getObject().rejected.add(
          '${book.isbn}: ${violations.map((v) => v.propertyPath).join(', ')}',
        );
      }
    }
    final batch = _batch.getObject();
    _scope.end();
    return batch;
  }
}
