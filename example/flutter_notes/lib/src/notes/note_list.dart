import 'package:flutter/material.dart';
import 'package:flutter_notes/src/notes/notes.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The notes, the newest first. It reads `notes.all` in build, so it
/// rebuilds after every change of the bean: a tap here or a request to the
/// API.
class NoteList extends SpringStatelessWidget<(Notes,)> {
  const NoteList({super.key});

  @override
  Widget build(BuildContext context) {
    final (notes,) = beans;
    final all = notes.all;
    if (all.isEmpty) {
      return const Center(child: Text('No notes yet'));
    }
    return ListView.builder(
      itemCount: all.length,
      itemBuilder: (context, index) {
        final note = all[index];
        return ListTile(
          leading: CircleAvatar(child: Text('${note.id}')),
          title: Text(note.text),
          subtitle: Text(_time(note.createdAt.toLocal())),
          trailing: IconButton(
            onPressed: () => notes.remove(note.id),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
          ),
        );
      },
    );
  }

  static String _time(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
