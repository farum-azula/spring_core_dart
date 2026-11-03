import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/logs.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';

/// The app's own log, in the colors of the Spring console: neon_ui's
/// NeonLogsPanel on the LogBuffer bean.
typedef LogsBeans = (LogBuffer, DemoLog);

class LogsPage extends SpringStatefulWidget<LogsBeans> {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends SpringState<LogsPage, LogsBeans> {
  double _height = 280;

  @override
  Widget build(BuildContext context) {
    final (buffer, demo) = beans;
    final space = context.theme.spacing;
    return PageFrame(
      kicker: 'NEONLOGSPANEL',
      title: 'Logs',
      intro:
          'The lines the app writes through the Spring logger (a page '
          'opened, a theme selected) appear here, in the colors of '
          'tokens.logs.*. Write more, and drag the grip to resize.',
      children: [
        Section(
          title: 'Write a line',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              SizedBox(
                width: 140,
                child: NeonButton(label: 'Info', onPressed: demo.info),
              ),
              SizedBox(
                width: 140,
                child: NeonButton(
                  label: 'Warning',
                  filled: false,
                  onPressed: demo.warn,
                ),
              ),
              SizedBox(
                width: 140,
                child: NeonButton(
                  label: 'Error',
                  filled: false,
                  onPressed: demo.error,
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            SizedBox(
              height: _height,
              child: NeonLogsPanel(
                buffer: buffer,
                emptyMessage: 'no lines yet',
              ),
            ),
            NeonResizeHandle(
              onDrag: (dy) =>
                  setState(() => _height = (_height + dy).clamp(160, 560)),
            ),
          ],
        ),
      ],
    );
  }
}
