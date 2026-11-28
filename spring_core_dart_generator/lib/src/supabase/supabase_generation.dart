// spring_boot_starter_supabase's part of the module build: where the
// methods of its generated interfaces go, and the group its Edge Functions
// interfaces are imported into.
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_model.dart';

// Matched by URL (the generator does not depend on the starter).
const _storage =
    'package:spring_boot_starter_supabase/src/storage/storage_bucket.dart';
const _realtime =
    'package:spring_boot_starter_supabase/src/realtime/realtime_channel.dart';
const _functions =
    'package:spring_boot_starter_supabase/src/functions/edge_functions.dart';

/// The part of `spring_boot_starter_supabase` in the module build: the
/// operations of a `@StorageBucket`, a `@RealtimeChannel` and an
/// `@EdgeFunctions` interface go on the abstract methods of such an
/// interface, whose implementation the starter makes; on a class of the
/// application nothing would read them. An `@EdgeFunctions` interface is
/// imported into the group `EdgeFunctions.group`, the one the starter
/// points at the project; another group fails the build. It writes
/// nothing of its own.
final class SupabaseGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const SupabaseGeneration();

  @override
  String get package => 'spring_boot_starter_supabase';

  // What an app connects with: the anon key is public by design (row
  // level security guards the data).
  @override
  List<String> get publicDefines => const [
    'spring.supabase.url',
    'spring.supabase.anon-key',
  ];

  @override
  List<AnnotationPlacement> get placements => const [
    MethodPlacement(
      [
        TypeChecker.fromUrl('$_storage#Upload'),
        TypeChecker.fromUrl('$_storage#Download'),
        TypeChecker.fromUrl('$_storage#SignedUrl'),
        TypeChecker.fromUrl('$_storage#PublicUrl'),
        TypeChecker.fromUrl('$_storage#StorageObject'),
        TypeChecker.fromUrl('$_storage#DeleteObject'),
      ],
      does: 'the starter implements it on the bucket',
      methodOwner: AnnotatedOwner([
        TypeChecker.fromUrl('$_storage#StorageBucket'),
      ]),
      ownerNoun: '@StorageBucket interface',
      ownerFix: "an abstract interface with @StorageBucket('...')",
    ),
    MethodPlacement(
      [
        TypeChecker.fromUrl('$_realtime#Broadcast'),
        TypeChecker.fromUrl('$_realtime#Presence'),
        TypeChecker.fromUrl('$_realtime#PostgresChanges'),
      ],
      does: 'the starter implements it on the channel',
      methodOwner: AnnotatedOwner([
        TypeChecker.fromUrl('$_realtime#RealtimeChannel'),
      ]),
      ownerNoun: '@RealtimeChannel interface',
      ownerFix: "an abstract interface with @RealtimeChannel('...')",
    ),
    MethodPlacement(
      [TypeChecker.fromUrl('$_functions#EdgeFunction')],
      does: 'the starter calls the function through it',
      methodOwner: AnnotatedOwner([
        TypeChecker.fromUrl('$_functions#EdgeFunctions'),
      ]),
      ownerNoun: '@EdgeFunctions interface',
      ownerFix: 'an abstract interface with @EdgeFunctions()',
    ),
  ];
  // The interfaces of `@ImportHttpServices` (the HTTP service part) whose
  // annotation pins their group: imported into another one, they would
  // call that group's RestClient, not the project's.
  @override
  Future<void> checkModule(ModuleBuild build) async {
    final model = HttpServiceModuleModel.of(build.module);
    for (final MapEntry(key: element, value: group) in model.groupOf.entries) {
      for (final pinned in _pinnedGroups) {
        build.collectErrors(() => pinned.check(element, group));
      }
    }
  }
}

const _pinnedGroups = [
  _PinnedGroup(
    TypeChecker.fromUrl('$_functions#EdgeFunctions'),
    calls: "the project's Edge Functions",
  ),
];

// An interface annotation whose class names, in its static `group`, the
// one HTTP service group its interfaces may be imported into.
final class _PinnedGroup {
  const _PinnedGroup(this.annotation, {required this.calls});

  final TypeChecker annotation;

  // What the group's RestClient reaches, for the message.
  final String calls;

  void check(InterfaceElement element, String group) {
    final marked = annotation
        .firstAnnotationOfExact(element, throwOnUnresolved: false)
        ?.type
        ?.element;
    if (marked is! InterfaceElement) {
      return;
    }
    final pinned = marked
        .getField('group')
        ?.computeConstantValue()
        ?.toStringValue();
    if (pinned == null || pinned == group) {
      return;
    }
    final name = element.displayName;
    final annotationName = marked.displayName;
    throw InvalidGenerationSource(
      '$name has @$annotationName and is imported into the group "$group": '
      'an @$annotationName interface calls $calls through the group '
      '"$pinned", whose RestClient the starter configures, and the group '
      '"$group" would send its calls elsewhere. Import it with '
      '@ImportHttpServices(group: $annotationName.group, types: [$name]).',
      element: element,
    );
  }
}
