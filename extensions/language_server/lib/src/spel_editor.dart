import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// What every Dart object has: not reported as unknown members.
const _objectMembers = {'toString', 'hashCode', 'runtimeType', 'noSuchMethod'};

/// One `@bean.member.member` path in an expression.
final class _Chain {
  _Chain(this.bean, this.start, this.end);

  final String bean;

  /// The span of `@bean`.
  final int start;
  final int end;

  /// The members after it, each with its own span.
  final members = <(String, int, int)>[];
}

/// What SpEL editing knows about beans and their members: completion after
/// `@` and `.`, hovers, go to definition and the unknown bean / member
/// check. The beans and their members come from the metadata of the package
/// and its dependencies; a bean the workspace finds in the source and the
/// metadata does not list yet has no members, so nothing is said about
/// them.
final class SpelEditor {
  /// An editor over the beans of [workspace].
  SpelEditor(this.workspace);

  /// The workspace whose beans are used.
  final SpringWorkspace workspace;

  // Spans of string literals, where an `@` is plain text.
  static List<(int, int)> _strings(String expression) {
    final spans = <(int, int)>[];
    String? quote;
    var from = 0;
    for (var i = 0; i < expression.length; i++) {
      final c = expression[i];
      if (quote != null) {
        if (c == quote) {
          spans.add((from, i));
          quote = null;
        }
      } else if (c == "'" || c == '"') {
        quote = c;
        from = i;
      }
    }
    return spans;
  }

  static List<_Chain> _chains(String expression) {
    final strings = _strings(expression);
    final result = <_Chain>[];
    for (final match in RegExp(r'@([A-Za-z_]\w*)').allMatches(expression)) {
      if (strings.any((s) => match.start > s.$1 && match.start < s.$2)) {
        continue;
      }
      final chain = _Chain(match.group(1)!, match.start, match.end);
      var position = match.end;
      final step = RegExp(r'\s*\??\.\s*([A-Za-z_]\w*)');
      while (true) {
        final next = step.matchAsPrefix(expression, position);
        if (next == null) {
          break;
        }
        final name = next.group(1)!;
        chain.members.add((name, next.end - name.length, next.end));
        position = next.end;
        if (position < expression.length && expression[position] == '(') {
          var depth = 0;
          var i = position;
          for (; i < expression.length; i++) {
            if (expression[i] == '(') {
              depth++;
            } else if (expression[i] == ')') {
              depth--;
              if (depth == 0) {
                break;
              }
            }
          }
          position = i + 1;
        }
      }
      result.add(chain);
    }
    return result;
  }

  static String _baseType(String type) {
    var base = type.trim();
    final angle = base.indexOf('<');
    if (angle > 0) {
      base = base.substring(0, angle);
    }
    return base.replaceAll('?', '').trim();
  }

  // The members of the bean named [name]: from the metadata; `null` when no
  // bean of that name lists any.
  List<MetaMember>? _membersOfBean(String name) {
    for (final bean in workspace.beansNamed(name)) {
      if (bean.members.isNotEmpty) {
        return bean.members;
      }
    }
    return null;
  }

  // The members of the beans of [type], when one lists them.
  List<MetaMember>? _membersOfType(String type) {
    final base = _baseType(type);
    for (final bean in workspace.beans) {
      if (bean.members.isNotEmpty && bean.providedTypes.contains(base)) {
        return bean.members;
      }
    }
    return null;
  }

  // The members and the types along [chain] up to (not including) the
  // member at [index]: the members the member at [index] is looked up in.
  List<MetaMember>? _scopeOf(_Chain chain, int index) {
    var members = _membersOfBean(chain.bean);
    for (var i = 0; i < index && members != null; i++) {
      final found = members.where((m) => m.name == chain.members[i].$1);
      members = found.isEmpty ? null : _membersOfType(found.first.type);
    }
    return members;
  }

