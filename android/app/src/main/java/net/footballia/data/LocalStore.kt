package net.footballia.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

private val Context.localDataStore by preferencesDataStore(name = "favorites")

/**
 * Disk-backed local state: the favorite-teams list plus the signed-in account email.
 *
 * The favorites list is seeded once from the site's featured teams on first app start (see
 * FootballiaViewModel) and read from disk from then on, so it stays stable even as the site
 * rotates its own strip — and so an editing UI can own it later.
 */
class LocalStore(private val context: Context) {
    private val teamsKey = stringPreferencesKey("favorite_teams")
    private val emailKey = stringPreferencesKey("account_email")
    private val masterKey = booleanPreferencesKey("master_access")

    suspend fun loadTeams(): List<Team>? {
        val json = context.localDataStore.data.first()[teamsKey] ?: return null
        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            Team(
                id = o.getString("id"),
                slug = o.getString("slug"),
                name = o.getString("name"),
                logoPath = o.getString("logoPath")
            )
        }
    }

    suspend fun saveTeams(teams: List<Team>) {
        val array = JSONArray()
        teams.forEach { team ->
            array.put(JSONObject().apply {
                put("id", team.id)
                put("slug", team.slug)
                put("name", team.name)
                put("logoPath", team.logoPath)
            })
        }
        context.localDataStore.edit { it[teamsKey] = array.toString() }
    }

    suspend fun loadAccountEmail(): String? =
        context.localDataStore.data.first()[emailKey]

    suspend fun saveAccountEmail(email: String) {
        context.localDataStore.edit { it[emailKey] = email }
    }

    suspend fun clearAccountEmail() {
        context.localDataStore.edit { it.remove(emailKey) }
    }

    suspend fun loadMasterAccess(): Boolean? =
        context.localDataStore.data.first()[masterKey]

    suspend fun saveMasterAccess(hasAccess: Boolean) {
        context.localDataStore.edit { it[masterKey] = hasAccess }
    }

    suspend fun clearMasterAccess() {
        context.localDataStore.edit { it.remove(masterKey) }
    }
}
