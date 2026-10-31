package dev.farumazula.spring_boot_starter_flutter_security

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
 * The Android side of spring_boot_starter_flutter_security: the secret store
 * (`spring_boot_starter_flutter_security/secret_store`) on the Android Keystore,
 * the DPoP key (`spring_boot_starter_flutter_security/dpop_key`) in the Android
 * Keystore, and the login window
 * (`spring_boot_starter_flutter_security/authorization_window`) on Custom Tabs.
 */
class SpringBootStarterFlutterSecurityPlugin : FlutterPlugin, ActivityAware {
    private var secretStoreChannel: MethodChannel? = null
    private var windowChannel: MethodChannel? = null
    private var dPoPKeyChannel: MethodChannel? = null
    private var dPoPKey: KeystoreDPoPKey? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var secretStore: KeystoreSecretStore? = null
    private var executor: ExecutorService? = null
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        // The Keystore and the preferences file are slow: one thread off
        // the UI, in order.
        executor = Executors.newSingleThreadExecutor()
        secretStoreChannel =
            MethodChannel(binding.binaryMessenger, "spring_boot_starter_flutter_security/secret_store").apply {
                setMethodCallHandler(::onSecretStoreCall)
            }
        windowChannel =
            MethodChannel(binding.binaryMessenger, "spring_boot_starter_flutter_security/authorization_window").apply {
                setMethodCallHandler(::onWindowCall)
            }
        dPoPKeyChannel =
            MethodChannel(binding.binaryMessenger, "spring_boot_starter_flutter_security/dpop_key").apply {
                setMethodCallHandler(::onDPoPKeyCall)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // A login of this engine has nobody left to answer; the next
        // engine must not find it running.
        AuthorizationFlow.detach(this)
        secretStoreChannel?.setMethodCallHandler(null)
        windowChannel?.setMethodCallHandler(null)
        dPoPKeyChannel?.setMethodCallHandler(null)
        secretStoreChannel = null
        windowChannel = null
        dPoPKeyChannel = null
        dPoPKey = null
        executor?.shutdown()
        executor = null
        secretStore = null
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

    private fun onSecretStoreCall(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        if (method !in setOf("read", "write", "delete", "keys", "deleteAll")) {
            result.notImplemented()
            return
        }
        val key = call.argument<String>("key")
        if (method in setOf("read", "write", "delete") && key.isNullOrEmpty()) {
            result.error("keystore", "a key is required", null)
            return
        }
        val value = call.argument<String>("value")
        if (method == "write" && value == null) {
            result.error("keystore", "a value is required", null)
            return
        }
        val appContext = context ?: return result.error("keystore", "the plugin is detached", null)
        val store = secretStore ?: KeystoreSecretStore(appContext).also { secretStore = it }
        val work = executor ?: return result.error("keystore", "the plugin is detached", null)
        work.execute {
            try {
                val answer: Any? =
                    when (method) {
                        "read" -> store.read(key!!)
                        "write" -> {
                            store.write(key!!, value!!)
                            null
                        }
                        "delete" -> {
                            store.delete(key!!)
                            null
                        }
                        "keys" -> store.keys()
                        else -> {
                            store.deleteAll()
                            null
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

    // Never puts key material into an error or a log: the messages name
    // the failure only.
    private fun onDPoPKeyCall(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        if (method !in setOf("dpopPublicJwk", "dpopSign", "dpopDelete")) {
            result.notImplemented()
            return
        }
        val data = call.argument<ByteArray>("data")
        if (method == "dpopSign" && data == null) {
            result.error("dpop_key", "data is required", null)
            return
        }
        val appContext = context ?: return result.error("dpop_key", "the plugin is detached", null)
        val key = dPoPKey ?: KeystoreDPoPKey(appContext).also { dPoPKey = it }
        val work = executor ?: return result.error("dpop_key", "the plugin is detached", null)
        work.execute {
            try {
                val answer: Any? =
                    when (method) {
                        "dpopPublicJwk" -> {
                            val (encoded, storage) = key.publicKey()
                            mapOf("publicKey" to encoded, "storage" to storage)
                        }
                        "dpopSign" -> key.sign(data!!)
                        else -> {
                            key.delete()
                            null
                        }
                    }
                mainThread.post { result.success(answer) }
            } catch (e: DPoPKeyException) {
                mainThread.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                val message = "${e.javaClass.simpleName}: ${e.message}"
                mainThread.post { result.error("dpop_key", message, null) }
            }
        }
    }

    private fun onWindowCall(call: MethodCall, result: MethodChannel.Result) {
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
        // The first login of the engine's root isolate: a login still
        // running for this engine belongs to the isolate a hot restart
        // replaced (a background isolate never sends it).
        val replaceStale = call.argument<Boolean>("replaceStale") ?: false
        AuthorizationFlow.start(current, url, redirectUri, result, owner = this, replaceStale = replaceStale)
    }
}
