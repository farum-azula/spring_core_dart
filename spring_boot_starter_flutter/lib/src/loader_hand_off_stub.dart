/// Off the web there is no page loader: nothing to do.
void springLoaderHandOff(double progress) {}

/// Off the web there is no page loader.
double? springPageLoaderProgress() => null;

/// Off the web there is no page loader.
Duration? springPageLoaderElapsed() => null;

/// No page loader off the web: no stages.
Map<String, Duration> springPageLoaderStages() => const {};
