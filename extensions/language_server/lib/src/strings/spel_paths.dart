import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/index/dart_types.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/spel_editor.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/tokens/spel_tokens.dart';
// The SpEL tokenizer is not exported: the paths are read from its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';

/// What the names of one expression stand for at run time.
final class SpelEnv {
  /// [variables] by name (`#order`), and what [rootValues] the root offers.
  const SpelEnv({this.variables = const {}, this.rootValues = const {}});

  /// The `#variables` with a known type; `null` for one without.
  final Map<String, TypeRef?> variables;

  /// The names read on the root with a known type.
  final Map<String, TypeRef?> rootValues;
}

/// A member read in an expression: `owner` of `#order.owner`.
final class SpelMemberUse {
  /// [name] at [start] to [end], read on [owner].
  const SpelMemberUse(this.name, this.start, this.end, this.owner, this.member);

  /// The name.
  final String name;

  /// Its offset in the expression.
  final int start;

  /// The offset after it.
  final int end;

  /// The members of the type it is read on.
  final TypeMembers owner;

  /// The declaration; `null` when the type has none of that name.
  final DartMember? member;
}

/// A name read on the root of an expression.
final class SpelRootUse {
  /// [name] at [start] to [end], [called] when followed by `(`.
  const SpelRootUse(this.name, this.start, this.end, {required this.called});

  /// The name.
  final String name;

  /// Its offset in the expression.
  final int start;

  /// The offset after it.
  final int end;

  /// Whether it is a call.
  final bool called;
}

/// What reading an expression found.
final class SpelReading {
  /// The [members], the [roots], and what a trailing `.` is read on.
  const SpelReading(this.members, this.roots, this.trailing);

  /// The members read on a type that is known.
  final List<SpelMemberUse> members;

  /// The names read on the root.
  final List<SpelRootUse> roots;

  /// The members after a final `.`, when the type before it is known.
  final TypeMembers? trailing;
}

/// A member of a Dart type named in an expression.
final class SpelMemberTarget extends Target {
  /// The target of [member], read on a value of [typeName].
  const SpelMemberTarget(this.member, this.typeName);

  /// The declaration.
  final DartMember member;

  /// The type it was read on.
  final String typeName;

  @override
  List<SourceRange> definitions(TargetContext context) {
    final at = member.file.lineInfo.getLocation(member.offset);
    final end = member.file.lineInfo.getLocation(
      member.offset + member.name.length,
    );
    return [
      SourceRange(
        member.file.path,
        at.lineNumber - 1,
        at.columnNumber - 1,
        end.lineNumber - 1,
        end.columnNumber - 1,
      ),
    ];
  }

  @override
  String hover(TargetContext context) {
    final inherited = member.owner == typeName.split('<').first
        ? ''
        : '\n\nfrom `${member.owner}`';
    final where = context.locations.shortPath(member.file.path);
    return '**$typeName.${member.name}**\n\n`${member.signature}`'
        '$inherited — `$where`';
  }
}

final class _Value {
  const _Value(this.type, {this.isRoot = false});

  static const root = _Value(null, isRoot: true);

  final TypeRef? type;
  final bool isRoot;
}

final class _Frame {
  _Frame({this.after, this.element, this.names = _Names.root});

  final _Value? after;

  /// `#this` and the bare names in a selection or a projection.
  final _Value? element;
  final _Names names;
}

// What a bare name reads in a bracket: the root, the element, or nothing
// that is known (a key of an inline map, a method's argument).
enum _Names { root, element, unknown }

