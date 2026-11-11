// An application that declares what the starter gives: buckets, functions
// and cached calls. The generator writes its beans
// (../spring_gen/app/supabase_app.spring.dart, from
// `dart run build_runner build`); the tests start it with the starter's
// auto-configurations and a fake HTTP transport.
import 'dart:async';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

import '../spring_gen/app/supabase_app.spring.dart';

@Introspected()
class Settings {
  Settings({required this.theme, this.fontSize = 14});

  final String theme;
  final int fontSize;
}

@Introspected()
class Invite {
  Invite({required this.email});

  final String email;
}

@Introspected()
class InviteResult {
  InviteResult({required this.id});

  final String id;
}

enum AvatarKind { small, large }

enum Priority { low, high }

@Table('todos')
class Todo {
  Todo({
    required this.title,
    required this.listId,
    this.done = false,
    this.priority = Priority.low,
    this.id,
    this.createdAt,
    this.version,
  });

  @Id()
  int? id;

  String title;
  String listId;
  bool done;
  Priority priority;
  DateTime? createdAt;

  @Version()
  int? version;
}

@Table('notes')
class Note {
  Note({required this.text, this.id});

  @Id()
  String? id;

  String text;
}

/// How a parcel is packed: a class kept in a `jsonb` column, described for
/// the ObjectMapper by the build.
class Packaging {
  Packaging({required this.box, this.fragile = false, this.size});

  String box;
  bool fragile;
  BoxSize? size;
}

/// A class inside [Packaging].
class BoxSize {
  BoxSize({required this.width, required this.height});

  int width;
  int height;
}

/// An element of a list kept in a `jsonb` column.
class Stop {
  Stop({required this.city, this.day});

  String city;
  int? day;
}

@Table('parcels')
class Parcel {
  Parcel({
    required this.label,
    required this.packaging,
    this.stops = const [],
    this.id,
  });

  @Id()
  int? id;

  String label;

  @Json()
  Packaging packaging;

  @Json()
  List<Stop> stops;
}

/// JSON columns over the REST API.
@UseStore('supabase')
abstract interface class Parcels implements ListCrudRepository<Parcel, int> {
  Future<List<Parcel>> findByLabel(String label);
}

/// On the REST API of the project.
@UseStore('supabase')
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  Future<List<Todo>> findByDoneOrderByCreatedAtDesc(bool done);

  Future<List<Todo>> findByTitleStartingWithIgnoreCase(String prefix);

  Future<List<Todo>> findByListIdAndDoneOrPriority(
    String listId,
    bool done,
    Priority priority,
  );

  Future<Page<Todo>> findByListId(String listId, Pageable pageable);

  Future<List<Todo>> findByIdIn(List<int> ids);

  Future<List<Todo>> findByCreatedAtBetween(DateTime from, DateTime to);

  Future<Todo?> findFirstByListIdOrderByIdDesc(String listId);

  Future<int> countByDone(bool done);

  Future<bool> existsByTitle(String title);

  Future<int> deleteByDone(bool done);

  @Procedure('close_all')
  Future<int> closeAll(String listId);

  Stream<List<Todo>> watchByListId(String listId);

  Stream<RowChange<Todo>> changesByListId(String listId);
}

/// Without a version: an update of a row that is not there.
@UseStore('supabase')
abstract interface class Notes implements ListCrudRepository<Note, String> {}

@StorageBucket(r'${app.buckets.avatars:avatars}')
abstract interface class Avatars {
  @Upload('#{authentication.name}/avatar.png', upsert: true)
  Future<void> put(Uint8List bytes);

  @Upload('{userId}/{name}', contentType: 'text/plain')
  Future<void> putText(String userId, String name, @RequestBody() String text);

  @Upload('{userId}/stream.bin')
  Future<void> putStream(String userId, Stream<List<int>> bytes);

  @Download('{userId}/#{#kind.name}.png')
  Stream<List<int>> get(String userId, AvatarKind kind);

  @Download('{userId}/avatar.png')
  Future<Uint8List> bytes(String userId);

  @Download('{userId}/avatar.png')
  Future<Uint8List?> bytesOrNull(String userId);

  @SignedUrl('{userId}/avatar.png', expiresIn: Duration(minutes: 5))
  Future<Uri> link(String userId);

  @SignedUrl('{userId}/avatar.png')
  Future<String> linkText(String userId);

  @PublicUrl('{userId}/avatar.png')
  Uri publicLink(String userId);

  @PublicUrl('{userId}/avatar.png', download: true)
  String publicDownload(String userId);

  @StorageObject('{userId}/settings.json')
  Future<Settings?> settings(String userId);

  @StorageObject('{userId}/settings.json')
  Future<Settings> requiredSettings(String userId);

  @StorageObject('{userId}/settings.json')
  Future<void> saveSettings(String userId, Settings settings);

  @DeleteObject('{userId}/avatar.png')
  Future<void> remove(String userId);
}

@Introspected()
class Cursor {
  Cursor({required this.x, required this.y});

  final int x;
  final int y;
}

@Introspected()
class Member {
  Member({required this.name, this.typing = false});

  final String name;
  final bool typing;
}

@RealtimeChannel('room:{id}')
abstract interface class Room {
  @Broadcast('cursor')
  Stream<Cursor> cursors(String id);

  @Broadcast('cursor')
  Future<void> moveCursor(String id, Cursor cursor);

  @Presence()
  Stream<List<Member>> members(String id);

  @Presence()
  Future<void> join(String id, Member me);

  @PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}')
  Stream<RealtimeRowChange> messages(String id);
}

@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('send-invite')
  Future<InviteResult> sendInvite(@RequestBody() Invite invite);

  @EdgeFunction('stats', method: HttpMethod.get)
  Future<Map<String, Object?>> stats(@RequestParam('from') String from);

  @EdgeFunction('reports/{year}', method: HttpMethod.get)
  Future<String> report(@PathVariable() int year);

  /// Server-sent events, as they arrive.
  @EdgeFunction('progress', method: HttpMethod.get)
  EventStream<Map<String, Object?>> progress();

  /// A file, whole.
  @EdgeFunction('export', method: HttpMethod.get)
  Future<Uint8List> export();

  /// A file (or any body), as it arrives.
  @EdgeFunction('export', method: HttpMethod.get)
  Stream<List<int>> exportStream();
}

/// Cached calls of a function, with and without a key of their own.
@Service()
class Reports {
  Reports(this.functions);

  final Functions functions;

  /// How many times a body ran.
  int calls = 0;

  @Cacheable('reports')
  Future<String> byYear(int year) {
    calls++;
    return functions.report(year);
  }

  @Cacheable('reports', key: "'explicit:' + #year")
  Future<String> byYearWithKey(int year) {
    calls++;
    return functions.report(year);
  }

  @Cacheable('catalog')
  Future<String> shared(int year) {
    calls++;
    return functions.report(year);
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
