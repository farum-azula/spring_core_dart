// What spring_boot_starter_restclient's part writes into a module: the
// class of each HTTP service interface, whose methods are `RestClient`
// calls written out (no handler, no annotation read at run time), how its
// bean is made, and the `HttpServiceGroup` bean of each group.
//
// ```dart
// class _$BookServiceHttpService implements BookService {
//   _$BookServiceHttpService(this._rest);
//
//   final RestClient _rest;
//
//   @override
//   Future<Book> find(String isbn) => _rest
//       .get()
//       .uri(r'/books/{isbn}', {r'isbn': isbn})
//       .retrieve()
//       .body<Book>();
//
//   @override
//   Future<List<Book>> search(String q, {int? year}) => _rest
//       .get()
//       .uri(
//         (UriBuilder uri) => uri
//             .path(r'/books')
//             .queryParam(r'q', q)
//             .queryParamIfPresent(r'year', year)
//             .build(),
//       )
//       .retrieve()
//       .body<List<Book>>(const ListType<Book>(ClassType<Book>()));
// }
// ```
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_model.dart';

// The starter re-exports the web library, so its one import names every
// type the calls use.
const _starterUrl =
    'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

Reference _starter(String name) => refer(name, _starterUrl);

// The methods of `RestClient` that start a request of their own method;
// those of the first line have no body.
const _withoutBody = {'get', 'head', 'options', 'delete'};
const _withBody = {'post', 'put', 'patch'};

/// Writes the HTTP services of one module ([model]) through the emitter's
/// [emission].
final class HttpServiceEmitter {
  /// The HTTP service code of [model], written through [emission].
  HttpServiceEmitter(this.emission, this.model);

  /// The emitter's ways of naming types and values.
  final ModuleEmission emission;

  /// What the part found in the module.
  final HttpServiceModuleModel model;

  /// The class of each service, in the order of their beans.
  List<Class> serviceClasses() => [
    for (final service in model.services) _serviceClass(service),
  ];

  /// How the bean of [service] is made: its class on the `RestClient` of
  /// its group.
  Expression serviceCreation(HttpServiceModel service) {
    Expression dependency(Reference type) =>
        refer('r').property('dependency').call([], {}, [type]);
    return refer(service.className).newInstance(
      [
        dependency(
          _starter('HttpServiceGroups'),
        ).property('restClient').call([emission.string(service.group)]),
      ],
      {
        if (service.resolvesPlaceholders)
          'environment': dependency(emission.spring('Environment')),
        if (service.writesJsonParts)
          'mapper': dependency(emission.spring('ObjectMapper')),
      },
    );
  }

  /// The `HttpServiceGroup` bean of each group the module's
  /// `@ImportHttpServices` declare, one per importer, with its interfaces
  /// and the importer's conditions: the `HttpServiceGroups` bean joins
  /// those of a name and makes a `RestClient` for each.
  List<Expression> groupDefinitions() {
    final group = _starter('HttpServiceGroup');
    return [
      for (final HttpServiceGroupModel(:name, :types, :importer)
          in model.groups)
        emission
            .spring('BeanDefinition')
            .newInstance(
              [],
              {
                'name': emission.string(
                  'httpServiceGroup.$name#${emission.moduleName}'
                  '${importer.key == null ? '' : '.${importer.key}'}',
                ),
                'source': emission.string(
                  'package:spring_boot_starter_restclient#HttpServiceGroup.'
                  '$name',
                ),
                'types': literalConstList([group]),
                if (importer.conditions.isNotEmpty)
                  'conditions': literalList([
                    for (final condition in importer.conditions)
                      emission.condition(condition, importer.element),
                  ]),
                'create': emission.closure(
                  ['r'],
                  group
                      .constInstance(
                        [emission.string(name)],
                        {
                          if (types.isNotEmpty)
                            'types': literalList([
                              for (final type in types)
                                emission.typeValue(type, type.element),
                            ]),
                        },
                      )
                      .code,
                  lambda: true,
                ),
              },
              [group],
            ),
    ];
  }

