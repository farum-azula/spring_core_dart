import 'dart:io';

/// The resident memory of the process in bytes.
int? processMemory() {
  try {
    return ProcessInfo.currentRss;
  } on Object {
    return null;
  }
}
