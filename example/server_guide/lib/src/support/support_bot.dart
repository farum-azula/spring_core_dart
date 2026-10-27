// The support bot: on unless `neon.support.bot.enabled=false`, its answers
// in support/bot.properties (a @PropertySource), its texts in
// messages*.properties (English, Japanese).
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Component()
@ConditionalOnProperty('neon.support.bot.enabled', havingValue: 'true')
@PropertySource(['classpath:support/bot.properties'])
class SupportBot {
  SupportBot(this._environment, this._messages, this._shop);

  final Environment _environment;
  final MessageSource _messages;
  final ShopProperties _shop;

  /// The name the bot writes under.
  static const name = 'NEON Books';

  /// The greeting for [user], in [locale].
  String greet(String user, {String? locale}) =>
      _messages.getMessage('bot.greeting', args: [user], locale: locale);

  /// The answer to [question] of [user], in [locale] (`ja` or English).
  String answer(String question, String user, {String? locale}) {
    final text = question.toLowerCase();
    final code =
        _keywords.entries
            .where((entry) => text.contains(entry.key))
            .map((entry) => entry.value)
            .firstOrNull ??
        _environment.getProperty('bot.fallback') ??
        'bot.fallback';
    return _messages.getMessage(
      code,
      args: switch (code) {
        'bot.delivery' => [_shop.deliveryTime.inDays],
        'bot.hours' => [_shop.opensAt, _shop.closesAt],
        _ => [user],
      },
      locale: locale,
    );
  }

  /// `bot.answers.<keyword>=<message code>`.
  Map<String, String> get _keywords => {
    for (final keyword in const [
      'delivery',
      'shipping',
      'hours',
      'open',
      'refund',
    ])
      keyword: ?_environment.getProperty('bot.answers.$keyword'),
  };
}
