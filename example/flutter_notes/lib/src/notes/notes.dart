import 'dart:async';

import 'package:flutter_notes/src/notes/note.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The notes: one bean for the screen and the API. The widgets and
/// `NoteController` get the same instance, so a note added by either is
/// seen by both.
///
/// `@ChangeNotifierComponent`: the proxy notifies the widgets after every
/// method (`add`, `remove`), whoever called it: a tap or an HTTP request.
@ChangeNotifierComponent(exclude: ['find'])
class Notes {
  final _notes = <Note>[];
  final _added = StreamController<Note>.broadcast();
  var _nextId = 1;

  /// Every note, the newest first.
  List<Note> get all => List.unmodifiable(_notes.reversed);

  /// Each note as it is added (`GET /api/notes/events`).
  Stream<Note> get added => _added.stream;

  /// The note [id], or `null`.
  Note? find(int id) => _notes.where((note) => note.id == id).firstOrNull;

  /// Adds a note with [text] (trimmed).
  Note add(String text) {
    final note = Note(
      id: _nextId++,
      text: text.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    _notes.add(note);
    _added.add(note);
    return note;
  }

  /// Removes the note [id]; `false` when there is none.
  bool remove(int id) {
    final before = _notes.length;
    _notes.removeWhere((note) => note.id == id);
    return _notes.length != before;
  }
}
