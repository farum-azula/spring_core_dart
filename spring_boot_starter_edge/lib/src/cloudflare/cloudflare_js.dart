import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_edge/src/cloudflare/cloudflare.dart';
import 'package:spring_boot_starter_edge/src/fetch/platform_environment_js.dart';

/// In a Worker: the bindings of the environment object the platform
/// gave with the last request.
CloudflareBindings createCloudflareBindings() => const _Bindings();

final class _Bindings implements CloudflareBindings {
  const _Bindings();

  JSObject? _find(String binding) {
    final value = platformEnvironment?.getProperty<JSAny?>(binding.toJS);
    return value != null && value.isA<JSObject>() ? value as JSObject : null;
  }

  JSObject _need(String binding) =>
      _find(binding) ??
      (throw StateError(
        'The Worker has no binding "$binding" (wrangler.toml), or no '
        'request has arrived yet',
      ));

  @override
  bool has(String binding) => _find(binding) != null;

  @override
  bool get loaded => platformEnvironment != null;

  @override
  KvNamespace kv(String binding) => _Kv(_need(binding) as _KvNamespace);

  @override
  D1Database d1(String binding) => _D1(_need(binding) as _D1Database);
}

final class _Kv implements KvNamespace {
  _Kv(this._namespace);

  final _KvNamespace _namespace;

  @override
  Future<String?> get(String key) async =>
      (await _namespace.get(key).toDart)?.toDart;

  @override
  Future<void> put(String key, String value, {Duration? expirationTtl}) =>
      _namespace
          .put(
            key,
            value,
            expirationTtl == null
                ? _KvPutOptions()
                : _KvPutOptions(expirationTtl: expirationTtl.inSeconds),
          )
          .toDart;

  @override
  Future<void> delete(String key) => _namespace.delete(key).toDart;

  @override
  Future<List<String>> keys({String? prefix}) async {
    final listed = await _namespace
        .list(
          prefix == null ? _KvListOptions() : _KvListOptions(prefix: prefix),
        )
        .toDart;
    return [for (final key in listed.keys.toDart) key.name];
  }
}

final class _D1 implements D1Database {
  _D1(this._database);

  final _D1Database _database;

  _D1Statement _statement(String sql, List<Object?> parameters) {
    final statement = _database.prepare(sql);
    if (parameters.isEmpty) {
      return statement;
    }
    return statement.callMethodVarArgs<JSAny?>('bind'.toJS, [
          for (final value in parameters) value.jsify(),
        ])!
        as _D1Statement;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _statement(sql, parameters).all().toDart;
    // Through JSON: the rows are plain values.
    final rows = jsonDecode(_stringify(result.results).toDart) as List<Object?>;
    return [for (final row in rows) (row! as Map).cast<String, Object?>()];
  }

  @override
  Future<int> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _statement(sql, parameters).run().toDart;
    return result.meta?.changes ?? 0;
  }
}

@JS('JSON.stringify')
external JSString _stringify(JSAny? value);

extension type _KvNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSString?> get(String key);
  external JSPromise<JSAny?> put(String key, String value, _KvPutOptions o);
  external JSPromise<JSAny?> delete(String key);
  external JSPromise<_KvList> list(_KvListOptions options);
}

extension type _KvPutOptions._(JSObject _) implements JSObject {
  external factory _KvPutOptions({int expirationTtl});
}

extension type _KvListOptions._(JSObject _) implements JSObject {
  external factory _KvListOptions({String prefix});
}

extension type _KvList._(JSObject _) implements JSObject {
  external JSArray<_KvKey> get keys;
}

extension type _KvKey._(JSObject _) implements JSObject {
  external String get name;
}

extension type _D1Database._(JSObject _) implements JSObject {
  external _D1Statement prepare(String sql);
}

extension type _D1Statement._(JSObject _) implements JSObject {
  external JSPromise<_D1Result> all();
  external JSPromise<_D1Result> run();
}

extension type _D1Result._(JSObject _) implements JSObject {
  external JSAny? get results;
  external _D1Meta? get meta;
}

extension type _D1Meta._(JSObject _) implements JSObject {
  external int? get changes;
}
