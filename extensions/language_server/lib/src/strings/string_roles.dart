import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/strings/roles/bean_name_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/conditional_property_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/configuration_properties_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/message_code_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/pointcut_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/profile_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/property_method_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/resource_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/route_address_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/route_message_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/screen_branch_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/spel_argument_role.dart';
import 'package:dart_spring_language_server/src/strings/roles/template_role.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

/// The roles a string of a Dart file can have, in the order they are
/// asked: a new kind of string is a new [StringRole] and one entry here.
///
/// The order matters where two roles could claim a string: a resource
/// location is one wherever it is written, a pointcut or a cache key is
/// not read as a template, a bean name before a template.
List<StringRole> stringRoles(ProjectModel model) => [
  ResourceRole(model),
  RouteMessageRole(model),
  ScreenBranchRole(model),
  RouteAddressRole(model),
  PointcutRole(model),
  SpelArgumentRole(model),
  BeanNameRole(model),
  ConditionalPropertyRole(model),
  ConfigurationPropertiesRole(model),
  TemplateRole(model),
  MessageCodeRole(model),
  PropertyMethodRole(model),
  ProfileRole(model),
];

/// The chain of [StringRole]s: asks them about a string, each feature the
/// way it needs.
final class StringRoles {
  /// The chain of [roles], asked in their order.
  StringRoles(this.roles);

  /// The roles.
  final List<StringRole> roles;

  /// The target at [offset] of [string]: the answer of the first role that
  /// handles it.
  Target? targetAt(StringContext string, int offset) {
    for (final role in roles) {
      if (role.target(string, offset) case final handled?) {
        return handled.value;
      }
    }
    return null;
  }

  /// The completion of [request]: the answer of the first role that
  /// handles its string.
  CompletionResult? complete(CompletionRequest request) {
    for (final role in roles) {
      if (role.complete(request.string, request) case final handled?) {
        return handled.value;
      }
    }
    return null;
  }

  /// Adds the tokens every role finds in [strings].
  void tokens(Iterable<StringContext> strings, AddToken add) {
    for (final role in roles) {
      for (final string in strings) {
        role.tokens(string, add);
      }
    }
  }

  /// Adds the problems every role finds in [strings], role by role.
  void problems(Iterable<StringContext> strings, List<Problem> problems) {
    for (final role in roles) {
      for (final string in strings) {
        role.problems(string, problems);
      }
    }
  }

  /// The keys [string] reads, as the first role that knows says.
  Iterable<String> keysRead(StringContext string) {
    for (final role in roles) {
      if (role.keysRead(string) case final keys?) {
        return keys;
      }
    }
    return const [];
  }

  /// The places in [strings] that read a property.
  Iterable<PropertyReference> references(
    Iterable<StringContext> strings,
  ) sync* {
    for (final string in strings) {
      for (final role in roles) {
        yield* role.references(string);
      }
    }
  }
}
