package dev.farumazula.spring_boot_starter_flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * The login that runs: at most one, answered once. Used on the main
 * thread only (method calls and activity callbacks).
 */
internal object AuthorizationFlow {
    private var pending: MethodChannel.Result? = null

    fun start(activity: Activity, url: String, redirectUri: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("in_progress", "a login is already running", null)
            return
        }
        val redirect = Uri.parse(redirectUri)
        if (!redirectActivityDeclared(activity, redirect)) {
            result.error(
                "redirect_not_configured",
                "No activity of this app receives the redirect $redirectUri. Declare " +
                    "${RedirectReceiverActivity::class.java.name} in android/app/src/main/" +
                    "AndroidManifest.xml, exported, with an intent filter (VIEW, DEFAULT, " +
                    "BROWSABLE) for the scheme \"${redirect.scheme}\" (see the README of " +
                    "spring_boot_starter_flutter, \"Login and tokens\").",
                null,
            )
            return
        }
        pending = result
        try {
            activity.startActivity(AuthorizationManagementActivity.startIntent(activity, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            fail("failed", "the login activity could not start: ${e.message}")
        }
    }

    fun complete(redirect: Uri) {
        pending?.success(redirect.toString())
        pending = null
    }

    fun cancel() {
        pending?.error("cancelled", "the user closed the login page", null)
        pending = null
    }

    fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
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
