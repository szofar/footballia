package net.footballia.dev

import android.content.Context
import org.json.JSONObject

/** Debug-only convenience: auto-fills login from a local credentials file, never shipped in release. */
object DevCredentials {
    private const val FILE_NAME = "footballia-credentials.json"

    fun load(context: Context): Pair<String, String>? = runCatching {
        val json = context.assets.open(FILE_NAME).bufferedReader().use { it.readText() }
        val obj = JSONObject(json)
        obj.getString("email") to obj.getString("password")
    }.getOrNull()
}