package dev.farumazula.spring_boot_starter_flutter_security

import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale

/**
 * Decides whether a link that reached [RedirectReceiverActivity] is the
 * redirect of the login that runs: the same scheme and authority (host
 * ignoring case, the same port), exactly the same path as the
 * registration's redirect URI and, when the login sent a `state`, exactly
 * that `state` once in the query. The rest of the query (`code`, `iss`)
 * and the fragment do not take part; the Dart side checks them.
 *
 * An `https` redirect (an App Link) shares its host with the app's web
 * site, so other links of that host can reach the activity too (a link in
 * a mail, a page of the site): they never complete a login. A custom
 * scheme gets the same check, so another path of the app's scheme is no
 * login either. A link with the exact path but another `state` (a page
 * of another site sending the browser there) is ignored too, and the
 * login goes on waiting: the provider always sends the request's
 * `state` back (RFC 6749 §4.1.2, errors included).
 *
 * Pure JVM code (java.net.URI), so the unit tests run without Android.
 */
internal object RedirectMatcher {
    /**
     * Whether [actual] is a redirect to [expected] carrying [expectedState]
     * (no check of the state when it is `null`).
     */
    fun matches(expected: String, actual: String, expectedState: String? = null): Boolean {
        val want = parse(expected) ?: return false
        val got = parse(actual) ?: return false
        if (got.isOpaque || want.isOpaque) return false
        val scheme = want.scheme?.lowercase(Locale.ROOT) ?: return false
        if (got.scheme?.lowercase(Locale.ROOT) != scheme) return false
        if (got.rawUserInfo != null) return false
        if (!sameAuthority(want, got)) return false
        if (path(got) != path(want)) return false
        return expectedState == null || hasState(got, expectedState)
    }

    /** Whether [redirectUri] can bring a login back to the app at all. */
    fun isAppRedirect(redirectUri: String): Boolean {
        val uri = parse(redirectUri) ?: return false
        // `books.neon.app:callback` has no path a link could match.
        if (uri.isOpaque) return false
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return false
        return when (scheme) {
            // A plain http link is never verified as an App Link: the
            // browser would keep it, and anyone on the way could read it.
            "http" -> false
            "https" -> !uri.host.isNullOrEmpty()
            else -> true
        }
    }

    /**
     * The `state` the authorization URI [authorizationUri] sends, when it
     * sends exactly one; `null` otherwise (then no link is judged by it).
     */
    fun stateOf(authorizationUri: String): String? {
        val uri = parse(authorizationUri) ?: return null
        if (uri.isOpaque) return null
        return queryValues(uri.rawQuery, "state")?.singleOrNull()
    }

    private fun parse(text: String): URI? =
        try {
            URI(text)
        } catch (e: URISyntaxException) {
            null
        }

    // A server-based authority compares its host (ignoring case) and its
    // port (the scheme's default when none); an authority that is no
    // valid host (java.net.URI's registry-based one, host null) compares
    // its raw text, so two invalid hosts never match each other. No
    // authority matches only no authority.
    private fun sameAuthority(want: URI, got: URI): Boolean {
        val wantHost = want.host
        val gotHost = got.host
        if (wantHost == null || gotHost == null) {
            return wantHost == null &&
                gotHost == null &&
                want.rawAuthority?.lowercase(Locale.ROOT) == got.rawAuthority?.lowercase(Locale.ROOT)
        }
        return gotHost.lowercase(Locale.ROOT) == wantHost.lowercase(Locale.ROOT) && port(got) == port(want)
    }

    private fun port(uri: URI): Int =
        when {
            uri.port != -1 -> uri.port
            uri.scheme.equals("https", ignoreCase = true) -> 443
            uri.scheme.equals("http", ignoreCase = true) -> 80
            else -> -1
        }

    // The raw path, so `/a%2Fb` and `/a/b` stay different; an empty path
    // of an https URI is `/`.
    private fun path(uri: URI): String {
        val raw = uri.rawPath ?: ""
        return if (raw.isEmpty() && uri.host != null) "/" else raw
    }

    // Exactly one `state`, equal to [expected] (compared in constant time).
    private fun hasState(uri: URI, expected: String): Boolean {
        val actual = queryValues(uri.rawQuery, "state")?.singleOrNull() ?: return false
        return MessageDigest.isEqual(
            actual.toByteArray(StandardCharsets.UTF_8),
            expected.toByteArray(StandardCharsets.UTF_8),
        )
    }

    // The decoded values of [name] in [rawQuery]; `null` for a query that
    // does not decode (a malformed `%`).
    private fun queryValues(rawQuery: String?, name: String): List<String>? {
        if (rawQuery == null) return emptyList()
        return try {
            rawQuery
                .split('&')
                .filter { it.isNotEmpty() }
                .mapNotNull { pair ->
                    val separator = pair.indexOf('=')
                    val key = if (separator < 0) pair else pair.substring(0, separator)
                    val value = if (separator < 0) "" else pair.substring(separator + 1)
                    if (decode(key) == name) decode(value) else null
                }
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    private fun decode(text: String): String = URLDecoder.decode(text, StandardCharsets.UTF_8.name())
}
