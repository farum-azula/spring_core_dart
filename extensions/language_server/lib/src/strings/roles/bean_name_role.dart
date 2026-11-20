import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Annotations whose string arguments name beans.
const _beanNameAnnotations = {
  'Qualifier',
  'DependsOn',
  'ConditionalOnBean',
  'ConditionalOnMissingBean',
};

/// A bean name: a string of `@Qualifier`, `@DependsOn`,
/// `@ConditionalOnBean` or `@ConditionalOnMissingBean`. Go to definition
/// on `'cash'` in `@Qualifier('cash')` leads to the beans named or
/// qualified `cash`, and each completes with the bean names.
final class BeanNameRole extends StringRole {
  /// The role, over [model].
  const BeanNameRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    if (!_beanNameAnnotations.contains(string.annotationType)) {
      return null;
    }
    final name = string.value;
    return Handled(BeanTarget(model.beans.beansNamed(name), "Bean '$name'"));
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (!_beanNameAnnotations.contains(string.annotationType) ||
        request.inTemplate) {
      return null;
    }
    return Handled(
      CompletionResult(request.wordRange, [
        for (final bean in model.beans.beans)
          Completion(bean.name, kind: 6, detail: bean.typeName),
      ]),
    );
  }
}
