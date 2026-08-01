package net.footballia.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

private val Context.favoritesDataStore by preferencesDataStore(name = "favorites")

/**
 * Persists the favorite-teams list across launches. Populated once from the site's featured
 * teams on first app start (see FootballiaViewModel); editing comes later.
 */
class FavoritesStore(private val context: Context) {
    private val teamsKey = stringPreferencesKey("favorite_teams")

    suspend fun loadTeams(): List<Team>? {
        val json = context.favoritesDataStore.data.first()[teamsKey] ?: return null
        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            Team(id = o.getString("id"), slug = o.getString("slug"), name = o.getString("name"), logoPath = o.getString("logoPath"))
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
        context.favoritesDataStore.edit { it[teamsKey] = array.toString() }
    }
}