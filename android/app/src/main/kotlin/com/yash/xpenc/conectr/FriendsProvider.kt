package com.yash.xpenc.conectr

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import java.security.MessageDigest

/**
 * Shares the friends list with XPENC, so a person there can be linked to a
 * Connector friend. One call — `call("friends")` — answering with the JSON
 * the Flutter side last published (`friends_cache.dart`), or null if it
 * never has. Nothing else is readable, and nothing is writable.
 *
 * Answers only XPENC: the caller must be `com.yash.xpenc`, signed by one of
 * [XPENC_CERTS]. A debuggable Connector build skips the certificate check,
 * so it works with a locally built XPENC.
 */
class FriendsProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        if (method != "friends") return null
        val context = context ?: return null
        if (!callerIsXpenc(context)) throw SecurityException("Only XPENC may read this.")
        return Bundle().apply { putString("json", prefs(context).getString(KEY_JSON, null)) }
    }

    private fun callerIsXpenc(context: Context): Boolean {
        if (callingPackage != XPENC_PACKAGE) return false
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) return true
        return certDigests(context.packageManager, XPENC_PACKAGE).any { it in XPENC_CERTS }
    }

    // Read-only, and only through call().
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    companion object {
        private const val XPENC_PACKAGE = "com.yash.xpenc"
        private const val AUTHORITY = "com.yash.xpenc.conectr.friends"
        private const val PREFS = "xpenc_friends_cache"
        private const val KEY_JSON = "json"

        /**
         * SHA-256 of each certificate XPENC is signed with — read off the
         * published APKs with `apksigner verify --print-certs`:
         * GitHub Releases (Yash's key) and F-Droid (F-Droid's key for XPENC).
         * TODO: add the Play build's — Play Console → App integrity → App
         * signing key certificate — until then, XPENC from Play is refused.
         */
        private val XPENC_CERTS = setOf(
            "d4b3388c8d1b283837d56a18e5c163bad2e446b834819f285f88be91bfb29758",
            "468837a82df775b5974a50d20773a1b3b19adbd0657a794c9f512ed43ce6dce6",
        )

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Stores [json] for XPENC and tells anyone watching that it changed. */
        fun publish(context: Context, json: String) {
            prefs(context).edit().putString(KEY_JSON, json).apply()
            context.contentResolver.notifyChange(Uri.parse("content://$AUTHORITY"), null)
        }

        private fun certDigests(pm: PackageManager, pkg: String): List<String> {
            val signatures: Array<Signature>? = try {
                signaturesOf(pm, pkg)
            } catch (e: PackageManager.NameNotFoundException) {
                null
            }
            if (signatures == null) return emptyList()
            val sha256 = MessageDigest.getInstance("SHA-256")
            return signatures.map { signature ->
                sha256.digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
            }
        }

        private fun signaturesOf(pm: PackageManager, pkg: String): Array<Signature>? {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo ?: return null
                return if (info.hasMultipleSigners()) {
                    info.apkContentsSigners
                } else {
                    info.signingCertificateHistory
                }
            }
            @Suppress("DEPRECATION")
            return pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures
        }
    }
}
