# Keycloak for the guides

The identity provider of the guides' single sign-on: the server guide
logs browsers in through it (`oauth2Login()`, the server's `sso`
profile, [chapter 4](../server_guide/README.md#single-sign-on-with-keycloak)),
and the Flutter guide's native apps log in at it themselves
([chapter 7](../flutter_guide/README.md#single-sign-on-with-keycloak)).

```sh
docker compose up        # in this folder: http://localhost:8180, admin / admin
```

Without Docker, the plain distribution
([keycloak.org/downloads](https://www.keycloak.org/downloads), Java 21)
does the same:

```sh
cp neon-realm.json keycloak-26.x/data/import/
keycloak-26.x/bin/kc.sh start-dev --http-port=8180 --import-realm
```

`neon-realm.json`, the realm `neon` (`http://localhost:8180/realms/neon`):

| | |
|---|---|
| users | `ada` / `ada-secret` (role USER), `root` / `root-secret` (USER, ADMIN), as the server's form login |
| roles | the realm roles, in a top-level `roles` claim of the ID token, the access token and the user info |
| `neon-server` | the server: a confidential client (secret `neon-server-dev-secret`), redirect `http://localhost:8080/login/oauth2/code/keycloak`, back after logout to `http://localhost:8080/*` and `http://localhost:5050/*` (the web app) |
| `neon-app` | the native apps: a public client with PKCE (S256), redirects `books.neon.app:/oauth2/callback` and `http://127.0.0.1/oauth2/callback` (any port), back after logout to `books.neon.app:/oauth2/logout` and `http://127.0.0.1/oauth2/logout` |
| access tokens | audience `neon-api` (the server checks it), 5 minutes; the users' name in `preferred_username` |

Development only: every password and the client secret here are public.
The realm is imported at the first start; `docker compose down` forgets
everything.
