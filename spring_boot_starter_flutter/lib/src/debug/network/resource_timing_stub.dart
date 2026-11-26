import 'package:spring_boot_starter_flutter/src/debug/network/resource_timing.dart';

/// No Resource Timing outside a browser: `dart:io` gives no phases.
ResourceTimingSource? resourceTimingSource() => null;
