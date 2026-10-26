import 'package:flutter/material.dart';
import 'package:flutter_notes/src/notes/note.dart';
import 'package:flutter_notes/src/notes/notes.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The text field and its button: adds a note to the `Notes` bean, the
/// one the API reads.
class NoteInput extends SpringStatefulWidget<(Notes,)> {
  const NoteInput({super.key});

  @override
  State<NoteInput> createState() => _NoteInputState();
}

class _NoteInputState extends SpringState<NoteInput, (Notes,)> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    if (_text.text.trim().isEmpty) {
      return;
    }
    final (notes,) = beans;
    notes.add(_text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('note-text'),
              controller: _text,
              maxLength: noteMaxLength,
              decoration: const InputDecoration(
                hintText: 'A new note',
                counterText: '',
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _add,
            tooltip: 'Add',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
