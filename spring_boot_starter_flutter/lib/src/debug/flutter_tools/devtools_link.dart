import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tools_mode.dart';

/// Finds the address of the running app's VM service, `null` when it has
/// none (a release build, or a debug one started without it).
typedef VmServiceLookup = Future<Uri?> Function();

/// The VM service's address from `dart:developer` (`Service.getInfo`):
/// its WebSocket address, else its HTTP one.
Future<Uri?> vmServiceAddress() async {
  final info = await developer.Service.getInfo();
  return info.serverWebSocketUri ?? info.serverUri;
}

/// DevTools cannot be drawn inside the app, so the Flutter tab shows the
/// address it connects to, to copy: `dart devtools <address>` opens it.
/// On the web the app cannot know it; the console of `flutter run` has
/// DevTools' link.
class DevToolsLink extends StatefulWidget {
  /// The link in [mode], the address found by [lookup].
  const DevToolsLink({
    required this.mode,
    this.lookup = vmServiceAddress,
    super.key,
  });

  /// Requirements of the link: the address is not known in a browser.
  static const List<FlutterToolRequirement> requirements = [
    NotOnWebRequirement(
      'Not available from inside the app on the web: open DevTools from '
      'the link `flutter run` prints, or press v in its console.',
    ),
  ];

  /// The running build.
  final FlutterToolsMode mode;

  /// Finds the VM service's address.
  final VmServiceLookup lookup;

  @override
  State<DevToolsLink> createState() => _DevToolsLinkState();
}

class _DevToolsLinkState extends State<DevToolsLink> {
  late final String? _unavailable = unmetRequirement(
    DevToolsLink.requirements,
    widget.mode,
  );
  late final Future<Uri?>? _address = _unavailable == null
      ? widget.lookup()
      : null;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = style.text.copyWith(color: style.muted);
    final unavailable = _unavailable;
    if (unavailable != null) {
      return Text(unavailable, style: muted);
    }
    return FutureBuilder<Uri?>(
      future: _address,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text('Looking for the VM service...', style: muted);
        }
        final address = snapshot.data;
        if (address == null) {
          return Text(
            'The VM service is off in this ${widget.mode.build} build, so '
            'DevTools cannot connect.',
            style: muted,
          );
        }
        final command = 'dart devtools $address';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(command, style: style.code),
            const SizedBox(height: 6),
            DebugChip(
              _copied ? 'Copied' : 'Copy',
              selected: _copied,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: command));
                if (mounted) {
                  setState(() => _copied = true);
                }
              },
            ),
          ],
        );
      },
    );
  }
}
