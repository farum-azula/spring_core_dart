import 'package:flutter_notes/src/notes/note.dart';
import 'package:flutter_notes/src/notes/notes.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The REST API of the notes, served by the app itself:
///
/// | Request | Answer |
/// |---|---|
/// | `GET /api/notes` | every note, the newest first |
/// | `GET /api/notes/{id}` | one note, or 404 |
/// | `POST /api/notes` `{"text": "..."}` | 201 with the note and a `Location` header; 400 when the text is empty |
/// | `DELETE /api/notes/{id}` | 204, or 404 |
/// | `GET /api/notes/events` | each new note as a server-sent event |
///
/// It calls the same `Notes` bean as the screen, so the screen updates
/// while the request is answered.
@RestController()
@RequestMapping('/api/notes')
class NoteController {
  NoteController(this.notes);

  final Notes notes;

  @GetMapping()
  List<Note> all() => notes.all;

  @GetMapping('/{id}')
  Note find(@PathVariable() int id) =>
      notes.find(id) ?? (throw NoteNotFound(id));

  @PostMapping()
  ResponseEntity<Note> add(@RequestBody() @Valid() NewNote note) {
    final added = notes.add(note.text);
    return ResponseEntity.created(Uri.parse('/api/notes/${added.id}'))
        .body(added);
  }

  @DeleteMapping('/{id}')
  @ResponseStatus(HttpStatus.noContent)
  void remove(@PathVariable() int id) {
    if (!notes.remove(id)) {
      throw NoteNotFound(id);
    }
  }

  /// `text/event-stream`: `curl -N localhost:8080/api/notes/events`.
  @GetMapping('/events')
  EventStream<Note> events() => EventStream(
    () => notes.added.map((note) => ServerSentEvent(note, id: '${note.id}')),
  );

  /// `application/problem+json`: `{"status": 404, "detail": "No note 7"}`.
  @ExceptionHandler()
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail notFound(NoteNotFound e) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No note ${e.id}');
}