  Class _serviceClass(HttpServiceModel service) {
    final element = service.type.element;
    final resolved = <(String, String)>[
      for (final call in service.calls) ...[
        if (call.url.hasPlaceholders) (call.url.fieldName, call.url.text),
        for (final header in call.headers)
          for (final (index, value) in header.values.indexed)
            if (value.contains(r'${')) (header.fieldName(index), value),
      ],
    ];
    final mapper = service.writesJsonParts;
    Field field(String name, Reference type) => Field(
      (f) => f
        ..modifier = FieldModifier.final$
        ..name = name
        ..type = type,
    );
    Parameter named(String name, Reference type) => Parameter(
      (p) => p
        ..name = name
        ..named = true
        ..required = true
        ..type = type,
    );
    return Class(
      (c) => c
        ..docs.add(
          '/// `${element.name}`: each method a call through the '
          '`RestClient` of the HTTP\n/// service group '
          '"${emission.docText(service.group)}".',
        )
        ..name = service.className
        ..implements.add(emission.type(service.type, element))
        ..constructors.add(
          Constructor(
            (k) => k
              ..requiredParameters.add(
                Parameter(
                  (p) => p
                    ..name = '_rest'
                    ..toThis = true,
                ),
              )
              ..optionalParameters.addAll([
                if (resolved.isNotEmpty)
                  named('environment', emission.spring('Environment')),
                if (mapper) named('mapper', emission.spring('ObjectMapper')),
              ])
              ..initializers.addAll([
                if (mapper) refer('_mapper').assign(refer('mapper')).code,
                for (final (name, text) in resolved)
                  refer(name)
                      .assign(
                        refer('environment')
                            .property('resolveRequiredPlaceholders')
                            .call([emission.string(text)]),
                      )
                      .code,
              ]),
          ),
        )
        ..fields.addAll([
          field('_rest', _starter('RestClient')),
          if (mapper) field('_mapper', emission.spring('ObjectMapper')),
          for (final (name, _) in resolved) field(name, refer('String')),
        ])
        ..methods.addAll([
          for (final call in service.calls)
            _CallWriter(this, call, element).method(),
        ]),
    );
  }
}

// Writes the method of one call: the request as one chain of the request
// spec's methods, with statements for what a `null` leaves out, then what
// is read of the response.
final class _CallWriter {
  _CallWriter(HttpServiceEmitter emitter, this.call, this._element)
    : _emission = emitter.emission,
      _taken = {for (final parameter in call.member.parameters) parameter.name};

  final ModuleEmission _emission;
  final HttpCallModel call;

  // The interface, which the types of the signature are named from.
  final Element _element;

  // The names in the method's scope: a local variable gets a free one.
  final Set<String> _taken;

  String _free(String name) {
    var candidate = name;
    for (var i = 2; _taken.contains(candidate); i++) {
      candidate = '$name$i';
    }
    _taken.add(candidate);
    return candidate;
  }

