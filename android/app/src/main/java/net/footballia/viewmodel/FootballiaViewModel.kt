package net.footballia.viewmodel

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import net.footballia.data.*
import java.util.Calendar

class FootballiaViewModel(application: Application) : AndroidViewModel(application) {

    private val repo = FootballiaRepository()
    private val localStore = LocalStore(application)

    // Auth
    var isLoggedIn by mutableStateOf(false); private set
    var isCheckingSession by mutableStateOf(true); private set
    var isLoading by mutableStateOf(false); private set
    var loginError by mutableStateOf<String?>(null); private set

    // Whether the account has a Footballia Master subscription; null while still checking.
    var hasMasterAccess by mutableStateOf<Boolean?>(null); private set

    // Email the session was established with, restored from disk for the Profile tab.
    var accountEmail by mutableStateOf<String?>(null); private set

    /**
     * Startup entry point. Tries to restore a persisted session from stored cookies first; only if
     * that fails does it fall back to the debug-only dev credentials. Call once from the Activity.
     */
    fun start(devCredentials: Pair<String, String>? = null) {
        viewModelScope.launch {
            // Seed from the last known value so the tab order is stable at launch instead of
            // waiting on (and flip-flopping with) the network check below.
            hasMasterAccess = runCatching { localStore.loadMasterAccess() }.getOrNull()

            val restored = runCatching { repo.restoreSession() }.getOrDefault(false)
            if (restored) {
                isLoggedIn = true
                launch { accountEmail = runCatching { localStore.loadAccountEmail() }.getOrNull() }
                launch { loadFavoriteTeams() }
                launch { refreshMasterAccess() }
                loadMatches()
            }
            isCheckingSession = false
            if (!isLoggedIn && devCredentials != null) {
                login(devCredentials.first, devCredentials.second)
            }
        }
    }

    /**
     * Resolves Master entitlement from the calendar page and caches it.
     *
     * A failed check leaves the previously cached value alone rather than asserting "no access":
     * downgrading on a network blip would reorder the tab bar and lock the Calendar for a user
     * who actually is a Master. Only when there is no cached value at all does it fall back to
     * `false`, so the UI still resolves instead of spinning on null forever.
     */
    private suspend fun refreshMasterAccess() {
        val result = runCatching { repo.checkMasterAccess() }.getOrNull()
        if (result != null) {
            hasMasterAccess = result
            runCatching { localStore.saveMasterAccess(result) }
        } else if (hasMasterAccess == null) {
            hasMasterAccess = false
        }
    }

    // Home matches
    var matches by mutableStateOf<List<Match>>(emptyList()); private set
    var isLoadingMatches by mutableStateOf(false); private set
    var currentPage by mutableStateOf(1); private set
    var hasNextPage by mutableStateOf(false); private set
    var paginationReversed by mutableStateOf(false); private set
    var currentFilter by mutableStateOf<MatchFilter>(MatchFilter.All); private set

    // Favorite teams (cached locally; seeded from the site's featured teams on first launch)
    var favoriteTeams by mutableStateOf<List<Team>>(emptyList()); private set

    /**
     * False until the favourites list has been read from disk (or seeded). Lets the Favorites
     * page tell "still loading" apart from "the user cleared the list", which otherwise both
     * look like an empty list and would leave a spinner up forever.
     */
    var favoritesLoaded by mutableStateOf(false); private set

    // Favorite-team editing (Profile tab). Kept apart from the Search tab's state so editing
    // favourites never disturbs an in-progress search on the other tab.
    var favoriteTeamSearchResults by mutableStateOf<List<SearchSuggestion>>(emptyList()); private set
    var isSearchingFavoriteTeams by mutableStateOf(false); private set
    var favoriteTeamSearchError by mutableStateOf<String?>(null); private set

    /** Slugs whose crest/name lookup is still in flight, so rows can show a spinner. */
    var pendingFavoriteSlugs by mutableStateOf<Set<String>>(emptySet()); private set

    /** In-flight favourites search, cancelled whenever a newer query supersedes it. */
    private var favoriteSearchJob: Job? = null

    // Competitions
    var competitionCategories by mutableStateOf<List<CompetitionCategory>>(emptyList()); private set
    var isLoadingCompetitions by mutableStateOf(false); private set

    // Search
    var searchSuggestions by mutableStateOf<List<SearchSuggestion>>(emptyList()); private set
    var searchResults by mutableStateOf<List<Match>>(emptyList()); private set
    var isSearching by mutableStateOf(false); private set
    var isLoadingSearchMatches by mutableStateOf(false); private set
    var searchError by mutableStateOf<String?>(null); private set
    var searchCurrentPage by mutableStateOf(1); private set
    var searchHasNextPage by mutableStateOf(false); private set
    var searchPaginationReversed by mutableStateOf(true); private set
    var activeSuggestion by mutableStateOf<SearchSuggestion?>(null); private set

