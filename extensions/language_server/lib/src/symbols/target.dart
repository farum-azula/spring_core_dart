import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';
import 'package:dart_spring_language_server/src/symbols/source_locations.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// Where a definition or hover is asked: the text of the file and the
/// offset in it, with the [locations] to turn offsets into ranges.
final class TargetContext {
  /// A question at [offset] of [text].
  const TargetContext(this.locations, this.text, this.offset);

  /// Turns offsets into ranges and shortens paths.
  final SourceLocations locations;

  /// The text of the file asked about.
  final String text;

  /// The offset asked about.
  final int offset;
}

/// What is at a place of a Dart file that Spring knows: the beans of an
/// injection point, the definitions of a property, the files of a
/// location. Go to definition goes to its [definitions]; a hover shows
/// its [hover].
abstract class Target {
  /// A target.
  const Target();

  /// Where go to definition leads.
  List<SourceRange> definitions(TargetContext context);

  /// The Markdown of the hover; `null` for none.
  String? hover(TargetContext context);
}

/// The candidate beans of an injection point or a bean name.
final class BeanTarget extends Target {
  /// [beans], described as [description] (`Beans of type Clock`).
  const BeanTarget(this.beans, this.description);

  /// The beans, `@Primary` ones first where that matters.
  final List<BeanInfo> beans;

  /// What was looked for, as the hover's title.
  final String description;

  @override
  List<SourceRange> definitions(TargetContext context) => [
    for (final bean in beans)
      if (bean.path.isNotEmpty) context.locations.beanRange(bean),
  ];

  static String _origin(TargetContext context, BeanInfo bean) =>
      bean.origin ?? context.locations.shortPath(bean.path);

  @override
  String hover(TargetContext context) {
    if (beans.isEmpty) {
      return '**$description**: no bean found in this project';
    }
    return [
      '**$description**',
      '',
      for (final bean in beans)
        '- ${bean.summary} — `${_origin(context, bean)}`',
    ].join('\n');
  }
}

/// The definitions of a property key in the config files (and the
/// properties of a test).
class PropertyTarget extends Target {
  /// The [entries] that define [key]; [fallback] is the default of the
  /// placeholder asked about, if it has one.
  const PropertyTarget(this.key, this.entries, {this.fallback});

  /// The key, as written.
  final String key;

  /// Its definitions.
  final List<PropertyEntry> entries;

  /// The default of the placeholder asked about (`8080` of
  /// `${server.port:8080}`), used when nothing defines the key.
  final String? fallback;

  @override
  List<SourceRange> definitions(TargetContext context) => [
    for (final entry in entries)
      SourceRange(
        entry.path,
        entry.line,
        entry.keyStart,
        entry.line,
        entry.keyEnd,
      ),
  ];

  @override
  String hover(TargetContext context) {
    if (entries.isEmpty) {
      return missing(context);
    }
    return [
      title,
      '',
      for (final entry in entries)
        if (entry.provider case final provider?)
          '- provided by `$provider` (`@ServiceConnection`)'
        else
          '- `${entry.fileName}`: `${entry.value}`',
    ].join('\n');
  }

  /// The title of the hover when something defines the key.
  String get title => '**`$key`**';

  /// The hover when nothing defines the key: the placeholder's default
  /// is used then, if it has one.
  String missing(TargetContext context) => switch (fallback) {
    null => '**`$key`**: not defined in any properties file',
    final fallback =>
      '**`$key`**: not defined in any properties file; '
          'the default after the colon is used: `$fallback`',
  };
}

/// The definitions of a message code in the message bundles.
final class MessageTarget extends PropertyTarget {
  /// The [entries] of the bundles that define the message code [key].
  const MessageTarget(super.key, super.entries);

  @override
  String get title => '**`$key`** (message)';

  @override
  String missing(TargetContext context) =>
      '**`$key`**: no such message in the message bundles';
}

/// A declaration of the workspace to go to: a class, a method, a
/// parameter, with a one-line summary for the hover.
final class DeclarationSite {
  /// The declaration whose name is [length] long at [offset] of [path].
  const DeclarationSite(this.path, this.offset, this.length, this.summary);

  /// The file that declares it.
  final String path;

  /// The offset of its name.
  final int offset;

  /// The length of its name.
  final int length;

  /// The hover's line about it.
  final String summary;
}

/// The declarations a pointcut, a route or a SpEL variable names.
final class DeclarationTarget extends Target {
  /// [declarations], described as [description].
  const DeclarationTarget(this.description, this.declarations);

  /// What was looked for, as the hover's title.
  final String description;

  /// What was found.
  final List<DeclarationSite> declarations;

  @override
  List<SourceRange> definitions(TargetContext context) => [
    for (final declaration in declarations)
      ?context.locations.declarationRange(
        declaration.path,
        declaration.offset,
        declaration.length,
      ),
  ];

  static String _shortPath(TargetContext context, DeclarationSite site) =>
      context.locations.shortPath(site.path);

  @override
  String hover(TargetContext context) {
    if (declarations.isEmpty) {
      return '**$description**: nothing found in this project';
    }
    return [
      '**$description**',
      '',
      for (final declaration in declarations)
        '- ${declaration.summary} — `${_shortPath(context, declaration)}`',
    ].join('\n');
  }
}

/// The files a resource location (`resources:legacy.properties`,
/// `asset:assets/logo.png`) resolves to.
final class ResourceTarget extends Target {
  /// The [files] that exist of those [searched] for [location].
  const ResourceTarget(this.location, this.files, this.searched);

  /// The location as written.
  final String location;

  /// The files found.
  final List<String> files;

  /// Every place looked in.
  final List<String> searched;

  @override
  List<SourceRange> definitions(TargetContext context) => [
    for (final file in files) SourceRange(file, 0, 0, 0, 0),
  ];

  @override
  String hover(TargetContext context) {
    final short = context.locations.shortPath;
    if (files.isEmpty) {
      return '**`$location`**: not found (looked in '
          '${searched.map((path) => '`${short(path)}`').join(', ')})';
    }
    return [
      '**`$location`**',
      '',
      for (final file in files) '- `${short(file)}`',
    ].join('\n');
  }
}

/// A hover text with nothing to go to (a member of a bean in SpEL).
final class TextTarget extends Target {
  /// The hover [text].
  const TextTarget(this.text);

  /// The Markdown shown.
  final String text;

  @override
  List<SourceRange> definitions(TargetContext context) => const [];

  @override
  String hover(TargetContext context) => text;
}
