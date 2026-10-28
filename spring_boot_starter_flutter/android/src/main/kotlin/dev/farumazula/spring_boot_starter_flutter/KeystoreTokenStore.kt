package dev.farumazula.spring_boot_starter_flutter

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Values sealed with an AES-256-GCM key of the Android Keystore, in a
 * private preferences file of the app.
 *
 * The key is generated inside the Keystore (in the secure hardware where
 * the phone has it) and never leaves it. Each value is stored as
 * base64(iv + ciphertext + tag), with the key's name as associated data,
 * so a value moved to another key does not decrypt. A value that does not
 * decrypt (restored from a backup on another phone, the key lost) is
 * deleted and read as missing. Called on one background thread.
 */
internal class KeystoreTokenStore(context: Context) {
    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    @Synchronized
    fun read(key: String): String? {
        val stored = preferences.getString(key, null) ?: return null
        return try {
            decrypt(key, stored)
        } catch (e: GeneralSecurityException) {
            remove(key)
            null
        } catch (e: IllegalArgumentException) {
            remove(key)
            null
        }
    }

    @Synchronized
    fun write(key: String, value: String) {
        val sealed = encrypt(key, value)
        if (!preferences.edit().putString(key, sealed).commit()) {
            throw IOException("the preferences file could not be written")
        }
    }

    @Synchronized
    fun delete(key: String) = remove(key)

    private fun remove(key: String) {
        if (!preferences.edit().remove(key).commit()) {
            throw IOException("the preferences file could not be written")
        }
    }

    private fun encrypt(key: String, value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        // The Keystore picks a random IV.
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + sealed, Base64.NO_WRAP)
    }

    private fun decrypt(key: String, stored: String): String {
        val bytes = Base64.decode(stored, Base64.NO_WRAP)
        if (bytes.size <= IV_SIZE) throw IllegalArgumentException("too short")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(TAG_BITS, bytes, 0, IV_SIZE),
        )
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val plain = cipher.doFinal(bytes, IV_SIZE, bytes.size - IV_SIZE)
        return String(plain, Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        try {
            (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        } catch (e: UnrecoverableKeyException) {
            // A key the Keystore can no longer use (its values are lost
            // with it): a new one is made.
            keyStore.deleteEntry(KEY_ALIAS)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec
                .Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "dev.farumazula.spring_boot_starter_flutter.token_store"
        const val PREFERENCES = "dev.farumazula.spring_boot_starter_flutter.token_store"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_SIZE = 12
        const val TAG_BITS = 128
    }
}
