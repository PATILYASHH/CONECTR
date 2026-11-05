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
import android.os.FileObserver
import android.os.ParcelFileDescriptor
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONException
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
 * - `call("shared")`: every entry shared with friends, from this account's
 *   side (`xpenc/shared.json`, see `shared_files.dart`), plus what XPENC
 *   queued that hasn't gone out yet.
 * - `call("sharedOp", json)`: queue an add / edit / delete / answer
 *   (`xpenc/outbox/`), and start the background sync that sends it.
 * - `call("sharedSync")`: start that sync — XPENC opening, say.
 * - Changes to any of it: `notifyChange(content://…/shared)`, watched by
 *   XPENC while it's open.
 *
 * Answers only XPENC: the caller must be `com.yash.xpenc`, signed by one of
 * [XPENC_CERTS]. A debuggable Connector build skips the certificate check,
 * so it works with a locally built XPENC.
 */
class XpencProvider : ContentProvider() {
    /** Runs whenever Connector's process starts, the background job's too. */
    override fun onCreate(): Boolean {
        context?.let { watch(it.applicationContext) }
        return true
    }

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val context = context ?: return null
        if (method !in METHODS) return null
        if (!callerIsXpenc(context)) throw SecurityException("Only XPENC may read this.")
        return when (method) {
            "friends" -> Bundle().apply { putString("json", newestFriends(context)) }
            "shared" -> Bundle().apply {
                putString("json", inboxFile(context, SHARED).takeIf { it.exists() }?.readText())
                putString("outbox", queuedOps(context).toString())
            }
            "sharedOp" -> Bundle().apply { putBoolean("ok", queueOp(context, arg)) }
            "sharedSync" -> Bundle().apply {
                enqueueSharedSync(context)
                putBoolean("ok", true)
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

    /**
     * Writes [json] into the outbox as its own file — named so files sort in
     * the order XPENC made them — then starts the sync. Refuses anything
     * that isn't a plausible op; the Dart side checks the rest.
     */
    private fun queueOp(context: Context, json: String?): Boolean {
        if (json == null || json.length > MAX_OP_BYTES) return false
        val op = try {
            JSONObject(json)
        } catch (e: JSONException) {
            return false
        }
        val opId = op.optString("opId")
        if (!OP_ID.matches(opId) || op.optString("type") !in OP_TYPES) return false
        val dir = File(File(context.filesDir, "xpenc"), OUTBOX).apply { mkdirs() }
        val name = String.format(
            Locale.ROOT,
            "%013d-%06d-%s.json",
            System.currentTimeMillis(),
            sequence.incrementAndGet() % 1_000_000,
            opId,
        )
        val temp = File(dir, "$name.tmp")
        temp.writeText(json)
        if (!temp.renameTo(File(dir, name))) {
            temp.delete()
            return false
        }
        enqueueSharedSync(context)
        return true
    }

    /** What's still waiting to go out, oldest first. */
    private fun queuedOps(context: Context): JSONArray {
        val files = File(File(context.filesDir, "xpenc"), OUTBOX)
            .listFiles { f -> f.name.endsWith(".json") }
            ?.sortedBy { it.name }
            ?: emptyList()
        val ops = JSONArray()
        for (file in files) {
            try {
                ops.put(JSONObject(file.readText()))
            } catch (e: Exception) {
                // Half-gone or unreadable: the sync sets it aside.
            }
        }
        return ops
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
        private val METHODS = setOf(
            "friends", "pendingBackup", "confirmImport", "shared", "sharedOp", "sharedSync",
        )

        // Shared entries — written by shared_files.dart.
        private const val SHARED = "shared.json"
        private const val FRIENDS_FILE = "friends.json"
        private const val OUTBOX = "outbox"
        private const val MAX_OP_BYTES = 8 * 1024
        private val OP_ID = Regex("^[A-Za-z0-9-]{8,64}$")
        private val OP_TYPES = setOf("add", "edit", "delete", "respond")
        private val sequence = AtomicLong()

        /** Keep in step with `sharedSyncTask` in auto_sync.dart. */
        private const val SHARED_SYNC_TASK = "connector-shared-sync"

        /**
         * One-off run of the Dart sync, through the workmanager plugin's own
         * worker — the same entry point as the scheduled jobs. Appended to a
         * run already going, so an op queued mid-run still goes out.
         */
        fun enqueueSharedSync(context: Context) {
            val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                .setInputData(buildTaskInputData(SHARED_SYNC_TASK, null, null, SHARED_SYNC_TASK))
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                SHARED_SYNC_TASK,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
        }

        private var observer: FileObserver? = null

        /**
         * Tells XPENC when what it reads changed — whichever engine wrote it.
         * The Dart side writes each file to a temp name and renames it in.
         */
        @Suppress("DEPRECATION")
        private fun watch(context: Context) {
            if (observer != null) return
            val dir = File(context.filesDir, "xpenc").apply { mkdirs() }
            observer = object : FileObserver(dir.path, MOVED_TO or CLOSE_WRITE) {
                override fun onEvent(event: Int, path: String?) {
                    if (path == SHARED || path == FRIENDS_FILE) {
                        context.contentResolver.notifyChange(
                            Uri.parse("content://$AUTHORITY/shared"),
                            null,
                        )
                    }
                }
            }.also { it.startWatching() }
        }

        /**
         * The friends list as the app published it live, or as the
         * background job last read it — whichever is newer.
         */
        private fun newestFriends(context: Context): String? {
            val live = prefs(context).getString(KEY_JSON, null)
            val file = File(File(context.filesDir, "xpenc"), FRIENDS_FILE)
                .takeIf { it.exists() }
                ?.readText()
            fun updatedAt(json: String?): Long = try {
                if (json == null) -1L else JSONObject(json).optLong("updatedAt", 0L)
            } catch (e: JSONException) {
                -1L
            }
            return if (updatedAt(file) > updatedAt(live)) file else live
        }

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
