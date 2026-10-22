// JSON the fake servers answer with, shaped like the real APIs (with extra
// fields the models do not have, as the real ones send).

/// `GET /users/1` of JSONPlaceholder.
const user = {
  'id': 1,
  'name': 'Leanne Graham',
  'username': 'Bret',
  'email': 'Sincere@april.biz',
  'address': {
    'street': 'Kulas Light',
    'suite': 'Apt. 556',
    'city': 'Gwenborough',
    'zipcode': '92998-3874',
  },
  'phone': '1-770-736-8031 x56442',
  'website': 'hildegard.org',
  'company': {
    'name': 'Romaguera-Crona',
    'catchPhrase': 'Multi-layered client-server neural-net',
    'bs': 'harness real-time e-markets',
  },
};

/// `GET /posts?userId=1`.
const posts = [
  {'userId': 1, 'id': 1, 'title': 'first post', 'body': 'one'},
  {'userId': 1, 'id': 2, 'title': 'second post', 'body': 'two'},
];

/// `GET /posts/1/comments`.
const comments = [
  {
    'postId': 1,
    'id': 1,
    'name': 'nice',
    'email': 'ann@example.com',
    'body': 'great',
  },
  {
    'postId': 1,
    'id': 2,
    'name': 'meh',
    'email': 'bob@example.com',
    'body': 'fine',
  },
  {
    'postId': 1,
    'id': 3,
    'name': 'ok',
    'email': 'eve@example.com',
    'body': 'ok',
  },
];

/// The answer to `POST /posts` (JSONPlaceholder gives every new post id
/// 101).
Map<String, Object?> created(Map<String, Object?> post) => {...post, 'id': 101};

/// One Wikimedia recent change (`data:` of an event), number [n].
Map<String, Object?> recentChange(int n) => {
  r'$schema': '/mediawiki/recentchange/1.0.0',
  'meta': {'domain': 'en.wikipedia.org', 'id': 'event-$n'},
  'id': 1000 + n,
  'type': n.isEven ? 'edit' : 'new',
  'title': 'Page $n',
  'user': n == 3 ? 'TidyBot' : 'Editor$n',
  'bot': n == 3,
  'wiki': 'enwiki',
  'server_name': 'en.wikipedia.org',
};
