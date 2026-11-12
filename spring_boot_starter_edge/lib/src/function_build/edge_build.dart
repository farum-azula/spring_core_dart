import 'dart:io';

import 'package:spring_boot_starter_edge/src/function_build/entry_templates.dart';

/// The platforms a function is built for.
enum EdgePlatform {
  /// Supabase Edge Functions (Deno): `index.ts`, `main.js`. WebAssembly
  /// compiled by Dart 3.13 only, for now ([newestWasmDart]).
  supabase(
    'supabase/functions',
    'deno',
    newestWasmDart: '3.13.7',
    wasmLimit:
        "Supabase's Edge Runtime is Deno 2.1, whose V8 (13.0) lacks the "
        'WebAssembly exception handling (exnref) that dart compile wasm '
        'uses from Dart 3.14 on',
  ),

  /// Cloudflare Workers: `worker.mjs`, `main.js`, and `wrangler.toml` in
  /// the application's directory.
  cloudflare('build/cloudflare', 'cloudflare'),

  /// AWS Lambda on the Node.js runtime: `index.mjs`, `main.cjs`.
  aws('build/aws', 'node'),

  /// Deno Deploy, and Deno anywhere: `main.ts`, `main.js`.
  deno('build/deno', 'deno'),

  /// Netlify Edge Functions (Deno): `index.js`, `main.js`.
  netlify('netlify/edge-functions', 'deno'),

  /// Vercel Functions with the `fetch` export (Node.js): `index.mjs`,
  /// `main.cjs`.
  vercel('build/vercel', 'node');

  EdgePlatform(
    this.defaultOutput,
    this.runtime, {
    this.newestWasmDart,
    this.wasmLimit,
  });

  /// Where the function goes by default, from the application's
  /// directory; on Supabase and Netlify the function's name is added.
  final String defaultOutput;

  /// The JavaScript runtime of the platform: `deno`, `node`,
  /// `cloudflare`.
  final String runtime;

  /// The newest Dart whose WebAssembly the platform runs (its minor
  /// version counts: `3.13.7` allows every 3.13); `null` when it runs that
  /// of every Dart. A deploy workflow installs this one for such a build.
  final String? newestWasmDart;

  /// Why the platform runs no WebAssembly of a newer Dart than
  /// [newestWasmDart].
  final String? wasmLimit;

  /// Whether the function's name is a directory under [defaultOutput].
  bool get namedDirectory => this == supabase || this == netlify;
}

/// What the application is compiled to.
enum EdgeTarget {
  /// `dart compile js`: one script; runs on every platform.
  js,

  /// `dart compile wasm` (WasmGC): `app.wasm` with its `app.mjs`, and a
  /// loader in place of the script. The platform's runtime must have
  /// WasmGC.
  wasm,
}

/// What a build wrote.
final class EdgeBuildResult {
  /// The files in [directory], and the size of the compiled application.
  const EdgeBuildResult(this.directory, this.files, this.scriptBytes);

  /// The directory of the function.
  final Directory directory;

  /// The names of the files written there.
  final List<String> files;

  /// The size of the compiled application (`main.js`, or `app.wasm`), in
  /// bytes.
  final int scriptBytes;
}

/// Compiles an application to JavaScript and writes the entry file of a
/// platform next to it.
///
/// ```dart
/// final result = await EdgeBuild(
///   platform: EdgePlatform.supabase,
///   name: 'api',
/// ).run();
/// ```
///
/// The compile command is `dart compile js -O<n> -DSPRING_ALL_PLATFORMS=true`:
/// the definition keeps the modules of a server (the web and the security
/// starters), which a JavaScript build otherwise leaves out as code for a
/// browser.
final class EdgeBuild {
  /// A build of [entry] (from [application], the application's directory)
  /// for [platform].
  EdgeBuild({
    required this.platform,
    this.name = 'api',
    this.entry = 'bin/main.dart',
    this.output,
    this.optimization = 2,
    this.streaming = false,
    this.target = EdgeTarget.js,
    this.path = '/*',
    this.defines = const {},
    Directory? application,
    this.dart = 'dart',
  }) : application = application ?? Directory.current;

  /// The platform.
  final EdgePlatform platform;

  /// The name of the function: its directory on Supabase, where it is
  /// also the first segment of every path; the Worker's name in a new
  /// `wrangler.toml`.
  final String name;

  /// The Dart file with `main`, from [application].
  final String entry;

  /// The directory of the function, from [application]; `null` for the
  /// platform's default.
  final String? output;

  /// The `-O` level of `dart compile js`, 0 to 4.
  final int optimization;

  /// On AWS: a response-streaming handler.
  final bool streaming;

  /// JavaScript, or WebAssembly.
  final EdgeTarget target;

  /// On Netlify: the paths the function answers.
  final String path;

  /// More `-D` definitions for the compiler.
  final Map<String, String> defines;

  /// The application's directory.
  final Directory application;

  /// The `dart` executable.
  final String dart;

  /// The directory the function is written to.
  Directory get directory {
    final path =
        output ??
        (platform.namedDirectory
            ? '${platform.defaultOutput}/$name'
            : platform.defaultOutput);
    return Directory(
      path.startsWith('/') ? path : '${application.path}/$path',
    );
  }

