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
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import org.json.JSONObject

/**
 * What Connector shares with XPENC, on the phone:
 *
 * - `call("friends")`: the friends list the Flutter side last published
 *   (`friends_cache.dart`), so a person can be linked to a Connector friend.
 * - `call("pendingBackup")`: `xpenc/inbox.json` — the pulled backup waiting
 *   for XPENC, and which file this phone's data is built on
 *   (`xpenc_inbox.dart`).
 * - `openFile(…/pending-backup)`: that backup itself.
 * - `call("confirmImport", sha, {at})`: XPENC took it in. Recorded in
 *   `xpenc/imported.json` for the next sync to apply — only for the very
 *   file waiting.
 *
 * Answers only XPENC: the caller must be `com.yash.xpenc`, signed by one of
 * [XPENC_CERTS]. A debuggable Connector build skips the certificate check,
 * so it works with a locally built XPENC.
 */
class XpencProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val context = context ?: return null
        if (method !in METHODS) return null
        if (!callerIsXpenc(context)) throw SecurityException("Only XPENC may read this.")
        return when (method) {
            "friends" -> Bundle().apply {
                putString("json", prefs(context).getString(KEY_JSON, null))
            }
            "pendingBackup" -> Bundle().apply {
                putString("json", inboxFile(context, INBOX).takeIf { it.exists() }?.readText())
            }
            "confirmImport" -> Bundle().apply {
                putBoolean("ok", confirmImport(context, arg, extras?.getLong("at") ?: 0L))
            }
            else -> null
        }
    }

    /** The pulled backup, read-only, for XPENC alone. */
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val context = context ?: return null
        if (uri.path != "/pending-backup" || mode != "r") throw FileNotFoundException(uri.toString())
        if (!callerIsXpenc(context)) throw SecurityException("Only XPENC may read this.")
        val file = inboxFile(context, PENDING)
        if (!file.exists()) throw FileNotFoundException("No backup waiting.")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    /** Only for the backup actually waiting; the next sync applies it. */
    private fun confirmImport(context: Context, sha: String?, at: Long): Boolean {
        if (sha.isNullOrEmpty() || at <= 0L) return false
        val inbox = inboxFile(context, INBOX).takeIf { it.exists() } ?: return false
        val pending = JSONObject(inbox.readText()).optJSONObject("pending") ?: return false
        if (pending.optString("sha") != sha) return false
        val record = inboxFile(context, IMPORTED)
        val temp = File(record.path + ".tmp")
        temp.writeText(JSONObject().put("sha", sha).put("at", at).toString())
        if (!temp.renameTo(record)) {
            record.delete()
            temp.renameTo(record)
        }
        return true
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

    override fun getType(uri: Uri): String? =
        if (uri.path == "/pending-backup") "application/json" else null

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
        private val METHODS = setOf("friends", "pendingBackup", "confirmImport")

        // Written by xpenc_inbox.dart, in getApplicationSupportDirectory()
        // — filesDir on Android.
        private const val INBOX = "inbox.json"
        private const val PENDING = "pending_backup.json"
        private const val IMPORTED = "imported.json"

        private fun inboxFile(context: Context, name: String) =
            File(File(context.filesDir, "xpenc"), name)
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
