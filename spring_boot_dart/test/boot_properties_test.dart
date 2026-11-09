import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_boot_dart/src/properties/properties.dart';
import 'package:test/test.dart';

// The classes of boot_properties.dart are what the code reads (bound with
// `bindBootProperties`) and what the editor metadata describes. These tests
// check what binding must keep from the days of string reads.
void main() {
  StandardEnvironment env(Map<String, Object?> properties) =>
      StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(MapPropertySource('test', properties));

  test('the JSON defaults are the defaults of the mapper features', () {
    final json = JsonProperties();
    expect(
      json.deserialization.failOnUnknownProperties,
      DeserializationFeature.failOnUnknownProperties.enabledByDefault,
    );
    expect(
      json.deserialization.acceptFloatAsInt,
      DeserializationFeature.acceptFloatAsInt.enabledByDefault,
    );
    expect(
      json.deserialization.failOnNullForPrimitives,
      DeserializationFeature.failOnNullForPrimitives.enabledByDefault,
    );
    expect(
      json.serialization.writeDatesAsTimestamps,
      DateTimeFeature.writeDatesAsTimestamps.enabledByDefault,
    );
    expect(
      json.serialization.writeDurationsAsTimestamps,
      DateTimeFeature.writeDurationsAsTimestamps.enabledByDefault,
    );
    expect(
      json.serialization.writeDateTimestampsAsNanoseconds,
      DateTimeFeature.writeDateTimestampsAsNanoseconds.enabledByDefault,
    );
    expect(
      json.deserialization.readDateTimestampsAsNanoseconds,
      DateTimeFeature.readDateTimestampsAsNanoseconds.enabledByDefault,
    );
    expect(
      json.serialization.indentOutput,
      SerializationFeature.indentOutput.enabledByDefault,
    );
    expect(
      json.mapper.sortPropertiesAlphabetically,
      MapperFeature.sortPropertiesAlphabetically.enabledByDefault,
    );
    expect(
      json.mapper.defaultViewInclusion,
      MapperFeature.defaultViewInclusion.enabledByDefault,
    );
  });

  test('the JSON keys the mapper reads are those of the class', () {
    expect(jsonPropertyKeys(), contains('spring.json.time-zone'));
    expect(
      jsonPropertyKeys(),
      contains('spring.json.datatype.datetime.write-dates-as-timestamps'),
    );
    // The schemas' keys: the list, and the registry's switch.
    expect(jsonPropertyKeys(), contains('spring.json.schemas'));
    expect(
      jsonPropertyKeys(),
      contains('spring.json.schemas-registry.properties'),
    );
    expect(jsonPropertyKeys(), hasLength(19));
  });

  test('the banner mode accepts false and any case, and rejects the rest', () {
    BannerMode mode(String value) => bindBootProperties(
      env({'spring.main.banner-mode': value}),
      MainProperties(),
    ).bannerMode;
    expect(mode('false'), BannerMode.off);
    expect(mode(' LOG '), BannerMode.log);
    expect(
      () => mode('loud'),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
  });

  test('debug and trace are set by a bare flag, an empty value or true', () {
    final properties = bindBootProperties(
      env({'debug': '', 'trace': 'false'}),
      DebugProperties(),
    );
    expect(properties.debug, '');
    expect(properties.trace, 'false');
  });

  test('values the caller put in stay when the environment has none', () {
    final properties = bindBootProperties(
      env({}),
      MainProperties()
        ..bannerMode = BannerMode.log
        ..registerShutdownHook = true,
    );
    expect(properties.bannerMode, BannerMode.log);
    expect(properties.registerShutdownHook, isTrue);
    expect(properties.logStartupInfo, isTrue);
  });

  test('a plain message cache duration is in seconds', () {
    final properties = bindBootProperties(
      env({'spring.messages.cache-duration': '5'}),
      MessagesProperties(),
    );
    expect(properties.cacheDuration, const Duration(seconds: 5));
  });
}
