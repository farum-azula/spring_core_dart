package dev.farumazula.spring_boot_starter_flutter_security

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * The login that runs: at most one, answered once. Used on the main
 * thread only (method calls and activity callbacks).
 *
 * It remembers the redirect URI and the `state` of the login, so
 * [RedirectReceiverActivity] hands over only that redirect ([accepts]): an
 * `https` redirect (an App Link) shares its host with the app's site,
 * whose other links must not complete or cancel a login, and a link with
 * the exact path but another `state` must not end it either.
 *
 * Each login has an id ([Logins]), which its window
 * ([AuthorizationManagementActivity]) carries and gives back with its
 * answer: only the running login can be answered, so the window of an
 * earlier login (replaced, dropped, its activity destroyed late) never
 * ends the one that runs now.
 *
 * Every login is answered: by the redirect, by the user coming back
 * without one, or, when its window is destroyed without either (a
 * `singleTask` main activity or a `CLEAR_TOP` intent clears it), by
 * [AuthorizationManagementActivity.onDestroy] as cancelled. A login of an
 * engine that went away ([detach]) or of a Dart isolate that a hot
 * restart replaced ([start] with `replaceStale`) is dropped. A login
 * whose process the system ended while the browser was open is lost
 * with the process: the user comes back to the app logged out (the code
 * that comes back is useless without the PKCE verifier, which was in the
 * ended process) and logs in again.
 */
internal object AuthorizationFlow {
    private val logins = Logins<MethodChannel.Result>()

    /**
     * Starts the login of [url] for [owner] (the plugin of one engine).
     * With [replaceStale] (the first login of the root isolate), a login
     * that [owner] still has running belongs to an isolate a hot restart
     * replaced: it is answered as cancelled (nobody hears it), and the new
     * login runs in its place. Its window, if still open, takes the new
     * login (`singleTask`: the same activity gets the new page through
     * `onNewIntent`) and opens the new page.
     */
    fun start(
        activity: Activity,
        url: String,
        redirectUri: String,
        result: MethodChannel.Result,
        owner: Any? = null,
        replaceStale: Boolean = false,
    ) {
        val stale = logins.running
        if (stale != null && replaceStale && owner != null && stale.owner === owner) {
            cancel(stale.id)
        }
        if (logins.running != null) {
            result.error("in_progress", "a login is already running", null)
            return
        }
        if (!RedirectMatcher.isAppRedirect(redirectUri)) {
            result.error(
                "unsupported",
                "The redirect URI $redirectUri cannot return to the app: use an https " +
                    "redirect verified as an App Link, or the app's own scheme",
                null,
            )
            return
        }
        val redirect = Uri.parse(redirectUri)
        if (!redirectActivityDeclared(activity, redirect)) {
            result.error(
                "redirect_not_configured",
                "No activity of this app receives the redirect $redirectUri. Declare " +
                    "${RedirectReceiverActivity::class.java.name} in android/app/src/main/" +
                    "AndroidManifest.xml, exported, with an intent filter (VIEW, DEFAULT, " +
                    "BROWSABLE) for the scheme \"${redirect.scheme}\"" +
                    (if (redirect.scheme == "https") {
                        ", the host \"${redirect.host}\" and the path \"${redirect.path}\", " +
                            "with android:autoVerify=\"true\""
                    } else {
                        ""
                    }) +
                    " (see the README of spring_boot_starter_flutter_security, \"Login and tokens\").",
                null,
            )
            return
        }
        if (redirect.scheme == "https" && !appLinkVerified(activity, redirect.host!!)) {
            result.error(
                "redirect_not_verified",
                "The https redirect host ${redirect.host} is not verified for this app: " +
                    "Android opens its links in the browser, never in the app. Serve " +
                    "https://${redirect.host}/.well-known/assetlinks.json with the app's " +
                    "package name and signing certificate (see the README of " +
                    "spring_boot_starter_flutter_security, \"Android App Links\").",
                null,
            )
            return
        }
        val login = logins.begin(result, redirectUri, RedirectMatcher.stateOf(url), owner)
        try {
            activity.startActivity(AuthorizationManagementActivity.startIntent(activity, Uri.parse(url), login))
        } catch (e: ActivityNotFoundException) {
            fail(login, "failed", "the login activity could not start: ${e.message}")
        }
    }

    /** Whether [link] is the redirect of the login that runs. */
    fun accepts(link: Uri): Boolean {
        val login = logins.running ?: return false
        return RedirectMatcher.matches(login.redirectUri, link.toString(), login.state)
    }

    /** The id of the login that runs, or [Logins.NO_LOGIN]. */
    val runningLogin: Long
        get() = logins.running?.id ?: Logins.NO_LOGIN

    /** Whether a login waits for its answer. */
    val running: Boolean
        get() = logins.running != null

    /**
     * Drops the login of [owner], whose engine went away: its answer has
     * nobody to reach, and the next engine must be able to log in.
     */
    fun detach(owner: Any) {
        val login = logins.running ?: return
        if (login.owner === owner) logins.end(login.id)
    }

    /** Completes the login [login] with [redirect]; nothing when it does not run. */
    fun complete(login: Long, redirect: Uri) {
        logins.end(login)?.success(redirect.toString())
    }

    /** Answers the login [login] as cancelled; nothing when it does not run. */
    fun cancel(login: Long) {
        logins.end(login)?.error("cancelled", "the user closed the login page", null)
    }

    /** Fails the login [login]; nothing when it does not run. */
    fun fail(login: Long, code: String, message: String) {
        logins.end(login)?.error(code, message, null)
    }

    // Android 12+ opens an https link in an app only when the app's
    // domain verified it (assetlinks.json) or the user chose the app for
    // it in the settings; before Android 12 there is no way to ask.
    private fun appLinkVerified(context: Context, host: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = context.getSystemService(DomainVerificationManager::class.java) ?: return true
        val state =
            try {
                manager.getDomainVerificationUserState(context.packageName)
            } catch (e: Exception) {
                null
            } ?: return true
        val hostState = state.hostToStateMap[host] ?: return false
        return hostState == DomainVerificationUserState.DOMAIN_STATE_VERIFIED ||
            hostState == DomainVerificationUserState.DOMAIN_STATE_SELECTED
    }

    private fun redirectActivityDeclared(context: Context, redirect: Uri): Boolean {
        val intent =
            Intent(Intent.ACTION_VIEW, redirect)
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setPackage(context.packageName)
        val matches =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.queryIntentActivities(intent, 0)
            }
        return matches.any { it.activityInfo?.name == RedirectReceiverActivity::class.java.name }
    }
}
