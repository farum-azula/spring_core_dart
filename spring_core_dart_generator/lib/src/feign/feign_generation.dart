// spring_boot_starter_feign's part of the module build: what a client's
// methods and parameters may carry.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// Matched by URL (the generator depends on neither the starter nor the
// web library).
const _feignClient = TypeChecker.fromUrl(
  'package:spring_boot_starter_feign/src/feign_client.dart#FeignClient',
);
const _web = 'package:spring_web_dart/src/annotations.dart';
const _mapping = TypeChecker.fromUrl('$_web#Mapping');
const _requestMappings = [
  TypeChecker.fromUrl('$_web#RequestMapping'),
  TypeChecker.fromUrl('$_web#GetMapping'),
  TypeChecker.fromUrl('$_web#PostMapping'),
  TypeChecker.fromUrl('$_web#PutMapping'),
  TypeChecker.fromUrl('$_web#PatchMapping'),
  TypeChecker.fromUrl('$_web#DeleteMapping'),
];
// What a client sends a parameter as.
const _roles = [
  TypeChecker.fromUrl('$_web#PathVariable'),
  TypeChecker.fromUrl('$_web#RequestParam'),
  TypeChecker.fromUrl('$_web#RequestHeader'),
  TypeChecker.fromUrl('$_web#CookieValue'),
  TypeChecker.fromUrl('$_web#RequestBody'),
  TypeChecker.fromUrl('$_web#RequestPart'),
];

/// The part of `spring_boot_starter_feign` in the module build: a
/// `@FeignClient` method is mapped by a request mapping of the web library
/// (`@GetMapping`, ...), not by another starter's mapping (`@EdgeFunction`);
/// and each annotated parameter says how it is sent (`@PathVariable`,
/// `@RequestParam`, `@RequestHeader`, `@CookieValue`, `@RequestBody`,
/// `@RequestPart`). An annotation of another role (a server's
/// `@AuthenticationPrincipal`, `@PageableDefault`, `@Selector`) would
/// count as none, so the value would be sent as the body: it fails the
/// build. The container's own annotations (`@Valid`, constraints) are
/// kept. It writes nothing of its own.
final class FeignGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const FeignGeneration();

  @override
  String get package => 'spring_boot_starter_feign';

  @override
  List<AnnotationPlacement> get placements => const [
    ClassPlacement([
      _feignClient,
    ], instead: 'Put it on an abstract interface class'),
  ];

  @override
  void scanClass(ClassElement element, ModuleScan scan) {
    if (!_feignClient.hasAnnotationOf(element)) {
      return;
    }
    for (final method in element.methods) {
      for (final annotation in method.metadata.annotations) {
        final type = annotation.computeConstantValue()?.type;
        if (type is InterfaceType &&
            _mapping.isAssignableFromType(type) &&
            !_requestMappings.any((c) => c.isExactlyType(type))) {
          scan.collectErrors(
            () => throw InvalidGenerationSource(
              '@${type.element.name} on ${element.name}.${method.name}: a '
              '@FeignClient method is mapped by @GetMapping, @PostMapping, '
              '@PutMapping, @PatchMapping, @DeleteMapping or '
              '@RequestMapping; @${type.element.name} belongs to another '
              'kind of client.',
              element: method,
            ),
          );
        }
      }
      for (final parameter in method.formalParameters) {
        for (final annotation in parameter.metadata.annotations) {
          final type = annotation.computeConstantValue()?.type;
          if (type is! InterfaceType || _kept(type)) {
            continue;
          }
          scan.collectErrors(
            () => throw InvalidGenerationSource(
              '${element.name}.${method.name}: parameter ${parameter.name} '
              'has @${type.element.name}, which a client cannot send, so '
              'the value would go as the request body. Use @RequestParam, '
              '@RequestHeader, @PathVariable, @CookieValue, @RequestBody or '
              '@RequestPart.',
              element: parameter,
            ),
          );
        }
      }
    }
  }

  static bool _kept(InterfaceType type) {
    final library = type.element.library;
    final uri = '${library.uri}';
    return library.isInSdk ||
        uri.startsWith('package:meta/') ||
        uri.startsWith('package:spring_core_dart/') ||
        _roles.any((role) => role.isExactlyType(type));
  }
}
