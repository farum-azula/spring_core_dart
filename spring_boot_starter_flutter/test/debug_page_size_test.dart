import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

PageResource _resource(
  String name, {
  String initiator = 'fetch',
  int transfer = 0,
  int decoded = 0,
  bool crossOrigin = false,
}) => PageResource(
  name: name,
  initiator: initiator,
  transferSize: transfer,
  decodedBodySize: decoded,
  crossOrigin: crossOrigin,
);

final class _Resources implements PageResources {
  _Resources(this.resources);

  final List<PageResource> resources;
  int reads = 0;

  @override
  List<PageResource> read() {
    reads++;
    return resources;
  }

  @override
  bool get full => false;
}

void main() {
  test('a download is of the kind its extension or initiator says, else '
      'other', () {
    String kind(PageResource resource) => pageResourceKindOf(resource);

    expect(kind(_resource('https://a.b/main.dart.wasm')), 'code');
    expect(kind(_resource('https://a.b/', initiator: 'navigation')), 'code');
    expect(kind(_resource('https://a.b/f/inter.WOFF2?v=1')), 'fonts');
    expect(
      kind(_resource('https://a.b/heroes/74', initiator: 'img')),
      'images',
    );
    expect(kind(_resource('https://a.b/api/user')), 'other');
  });

  test('cross-origin without Timing-Allow-Origin is hidden; from the cache '
      'it transferred nothing; the weight is the larger size', () {
    final hidden = _resource('https://cdn/x.js', crossOrigin: true);
    final cached = _resource('https://a.b/x.js', decoded: 900);
    final zipped = _resource('https://a.b/y.js', transfer: 300, decoded: 900);

    expect(hidden.hidden, isTrue);
    expect(cached.hidden, isFalse);
    expect(cached.cached, isTrue);
    expect(zipped.cached, isFalse);
    expect(zipped.weight, 900);
  });

  testWidgets('the block: totals by kind, the heaviest, hidden ones told; '
      'read again on Refresh', (tester) async {
    final resources = _Resources([
      _resource('https://a.b/main.dart.js', transfer: 2000, decoded: 6000),
      _resource('https://a.b/inter.woff2', transfer: 500, decoded: 500),
      _resource('https://cdn.example/canvaskit.wasm', crossOrigin: true),
    ]);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: DebugSizeBlock(resources: resources, top: 2),
        ),
      ),
    );

    expect(find.textContaining('1 from other origins'), findsOneWidget);
    expect(find.text('main.dart.js'), findsOneWidget);
    expect(find.text('inter.woff2'), findsOneWidget);
    expect(find.text('canvaskit.wasm'), findsNothing, reason: 'top 2 only');
    expect(resources.reads, 1);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(resources.reads, 2);
  });

  testWidgets('the addresses it shows are masked', (tester) async {
    expect(
      PageResource.masked('https://ada:pw@a.b/img.png?token=t0k&w=2'),
      'https://ada:******@a.b/img.png?token=******&w=2',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: DebugSizeBlock(
            resources: _Resources([
              _resource('https://a.b/img.png?token=t0k', transfer: 10),
            ]),
          ),
        ),
      ),
    );
    final labels = [
      for (final semantics in tester.widgetList<Semantics>(
        find.byType(Semantics),
      ))
        ?semantics.properties.label,
    ];
    expect(labels, contains('https://a.b/img.png?token=******'));
    expect(labels.join(), isNot(contains('t0k')));
  });

  testWidgets('off the web the block points to the build size analysis', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DebugSizeBlock(),
      ),
    );

    expect(find.textContaining('--analyze-size'), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
  });
}
