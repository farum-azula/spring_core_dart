// What spring_boot_starter_data's part writes into a module: the class of
// each repository (repository_emitter.dart), the `EntityIntrospections`
// bean of its entities (entity_emitter.dart), and the drivers' glue.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/spel/spel_compiler.dart';
import 'package:spring_core_dart_generator/src/data/data_model.dart';
import 'package:spring_core_dart_generator/src/data/part_tree.dart';
import 'package:spring_core_dart_generator/src/data/query_expressions.dart';

part 'entity_emitter.dart';
part 'repository_emitter.dart';

/// Writes the data code of one module ([data]) through the emitter's
/// [emission].
final class DataEmitter {
  /// The data code of [data], written through [emission].
  DataEmitter(this.emission, this.data);

  /// The emitter's ways of naming types and values.
  final ModuleEmission emission;

  /// What the data part found in the module.
  final DataModuleModel data;

  /// The classes of the module's repositories, in the order of their
  /// beans.
  List<Class> repositoryClasses() => [
    for (final bean in emission.module.beans)
      if (bean.creation case RepositoryCreation(:final model))
        repositoryClass(model),
  ];

  /// How the bean of the repository [model] is made:
  /// `_$BookRepositoryImpl.$create(r)`.
  Expression repositoryCreation(RepositoryModel model) =>
      refer(model.className).property(r'$create').call([refer('r')]);

  /// The data layer's bean definitions: the `EntityIntrospections` bean of
  /// the module's entities, then those of the drivers' glue.
  List<Expression> beanDefinitions() => [
    if (data.entities.isNotEmpty) entityIntrospectionsBean(emission.moduleName),
    for (final glue in data.glue) glue.definition,
  ];
}
