import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// A value of a framework annotation that a composed annotation supplies
/// through a getter: the build reads annotations as constants, which hold
/// fields only, so it would crash on the value or read another one.
final class GetterValue {
  /// [getter] of [annotation] standing for the field of [declaring].
  const GetterValue(this.annotation, this.declaring, this.getter);

  /// The composed annotation class.
  final InterfaceElement annotation;

  /// The framework annotation whose field the getter stands for.
  final InterfaceElement declaring;

  /// The getter.
  final GetterElement getter;

  /// What to change, naming the annotation, the member and the field to
  /// write; [site] says where the annotation was found.
  String problem(String site) {
    final name = getter.displayName;
    final type = getter.returnType.getDisplayString();
    return '@${annotation.name} on $site: it supplies ${declaring.name}.$name '
        'through a getter, and the build reads annotations as constants, '
        'which hold fields only. In ${annotation.name}, write '
        '`final $type $name = ${_valueOf(getter) ?? '...'};` instead of the '
        'getter.';
  }

  // The expression of `get value => ...`, as written.
  static String? _valueOf(GetterElement getter) {
    final fragment = getter.firstFragment;
    final source = fragment.libraryFragment.source;
    final text = source.contents.data;
    final finder = _GetterBody(fragment.offset);
    parseString(content: text, throwIfDiagnostics: false).unit.accept(finder);
    return switch (finder.body) {
      ExpressionFunctionBody(:final expression) => text.substring(
        expression.offset,
        expression.end,
      ),
      _ => null,
    };
  }
}

final class _GetterBody extends RecursiveAstVisitor<void> {
  _GetterBody(this.offset);

  final int offset;
  FunctionBody? body;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.offset == offset) {
      body = node.body;
    }
    super.visitMethodDeclaration(node);
  }
}

/// The field of a framework annotation that [type], an annotation class of
/// the application, replaces by a getter; `null` when it has none. A
/// framework's own getter is left alone: its package reads it knowingly.
GetterValue? getterValueOf(InterfaceType type) {
  if (_isFramework(type.element.library)) {
    return null;
  }
  for (final supertype in type.element.allSupertypes) {
    final declaring = supertype.element;
    if (!_isFramework(declaring.library)) {
      continue;
    }
    for (final field in declaring.fields) {
      final name = field.name;
      if (name == null ||
          field.isStatic ||
          field.isPrivate ||
          !field.isOriginDeclaration) {
        continue;
      }
      final getter = type.lookUpGetter(name, type.element.library);
      if (getter != null &&
          getter.isOriginDeclaration &&
          !_isFramework(getter.library)) {
        return GetterValue(type.element, declaring, getter.baseElement);
      }
    }
  }
  return null;
}

bool _isFramework(LibraryElement library) =>
    library.uri.isScheme('package') &&
    library.uri.pathSegments.first.startsWith('spring_');
