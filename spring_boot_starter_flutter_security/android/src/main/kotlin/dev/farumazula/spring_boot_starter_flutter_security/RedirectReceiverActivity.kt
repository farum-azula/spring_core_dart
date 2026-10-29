package dev.farumazula.spring_boot_starter_flutter_security

import android.app.Activity
import android.os.Bundle

/**
 * Receives the provider's redirect to the app and hands it to
 * [AuthorizationManagementActivity], which closes the Custom Tab and
 * answers the login.
 *
 * Only the redirect of the login that runs is handed over (the same
 * scheme, host, port and path as its redirect URI, [AuthorizationFlow.accepts]);
 * any other link that reaches it (another page of the app's site, a stale
 * redirect, a link without a login running) is dropped, and the login in
 * progress goes on.
 *
 * The plugin's manifest declares it without an intent filter, so apps
 * that never log in are not affected. An app that logs in declares it
 * again in its own AndroidManifest.xml, exported, with an intent filter
 * for its redirect scheme:
 *
 * ```xml
 * <activity
 *     android:name="dev.farumazula.spring_boot_starter_flutter_security.RedirectReceiverActivity"
 *     android:exported="true">
 *     <intent-filter>
 *         <action android:name="android.intent.action.VIEW" />
 *         <category android:name="android.intent.category.DEFAULT" />
 *         <category android:name="android.intent.category.BROWSABLE" />
 *         <data android:scheme="neonbooks" />
 *     </intent-filter>
 * </activity>
 * ```
 *
 * or, for an `https` redirect (an App Link, verified by the
 * `/.well-known/assetlinks.json` of its host), for exactly its host and
 * path:
 *
 * ```xml
 * <intent-filter android:autoVerify="true">
 *     <action android:name="android.intent.action.VIEW" />
 *     <category android:name="android.intent.category.DEFAULT" />
 *     <category android:name="android.intent.category.BROWSABLE" />
 *     <data android:scheme="https" />
 *     <data android:host="books.neon.example" />
 *     <data android:path="/oauth2/callback" />
 * </intent-filter>
 * ```
 */
class RedirectReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val link = intent.data
        if (link != null && AuthorizationFlow.accepts(link)) {
            startActivity(AuthorizationManagementActivity.responseIntent(this, link))
        }
        finish()
    }
}
