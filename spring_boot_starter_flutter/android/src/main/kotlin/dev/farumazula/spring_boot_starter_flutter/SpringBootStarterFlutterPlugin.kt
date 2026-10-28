package dev.farumazula.spring_boot_starter_flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Android side of spring_boot_starter_flutter: the token store
 * (`spring_boot_starter_flutter/token_store`) on the Android Keystore and
 * the login browser (`spring_boot_starter_flutter/authorization_browser`)
 * on Custom Tabs.
 */
class SpringBootStarterFlutterPlugin : FlutterPlugin, ActivityAware {
    private var tokenStoreChannel: MethodChannel? = null
    private var browserChannel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var tokenStore: KeystoreTokenStore? = null
    private var executor: ExecutorService? = null
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        // The Keystore and the preferences file are slow: one thread off
        // the UI, in order.
        executor = Executors.newSingleThreadExecutor()
        tokenStoreChannel =
            MethodChannel(binding.binaryMessenger, "spring_boot_starter_flutter/token_store").apply {
                setMethodCallHandler(::onTokenStoreCall)
            }
        browserChannel =
            MethodChannel(binding.binaryMessenger, "spring_boot_starter_flutter/authorization_browser").apply {
                setMethodCallHandler(::onBrowserCall)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        tokenStoreChannel?.setMethodCallHandler(null)
        browserChannel?.setMethodCallHandler(null)
        tokenStoreChannel = null
        browserChannel = null
        executor?.shutdown()
        executor = null
        tokenStore = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun onTokenStoreCall(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key.isNullOrEmpty()) {
            result.error("keystore", "a key is required", null)
            return
        }
        val value = call.argument<String>("value")
        if (call.method == "write" && value == null) {
            result.error("keystore", "a value is required", null)
            return
        }
        val appContext = context ?: return result.error("keystore", "the plugin is detached", null)
        val store = tokenStore ?: KeystoreTokenStore(appContext).also { tokenStore = it }
        val work = executor ?: return result.error("keystore", "the plugin is detached", null)
        work.execute {
            try {
                val answer: String? =
                    when (call.method) {
                        "read" -> store.read(key)
                        "write" -> {
                            store.write(key, value!!)
                            null
                        }
                        "delete" -> {
                            store.delete(key)
                            null
                        }
                        else -> {
                            mainThread.post { result.notImplemented() }
                            return@execute
                        }
                    }
                mainThread.post { result.success(answer) }
            } catch (e: Exception) {
                // The message names the failure, never a value.
                val message = "${e.javaClass.simpleName}: ${e.message}"
                mainThread.post { result.error("keystore", message, null) }
            }
        }
    }

    private fun onBrowserCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "authorize") {
            result.notImplemented()
            return
        }
        val url = call.argument<String>("url")
        val redirectUri = call.argument<String>("redirectUri")
        if (url == null || redirectUri == null) {
            result.error("failed", "url and redirectUri are required", null)
            return
        }
        val current = activity
        if (current == null) {
            result.error("no_activity", "the app has no activity to start the login from", null)
            return
        }
        AuthorizationFlow.start(current, url, redirectUri, result)
    }
}
