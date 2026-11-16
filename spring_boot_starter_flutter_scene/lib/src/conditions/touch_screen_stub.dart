import 'package:flutter/foundation.dart';

/// Whether the device's main pointer is a finger: off the web, a phone's
/// or a tablet's system.
bool get touchScreen => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  _ => false,
};
