package dev.farumazula.spring_boot_starter_flutter

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
 * without one (back button, closing the tab: a cancelled login).
 */
class AuthorizationManagementActivity : Activity() {
    private var browserStarted = false
    private var authorizationUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val state = savedInstanceState ?: intent.extras
        browserStarted = savedInstanceState?.getBoolean(KEY_BROWSER_STARTED) ?: false
        authorizationUri = state?.getString(KEY_AUTHORIZATION_URI)?.let(Uri::parse)
        if (authorizationUri == null) {
            // A redirect without a login of this process: nothing waits.
            finish()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        if (isFinishing) return
        if (!browserStarted) {
            browserStarted = true
            try {
                // Without a browser that supports Custom Tabs, the default
                // browser opens the page.
                CustomTabsIntent.Builder().build().launchUrl(this, authorizationUri!!)
            } catch (e: ActivityNotFoundException) {
                AuthorizationFlow.fail("no_browser", "no browser can open the login page")
                finish()
            }
            return
        }
        val response = intent.data
        if (response != null) AuthorizationFlow.complete(response) else AuthorizationFlow.cancel()
        finish()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_BROWSER_STARTED, browserStarted)
        outState.putString(KEY_AUTHORIZATION_URI, authorizationUri?.toString())
    }

    internal companion object {
        private const val KEY_BROWSER_STARTED = "browserStarted"
        private const val KEY_AUTHORIZATION_URI = "authorizationUri"

        fun startIntent(context: Context, authorizationUri: Uri): Intent =
            Intent(context, AuthorizationManagementActivity::class.java)
                .putExtra(KEY_AUTHORIZATION_URI, authorizationUri.toString())

        fun responseIntent(context: Context, response: Uri?): Intent =
            Intent(context, AuthorizationManagementActivity::class.java)
                .setData(response)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
}
