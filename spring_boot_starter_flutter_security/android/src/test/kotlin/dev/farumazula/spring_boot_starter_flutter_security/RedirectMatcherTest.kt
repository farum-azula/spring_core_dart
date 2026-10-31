package dev.farumazula.spring_boot_starter_flutter_security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The redirect of the login that runs, and only it, completes the login. */
class RedirectMatcherTest {
    private val appLink = "https://books.neon.example/oauth2/callback"
    private val scheme = "books.neon.app:/oauth2/callback"

    @Test
    fun theRedirectOfTheLoginMatchesWithItsQuery() {
        assertTrue(RedirectMatcher.matches(appLink, "$appLink?code=c&state=s"))
        assertTrue(RedirectMatcher.matches(appLink, "HTTPS://Books.Neon.Example/oauth2/callback?code=c"))
        assertTrue(RedirectMatcher.matches(appLink, "https://books.neon.example:443/oauth2/callback"))
        assertTrue(RedirectMatcher.matches(scheme, "$scheme?code=c&state=s"))
        assertTrue(RedirectMatcher.matches("https://books.neon.example", "https://books.neon.example/?code=c"))
    }

    @Test
    fun otherLinksOfTheSameHostAreIgnored() {
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/books/42"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/oauth2/callback/x?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/oauth2/callbac?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/OAUTH2/callback?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/oauth2%2Fcallback?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/oauth2/callback/?code=c"))
    }

    @Test
    fun anotherHostSchemePortOrUserIsIgnored() {
        assertFalse(RedirectMatcher.matches(appLink, "https://evil.example/oauth2/callback?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example.evil.example/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(appLink, "http://books.neon.example/oauth2/callback?code=c"))
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example:8443/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(appLink, "https://user@books.neon.example/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(scheme, "books.neon.other:/oauth2/callback?code=c"))
        assertFalse(RedirectMatcher.matches(scheme, "books.neon.app:/oauth2/logout?code=c"))
        assertFalse(RedirectMatcher.matches(scheme, "books.neon.app:opaque"))
    }

    @Test
    fun malformedLinksAreIgnored() {
        assertFalse(RedirectMatcher.matches(appLink, "https://books.neon.example/oauth2/callback?%%%"))
        assertFalse(RedirectMatcher.matches(appLink, "not a uri at all"))
        assertFalse(RedirectMatcher.matches(appLink, ""))
        assertFalse(RedirectMatcher.matches("", appLink))
    }

    @Test
    fun onlyHttpsAndCustomSchemesBringTheLoginBack() {
        assertTrue(RedirectMatcher.isAppRedirect(appLink))
        assertTrue(RedirectMatcher.isAppRedirect(scheme))
        assertFalse(RedirectMatcher.isAppRedirect("http://books.neon.example/oauth2/callback"))
        assertFalse(RedirectMatcher.isAppRedirect("https:/oauth2/callback"))
        assertFalse(RedirectMatcher.isAppRedirect("::"))
    }

    @Test
    fun anOpaqueRedirectIsRefusedBeforeTheLoginStarts() {
        // No link can ever match it: the login would wait for nothing.
        assertFalse(RedirectMatcher.isAppRedirect("books.neon.app:callback"))
        assertFalse(RedirectMatcher.isAppRedirect("books.neon.app:opaque?x=1"))
        assertFalse(RedirectMatcher.matches("books.neon.app:callback", "books.neon.app:callback"))
    }

    @Test
    fun anAuthorityThatIsNoValidHostMatchesOnlyItself() {
        // java.net.URI keeps such an authority without a host: two of them
        // must not count as the same (null) host.
        val invalid = "books.neon.app://bad_host/oauth2/callback"
        assertTrue(RedirectMatcher.matches(invalid, "$invalid?code=c"))
        assertTrue(RedirectMatcher.matches(invalid, "books.neon.app://BAD_HOST/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(invalid, "books.neon.app://evil_host/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(invalid, "books.neon.app:/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(invalid, "books.neon.app://evil.example/oauth2/callback"))
        // No authority matches only no authority.
        assertFalse(RedirectMatcher.matches(scheme, "books.neon.app://evil.example/oauth2/callback"))
        assertFalse(RedirectMatcher.matches(scheme, "books.neon.app://bad_host/oauth2/callback"))
    }

    @Test
    fun onlyTheStateOfTheLoginEndsIt() {
        val state = "f2Qw-9_aZ"
        assertTrue(RedirectMatcher.matches(appLink, "$appLink?code=c&state=$state", state))
        assertTrue(RedirectMatcher.matches(appLink, "$appLink?error=access_denied&state=$state", state))
        assertTrue(RedirectMatcher.matches(scheme, "$scheme?state=f2Qw%2D9_aZ&code=c", state))
        // A forged redirect to the exact path: ignored, the login waits.
        assertFalse(RedirectMatcher.matches(appLink, "$appLink?code=c&state=other", state))
        assertFalse(RedirectMatcher.matches(appLink, "$appLink?error=access_denied", state))
        assertFalse(RedirectMatcher.matches(appLink, "$appLink?code=c&state=$state&state=x", state))
        assertFalse(RedirectMatcher.matches(appLink, "$appLink?code=c&state=${state}x", state))
        assertFalse(RedirectMatcher.matches(appLink, "$appLink?code=c&state=%zz", state))
        assertFalse(RedirectMatcher.matches(appLink, appLink, state))
        // Without a state to expect (a logout page), the path decides.
        assertTrue(RedirectMatcher.matches(appLink, appLink, null))
    }

    @Test
    fun theStateIsReadFromTheAuthorizationUri() {
        assertEquals(
            "s 1",
            RedirectMatcher.stateOf("https://id.neon.books/auth?client_id=a&state=s%201&nonce=n"),
        )
        assertEquals("s+1", RedirectMatcher.stateOf("https://id.neon.books/auth?state=s%2B1"))
        assertNull(RedirectMatcher.stateOf("https://id.neon.books/logout?id_token_hint=t"))
        assertNull(RedirectMatcher.stateOf("https://id.neon.books/auth?state=a&state=b"))
        assertNull(RedirectMatcher.stateOf("https://id.neon.books/auth?state=%zz"))
        assertNull(RedirectMatcher.stateOf("not a uri at all"))
    }
}