  // A WebAssembly build of a platform that runs only that of an older
  // Dart than [dart]: refused, before anything is compiled, with what
  // works instead.
  Future<void> _checkWasmDart() async {
    final newest = platform.newestWasmDart;
    if (newest == null) {
      return;
    }
    final version = await _dartVersion();
    if (version == null || !_newerMinor(version, newest)) {
      return;
    }
    final minor = newest.split('.').take(2).join('.');
    throw UnsupportedError(
      'A WebAssembly build for ${platform.name} works only when Dart '
      '$minor compiles it, until Supabase updates its Edge Runtime: '
      "${platform.wasmLimit}. This build's Dart is $version. Build it "
      'with Dart $minor (--dart <the dart of a Dart $newest SDK>), or with '
      '--target js.',
    );
  }

  // The version of [dart] (`3.14.0`); `null` when it does not say.
  Future<String?> _dartVersion() async {
    final ProcessResult result;
    try {
      result = await Process.run(dart, const ['--version']);
    } on ProcessException {
      return null;
    }
    return RegExp(
      r'(\d+\.\d+\.\d+)',
    ).firstMatch('${result.stdout}${result.stderr}')?.group(1);
  }

  // Whether [version] is of a later minor version than [newest].
  static bool _newerMinor(String version, String newest) {
    List<int> minor(String v) => [
      for (final part in v.split('.').take(2)) int.parse(part),
    ];
    final (a, b) = (minor(version), minor(newest));
    return a[0] != b[0] ? a[0] > b[0] : a[1] > b[1];
  }

  /// Compiles and writes. Throws a [ProcessException] with the compiler's
  /// output when the application does not compile, and an
  /// [UnsupportedError] for a WebAssembly build that [dart] is too new
  /// for on the platform ([EdgePlatform.newestWasmDart]).
  Future<EdgeBuildResult> run() async {
    if (target == EdgeTarget.wasm) {
      await _checkWasmDart();
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Letters, digits, "-" and "_" only',
      );
    }
    await directory.create(recursive: true);
    final node = platform.runtime == 'node';
    // What the entry file imports: the program, or the loader of the
    // WebAssembly module.
    final script = switch (target) {
      EdgeTarget.js => node ? 'main.cjs' : 'main.js',
      EdgeTarget.wasm => node ? 'main.mjs' : 'main.js',
    };
    final compiled = target == EdgeTarget.js ? script : 'app.wasm';
    final arguments = [
      'compile',
      target.name,
      '-O$optimization',
      '-DSPRING_ALL_PLATFORMS=true',
      for (final MapEntry(:key, :value) in defines.entries) '-D$key=$value',
      if (target == EdgeTarget.js) '--no-source-maps',
      '-o',
      '${directory.path}/$compiled',
      entry,
    ];
    final out = directory;
    final compile = await Process.run(
      dart,
      arguments,
      workingDirectory: application.path,
    );
    if (compile.exitCode != 0) {
      throw ProcessException(
        dart,
        arguments,
        '${compile.stdout}\n${compile.stderr}',
        compile.exitCode,
      );
    }
    // What the compiler writes besides the program.
    for (final extra in [
      '$compiled.deps',
      'app.wasm.map',
      'app.support.js',
    ]) {
      final file = File('${out.path}/$extra');
      if (file.existsSync()) {
        await file.delete();
      }
    }
    final files = <String>[compiled, 'prelude.js'];
    await File('${out.path}/prelude.js').writeAsString(preludeScript);
    if (target == EdgeTarget.wasm) {
      await File(
        '${out.path}/$script',
      ).writeAsString(wasmLoader(platform.runtime));
      files.addAll(['app.mjs', script]);
    }
    // The entry imports the program under its name.
    String entryOf(String template) => node
        ? template.replaceFirst('import "./main.cjs";', 'import "./$script";')
        : template;
    Future<void> write(String name, String content) async {
      await File('${out.path}/$name').writeAsString(content);
      files.add(name);
    }

    switch (platform) {
      case EdgePlatform.supabase:
        await write('index.ts', supabaseEntry(name));
      case EdgePlatform.cloudflare:
        await write('worker.mjs', cloudflareEntry);
        // The Worker's configuration is the application's: next to its
        // pubspec.yaml (or, when someone put one there, next to the
        // Worker). Written once.
        final config = File('${application.path}/wrangler.toml');
        if (!config.existsSync() &&
            !File('${out.path}/wrangler.toml').existsSync()) {
          final today = DateTime.now().toUtc().toIso8601String();
          final root = '${application.absolute.path}/';
          final worker = '${out.absolute.path}/worker.mjs';
          await config.writeAsString(
            wranglerConfig(
              name,
              today.substring(0, 10),
              main: worker.startsWith(root)
                  ? worker.substring(root.length)
                  : worker,
            ),
          );
          files.add('wrangler.toml (in the application)');
        }
      case EdgePlatform.aws:
        await write('index.mjs', entryOf(awsEntry(streaming: streaming)));
      case EdgePlatform.deno:
        await write('main.ts', denoEntry);
      case EdgePlatform.netlify:
        await write('index.js', netlifyEntry(path));
      case EdgePlatform.vercel:
        await write('index.mjs', entryOf(vercelEntry));
    }
    return EdgeBuildResult(
      out,
      files,
      File('${out.path}/$compiled').lengthSync(),
    );
  }
}
