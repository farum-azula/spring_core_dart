// Outside a browser there is no page: BrowserPage is a bean of the `web`
// profile only, and tests replace it.
String? cookie(String name) =>
    throw UnsupportedError('No browser page outside the web');

void open(String url) =>
    throw UnsupportedError('No browser page outside the web');
