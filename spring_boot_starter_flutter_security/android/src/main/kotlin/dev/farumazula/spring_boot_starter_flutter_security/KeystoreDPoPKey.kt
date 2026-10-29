package dev.farumazula.spring_boot_starter_flutter_security

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.UnrecoverableKeyException
import java.security.spec.ECGenParameterSpec

/** A DPoP key call that failed; [code] is `dpop_key` or `no_key`. */
internal class DPoPKeyException(val code: String, message: String) : Exception(message)

/**
 * The app's DPoP key (RFC 9449): an EC P-256 key pair of the Android
 * Keystore that signs proofs with SHA256withECDSA. The private key is
 * made inside the Keystore and never leaves it: in the StrongBox chip
 * when the phone has one, else in the trusted execution environment (or
 * the Keystore's software on devices without secure hardware).
 *
 * The key is not in backups: after a restore on another phone, or when
 * the Keystore is wiped, there is none, and the next public key call
 * makes a new one. Called on one background thread.
 */
internal class KeystoreDPoPKey(private val context: Context) {
    /**
     * The public key as its X.509 encoding (SubjectPublicKeyInfo) and
     * where the private key is (`strongBox`, `trustedEnvironment` or
     * `software`); makes the key when there is none.
     */
    @Synchronized
    fun publicKey(): Pair<ByteArray, String> {
        val keyStore = keyStore()
        val privateKey = existingKey(keyStore) ?: run {
            create()
            existingKey(keyStore) ?: throw DPoPKeyException("dpop_key", "the DPoP key was not stored")
        }
        val certificate =
            keyStore.getCertificate(KEY_ALIAS)
                ?: throw DPoPKeyException("dpop_key", "the DPoP key has no public key")
        return Pair(certificate.publicKey.encoded, storageOf(privateKey))
    }

    /**
     * The DER signature of [data]; never makes a key (the Dart side put
     * the old public key into the proof's header): fails with `no_key`.
     */
    @Synchronized
    fun sign(data: ByteArray): ByteArray {
        val privateKey =
            existingKey(keyStore()) ?: throw DPoPKeyException("no_key", "there is no DPoP key")
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(data)
            sign()
        }
    }

    /** Removes the key; nothing happens when there is none. */
    @Synchronized
    fun delete() {
        val keyStore = keyStore()
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun existingKey(keyStore: KeyStore): PrivateKey? =
        try {
            keyStore.getKey(KEY_ALIAS, null) as? PrivateKey
        } catch (e: UnrecoverableKeyException) {
            // A key the Keystore can no longer use: gone, a new one is made.
            keyStore.deleteEntry(KEY_ALIAS)
            null
        }

    private fun create() {
        val strongBox =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        if (strongBox) {
            try {
                generate(strongBox = true)
                return
            } catch (e: StrongBoxUnavailableException) {
                // Announced but not usable for this key: the TEE instead.
            }
        }
        generate(strongBox = false)
    }

    private fun generate(strongBox: Boolean) {
        val spec =
            KeyGenParameterSpec
                .Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .apply {
                    if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        setIsStrongBoxBacked(true)
                    }
                }.build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE).run {
            initialize(spec)
            generateKeyPair()
        }
    }

    private fun storageOf(privateKey: PrivateKey): String =
        try {
            val info =
                KeyFactory
                    .getInstance(privateKey.algorithm, ANDROID_KEYSTORE)
                    .getKeySpec(privateKey, KeyInfo::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                when (info.securityLevel) {
                    KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongBox"
                    KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trustedEnvironment"
                    else -> "software"
                }
            } else {
                @Suppress("DEPRECATION")
                if (info.isInsideSecureHardware) "trustedEnvironment" else "software"
            }
        } catch (e: Exception) {
            "software"
        }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "dev.farumazula.spring_boot_starter_flutter_security.dpop_key"
    }
}
