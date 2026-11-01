part of 'module_emitter.dart';

// The `EntityIntrospection`s of spring_boot_starter_data (see
// `EntityModel`), registered as one bean per module: the data layer reads
// the beans of every module. The runtime types are imported from the
// starter's public library, like the driver glue does.

const _dataUrl =
    'package:spring_boot_starter_data/spring_boot_starter_data.dart';

// A reference to a public type of the starter, e.g. `EntityProperty`.
Reference _data(String name) => refer(name, _dataUrl);

extension _EntityEmitter on ModuleEmitter {
  /// The bean holding the entities of the module [moduleName]: one
  /// `EntityIntrospections` with an `EntityIntrospection` for each. The
  /// name carries the module's, so the modules of one application, each
  /// with entities, register one each.
  Expression entityIntrospectionsBean(String moduleName) {
    final holder = _data('EntityIntrospections');
    return _spring('BeanDefinition').newInstance(
      [],
      {
        'name': _str('entityIntrospections#$moduleName'),
        'source': _str('package:spring_boot_starter_data#EntityIntrospections'),
        'types': literalConstList([holder]),
        'create': _closure(
          ['r'],
          holder.newInstance([
            literalList([
              for (final entity in _module.entities)
                _entityIntrospection(entity),
            ]),
          ]).code,
          lambda: true,
        ),
      },
      [holder],
    );
  }

  // One `EntityIntrospection<T>`: the properties as constants, and the
  // closures that read one, call the constructor with them and set one.
  Expression _entityIntrospection(EntityModel model) {
    final element = model.element;
    final beanType = _type(model.type, element);
    final infos = [
      for (final property in model.properties)
        _typeInfo(property.type, element),
    ];
    // A type info that is not constant (an enum with `@JsonValue`) makes
    // the list and its properties plain code.
    final isConst = infos.every((info) => info.$2);
    final properties = [
      for (final (index, property) in model.properties.indexed)
        (isConst
            ? _data('EntityProperty').constInstance
            : _data('EntityProperty').newInstance)(
          [_str(property.name), infos[index].$1],
          {
            if (property.annotations.isNotEmpty)
              'annotations': literalConstList([
                for (final annotation in property.annotations)
                  _constant(annotation, element),
              ]),
            if (property.parameter) 'parameter': literalTrue,
            if (property.writable) 'writable': literalTrue,
            if (property.defaultValue case final initial?) ...{
              'hasDefaultValue': literalTrue,
              'defaultValue': _initialValue(initial.value, element),
            },
          },
        ),
    ];
    final writable = [
      for (final (index, property) in model.properties.indexed)
        if (property.writable) (index, property),
    ];
    return _data('EntityIntrospection').newInstance(
      [
        _str(element.name!),
        (isConst ? literalConstList : literalList)(properties),
      ],
      {
        if (model.annotations.isNotEmpty)
          'annotations': literalConstList([
            for (final annotation in model.annotations)
              _constant(annotation, element),
          ]),
        'get': _closure(['e', 'i'], _entityGet(model).code, lambda: true),
        'create': _closure(
          ['v'],
          beanType
              .newInstance(
                [
                  for (final argument in model.arguments)
                    if (argument.name == null) _entityValue(model, argument),
                ],
                {
                  for (final argument in model.arguments)
                    ?argument.name: _entityValue(model, argument),
                },
              )
              .code,
          lambda: true,
        ),
        if (writable.isNotEmpty)
          'write': _closure(
            ['e', 'i', 'v'],
            _entitySwitch([
              for (final (index, property) in writable)
                (
                  index,
                  refer('e')
                      .property(property.name)
                      .assign(
                        _cast(refer('v'), _anyType(property.type, element)),
                      ),
                ),
            ]).code,
            lambda: true,
          ),
      },
      [beanType],
    );
  }

  // The value of the property at `i`: `switch (i) { 0 => e.id, _ => e.name }`.
  // One property at a time, so the mapping reads the stored ones only.
  Expression _entityGet(EntityModel model) {
    final values = [
      for (final property in model.properties)
        refer('e').property(property.name),
    ];
    return switch (values) {
      [] => literalNull,
      [final only] => only,
      [...final first, final last] => _entitySwitch([
        for (final (index, value) in first.indexed) (index, value),
      ], otherwise: last),
    };
  }

  // `v[2] as T`, T the type of the constructor parameter, which the scan
  // checked the property fits.
  Expression _entityValue(EntityModel model, EntityArgument argument) {
    final name = model.properties[argument.property].name;
    final parameter = model.element.unnamedConstructor!.formalParameters
        .firstWhere((parameter) => parameter.name == name);
    return _cast(
      refer('v').index(literalNum(argument.property)),
      _anyType(parameter.type, model.element),
    );
  }

  // `value as T`, without the parentheses `asA` adds.
  Expression _cast(Expression value, Reference type) => CodeExpression(
    Block.of([value.code, const Code(' as '), type.code]),
  );

  // `switch (i) { 0 => a, 1 => b, _ => null }`; [otherwise] replaces the
  // `null`.
  Expression _entitySwitch(
    List<(int, Expression)> cases, {
    Expression otherwise = literalNull,
  }) => CodeExpression(
    Block.of([
      const Code('switch (i) {'),
      for (final (index, body) in cases) ...[
        Code('$index => '),
        body.code,
        const Code(','),
      ],
      const Code('_ => '),
      otherwise.code,
      const Code(','),
      const Code('}'),
    ]),
  );
}
