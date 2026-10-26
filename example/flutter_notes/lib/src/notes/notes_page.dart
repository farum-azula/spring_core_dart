import 'package:flutter/material.dart';
import 'package:flutter_notes/src/api/api_banner.dart';
import 'package:flutter_notes/src/notes/note_input.dart';
import 'package:flutter_notes/src/notes/note_list.dart';

/// The only page: where the API listens, a field to add a note, the notes.
///
/// The page holds no state and reads no bean: only [NoteList] rebuilds when
/// a note is added (from here or over HTTP), only [ApiBanner] when the
/// server starts or stops.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Notes'),
      ),
      body: const Column(
        children: [
          ApiBanner(),
          NoteInput(),
          Expanded(child: NoteList()),
        ],
      ),
    );
  }
}