  Method method() {
    final member = call.member;
    final element = _element;
    final statements = <Code>[];
    var request = _uri(_start());
    final bodySpec = _isBodySpec;
    for (final header in call.headers) {
      for (final (index, value) in header.values.indexed) {
        final text = value.contains(r'${')
            ? refer(header.fieldName(index))
            : _emission.string(value);
        request = request.property('header').call([
          _emission.string(header.name),
          text,
        ]);
      }
    }
    if (call.accept.isNotEmpty) {
      request = request.property('accept').call([
        _emission.string(call.accept.join(', ')),
      ]);
    }
    final parts = [
      for (final argument in call.arguments)
        if (argument is PartArgument) argument,
    ];
    if (call.contentType case final contentType? when parts.isEmpty) {
      request = bodySpec
          ? request.property('contentType').call([
              _emission.string(contentType),
            ])
          : request.property('header').call([
              _emission.string('Content-Type'),
              _emission.string(contentType),
            ]);
    }
    if (call.version case final version?) {
      request = request.property('apiVersion').call([
        _emission.string(version),
      ]);
    }
    for (final attribute in call.attributes) {
      request = request.property('attribute').call([
        _emission.string(attribute.name),
        _emission.constant(attribute.value, attribute.element),
      ]);
    }
    final pending = <HttpArgument>[];
    for (final argument in call.arguments) {
      switch (argument) {
        case TextArgument(:final name, :final text, shape: ValueShape.single)
            when !argument.isNullable:
          request = request.property(argument.specMethod).call([
            _emission.string(name),
            _text(refer(argument.parameter), text),
          ]);
        case AttributeArgument(:final name, isMap: false)
            when !argument.isNullable:
          request = request.property('attribute').call([
            _emission.string(name),
            refer(argument.parameter),
          ]);
        case HeadersArgument(:final parameter) when !argument.isNullable:
          request = request.property('headers').call([
            _addHeaders(refer(parameter)),
          ]);
        case TextArgument() || AttributeArgument() || HeadersArgument():
          pending.add(argument);
        case BodyArgument(:final parameter, :final type):
          request = request.property('body').call([
            refer(parameter),
            ?_typeInfo(type, element),
          ]);
        case PathArgument() || QueryArgument() || PartArgument():
          break;
      }
    }
    if (call.sendsForm) {
      request = request.property('body').call([_form()]);
    }
    if (parts.isNotEmpty) {
      request = request.property('body').call([
        _starter('MultipartBody').newInstance([
          literalList([for (final part in parts) _part(part)]),
        ]),
      ]);
    }
    var sent = request;
    if (pending.isNotEmpty) {
      final name = _free('request');
      statements.add(declareFinal(name).assign(request).statement);
      for (final argument in pending) {
        statements.add(_pendingStatement(name, argument));
      }
      sent = refer(name);
    }
    final result = _response(sent.property('retrieve').call([]), element);
    final lambda = statements.isEmpty;
    return Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..name = member.name
        ..returns = _emission.anyType(member.returnType, element)
        ..requiredParameters.addAll([
          for (final parameter in member.parameters)
            if (!parameter.isNamed && parameter.isRequired)
              _emission.parameter(parameter, element),
        ])
        ..optionalParameters.addAll([
          for (final parameter in member.parameters)
            if (parameter.isNamed || !parameter.isRequired)
              _emission.parameter(parameter, element),
        ])
        ..lambda = lambda
        ..body = lambda
            ? result.code
            : Block.of([...statements, result.returned.statement]),
    );
  }

  // The request of the call's method: `_rest.get()`, or `_rest.method(...)`
  // for one with a body that the shortcut has not, or given by a parameter.
  Expression _start() {
    final rest = refer('_rest');
    if (call.methodParameter case final parameter?) {
      return rest.property('method').call([refer(parameter)]);
    }
    final method = call.httpMethod;
    if (_withBody.contains(method) ||
        (_withoutBody.contains(method) && !call.hasBody)) {
      return rest.property(method).call([]);
    }
    return rest.property('method').call([
      _starter('HttpMethod').property(method),
    ]);
  }

  // Whether the request spec has a body (`contentType`, `body`).
  bool get _isBodySpec =>
      call.methodParameter != null ||
      !_withoutBody.contains(call.httpMethod) ||
      call.hasBody;

  // `.uri(...)`: the template and its variables, a `UriBuilder` function
  // when there are query parameters, the `Uri` parameter, or the URL
  // expanded by the `UriBuilderFactory` parameter.
  Expression _uri(Expression request) {
    if (call.uriParameter case final uri?) {
      return request.property('uri').call([refer(uri)]);
    }
    final url = call.url;
    final paths = [
      for (final argument in call.arguments)
        if (argument is PathArgument) argument,
    ];
    final variables = paths.isEmpty
        ? null
        : paths.length == 1 && paths.single.isMap && !paths.single.isNullable
        ? refer(paths.single.parameter)
        : literalMap({
            for (final path in paths)
              if (path.isMap)
                (path.isNullable ? literalNullSafeSpread() : literalSpread()):
                    refer(path.parameter)
              else
                _emission.string(path.name): refer(path.parameter),
          });
    final template = url.hasPlaceholders
        ? refer(url.fieldName)
        : _emission.string(url.text);
    final queries = call.sendsForm
        ? const <QueryArgument>[]
        : [
            for (final argument in call.arguments)
              if (argument is QueryArgument) argument,
          ];
    final factory = switch (call.uriBuilderFactory) {
      null => null,
      UriBuilderFactoryParameter(:final name, isNullable: false) => refer(name),
      UriBuilderFactoryParameter(:final name) =>
        refer(name)
            .ifNullThen(_starter('UriBuilderFactory').constInstance([]))
            .parenthesized,
    };
    if (queries.isEmpty) {
      if (factory != null) {
        return request.property('uri').call([
          factory.property('expand').call([template, ?variables]),
        ]);
      }
      return request.property('uri').call([template, ?variables]);
    }
    final absolute = !url.hasPlaceholders && url.isAbsolute;
    final path = url.hasPlaceholders ? template : _emission.string(url.path);
    final builderName = absolute || factory != null ? '_' : _free('uri');
    var builder = factory != null
        ? factory.property('uriString').call([path])
        : absolute
        ? _starter('UriBuilder').newInstance([_emission.string(url.path)])
        : refer(builderName).property('path').call([path]);
    if (!url.hasPlaceholders) {
      for (final (name, value) in url.query) {
        builder = builder.property('queryParam').call([
          _emission.string(name),
          if (value != null) _emission.string(value),
        ]);
      }
    }
    for (final query in queries) {
      builder = query.shape.isMap
          ? builder.property('queryParams').call([
              if (query.isNullable)
                refer(query.parameter).ifNullThen(literalConstMap({}))
              else
                refer(query.parameter),
            ])
          : builder
                .property(
                  query.isNullable ? 'queryParamIfPresent' : 'queryParam',
                )
                .call([_emission.string(query.name), refer(query.parameter)]);
    }
    builder = builder.property('build').call([?variables]);
    if (factory != null) {
      return request.property('uri').call([builder]);
    }
    return request.property('uri').call([
      Method(
        (m) => m
          ..requiredParameters.add(
            Parameter(
              (p) => p
                ..name = builderName
                ..type = _starter('UriBuilder'),
            ),
          )
          ..lambda = true
          ..body = builder.code,
      ).closure,
    ]);
  }

  // `(all) => all.addHeaders(headers)`: every header of an `HttpHeaders`
  // parameter added to the request's.
  Expression _addHeaders(Expression headers) {
    final all = _free('all');
    return Method(
      (m) => m
        ..requiredParameters.add(Parameter((p) => p..name = all))
        ..lambda = true
        ..body = refer(all).property('addHeaders').call([headers]).code,
    ).closure;
  }

  // A value set by a statement of its own: a header or cookie that a
  // `null` leaves out, that has a value for each item or a value for each
  // entry of a map; a nullable request attribute or a map of them; the
  // headers of a nullable `HttpHeaders`.
  Code _pendingStatement(String request, HttpArgument argument) {
    final parameter = argument.parameter;
    final each = switch (argument) {
      TextArgument() => _textStatement(request, argument),
      AttributeArgument() => _attributeStatement(request, argument),
      HeadersArgument() => refer(
        request,
      ).property('headers').call([_addHeaders(refer(parameter))]).statement,
      _ => throw StateError('No statement for ${argument.runtimeType}'),
    };
    return argument.isNullable
        ? Block.of([Code('if ($parameter != null) {'), each, const Code('}')])
        : each;
  }

  Code _textStatement(String request, TextArgument argument) {
    Code add(Expression name, Expression value) =>
        refer(request)
            .property(argument.specMethod)
            .call([name, _text(value, argument.text)])
            .statement;
    Code loop(String item, String over, Code body) =>
        Block.of([Code('for (final $item in $over) {'), body, const Code('}')]);
    final parameter = argument.parameter;
    final name = _emission.string(argument.name);
    switch (argument.shape) {
      case ValueShape.single:
        return add(name, refer(parameter));
      case ValueShape.iterable:
        final item = _free('value');
        return loop(item, parameter, add(name, refer(item)));
      case ValueShape.map:
        final (key, value) = (_free('name'), _free('value'));
        return loop(
          'MapEntry(key: $key, value: $value)',
          '$parameter.entries',
          add(refer(key), refer(value)),
        );
      case ValueShape.multiMap:
        final (key, values, value) = (
          _free('name'),
          _free('values'),
          _free('value'),
        );
        return loop(
          'MapEntry(key: $key, value: $values)',
          '$parameter.entries',
          loop(value, values, add(refer(key), refer(value))),
        );
    }
  }

  Code _attributeStatement(String request, AttributeArgument argument) {
    Code set(Expression name, Expression value) => refer(
      request,
    ).property('attribute').call([name, value]).statement;
    final parameter = argument.parameter;
    if (!argument.isMap) {
      return set(_emission.string(argument.name), refer(parameter));
    }
    final (key, value) = (_free('name'), _free('value'));
    final body = set(refer(key), refer(value));
    return Block.of([
      Code(
        'for (final MapEntry(key: $key, value: $value) in '
        '$parameter.entries) {',
      ),
      if (argument.nullableValues)
        Block.of([Code('if ($value != null) {'), body, const Code('}')])
      else
        body,
      const Code('}'),
    ]);
  }

  // The `@RequestParam` values as the fields of a form body; a `null` one
  // is left out by the form converter, a map's entries spread into it.
  Expression _form() => literalMap({
    for (final argument in call.arguments)
      if (argument is QueryArgument)
        if (argument.shape.isMap)
          (argument.isNullable ? literalNullSafeSpread() : literalSpread()):
              _formMap(argument)
        else
          _emission.string(argument.name): _formValue(argument),
  });

  Expression _formValue(QueryArgument argument) {
    final value = refer(argument.parameter);
    final nullable = argument.isNullable;
    Expression convert(Expression item, bool itemNullable) =>
        switch (argument.text) {
          TextKind.enumName =>
            itemNullable
                ? item.nullSafeProperty('name')
                : item.property('name'),
          TextKind.dateTime =>
            (itemNullable
                    ? item.nullSafeProperty('toIso8601String')
                    : item.property('toIso8601String'))
                .call([]),
          TextKind.string || TextKind.other => item,
        };
    final isIterable = argument.isIterable;
    if (!isIterable ||
        argument.text == TextKind.string ||
        argument.text == TextKind.other) {
      return isIterable ? value : convert(value, nullable);
    }
    final item = _free('value');
    final mapped = Method(
      (m) => m
        ..requiredParameters.add(Parameter((p) => p..name = item))
        ..lambda = true
        ..body = convert(refer(item), false).code,
    ).closure;
    return (nullable ? value.nullSafeProperty('map') : value.property('map'))
        .call([mapped]);
  }

  // A map of form fields, its values converted when the form converter's
  // `toString()` would not write them (an enum's name, a `DateTime` in
  // ISO-8601).
  Expression _formMap(QueryArgument argument) {
    final map = refer(argument.parameter);
    if (argument.text == TextKind.string || argument.text == TextKind.other) {
      return map;
    }
    final (key, value) = (_free('name'), _free('value'));
    Expression converted(Expression item) => _text(item, argument.text);
    final Expression entryValue;
    if (argument.shape == ValueShape.multiMap) {
      final item = _free('item');
      entryValue = refer(value).property('map').call([
        Method(
          (m) => m
            ..requiredParameters.add(Parameter((p) => p..name = item))
            ..lambda = true
            ..body = converted(refer(item)).code,
        ).closure,
      ]);
    } else {
      entryValue = converted(refer(value));
    }
    final mapped = argument.isNullable
        ? map.nullSafeProperty('map')
        : map.property('map');
    return mapped.call([
      Method(
        (m) => m
          ..requiredParameters.addAll([
            Parameter((p) => p..name = key),
            Parameter((p) => p..name = value),
          ])
          ..lambda = true
          ..body = refer('MapEntry').call([refer(key), entryValue]).code,
      ).closure,
    ]);
  }

  // The parts of one `@RequestPart` parameter, as elements of the parts'
  // list: `if (x != null)` and `for (final file in files)` where needed. A
  // `MultipartFile` streams its content, opened again for each attempt of
  // a retried call, so nothing is awaited.
  Expression _part(PartArgument argument) {
    final name = _emission.string(argument.name);
    final part = _starter('MultipartBodyPart');
    final parameter = argument.parameter;
    Expression file(Expression value) =>
        part.newInstanceNamed('multipartFile', [name, value]);
    Expression field(Expression value) =>
        part.newInstanceNamed('field', [name, _text(value, argument.text)]);
    Code each(Expression Function(Expression item) make) {
      final item = _free(argument.kind == PartKind.fields ? 'value' : 'file');
      return Block.of([
        Code('for (final $item in $parameter) '),
        make(refer(item)).code,
      ]);
    }

    final value = refer(parameter);
    final element = switch (argument.kind) {
      PartKind.multipartFile => file(value).code,
      PartKind.multipartFiles => each(file),
      PartKind.bytes => part.newInstanceNamed('file', [name, value]).code,
      PartKind.field => field(value).code,
      PartKind.fields => each(field),
      PartKind.json => part.newInstanceNamed('json', [
        name,
        refer('_mapper').property('writeValueAsString').call([value]),
      ]).code,
    };
    return CodeExpression(
      argument.isNullable
          ? Block.of([Code('if ($parameter != null) '), element])
          : element,
    );
  }

  // What the method reads of the response, from `retrieve()`.
  Expression _response(Expression retrieve, Element element) =>
      switch (call.response) {
        BodyResponse(:final type) =>
          retrieve
              .property('body')
              .call(
                [?_typeInfo(type, element)],
                {},
                [_emission.anyType(type, element)],
              ),
        BodilessResponse() || EntityResponse(type: null) =>
          retrieve.property('toBodilessEntity').call([]),
        EntityResponse(:final type?) =>
          retrieve
              .property('toEntity')
              .call(
                [?_typeInfo(type, element)],
                {},
                [_emission.anyType(type, element)],
              ),
        HeadersResponse() => () {
          final response = _free('response');
          return retrieve
              .property('toBodilessEntity')
              .call([])
              .property('then')
              .call([
                Method(
                  (m) => m
                    ..requiredParameters.add(
                      Parameter((p) => p..name = response),
                    )
                    ..lambda = true
                    ..body = refer(response).property('headers').code,
                ).closure,
              ]);
        }(),
        EventStreamResponse(:final type) =>
          retrieve
              .property('eventStream')
              .call(
                [],
                {'type': ?_typeInfo(type, element)},
                [_emission.anyType(type, element)],
              ),
        BodyStreamResponse() => retrieve.property('bodyStream').call([]),
      };

  // The `TypeInfo` a generic type (`List<Book>`), an enum or `Object`
  // needs; `null` for a plain class, which the client reads by its type
  // argument.
  Expression? _typeInfo(DartType type, Element element) {
    if (type is InterfaceType &&
        type.typeArguments.isEmpty &&
        type.element is! EnumElement &&
        !type.isDartCoreObject) {
      return null;
    }
    return _emission.typeInfo(type, element).$1;
  }

  // A simple value as text.
  static Expression _text(Expression value, TextKind kind) => switch (kind) {
    TextKind.string => value,
    TextKind.enumName => value.property('name'),
    TextKind.dateTime => value.property('toIso8601String').call([]),
    TextKind.other => value.property('toString').call([]),
  };
}
