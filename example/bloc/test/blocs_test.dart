// Bloc and Cubit as beans: injection, the application's and a screen's
// lifetime, and their changes heard as application events.
import 'package:bloc_showcase/spring_gen/main.spring.dart';
import 'package:bloc_showcase/src/blocs/books_bloc.dart';
import 'package:bloc_showcase/src/blocs/books_event.dart';
import 'package:bloc_showcase/src/blocs/books_state.dart';
import 'package:bloc_showcase/src/blocs/counter_cubit.dart';
import 'package:bloc_showcase/src/blocs/draft_cubit.dart';
import 'package:bloc_showcase/src/books/book.dart';
import 'package:bloc_showcase/src/books/book_repository.dart';
import 'package:bloc_showcase/src/events/spring_bloc_observer.dart';
import 'package:bloc_showcase/src/journal.dart';
import 'package:bloc_showcase/src/pages/home_page.dart';
import 'package:bloc_showcase/src/pages/new_book_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show BeanOverride, springBootTest;

/// A shelf that answers at once.
class _Shelf extends BookRepository {
  final List<Book> books = [const Book('Solaris')];

  @override
  Future<List<Book>> all() async => List.of(books);

  @override
  Future<void> add(String title) async => books.add(Book(title));
}

void main() {
  group('the beans', () {
    final app = springBootTest(
      springApplication,
      overrides: [BeanOverride<BookRepository>(_Shelf())],
    );

    test('a cubit is one bean for the app', () {
      final counter = app.getBean<CounterCubit>();
      expect(app.getBean<CounterCubit>(), same(counter));
      counter.increment();
      expect(counter.state, 1);
    });

    test('a bloc gets its repository by injection', () async {
      final books = app.getBean<BooksBloc>();
      expect(books.repository, isA<_Shelf>());

      books.add(const BooksRequested());
      final loaded = await books.stream.firstWhere(
        (state) => state is BooksLoaded,
      ) as BooksLoaded;
      expect(loaded.books.single.title, 'Solaris');
    });

    test('what a bloc does is heard as application events', () async {
      final journal = app.getBean<Journal>();
      final before = journal.counterChanges;

      app.getBean<CounterCubit>().increment();
      final books = app.getBean<BooksBloc>()..add(const BookAdded('Ubik'));
      await books.stream.firstWhere(
        (state) => state is BooksLoaded && state.books.length == 2,
      );

      expect(journal.counterChanges, before + 1);
      expect(journal.lines, contains('BooksBloc ← BookAdded(Ubik)'));
      expect(
        journal.lines.any((line) => line.startsWith('CounterCubit: ')),
        isTrue,
      );
      // The observer is the app's, as long as the app runs.
      expect(Bloc.observer, same(app.getBean<SpringBlocObserver>()));
    });
  });

  test('the container closes the blocs with the application', () async {
    final previous = Bloc.observer;
    final context = await springApplication.runAsync(const []);
    final counter = context.getBean<CounterCubit>();
    final books = context.getBean<BooksBloc>();
    expect(counter.isClosed, isFalse);

    await context.closeAsync();

    expect(counter.isClosed, isTrue);
    expect(books.isClosed, isTrue);
    // And the observer gave its place back.
    expect(Bloc.observer, same(previous));
  });

  testWidgets('the screens: a tap changes the cubit, a screen has a cubit '
      'of its own', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(application: () => springApplication),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Dune'), findsOneWidget);

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('count'))).data,
      '1',
    );

    // The "new book" screen and its own cubit.
    await tester.tap(find.text('Add a book'));
    await tester.pumpAndSettle();
    final first = SpringScope.beanOf<DraftCubit>(
      tester.element(find.byType(NewBookPage)),
    );
    await tester.enterText(find.byType(EditableText), 'Hyperion');
    await tester.pump();
    expect(find.text('Title: Hyperion'), findsOneWidget);
    expect(first.state, 'Hyperion');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Hyperion'), findsOneWidget);
    // Leaving the screen closed its cubit.
    expect(first.isClosed, isTrue);

    // The next visit starts with a new one, empty.
    await tester.tap(find.text('Add a book'));
    await tester.pumpAndSettle();
    final second = SpringScope.beanOf<DraftCubit>(
      tester.element(find.byType(NewBookPage)),
    );
    expect(second, isNot(same(first)));
    expect(second.state, '');
    expect(find.text('Type a title'), findsOneWidget);
  });
}
