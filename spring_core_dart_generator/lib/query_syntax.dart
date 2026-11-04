/// What the build knows of the syntax of Spring Data queries, without the
/// analyzer: the SQL lexer of `@Query` texts, the grammar of derived query
/// names and the naming of tables and columns. The language server reads
/// queries with the same code the build checks them with, so the editor and
/// the build agree.
library;

export 'package:spring_core_dart_generator/src/data_schema.dart'
    show DataSchema;
export 'package:spring_core_dart_generator/src/did_you_mean.dart'
    show closestName;
export 'package:spring_core_dart_generator/src/part_tree.dart';
export 'package:spring_core_dart_generator/src/part_tree_reader.dart';
export 'package:spring_core_dart_generator/src/sql_lexer.dart';
