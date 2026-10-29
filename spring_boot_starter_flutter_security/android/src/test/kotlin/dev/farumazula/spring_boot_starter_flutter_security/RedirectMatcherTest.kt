package dev.farumazula.spring_boot_starter_flutter_security

import org.junit.Assert.assertFalse
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
}
