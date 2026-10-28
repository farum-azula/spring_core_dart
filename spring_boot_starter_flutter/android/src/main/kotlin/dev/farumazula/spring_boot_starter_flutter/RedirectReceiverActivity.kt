package dev.farumazula.spring_boot_starter_flutter

import android.app.Activity
import android.os.Bundle

/**
 * Receives the provider's redirect to the app and hands it to
 * [AuthorizationManagementActivity], which closes the Custom Tab and
 * answers the login.
 *
 * The plugin's manifest declares it without an intent filter, so apps
 * that never log in are not affected. An app that logs in declares it
 * again in its own AndroidManifest.xml, exported, with an intent filter
 * for its redirect scheme:
 *
 * ```xml
 * <activity
 *     android:name="dev.farumazula.spring_boot_starter_flutter.RedirectReceiverActivity"
 *     android:exported="true">
 *     <intent-filter>
 *         <action android:name="android.intent.action.VIEW" />
 *         <category android:name="android.intent.category.DEFAULT" />
 *         <category android:name="android.intent.category.BROWSABLE" />
 *         <data android:scheme="neonbooks" />
 *     </intent-filter>
 * </activity>
 * ```
 */
class RedirectReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(AuthorizationManagementActivity.responseIntent(this, intent.data))
        finish()
    }
}
