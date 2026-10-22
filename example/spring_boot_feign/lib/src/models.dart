// The JSON of JSONPlaceholder as plain immutable classes: no @Introspected,
// no fromJson / toJson. The generator introspects them because the Feign
// client uses them, and the ObjectMapper does the rest.

class User {
  const User({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.address,
    required this.company,
    this.website,
  });

  final int id;
  final String name;
  final String username;
  final String email;
  final Address address;
  final Company company;
  final String? website;
}

class Address {
  const Address({
    required this.street,
    required this.city,
    required this.zipcode,
  });

  final String street;
  final String city;
  final String zipcode;
}

class Company {
  const Company({required this.name, required this.catchPhrase});

  final String name;
  final String catchPhrase;
}

class Post {
  const Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
  });

  final int id;
  final int userId;
  final String title;
  final String body;
}

class NewPost {
  const NewPost({
    required this.userId,
    required this.title,
    required this.body,
  });

  final int userId;
  final String title;
  final String body;
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.name,
    required this.email,
    required this.body,
  });

  final int id;
  final int postId;
  final String name;
  final String email;
  final String body;
}