    // Calendar
    var calendarMatchDays by mutableStateOf<Set<Int>>(emptySet()); private set
    var calendarYear by mutableStateOf(Calendar.getInstance().get(Calendar.YEAR)); private set
    var calendarMonth by mutableStateOf(Calendar.getInstance().get(Calendar.MONTH) + 1); private set
    var isLoadingCalendar by mutableStateOf(false); private set

    fun login(email: String, password: String) {
        viewModelScope.launch {
            isLoading = true
            loginError = null
            runCatching { repo.login(email, password) }
                .onSuccess { success ->
                    if (success) {
                        isLoggedIn = true
                        accountEmail = email
                        launch { runCatching { localStore.saveAccountEmail(email) } }
                        launch { loadFavoriteTeams() }
                        launch { refreshMasterAccess() }
                        loadMatches()
                    } else {
                        loginError = "Invalid email or password."
                    }
                }
                .onFailure { loginError = "Connection error: ${it.message}" }
            isLoading = false
        }
    }

    fun logout() {
        isLoggedIn = false
        matches = emptyList(); favoriteTeams = emptyList(); competitionCategories = emptyList()
        searchResults = emptyList(); searchSuggestions = emptyList(); calendarMatchDays = emptySet()
        currentPage = 1; hasNextPage = false; paginationReversed = false
        currentFilter = MatchFilter.All; activeSuggestion = null
        favoritesLoaded = false
        favoriteSearchJob?.cancel()
        favoriteTeamSearchResults = emptyList(); favoriteTeamSearchError = null
        isSearchingFavoriteTeams = false; pendingFavoriteSlugs = emptySet()
        hasMasterAccess = null
        accountEmail = null
        viewModelScope.launch {
            runCatching { localStore.clearAccountEmail() }
            runCatching { localStore.clearMasterAccess() }
        }
        repo.clearCookies()
    }

    /**
     * Loads the cached favorite-teams list, seeding the cache from the site on first launch.
     *
     * A cached empty list is honoured rather than re-seeded: it means the user cleared the list
     * on purpose, and silently repopulating it would make "Clear All" look broken.
     */
    private suspend fun loadFavoriteTeams() {
        val cached = runCatching { localStore.loadTeams() }.getOrNull()
        if (cached != null) {
            favoriteTeams = cached
            favoritesLoaded = true
            return
        }
        val fetched = runCatching { repo.loadFeaturedTeams() }.getOrDefault(emptyList())
        // The user may have edited the list from the Profile tab while the homepage fetch was
        // in flight; `favoritesLoaded` marks the list as theirs, so the seed must not win.
        if (favoritesLoaded) return
        if (fetched.isNotEmpty()) {
            favoriteTeams = fetched
            runCatching { localStore.saveTeams(fetched) }
        }
        // Resolved either way: a failed seed persists nothing, so the next launch retries while
        // the Favorites page shows its empty state instead of spinning for the whole session.
        favoritesLoaded = true
    }

    /** Replaces the cached favorites list; the Favorites page reads the same state. */
    fun updateFavoriteTeams(teams: List<Team>) {
        favoriteTeams = teams
        favoritesLoaded = true
        viewModelScope.launch { runCatching { localStore.saveTeams(teams) } }
    }

    fun isFavorite(slug: String): Boolean = favoriteTeams.any { it.slug == slug }

    /** Team-name search for the Profile tab's favourites editor. */
    fun searchFavoriteTeamCandidates(query: String) {
        val q = query.trim()
        if (q.isEmpty()) { clearFavoriteTeamSearch(); return }
        // The debounce lives in the UI, but the request itself runs in viewModelScope, so the
        // previous one has to be cancelled explicitly — otherwise a slow response for an
        // abandoned prefix can land last and stick on screen.
        favoriteSearchJob?.cancel()
        favoriteSearchJob = viewModelScope.launch {
            isSearchingFavoriteTeams = true
            favoriteTeamSearchError = null
            val result = runCatching { repo.search(q, SearchMode.TEAMS) }
            if (!isActive) return@launch  // superseded: the newer search owns the state now
            result
                .onSuccess {
                    favoriteTeamSearchResults = it
                    favoriteTeamSearchError = if (it.isEmpty()) "No teams found for \"$q\"." else null
                }
                .onFailure {
                    favoriteTeamSearchResults = emptyList()
                    favoriteTeamSearchError = "Could not reach the server."
                }
            isSearchingFavoriteTeams = false
        }
    }

    fun clearFavoriteTeamSearch() {
        favoriteSearchJob?.cancel()
        favoriteTeamSearchResults = emptyList()
        favoriteTeamSearchError = null
        isSearchingFavoriteTeams = false
    }

