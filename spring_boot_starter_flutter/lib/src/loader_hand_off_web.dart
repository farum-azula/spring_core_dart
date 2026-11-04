import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring_boot_starter_flutter.LoaderHandOff');

/// Calls `window.springLoaderHandOff(progress)` if the page has it.
void springLoaderHandOff(double progress) {
  try {
    final hook = globalContext.getProperty<JSAny?>('springLoaderHandOff'.toJS);
    if (hook.isA<JSFunction>()) {
      (hook as JSFunction).callAsFunction(null, progress.toJS);
    }
  } on Object catch (error) {
    _log.warning(() => 'The page loader hand-off failed: $error');
  }
}

/// The progress of the page loader while its element is in the page.
double? springPageLoaderProgress() {
  try {
    final document = globalContext.getProperty<JSObject?>('document'.toJS);
    final root = document?.callMethod<JSAny?>(
      'getElementById'.toJS,
      'spring-loader'.toJS,
    );
    if (root == null || root.isUndefinedOrNull) {
      return null;
    }
    final loader = globalContext.getProperty<JSObject?>('springLoader'.toJS);
    final progress = loader?.getProperty<JSAny?>('progress'.toJS);
    return progress.isA<JSNumber>()
        ? (progress as JSNumber).toDartDouble
        : null;
  } on Object {
    return null;
  }
}

/// How long the page loader has been running, while its element is in the
/// page.
Duration? springPageLoaderElapsed() {
  try {
    final document = globalContext.getProperty<JSObject?>('document'.toJS);
    final root = document?.callMethod<JSAny?>(
      'getElementById'.toJS,
      'spring-loader'.toJS,
    );
    if (root == null || root.isUndefinedOrNull) {
      return null;
    }
    final loader = globalContext.getProperty<JSObject?>('springLoader'.toJS);
    final elapsed = loader?.getProperty<JSAny?>('elapsed'.toJS);
    return elapsed.isA<JSNumber>()
        ? Duration(
            microseconds: ((elapsed as JSNumber).toDartDouble * 1000).round(),
          )
        : null;
  } on Object {
    return null;
  }
}