  /// The unknown beans and members of [expression] (offsets inside it).
  /// With [complete] false (a dependency has no metadata yet) they are
  /// warnings, since the missing metadata may hold them.
  List<SpelIssue> issues(String expression, {required bool complete}) {
    final result = <SpelIssue>[];
    final names = {
      for (final bean in workspace.beans) ...[bean.name, ...bean.aliases],
    };
    if (names.isEmpty) {
      return result;
    }
    for (final chain in _chains(expression)) {
      if (workspace.beansNamed(chain.bean).isEmpty) {
        final guess = didYouMean(chain.bean, names.toList());
        result.add(
          SpelIssue(
            chain.start,
            chain.end,
            "Unknown bean '${chain.bean}'"
            "${guess == null ? '' : ". Did you mean '@$guess'?"}",
            error: complete,
          ),
        );
        continue;
      }
      for (var i = 0; i < chain.members.length; i++) {
        final scope = _scopeOf(chain, i);
        if (scope == null) {
          break;
        }
        final (name, start, end) = chain.members[i];
        if (scope.any((m) => m.name == name) || _objectMembers.contains(name)) {
          continue;
        }
        final guess = didYouMean(name, [for (final m in scope) m.name]);
        final owner = i == 0
            ? "bean '${chain.bean}'"
            : "'${chain.members[i - 1].$1}'";
        result.add(
          SpelIssue(
            start,
            end,
            "Unknown member '$name' of $owner"
            "${guess == null ? '' : ". Did you mean '$guess'?"}",
          ),
        );
        break;
      }
    }
    return result;
  }

  /// A hover for the bean or member at [at] of [expression]; with [beanPart]
  /// false only for a member.
  String? hover(String expression, int at, {bool beanPart = true}) {
    for (final chain in _chains(expression)) {
      if (at >= chain.start && at <= chain.end) {
        if (!beanPart) {
          return null;
        }
        final beans = workspace.beansNamed(chain.bean);
        if (beans.isEmpty) {
          return '**@${chain.bean}**: no such bean';
        }
        return [
          '**@${chain.bean}**',
          '',
          for (final bean in beans) '- ${bean.summary}',
        ].join('\n');
      }
      for (var i = 0; i < chain.members.length; i++) {
        final (name, start, end) = chain.members[i];
        if (at < start || at > end) {
          continue;
        }
        final found = _scopeOf(chain, i)?.where((m) => m.name == name);
        if (found == null || found.isEmpty) {
          return null;
        }
        return '**$name**\n\n`${found.first.summary}`';
      }
    }
    return null;
  }

  /// The beans to go to from [at] in [expression].
  List<BeanInfo> definition(String expression, int at) {
    for (final chain in _chains(expression)) {
      final end = chain.members.isEmpty ? chain.end : chain.members.last.$3;
      if (at >= chain.start && at <= end) {
        return workspace.beansNamed(chain.bean);
      }
    }
    return const [];
  }

  /// Completions for the expression text before the cursor: the offset where
  /// the replaced word starts, and the proposals. `null` outside a bean
  /// reference.
  (int, List<Completion>)? complete(String prefix) {
    if ("'".allMatches(prefix).length.isOdd) {
      return null; // inside a string
    }
    final bean = RegExp(r'@(\w*)$').firstMatch(prefix);
    if (bean != null) {
      final typed = bean.group(1)!;
      return (
        prefix.length - typed.length,
        [
          for (final b in workspace.beans)
            Completion(
              b.name,
              kind: 6,
              detail: b.typeName,
              documentation: b.summary,
            ),
        ],
      );
    }
    final member = RegExp(
      r'@([A-Za-z_]\w*)((?:\s*\??\.\s*[A-Za-z_]\w*(?:\([^()]*\))?)*)\s*\??\.\s*(\w*)$',
    ).firstMatch(prefix);
    if (member == null) {
      return null;
    }
    final typed = member.group(3)!;
    final chain = _Chain(member.group(1)!, 0, 0);
    for (final step in RegExp(r'\.\s*([A-Za-z_]\w*)').allMatches(
      member.group(2)!,
    )) {
      chain.members.add((step.group(1)!, 0, 0));
    }
    final members = _scopeOf(chain, chain.members.length);
    if (members == null) {
      return null;
    }
    return (
      prefix.length - typed.length,
      [
        for (final m in members)
          Completion(
            m.name,
            kind: m.kind == 'method' ? 2 : 10,
            detail: m.type,
            documentation: m.summary,
          ),
      ],
    );
  }
}
