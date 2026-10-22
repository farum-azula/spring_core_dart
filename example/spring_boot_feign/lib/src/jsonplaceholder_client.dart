// The API as an interface. The generator writes its implementation; the
// starter turns each call into an HTTP request and the JSON into the
// models.
//
// Spring (Java): the same interface with Spring Cloud OpenFeign.
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@FeignClient('jsonplaceholder', url: r'${jsonplaceholder.url}')
abstract interface class JsonPlaceholderClient {
  @GetMapping('/users/{id}')
  Future<User> user(@PathVariable() int id);

  @GetMapping('/posts')
  Future<List<Post>> postsOf(@RequestParam('userId') int userId);

  @GetMapping('/posts/{id}')
  Future<Post> post(@PathVariable() int id);

  @GetMapping('/posts/{id}/comments')
  Future<List<Comment>> comments(@PathVariable() int id);

  @PostMapping('/posts')
  Future<ResponseEntity<Post>> create(@RequestBody() NewPost post);
}
