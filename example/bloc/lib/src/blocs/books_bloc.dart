import 'package:bloc_showcase/src/blocs/books_event.dart';
import 'package:bloc_showcase/src/blocs/books_state.dart';
import 'package:bloc_showcase/src/books/book_repository.dart';
import 'package:bloc_showcase/src/blocs/closed_with_bean.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// A Bloc with events and states, and a dependency: the repository comes
/// through the constructor, as into any bean. Nothing registers the bloc
/// or its repository by hand.
@Component()
class BooksBloc extends Bloc<BooksEvent, BooksState>
    with ClosedWithBean<BooksState> {
  /// The shelf of [repository], loading.
  BooksBloc(this.repository) : super(const BooksLoading()) {
    on<BooksRequested>(_load);
    on<BookAdded>(_add);
  }

  /// Where the books are kept.
  final BookRepository repository;

  Future<void> _load(BooksRequested event, Emitter<BooksState> emit) async {
    emit(const BooksLoading());
    emit(BooksLoaded(await repository.all()));
  }

  Future<void> _add(BookAdded event, Emitter<BooksState> emit) async {
    try {
      await repository.add(event.title);
      emit(BooksLoaded(await repository.all()));
    } on StateError catch (error) {
      emit(BooksLoaded(await repository.all(), problem: error.message));
    }
  }

  // A release build shortens class names: the journal shows this one.
  @override
  String toString() => 'BooksBloc';
}
