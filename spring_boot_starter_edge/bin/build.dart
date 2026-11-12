// dart run spring_boot_starter_edge:build --platform supabase --name api
//
// Compiles the application to JavaScript and writes the platform's entry
// file next to it (EdgeBuild).

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';

const _usage = '''
Builds the application as a function.

  dart run spring_boot_starter_edge:build --platform <platform> [options]

  --platform, -p   supabase | cloudflare | aws | deno | netlify | vercel
  --name, -n       the function's name (default: api); on Supabase its
                   directory and the first segment of its paths
  --target, -t     js (default) | wasm
  --entry          the Dart file with main (default: bin/main.dart)
  --output, -o     the function's directory (default:
                   supabase/functions/<name>, netlify/edge-functions/<name>,
                   build/<platform> for the others)
  --optimization   the -O level of dart compile js, 0 to 4 (default: 2)
  --dart           the dart that compiles (default: dart on the PATH);
                   WebAssembly for Supabase needs that of Dart 3.13
  --path           netlify: the paths the function answers (default: /*)
  --streaming      aws: a response-streaming handler (function URLs with
                   InvokeMode RESPONSE_STREAM; needed by server-sent events)
  -D<name>=<value> a definition for the compiler
''';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  final defines = <String, String>{};
  var streaming = false;
  const short = {
    '-p': '--platform',
    '-n': '--name',
    '-o': '--output',
    '-t': '--target',
  };
  for (var i = 0; i < args.length; i++) {
    var arg = args[i];
    if (arg == '--help' || arg == '-h') {
      print(_usage);
      return;
    }
    if (arg == '--streaming') {
      streaming = true;
      continue;
    }
    if (arg.startsWith('-D') && arg.contains('=')) {
      final at = arg.indexOf('=');
      defines[arg.substring(2, at)] = arg.substring(at + 1);
      continue;
    }
    arg = short[arg] ?? arg;
    if (!arg.startsWith('--')) {
      _fail('Unknown argument "$arg"');
    }
    final at = arg.indexOf('=');
    if (at > 0) {
      options[arg.substring(2, at)] = arg.substring(at + 1);
    } else if (i + 1 < args.length) {
      options[arg.substring(2)] = args[++i];
    } else {
      _fail('"$arg" needs a value');
    }
  }
  const known = {
    'platform',
    'name',
    'entry',
    'output',
    'optimization',
    'dart',
    'target',
    'path',
  };
  for (final key in options.keys) {
    if (!known.contains(key)) {
      _fail('Unknown option "--$key"');
    }
  }
  final platform = EdgePlatform.values
      .where((p) => p.name == options['platform'])
      .firstOrNull;
  if (platform == null) {
    _fail(
      '--platform must be one of '
      '${EdgePlatform.values.map((p) => p.name).join(', ')}',
    );
  }
  final target = EdgeTarget.values
      .where((t) => t.name == (options['target'] ?? 'js'))
      .firstOrNull;
  if (target == null) {
    _fail('--target must be js or wasm');
  }
  final level = int.tryParse(options['optimization'] ?? '2');
  if (level == null || level < 0 || level > 4) {
    _fail('--optimization must be 0 to 4');
  }
  final build = EdgeBuild(
    platform: platform,
    name: options['name'] ?? 'api',
    entry: options['entry'] ?? 'bin/main.dart',
    output: options['output'],
    optimization: level,
    streaming: streaming,
    target: target,
    path: options['path'] ?? '/*',
    defines: defines,
    dart: options['dart'] ?? 'dart',
  );
  try {
    final result = await build.run();
    final kb = (result.scriptBytes / 1024).round();
    print(
      'Built for ${platform.name}: ${result.directory.path} '
      '(${result.files.join(', ')}; $kb KB of '
      '${target == EdgeTarget.wasm ? 'WebAssembly' : 'JavaScript'})',
    );
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    exit(error.errorCode == 0 ? 1 : error.errorCode);
  } on ArgumentError catch (error) {
    _fail('${error.message}: ${error.invalidValue}');
  } on UnsupportedError catch (error) {
    _fail(error.message ?? '$error');
  }
}

Never _fail(String message) {
  stderr
    ..writeln(message)
    ..writeln()
    ..writeln(_usage);
  exit(64);
}