    /**
     * Adds a team picked from search. The suggestion only carries a name and slug, so the crest
     * is resolved from the team's own page and cached alongside it — the Favorites page renders
     * straight from the cache and never re-fetches.
     */
    fun addFavoriteTeam(suggestion: SearchSuggestion) {
        val slug = suggestion.slug
        if (slug.isEmpty() || isFavorite(slug) || slug in pendingFavoriteSlugs) return
        pendingFavoriteSlugs = pendingFavoriteSlugs + slug
        viewModelScope.launch {
            val team = runCatching { repo.loadTeamDetails(slug, suggestion.name) }
                .getOrDefault(Team(id = slug, slug = slug, name = suggestion.name, logoPath = ""))
            // A list-wide action taken during the round-trip drops the pending marker: the
            // user's newer intent wins, so this add is abandoned rather than resurrecting the
            // team into a list they just cleared or reset.
            if (slug !in pendingFavoriteSlugs) return@launch
            pendingFavoriteSlugs = pendingFavoriteSlugs - slug
            if (!isFavorite(slug)) updateFavoriteTeams(favoriteTeams + team)
        }
    }

    fun removeFavoriteTeam(team: Team) {
        updateFavoriteTeams(favoriteTeams.filterNot { it.slug == team.slug })
    }

    /** Empties the list. Persisted as an empty list so it is not re-seeded on the next launch. */
    fun clearFavoriteTeams() {
        pendingFavoriteSlugs = emptySet()
        updateFavoriteTeams(emptyList())
    }

    /** Restores the default list: the site's current featured-teams strip. */
    fun restoreDefaultFavoriteTeams() {
        viewModelScope.launch {
            val fetched = runCatching { repo.loadFeaturedTeams() }.getOrDefault(emptyList())
            if (fetched.isNotEmpty()) {
                pendingFavoriteSlugs = emptySet()
                updateFavoriteTeams(fetched)
            }
        }
    }

    fun loadMatches(filter: MatchFilter? = null, page: Int = 1) {
        val f = filter ?: currentFilter
        if (filter != null && filter != currentFilter) paginationReversed = false
        currentFilter = f
        currentPage = page
        viewModelScope.launch {
            isLoadingMatches = true
            runCatching { repo.loadMatches(f, page) }
                .onSuccess { (parsed, hasNext) ->
                    if (parsed.isNotEmpty()) matches = parsed
                    hasNextPage = hasNext
                }
            isLoadingMatches = false
        }
    }

    fun loadMatchesLastPage(filter: MatchFilter) {
        currentFilter = filter
        paginationReversed = true
        viewModelScope.launch {
            isLoadingMatches = true
            runCatching { repo.loadMatchesLastPage(filter) }
                .onSuccess { (parsed, page, hasNext) ->
                    if (parsed.isNotEmpty()) matches = parsed
                    currentPage = page; hasNextPage = hasNext
                }
            isLoadingMatches = false
        }
    }

    fun loadCompetitions() {
        if (competitionCategories.isNotEmpty()) return
        viewModelScope.launch {
            isLoadingCompetitions = true
            runCatching { competitionCategories = repo.loadCompetitions() }
            isLoadingCompetitions = false
        }
    }

    fun search(query: String, mode: SearchMode) {
        val q = query.trim()
        if (q.isEmpty()) { clearSearch(); return }
        viewModelScope.launch {
            isSearching = true
            searchError = null
            searchSuggestions = emptyList()
            runCatching { repo.search(q, mode) }
                .onSuccess { if (it.isEmpty()) searchError = "No results for \"$q\"." else searchSuggestions = it }
                .onFailure { searchError = "Could not reach the server." }
            isSearching = false
        }
    }

    fun clearSearch() {
        searchSuggestions = emptyList(); searchResults = emptyList()
        searchError = null; activeSuggestion = null
        searchCurrentPage = 1; searchHasNextPage = false
    }

    fun loadMatchesForSuggestion(suggestion: SearchSuggestion) {
        activeSuggestion = suggestion
        searchResults = emptyList()
        searchPaginationReversed = true
        viewModelScope.launch {
            isLoadingSearchMatches = true
            runCatching { repo.loadMatchesForSuggestion(suggestion) }
                .onSuccess { (m, page, hasNext) ->
                    searchResults = m; searchCurrentPage = page; searchHasNextPage = hasNext
                }
            isLoadingSearchMatches = false
        }
    }

    fun loadSearchPage(page: Int) {
        val sug = activeSuggestion ?: return
        viewModelScope.launch {
            isLoadingSearchMatches = true
            runCatching { repo.loadSearchPage(page, sug) }
                .onSuccess { (parsed, hasNext) ->
                    if (parsed.isNotEmpty()) searchResults = parsed
                    searchCurrentPage = page; searchHasNextPage = hasNext
                }
            isLoadingSearchMatches = false
        }
    }

    fun clearActiveSuggestion() {
        activeSuggestion = null
        searchResults = emptyList()
        searchCurrentPage = 1; searchHasNextPage = false
    }

    fun loadCalendar(year: Int = calendarYear, month: Int = calendarMonth) {
        viewModelScope.launch {
            isLoadingCalendar = true
            runCatching { repo.loadCalendar(year, month) }
                .onSuccess { result ->
                    calendarYear = result.year; calendarMonth = result.month
                    calendarMatchDays = result.days
                }
            isLoadingCalendar = false
        }
    }
}
