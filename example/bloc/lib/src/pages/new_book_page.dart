import 'package:bloc_showcase/src/blocs/books_bloc.dart';
import 'package:bloc_showcase/src/blocs/books_event.dart';
import 'package:bloc_showcase/src/blocs/draft_cubit.dart';
import 'package:bloc_showcase/src/pages/tap.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// `/new`: a title is typed into a Cubit that belongs to this screen (the
/// `route` scope): leaving the screen closes it, and the next visit gets
/// a new one.
@ScreenRoute('/new', title: 'A new book')
class NewBookPage extends StatefulWidget {
  /// The page.
  const NewBookPage({super.key});

  @override
  State<NewBookPage> createState() => _NewBookPageState();
}

class _NewBookPageState extends State<NewBookPage> {
  final TextEditingController _title = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The screen's own: the same object for every widget of this screen.
    final draft = context.bean<DraftCubit>();
    return ColoredBox(
      color: const Color(0xFF0B0E13),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE6EAF2), fontSize: 15),
        child: Center(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('A new book', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 16),
                EditableText(
                  controller: _title,
                  focusNode: _focus,
                  autofocus: true,
                  style: const TextStyle(
                    color: Color(0xFFE6EAF2),
                    fontSize: 15,
                  ),
                  cursorColor: const Color(0xFF22E6FF),
                  backgroundCursorColor: const Color(0xFF8A93A6),
                  onChanged: draft.type,
                ),
                const SizedBox(height: 8),
                BlocBuilder<DraftCubit, String>(
                  bloc: draft,
                  builder: (context, title) => Text(
                    title.isEmpty ? 'Type a title' : 'Title: $title',
                    key: const ValueKey('draft'),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tap('Cancel', onTap: () => context.route.pop()),
                    Tap(
                      'Add',
                      onTap: () {
                        if (draft.state.isNotEmpty) {
                          context.bean<BooksBloc>().add(BookAdded(draft.state));
                        }
                        context.route.pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
