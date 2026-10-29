package dev.farumazula.spring_boot_starter_flutter_security

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/**
 * Decides whether a link that reached [RedirectReceiverActivity] is the
 * redirect of the login that runs: the same scheme and host (ignoring
 * case), the same port and exactly the same path as the registration's
 * redirect URI. The query (`code`, `state`) and the fragment do not take
 * part; the Dart side checks them.
 *
 * An `https` redirect (an App Link) shares its host with the app's web
 * site, so other links of that host can reach the activity too (a link in
 * a mail, a page of the site): they never complete a login. A custom
 * scheme gets the same check, so another path of the app's scheme is no
 * login either.
 *
 * Pure JVM code (java.net.URI), so the unit tests run without Android.
 */
internal object RedirectMatcher {
    /** Whether [actual] is a redirect to [expected]. */
    fun matches(expected: String, actual: String): Boolean {
        val want = parse(expected) ?: return false
        val got = parse(actual) ?: return false
        if (got.isOpaque || want.isOpaque) return false
        val scheme = want.scheme?.lowercase(Locale.ROOT) ?: return false
        if (got.scheme?.lowercase(Locale.ROOT) != scheme) return false
        if (got.rawUserInfo != null) return false
        if (got.host?.lowercase(Locale.ROOT) != want.host?.lowercase(Locale.ROOT)) return false
        if (port(got) != port(want)) return false
        return path(got) == path(want)
    }

    /** Whether [redirectUri] can bring a login back to the app at all. */
    fun isAppRedirect(redirectUri: String): Boolean {
        val uri = parse(redirectUri) ?: return false
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return false
        return when (scheme) {
            // A plain http link is never verified as an App Link: the
            // browser would keep it, and anyone on the way could read it.
            "http" -> false
            "https" -> !uri.host.isNullOrEmpty()
            else -> true
        }
    }

    private fun parse(text: String): URI? =
        try {
            URI(text)
        } catch (e: URISyntaxException) {
            null
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
}
