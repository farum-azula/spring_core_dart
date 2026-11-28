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
    for (final attribute in call.attributes) {
      request = request.property('attribute').call([
        _emission.string(attribute.name),
        _emission.constant(attribute.value, attribute.element),
      ]);
    }
    final pending = <TextArgument>[];
    for (final argument in call.arguments) {
      switch (argument) {
        case TextArgument(:final name, :final text, isIterable: false)
            when !argument.isNullable:
          request = request.property(argument.specMethod).call([
            _emission.string(name),
            _text(refer(argument.parameter), text),
          ]);
        case TextArgument():
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
    final isAsync = call.awaitsParts;
    final voidResult = call.response is BodilessResponse;
    final lambda = statements.isEmpty && !(isAsync && voidResult);
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
        ..modifier = isAsync ? MethodModifier.async : null
        ..lambda = lambda
        ..body = lambda
            ? result.code
            : Block.of([
                ...statements,
                if (isAsync && voidResult)
                  result.awaited.statement
                else
                  result.returned.statement,
              ]),
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
  // when there are query parameters, or the `Uri` parameter.
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
        : literalMap({
            for (final path in paths)
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
    if (queries.isEmpty) {
      return request.property('uri').call([template, ?variables]);
    }
    final absolute = !url.hasPlaceholders && url.isAbsolute;
    final builderName = absolute ? '_' : _free('uri');
    var builder = absolute
        ? _starter('UriBuilder').newInstance([_emission.string(url.path)])
        : refer(builderName).property('path').call([
            if (url.hasPlaceholders) template else _emission.string(url.path),
          ]);
    if (!url.hasPlaceholders) {
      for (final (name, value) in url.query) {
        builder = builder.property('queryParam').call([
          _emission.string(name),
          if (value != null) _emission.string(value),
        ]);
      }
    }
    for (final query in queries) {
      builder = builder
          .property(query.isNullable ? 'queryParamIfPresent' : 'queryParam')
          .call([_emission.string(query.name), refer(query.parameter)]);
    }
    builder = builder.property('build').call([?variables]);
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

  // A header or cookie that a `null` leaves out, or that has a value for
  // each item.
  Code _pendingStatement(String request, TextArgument argument) {
    Code add(Expression value) => refer(request)
        .property(argument.specMethod)
        .call([_emission.string(argument.name), _text(value, argument.text)])
        .statement;
    final parameter = argument.parameter;
    final Code each;
    if (argument.isIterable) {
      final item = _free('value');
      each = Block.of([
        Code('for (final $item in $parameter) {'),
        add(refer(item)),
        const Code('}'),
      ]);
    } else {
      each = add(refer(parameter));
    }
    return argument.isNullable
        ? Block.of([Code('if ($parameter != null) {'), each, const Code('}')])
        : each;
  }

  // The `@RequestParam` values as the fields of a form body; a `null` one
  // is left out by the form converter.
  Expression _form() => literalMap({
    for (final argument in call.arguments)
      if (argument is QueryArgument)
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

  // The parts of one `@RequestPart` parameter, as elements of the parts'
  // list: `if (x != null)` and `for (final file in files)` where needed.
  Expression _part(PartArgument argument) {
    final name = _emission.string(argument.name);
    final part = _starter('MultipartBodyPart');
    final parameter = argument.parameter;
    Expression file(Expression value) => part.newInstanceNamed(
      'file',
      [name, value.property('bytes').awaited],
      {
        'filename': value.property('originalFilename'),
        'contentType': value.property('contentType'),
      },
    );
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
