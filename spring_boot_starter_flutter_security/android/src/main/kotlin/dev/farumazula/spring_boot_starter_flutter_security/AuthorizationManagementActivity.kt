package dev.farumazula.spring_boot_starter_flutter_security

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.browser.customtabs.CustomTabsIntent

/**
 * Opens the login page in a Custom Tab and waits, invisible, for the
 * result, as AppAuth's management activity does.
 *
 * Started first by the plugin: it opens the page. It comes back to the
 * front in one of two ways: [RedirectReceiverActivity] brings it the
 * provider's redirect (a finished login), or the user returns to the app
 * without one (back button, closing the tab: a cancelled login). When it
 * is destroyed without either (a `singleTask` main activity or a
 * `CLEAR_TOP` intent clears it from the task, without `onResume`), the
 * login is answered as cancelled in [onDestroy], so it never waits
 * forever.
 *
 * It is `singleTask`: a new login while this window still exists (its
 * login replaced after a hot restart, or dropped with its engine) comes
 * through [onNewIntent], and the window then belongs to the new login
 * and opens its page. Every answer names the window's login
 * ([LoginWindowState.login]); [AuthorizationFlow] ignores an answer for a
 * login that no longer runs.
 */
class AuthorizationManagementActivity : Activity() {
    private var window = LoginWindowState(Logins.NO_LOGIN, null, false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val state = savedInstanceState ?: intent.extras
        window =
            LoginWindowState(
                login = state?.getLong(KEY_LOGIN, Logins.NO_LOGIN) ?: Logins.NO_LOGIN,
                authorizationUri = state?.getString(KEY_AUTHORIZATION_URI),
                browserStarted = savedInstanceState?.getBoolean(KEY_BROWSER_STARTED) ?: false,
            )
        if (window.authorizationUri == null) {
            // The redirect reached a new instance: the one that opened the
            // page is gone. The redirect of the login that runs answers
            // it; anything else cancels the login the redirect was handed
            // over for (nothing when it no longer runs).
            val response = intent.data
            if (response != null && AuthorizationFlow.accepts(response)) {
                // The page was opened by the instance that is gone.
                window.browserStarted = true
                perform(window.resumed(response.toString()))
            } else {
                perform(window.destroyed(finishing = true))
            }
            // Never resumed: onDestroy follows at once.
            finish()
        }
    }

    override fun onDestroy() {
        // Destroyed for good without an answer: the user cannot come back
        // to this window, so the login must not wait for it. Not for a
        // configuration change (isFinishing is false; the activity is
        // made again from its saved state and answers then).
        perform(window.destroyed(isFinishing))
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = intent.getStringExtra(KEY_AUTHORIZATION_URI) ?: return
        // A new login while this window of an earlier one still exists:
        // the window takes it, and opens its page at the next onResume.
        perform(window.newLogin(intent.getLongExtra(KEY_LOGIN, Logins.NO_LOGIN), uri))
    }

    override fun onResume() {
        super.onResume()
        if (isFinishing) return
        perform(window.resumed(intent.data?.toString()))
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_BROWSER_STARTED, window.browserStarted)
        outState.putString(KEY_AUTHORIZATION_URI, window.authorizationUri)
        outState.putLong(KEY_LOGIN, window.login)
    }

    private fun perform(step: LoginWindowState.Step) {
        when (step) {
            is LoginWindowState.Step.OpenPage ->
                try {
                    // Without a browser that supports Custom Tabs, the
                    // default browser opens the page.
                    CustomTabsIntent.Builder().build().launchUrl(this, Uri.parse(step.uri))
                } catch (e: ActivityNotFoundException) {
                    window.failedToOpen()
                    AuthorizationFlow.fail(window.login, "no_browser", "no browser can open the login page")
                    finish()
                }
            is LoginWindowState.Step.Complete -> {
                AuthorizationFlow.complete(step.login, Uri.parse(step.response))
                finish()
            }
            is LoginWindowState.Step.Cancel -> {
                AuthorizationFlow.cancel(step.login)
                // The earlier login of a window that took a new one: the
                // window stays for the new login.
                if (step.login == window.login && !isFinishing) finish()
            }
            LoginWindowState.Step.Wait -> Unit
        }
    }

    internal companion object {
        private const val KEY_BROWSER_STARTED = "browserStarted"
        private const val KEY_AUTHORIZATION_URI = "authorizationUri"
        private const val KEY_LOGIN = "login"

        fun startIntent(context: Context, authorizationUri: Uri, login: Long): Intent =
            Intent(context, AuthorizationManagementActivity::class.java)
                .putExtra(KEY_AUTHORIZATION_URI, authorizationUri.toString())
                .putExtra(KEY_LOGIN, login)

        fun responseIntent(context: Context, response: Uri?, login: Long): Intent =
            Intent(context, AuthorizationManagementActivity::class.java)
                .setData(response)
                .putExtra(KEY_LOGIN, login)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
}
