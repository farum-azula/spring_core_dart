import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// Methods whose first positional argument is a message code:
/// `context.message('cart.empty')`, `messageSource.getMessage(...)`.
/// `Intl.message(...)` is not one.
const _messageMethods = {'message', 'getMessage'};

/// A message code: the first argument of `context.message('code')` or
/// `getMessage('code')`. It goes to the bundles of the package, completes
/// from them, and, in a package with bundles that does not use the code as
/// the default message, a code no bundle defines and no code registers is
/// reported (unless the call gives a `defaultMessage:`).
final class MessageCodeRole extends StringRole {
  /// The role, over [model].
  const MessageCodeRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  static bool _claims(StringContext string) {
    final invocation = string.invocation;
    return invocation != null &&
        _isMessageCall(invocation) &&
        identical(
          invocation.argumentList.arguments.first.argumentExpression,
          string.literal,
        );
  }

  // `context.message('code')`, `getMessage('code')`: a message method whose
  // first argument is positional; not `Intl.message('text', name: ...)`.
  static bool _isMessageCall(MethodInvocation invocation) {
    final first = invocation.argumentList.arguments.firstOrNull;
    final target = invocation.target;
    return _messageMethods.contains(invocation.methodName.name) &&
        first != null &&
        first is! NamedArgument &&
        !(target is SimpleIdentifier && target.name == 'Intl');
  }

  @override
  Handled<Target>? target(StringContext string, int offset) => _claims(string)
      ? Handled(
          MessageTarget(
            string.value,
            model.messages.messages(string.value, from: string.path),
          ),
        )
      : null;

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (!_claims(string)) {
      return null;
    }
    return Handled(
      CompletionResult(request.rangeFrom(string.contentStart), [
        for (final code
            in model.messages.messageCodes(string.path).toList()..sort())
          Completion(code, detail: 'message'),
      ]),
    );
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (!_claims(string) ||
        string.invocation!.argumentList.arguments.any(
          (a) => a is NamedArgument && a.name.lexeme == 'defaultMessage',
        ) ||
        !model.messages.checksCodes(string.path) ||
        model.messages.defines(string.path, string.value)) {
      return;
    }
    problems.add(
      Problem(
        model.locations.rangeOf(
          string.file,
          string.contentStart,
          string.contentEnd,
        ),
        "No message '${string.value}' in the message bundles "
        '(messages*.properties)',
      ),
    );
  }
}
