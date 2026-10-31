package dev.farumazula.spring_boot_starter_flutter_security

/**
 * The logins of [AuthorizationFlow]: at most one runs, each has an id,
 * and only the running one can be answered, once.
 *
 * The id goes with the login to its window ([AuthorizationManagementActivity])
 * and back with every answer the window gives: an answer of a window that
 * belongs to an earlier login (replaced after a hot restart, dropped when
 * its engine went away, already answered) ends nothing, so it can never
 * cancel or complete the login that runs now.
 *
 * Pure JVM code, so the unit tests run without Android; [R] is the
 * answer's channel (`MethodChannel.Result` in the plugin).
 */
internal class Logins<R : Any> {
    /** A running login: its [id], whom to answer, what ends it, who started it. */
    class Running<R>(
        val id: Long,
        val result: R,
        val redirectUri: String,
        val state: String?,
        val owner: Any?,
    )

    private var lastId = NO_LOGIN

    /** The login that runs, or `null`. */
    var running: Running<R>? = null
        private set

    /** Starts a login and returns its id; one must not be running. */
    fun begin(result: R, redirectUri: String, state: String?, owner: Any?): Long {
        check(running == null) { "a login is already running" }
        val id = ++lastId
        running = Running(id, result, redirectUri, state, owner)
        return id
    }

    /**
     * Ends the login [id] and returns whom to answer; `null` when [id] is
     * not the running login (an earlier one, already answered or
     * replaced): then nothing changes.
     */
    fun end(id: Long): R? {
        val current = running ?: return null
        if (current.id != id) return null
        running = null
        return current.result
    }

    /** Ends the running login, whichever it is, and returns whom to answer. */
    fun endRunning(): R? = running?.let { end(it.id) }

    companion object {
        /** No login: the id of a window that has none. */
        const val NO_LOGIN = 0L
    }
}

/**
 * What [AuthorizationManagementActivity] does for its login, kept apart
 * from the activity so the unit tests run without Android.
 *
 * The activity is `singleTask`: a login started while the window of an
 * earlier one still exists reaches that same activity through
 * `onNewIntent` ([newLogin]). It then belongs to the new login: it opens
 * the new page at the next `onResume` instead of answering, and its
 * earlier login, if not answered yet, is answered as cancelled.
 */
internal class LoginWindowState(
    /** The id of the window's login ([Logins.NO_LOGIN]: none). */
    var login: Long,
    /** The page to open, or `null` for a window that only carries a redirect. */
    var authorizationUri: String?,
    /** Whether the page was opened (the browser comes back with the answer). */
    var browserStarted: Boolean,
) {
    /** Whether the window answered its login. */
    var answered = false
        private set

    /** What the activity does next. */
    sealed interface Step {
        /** Opens [uri] in the browser. */
        data class OpenPage(val uri: String) : Step

        /** Answers the login [login] with the redirect [response]. */
        data class Complete(val login: Long, val response: String) : Step

        /** Answers the login [login] as cancelled. */
        data class Cancel(val login: Long) : Step

        /** Nothing. */
        data object Wait : Step
    }

    /**
     * A new login ([login], whose page is [uri]) took over this window;
     * returns the answer of the earlier login when it had none yet.
     */
    fun newLogin(login: Long, uri: String): Step {
        val earlier = if (!answered && this.login != login) Step.Cancel(this.login) else Step.Wait
        this.login = login
        authorizationUri = uri
        browserStarted = false
        answered = false
        return earlier
    }

    /**
     * The window came to the front: the first time it opens the page; after
     * that the browser came back, with the redirect ([response]) or without
     * (the user closed the page).
     */
    fun resumed(response: String?): Step {
        if (!browserStarted) {
            val uri = authorizationUri ?: return answer(Step.Cancel(login))
            browserStarted = true
            return Step.OpenPage(uri)
        }
        return answer(if (response != null) Step.Complete(login, response) else Step.Cancel(login))
    }

    /**
     * The window is destroyed; [finishing] is false for a configuration
     * change (it comes back from its saved state and answers then).
     */
    fun destroyed(finishing: Boolean): Step =
        if (finishing && !answered) answer(Step.Cancel(login)) else Step.Wait

    /** The browser could not open the page: the login fails. */
    fun failedToOpen(): Step = answer(Step.Wait)

    private fun answer(step: Step): Step {
        answered = true
        return step
    }
}
