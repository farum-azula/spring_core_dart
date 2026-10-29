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
 * It remembers the redirect URI of the login, so [RedirectReceiverActivity]
 * hands over only that redirect ([accepts]): an `https` redirect (an App
 * Link) shares its host with the app's site, whose other links must not
 * complete or cancel a login.
 */
internal object AuthorizationFlow {
    private var pending: MethodChannel.Result? = null
    private var pendingRedirect: String? = null

    fun start(activity: Activity, url: String, redirectUri: String, result: MethodChannel.Result) {
        if (pending != null) {
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
        pending = result
        pendingRedirect = redirectUri
        try {
            activity.startActivity(AuthorizationManagementActivity.startIntent(activity, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            fail("failed", "the login activity could not start: ${e.message}")
        }
    }

    /** Whether [link] is the redirect of the login that runs. */
    fun accepts(link: Uri): Boolean {
        val expected = pendingRedirect ?: return false
        return pending != null && RedirectMatcher.matches(expected, link.toString())
    }

    fun complete(redirect: Uri) {
        pending?.success(redirect.toString())
        clear()
    }

    fun cancel() {
        pending?.error("cancelled", "the user closed the login page", null)
        clear()
    }

    fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        clear()
    }

    private fun clear() {
        pending = null
        pendingRedirect = null
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
