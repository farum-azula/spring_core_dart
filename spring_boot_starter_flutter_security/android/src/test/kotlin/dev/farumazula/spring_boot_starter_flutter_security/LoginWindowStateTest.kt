package dev.farumazula.spring_boot_starter_flutter_security

import dev.farumazula.spring_boot_starter_flutter_security.LoginWindowState.Step
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The logins and their window: only the running login is answered, and
 * a window that takes a new login opens its page instead of answering it.
 */
class LoginWindowStateTest {
    private val redirect = "books.neon.app:/oauth2/callback"

    @Test
    fun onlyTheRunningLoginIsAnsweredOnce() {
        val logins = Logins<String>()
        val first = logins.begin("first", redirect, "s1", owner = null)
        assertEquals("first", logins.end(first))
        // Answered: a second answer (the window destroyed after it) ends nothing.
        assertNull(logins.end(first))

        val second = logins.begin("second", redirect, "s2", owner = null)
        assertNotEquals(first, second)
        // The late answer of the first login's window leaves the second running.
        assertNull(logins.end(first))
        assertEquals(second, logins.running?.id)
        assertEquals("second", logins.end(second))
        assertNull(logins.running)
    }

    @Test
    fun aReplacedLoginsWindowCannotEndTheNewOne() {
        // A hot restart: the first login is replaced (answered for the
        // dead isolate), the second runs.
        val logins = Logins<String>()
        val stale = logins.begin("stale", redirect, "s1", owner = "engine")
        assertEquals("stale", logins.endRunning())
        val fresh = logins.begin("fresh", redirect, "s2", owner = "engine")
        assertNull(logins.end(stale))
        assertEquals(fresh, logins.running?.id)
    }

    @Test
    fun aWindowOpensItsPageThenAnswersWithTheRedirect() {
        val window = LoginWindowState(login = 1, authorizationUri = "https://id/auth?state=s1", browserStarted = false)
        assertEquals(Step.OpenPage("https://id/auth?state=s1"), window.resumed(response = null))
        assertEquals(Step.Complete(1, "$redirect?code=c"), window.resumed("$redirect?code=c"))
        assertTrue(window.answered)
        // Destroyed after its answer: nothing more.
        assertEquals(Step.Wait, window.destroyed(finishing = true))
    }

    @Test
    fun theUserComingBackWithoutARedirectCancels() {
        val window = LoginWindowState(login = 1, authorizationUri = "https://id/auth", browserStarted = false)
        window.resumed(null)
        assertEquals(Step.Cancel(1), window.resumed(null))
    }

    @Test
    fun aNewLoginTakesTheWindowOfAnEarlierOne() {
        // singleTask: the login started after a hot restart reaches the
        // window of the replaced login through onNewIntent. Before the fix
        // the next onResume cancelled the new login.
        val window = LoginWindowState(login = 1, authorizationUri = "https://id/auth?state=s1", browserStarted = false)
        window.resumed(null) // the first page is open
        // The earlier login had no answer from the window: cancelled (a
        // no-op when the flow already replaced it).
        assertEquals(Step.Cancel(1), window.newLogin(2, "https://id/auth?state=s2"))
        assertEquals(2L, window.login)
        // Back to the front: the new page opens, nothing is answered.
        assertEquals(Step.OpenPage("https://id/auth?state=s2"), window.resumed(null))
        assertEquals(Step.Complete(2, "$redirect?code=c2"), window.resumed("$redirect?code=c2"))
    }

    @Test
    fun aNewLoginAfterTheEarlierWasAnsweredCancelsNothing() {
        val window = LoginWindowState(login = 1, authorizationUri = "https://id/auth", browserStarted = false)
        window.resumed(null)
        window.resumed("$redirect?code=c")
        assertEquals(Step.Wait, window.newLogin(2, "https://id/auth?state=s2"))
        assertEquals(Step.OpenPage("https://id/auth?state=s2"), window.resumed(null))
    }

    @Test
    fun destroyedWithoutAnAnswerCancelsItsOwnLogin() {
        val window = LoginWindowState(login = 3, authorizationUri = "https://id/auth", browserStarted = true)
        // A configuration change: made again, answers then.
        assertEquals(Step.Wait, window.destroyed(finishing = false))
        assertEquals(Step.Cancel(3), window.destroyed(finishing = true))
    }

    @Test
    fun theWindowsAnswersReachOnlyItsLogin() {
        // The whole path: login 1's window takes login 2; a late answer
        // for login 1 (its window destroyed late) leaves login 2 running.
        val logins = Logins<String>()
        val first = logins.begin("first", redirect, "s1", owner = "engine")
        val window = LoginWindowState(first, "https://id/auth?state=s1", browserStarted = false)
        window.resumed(null)
        logins.endRunning() // replaced after a hot restart
        val second = logins.begin("second", redirect, "s2", owner = "engine")
        val earlier = window.newLogin(second, "https://id/auth?state=s2") as Step.Cancel
        assertNull(logins.end(earlier.login))
        assertEquals(second, logins.running?.id)
        window.resumed(null)
        val done = window.resumed("$redirect?code=c2&state=s2") as Step.Complete
        assertEquals("second", logins.end(done.login))
    }
}
