import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

void main() {
  test('a workflow for each platform that has one', () {
    final supabase = deployWorkflow(
      platform: EdgePlatform.supabase,
      name: 'api',
      directory: 'functions/shop',
    );
    expect(supabase, contains('working-directory: "functions/shop"'));
    expect(
      supabase,
      contains(
        'dart run spring_boot_starter_edge:build --platform supabase '
        '--name api\n',
      ),
    );
    expect(supabase, contains('supabase functions deploy api --project-ref'));
    expect(supabase, contains(r'${{ secrets.SUPABASE_ACCESS_TOKEN }}'));

    final cloudflare = deployWorkflow(
      platform: EdgePlatform.cloudflare,
      name: 'shop',
      branch: 'release',
      target: EdgeTarget.wasm,
    );
    expect(cloudflare, contains('branches: [release]'));
    expect(cloudflare, contains('--name shop --target wasm'));
    expect(cloudflare, contains('wrangler@4 deploy'));

    final aws = deployWorkflow(
      platform: EdgePlatform.aws,
      name: 'api',
      streaming: true,
    );
    expect(aws, contains('--name api --streaming\n'));
    // What goes into the YAML as it is cannot break out of its value.
    expect(
      () => deployWorkflow(
        platform: EdgePlatform.aws,
        name: 'api',
        branch: 'main]\n  evil: [x',
      ),
      throwsArgumentError,
    );
    expect(aws, contains('id-token: write'));
    expect(aws, contains('aws lambda update-function-code'));
  });

  test('no secret is written, only named', () {
    for (final platform in [
      EdgePlatform.supabase,
      EdgePlatform.cloudflare,
      EdgePlatform.aws,
    ]) {
      final workflow = deployWorkflow(platform: platform, name: 'api');
      for (final line in workflow.split('\n')) {
        if (RegExp('TOKEN|SECRET|ROLE_ARN').hasMatch(line) &&
            !line.trimLeft().startsWith('#')) {
          expect(line, contains(r'${{ secrets.'), reason: line);
        }
      }
    }
  });

  test('the others deploy from the repository themselves', () {
    for (final platform in [
      EdgePlatform.deno,
      EdgePlatform.netlify,
      EdgePlatform.vercel,
    ]) {
      expect(
        () => deployWorkflow(platform: platform, name: 'api'),
        throwsArgumentError,
      );
    }
  });

  test('the command writes it into the repository of the application', () {
    final root = Directory.systemTemp.createTempSync('spring_edge_wf_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/.git').createSync();
    final app = Directory('${root.path}/apps/shop')
      ..createSync(recursive: true);
    // The command of this package, wherever the tests are run from.
    final script = Isolate.resolvePackageUriSync(
      Uri.parse('package:spring_boot_starter_edge/build.dart'),
    )!.resolve('../bin/workflow.dart').toFilePath();
    ProcessResult run(List<String> arguments) => Process.runSync(
      Platform.resolvedExecutable,
      [script, ...arguments],
      workingDirectory: app.path,
    );
    final first = run(['--platform', 'cloudflare', '-n', 'shop']);
    expect(first.exitCode, 0, reason: '${first.stderr}');
    final file = File('${root.path}/.github/workflows/deploy-shop.yml');
    expect(file.readAsStringSync(), contains('working-directory: "apps/shop"'));
    // Yours once written.
    expect(run(['--platform', 'cloudflare', '-n', 'shop']).exitCode, 64);
    expect(
      run(['--platform', 'cloudflare', '-n', 'shop', '--force']).exitCode,
      0,
    );
    expect(run(['--platform', 'vercel']).exitCode, 64);
  });
}
