// Sending mail: one bean name, `mailSender`, declared by two profile
// configurations. Its type is what the @Bean method's body returns
// (LogMailSender in dev, SmtpMailSender in prod), as Spring knows it only
// once the bean exists.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class MailSender {
  void send(String to, String subject, String body);
}

/// dev: mails go to the log (`neon.mail`).
@Log(topic: 'neon.mail')
class LogMailSender implements MailSender {
  @override
  void send(String to, String subject, String body) =>
      log.info('mail to $to: $subject', fields: {'body': body});
}

/// prod: a mail server (here a stand-in that logs where it would send).
@Log(topic: 'neon.mail')
class SmtpMailSender implements MailSender {
  SmtpMailSender(this.host);

  final String host;

  @override
  void send(String to, String subject, String body) =>
      log.info('mail to $to via $host: $subject');
}

@Configuration()
@Profile(['!prod'])
class DevMailConfig {
  @Bean()
  MailSender mailSender() => LogMailSender();
}

@Configuration()
@Profile(['prod'])
class ProdMailConfig {
  @Bean()
  MailSender mailSender(
    @Value(r'${neon.mail.host:smtp.neon.books}') String host,
  ) => SmtpMailSender(host);
}
