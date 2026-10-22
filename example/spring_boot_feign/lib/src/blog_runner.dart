// Runs once the application has started: calls the API through the
// injected client and prints what came back.
import 'package:spring_boot_feign_example/src/jsonplaceholder_client.dart';
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@Component()
class BlogRunner implements ApplicationRunner {
  BlogRunner(this.api);

  final JsonPlaceholderClient api;

  static const _log = SpringLog('blog');

  @override
  Future<void> run(ApplicationArguments args) async {
    try {
      final user = await api.user(1);
      _log.info(
        'user 1: ${user.name} <${user.email}>, ${user.address.city}, '
        'works at ${user.company.name}',
      );

      final posts = await api.postsOf(user.id);
      _log.info(
        '${posts.length} posts by ${user.username}, first: "${posts.first.title}"',
      );

      final comments = await api.comments(posts.first.id);
      _log.info(
        '${comments.length} comments on post ${posts.first.id}, by '
        '${comments.map((c) => c.email).take(2).join(', ')}, ...',
      );

      final created = await api.create(
        NewPost(userId: user.id, title: 'Spring in Dart', body: 'It works.'),
      );
      _log.info(
        'created: ${created.statusCode}, id ${created.body!.id}, '
        '"${created.body!.title}"',
      );

      try {
        await api.post(9999);
      } on FeignNotFound catch (error) {
        _log.info('post 9999: ${error.status} Not Found (FeignNotFound)');
      }
    } on RetryableException catch (error) {
      _log.error('JSONPlaceholder is not reachable: ${error.message}');
    } on FeignException catch (error) {
      _log.error('JSONPlaceholder answered with an error: $error');
    }
  }
}
