import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A group of beans of a [DebugBeanGraphSnapshot]: an auto-configuration
/// (`springBootStarterFlutterAutoConfiguration`), a package of the
/// framework, or a part of the application (`neon_books_app/account`, the
/// first folder under `lib/src`).
final class DebugBeanModule {
  /// The module [name] of [beans].
  const DebugBeanModule({
    required this.name,
    required this.application,
    required this.beans,
  });

  /// Its name.
  final String name;

  /// Whether it is the application's.
  final bool application;

  /// The names of its beans (and widgets), in definition order.
  final List<String> beans;

  @override
  String toString() => 'DebugBeanModule($name, ${beans.length} beans)';
}

/// Where a bean comes from: its module, and whether the application
/// defined it.
final class DebugBeanOrigin {
  /// The origin in [module].
  const DebugBeanOrigin(this.module, {required this.application});

  /// The [DebugBeanModule]'s name.
  final String module;

  /// Whether the application defined the bean.
  final bool application;
}

/// Which beans the application defined and which module each comes from,
/// from the modules it was started with: those of its own (the generated
/// `$application`, with what they import) and its auto-configurations.
///
/// The [DebugBeanGraph] takes them from the `SpringApplication` once it
/// has started (`ApplicationStartedEvent`); a context built by hand gives
/// them itself.
final class DebugBeanModules {
  /// The origins of the beans of [application] (the application's own
  /// modules) and of [autoConfigurations].
  DebugBeanModules({
    List<BeanModule> application = const [],
    List<BeanModule> autoConfigurations = const [],
  }) {
    for (final module in application) {
      _collect(module, null);
    }
    for (final module in autoConfigurations) {
      _collect(module, module.name);
    }
  }

  /// The modules [application] was started with.
  factory DebugBeanModules.of(SpringApplication application) =>
      DebugBeanModules(
        application: application.modules,
        autoConfigurations: application.autoConfigurations,
      );

  /// No module known: every bean is the framework's, grouped by package.
  static final none = DebugBeanModules();

  // Bean name -> its auto-configuration's name, or null for the
  // application's.
  final _owners = <String, String?>{};

  void _collect(BeanModule module, String? owner, [Set<BeanModule>? seen]) {
    final visited = seen ?? Set<BeanModule>.identity();
    if (!visited.add(module)) {
      return;
    }
    for (final imported in module.imports) {
      _collect(imported, owner, visited);
    }
    for (final definition in module.definitions) {
      _owners.putIfAbsent(definition.name, () => owner);
      _sources.putIfAbsent(definition.name, () => definition.source);
      if (classOf(definition.source) case final key?) {
        _classOwners.putIfAbsent(key, () => owner);
      }
    }
  }

  // Bean name -> its definition's source, for a bean the context did not
  // register (a condition left it out).
  final _sources = <String, String?>{};

  // Class key (`package:app/x.dart#CacheConfig`) -> as [_owners], for
  // what the condition report names by class.
  final _classOwners = <String, String?>{};

  /// The class part of a definition's [source]: `package:app/x.dart#Config`
  /// for `package:app/x.dart#Config.clock`, a `@Bean` method's; `null`
  /// for a source that is no class.
  static String? classOf(String? source) {
    final hash = source?.indexOf('#') ?? -1;
    if (source == null || hash < 0) {
      return null;
    }
    final dot = source.indexOf('.', hash);
    return dot < 0 ? source : source.substring(0, dot);
  }

  /// Where the bean [name] comes from; [source] is its definition's
  /// `source`, which groups the application's beans by folder and the
  /// framework's other beans by package. A [name] that is a class key
  /// (what the condition report names a configuration class by) is found
  /// by its class.
  DebugBeanOrigin originOf(String name, String? source) {
    final at = source ?? _sources[name] ?? name;
    final classKey = classOf(at);
    final (known, owner) = _owners.containsKey(name)
        ? (true, _owners[name])
        : classKey != null && _classOwners.containsKey(classKey)
        ? (true, _classOwners[classKey])
        : (false, null);
    if (!known) {
      return DebugBeanOrigin(frameworkGroupOf(at), application: false);
    }
    return owner == null
        ? DebugBeanOrigin(applicationGroupOf(at), application: true)
        : DebugBeanOrigin(owner, application: false);
  }

  /// The group of an application bean of [source]: its package and the
  /// first folder under `lib/src` (`package:shop/src/basket/basket.dart`
  /// is `shop/basket`), or the package alone for a file at the top.
  static String applicationGroupOf(String? source) {
    final path = _packagePath(source);
    if (path == null) {
      return 'application';
    }
    final parts = path.split('/');
    final folders = [
      for (final part in parts.sublist(1, parts.length - 1))
        if (part != 'src') part,
    ];
    return folders.isEmpty ? parts.first : '${parts.first}/${folders.first}';
  }

  /// The group of a framework bean of [source] outside any known module:
  /// its package, `registered` for an object given to
  /// `registerSingleton`, `context` for the context's own.
  static String frameworkGroupOf(String? source) => switch (source) {
    'registerSingleton' => 'registered',
    _ => _packagePath(source)?.split('/').first ?? 'context',
  };

  static String? _packagePath(String? source) {
    const scheme = 'package:';
    if (source == null || !source.startsWith(scheme)) {
      return null;
    }
    return source.substring(scheme.length).split('#').first;
  }
}
