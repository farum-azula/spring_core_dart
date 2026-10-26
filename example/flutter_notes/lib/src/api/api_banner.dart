import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_notes/src/api/local_api.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Where the API listens, with a button that copies a `curl` command.
class ApiBanner extends SpringStatelessWidget<(LocalApi,)> {
  const ApiBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final (api,) = beans;
    final url = api.url;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: ListTile(
        leading: Icon(url == null ? Icons.cloud_off : Icons.cloud_done),
        title: Text(url == null ? 'The API is not running' : 'GET $url'),
        subtitle: url == null
            ? null
            : const Text('The same notes as here, over HTTP'),
        trailing: url == null
            ? null
            : IconButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: 'curl $url')),
                tooltip: 'Copy curl command',
                icon: const Icon(Icons.copy),
              ),
      ),
    );
  }
}