/// Reads the member paths of SpEL expressions on real Dart types: after
/// `#param.`, `returnObject.`, `filterObject.`, `this.`, `#root.this.`,
/// `@bean.`, through `?.`, method calls, indexes and selections.
final class SpelPaths {
  /// Paths over [model].
  SpelPaths(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  DartTypes get _types => model.dartTypes;

  /// What [expression] reads in [env]; nothing when it does not tokenize.
  SpelReading read(String expression, SpelEnv env) {
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return const SpelReading([], [], null);
    }
    final members = <SpelMemberUse>[];
    final roots = <SpelRootUse>[];
    final frames = <_Frame>[_Frame(element: _Value.root)];
    _Value? current;

    String text(Token token) => expression.substring(token.start, token.end);
    bool nextIs(int i, TokenKind kind) =>
        i + 1 < tokens.length && tokens[i + 1].kind == kind;

    _Value? step(_Value? owner, Token token) {
      final name = text(token);
      if (owner == null) {
        return null;
      }
      if (owner.isRoot) {
        return _Value(env.rootValues[name]);
      }
      final type = owner.type;
      if (type == null) {
        return null;
      }
      if (_types.isCollection(type)) {
        return const {'first', 'last', 'single'}.contains(name)
            ? _Value(_types.elementOf(type))
            : null;
      }
      final known = _types.membersOf(type);
      if (known == null) {
        return null;
      }
      final member = known.members[name];
      members.add(SpelMemberUse(name, token.start, token.end, known, member));
      return member == null ? null : _Value(_types.awaited(member.type));
    }

    void call(int i, _Value? after) => frames.add(
      _Frame(
        after: after,
        element: frames.last.element,
        names: _Names.unknown,
      ),
    );

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      switch (token.kind) {
        case TokenKind.hash when nextIs(i, TokenKind.identifier):
          i++;
          final name = text(tokens[i]);
          current = switch (name) {
            'root' => _Value.root,
            'this' => frames.last.element,
            _ => _Value(env.variables[name]),
          };
        case TokenKind.beanRef when nextIs(i, TokenKind.identifier):
          i++;
          current = _Value(_beanType(text(tokens[i])));
        case TokenKind.factoryBeanRef when nextIs(i, TokenKind.identifier):
          i++;
          current = null;
        case TokenKind.identifier:
          final name = text(token);
          final previous = i > 0 ? tokens[i - 1].kind : null;
          final called = nextIs(i, TokenKind.lparen);
          if (previous == TokenKind.dot || previous == TokenKind.safeNavi) {
            current = step(current, token);
          } else if (name == 'T' && called) {
            i = _closing(tokens, i + 1);
            current = null;
            continue;
          } else if (name.toLowerCase() == 'new') {
            if (nextIs(i, TokenKind.identifier)) {
              i++;
            }
            current = null;
            continue;
          } else if (isSpelKeyword(name)) {
            current = null;
            continue;
          } else {
            final frame = frames.last;
            if (frame.names == _Names.unknown) {
              current = null;
            } else {
              final owner = frame.element;
              if (owner != null && owner.isRoot) {
                roots.add(
                  SpelRootUse(name, token.start, token.end, called: called),
                );
              }
              current = step(owner, token);
            }
          }
          if (called) {
            i++;
            call(i, current);
            current = null;
          }
        case TokenKind.lsquare:
          frames.add(
            _Frame(
              after: current == null
                  ? null
                  : _Value(_types.indexed(current.type)),
              element: frames.last.element,
              names: _Names.unknown,
            ),
          );
          current = null;
        case TokenKind.select || TokenKind.selectFirst || TokenKind.selectLast:
          final element = _Value(_types.elementOf(current?.type));
          frames.add(
            _Frame(
              after: token.kind == TokenKind.select ? current : element,
              element: element,
              names: _Names.element,
            ),
          );
          current = null;
        case TokenKind.project:
          frames.add(
            _Frame(
              element: _Value(_types.elementOf(current?.type)),
              names: _Names.element,
            ),
          );
          current = null;
        case TokenKind.lparen:
          frames.add(
            _Frame(element: frames.last.element, names: frames.last.names),
          );
          current = null;
        case TokenKind.lcurly:
          frames.add(
            _Frame(element: frames.last.element, names: _Names.unknown),
          );
          current = null;
        case TokenKind.rparen || TokenKind.rsquare || TokenKind.rcurly:
          if (frames.length > 1) {
            current = frames.removeLast().after;
          } else {
            current = null;
          }
        case TokenKind.dot || TokenKind.safeNavi:
          break;
        case _:
          current = null;
      }
    }
    final endsOnDot =
        tokens.isNotEmpty &&
        (tokens.last.kind == TokenKind.dot ||
            tokens.last.kind == TokenKind.safeNavi);
    final type = endsOnDot ? current?.type : null;
    return SpelReading(
      members,
      roots,
      type == null || _types.isCollection(type) ? null : _types.membersOf(type),
    );
  }

  static int _closing(List<Token> tokens, int open) {
    var depth = 0;
    for (var i = open; i < tokens.length; i++) {
      if (tokens[i].kind == TokenKind.lparen) {
        depth++;
      } else if (tokens[i].kind == TokenKind.rparen && --depth == 0) {
        return i;
      }
    }
    return tokens.length - 1;
  }

  // The type of the bean [name], when one bean has it. A `@Bean` method
  // may return a subtype, and a bean with metadata has its members checked
  // there: both are read but not reported on.
  TypeRef? _beanType(String name) {
    final beans = model.beans.beansNamed(name);
    if (beans.length != 1) {
      return null;
    }
    final bean = beans.single;
    final file = _types.fileAt(bean.path);
    if (file == null) {
      return null;
    }
    final angle = bean.typeName.indexOf('<');
    final simple =
        (angle < 0 ? bean.typeName : bean.typeName.substring(0, angle))
            .replaceAll('?', '')
            .trim();
    return TypeRef(
      simple.split('.').last,
      const [],
      file,
      open: bean.kind != BeanKind.component || bean.members.isNotEmpty,
    );
  }

  /// The member declared at [at] of [expression]; `null` when none is.
  Target? target(String expression, int at, SpelEnv env) {
    for (final use in read(expression, env).members) {
      if (at >= use.start && at <= use.end && use.member != null) {
        return SpelMemberTarget(use.member!, use.owner.typeName);
      }
    }
    return null;
  }

  /// The members to propose at the end of [before], with the offset where
  /// the typed name starts; `null` when the cursor is not after a member
  /// `.` of a known type.
  (int, List<Completion>)? complete(String before, SpelEnv env) {
    final reading = read(before, env);
    final last = reading.members.lastOrNull;
    final (start, owner) = last != null && last.end == before.length
        ? (last.start, last.owner)
        : (before.length, reading.trailing);
    if (owner == null) {
      return null;
    }
    return (
      start,
      [
        for (final member in owner.members.values)
          if (!member.isStatic && !member.name.startsWith('_'))
            Completion(
              member.name,
              kind: member.isMethod ? 2 : 10,
              detail: member.type?.display ?? member.typeText,
              documentation: '`${member.signature}` (`${member.owner}`)',
              insertText: member.isMethod ? '${member.name}(' : null,
            ),
      ],
    );
  }

  /// The members of [expression] that a fully known type does not have,
  /// as warnings: another accessor may always add a name.
  List<SpelIssue> issues(String expression, SpelEnv env) => [
    for (final use in read(expression, env).members)
      if (use.member == null &&
          use.owner.complete &&
          !dartObjectMembers.contains(use.name) &&
          !_belowDeclares(use))
        _unknown(use),
  ];

  bool _belowDeclares(SpelMemberUse use) {
    final name = use.owner.typeName.split('<').first;
    final any = model.classes.classesNamed(name);
    return any.isEmpty ||
        any.any(
          (info) => _types.subtypeDeclares(
            TypeRef(name, const [], _types.fileAt(info.path)!),
            use.name,
          ),
        );
  }

  SpelIssue _unknown(SpelMemberUse use) {
    final guess = didYouMean(use.name, [
      for (final member in use.owner.members.values)
        if (!member.isStatic && !member.name.startsWith('_')) member.name,
    ]);
    return SpelIssue(
      use.start,
      use.end,
      "Unknown member '${use.name}' of ${use.owner.typeName}"
      "${guess == null ? '' : ". Did you mean '$guess'?"}",
      error: false,
      guess: guess,
    );
  }
}
