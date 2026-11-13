import 'package:bloc_showcase/src/blocs/books_bloc.dart';
import 'package:bloc_showcase/src/blocs/books_event.dart';
import 'package:bloc_showcase/src/blocs/books_state.dart';
import 'package:bloc_showcase/src/blocs/counter_cubit.dart';
import 'package:bloc_showcase/src/journal.dart';
import 'package:bloc_showcase/src/pages/tap.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// `/`: the counter (a Cubit), the shelf (a Bloc) and the journal of what
/// they did.
@ScreenRoute('/', title: 'Bloc Showcase')
class HomePage extends StatefulWidget {
  /// The page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _text = TextStyle(color: Color(0xFFE6EAF2), fontSize: 15);
  static const _muted = TextStyle(color: Color(0xFF8A93A6), fontSize: 13);

  @override
  void initState() {
    super.initState();
    // The blocs are beans: taken from the application's context.
    SpringScope.of(
      context,
      listen: false,
    ).getBean<BooksBloc>().add(const BooksRequested());
  }

  @override
  Widget build(BuildContext context) {
    final counter = context.bean<CounterCubit>();
    final books = context.bean<BooksBloc>();
    final journal = context.bean<Journal>();
    return ColoredBox(
      color: const Color(0xFF0B0E13),
      child: DefaultTextStyle(
        style: _text,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Bloc Showcase', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 24),
                // Bloc's own widget, given the bean: no BlocProvider above.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tap('−', onTap: counter.decrement),
                    BlocBuilder<CounterCubit, int>(
                      bloc: counter,
                      builder: (context, count) =>
                          Text('$count', key: const ValueKey('count')),
                    ),
                    Tap('+', onTap: counter.increment),
                  ],
                ),
                const SizedBox(height: 24),
                BlocBuilder<BooksBloc, BooksState>(
                  bloc: books,
                  builder: (context, state) => switch (state) {
                    BooksLoading() => const Text('Loading the shelf…'),
                    BooksLoaded(:final books, :final problem) => Column(
                      children: [
                        for (final book in books) Text(book.title),
                        if (problem != null)
                          Text(
                            problem,
                            style: const TextStyle(color: Color(0xFFFF5A7A)),
                          ),
                      ],
                    ),
                  },
                ),
                Tap('Add a book', onTap: () => context.route.push('/new')),
                const SizedBox(height: 24),
                const Text('What the blocs did (application events)'),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: journal,
                  builder: (context, _) => Column(
                    children: [
                      for (final line in journal.lines)
                        Text(line, style: _muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
