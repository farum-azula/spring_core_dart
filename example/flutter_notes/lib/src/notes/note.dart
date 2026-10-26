import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The longest note, in characters.
const noteMaxLength = 200;

/// A note, as the screen shows it and the API returns it:
/// `{"id": 1, "text": "Buy milk", "createdAt": "2026-10-27T09:30:00.000Z"}`.
class Note {
  const Note({required this.id, required this.text, required this.createdAt});

  final int id;
  final String text;
  final DateTime createdAt;
}

/// The body of `POST /api/notes`: `{"text": "Buy milk"}`. An empty or too
/// long text is answered with a 400 ProblemDetail (`@Valid`).
class NewNote {
  const NewNote({required this.text});

  @NotBlank()
  @Size(max: noteMaxLength)
  final String text;
}

/// No note with [id]: 404 (see `NoteController.notFound`).
class NoteNotFound implements Exception {
  NoteNotFound(this.id);

  final int id;
}
