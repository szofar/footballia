package net.footballia.viewmodel

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import net.footballia.data.*
import java.util.Calendar

class FootballiaViewModel(application: Application) : AndroidViewModel(application) {

    private val repo = FootballiaRepository()
    private val favoritesStore = FavoritesStore(application)

    // Auth
    var isLoggedIn by mutableStateOf(false); private set
    var isCheckingSession by mutableStateOf(true); private set
    var isLoading by mutableStateOf(false); private set
    var loginError by mutableStateOf<String?>(null); private set

    // Whether the account has a Footballia Master subscription; null while still checking.
    var hasMasterAccess by mutableStateOf<Boolean?>(null); private set

    /**
     * Startup entry point. Tries to restore a persisted session from stored cookies first; only if
     * that fails does it fall back to the debug-only dev credentials. Call once from the Activity.
     */
    fun start(devCredentials: Pair<String, String>? = null) {
        viewModelScope.launch {
            val restored = runCatching { repo.restoreSession() }.getOrDefault(false)
            if (restored) {
                isLoggedIn = true
                launch { loadFavoriteTeams() }
                launch { runCatching { hasMasterAccess = repo.checkMasterAccess() } }
                loadMatches()
            }
            isCheckingSession = false
            if (!isLoggedIn && devCredentials != null) {
                login(devCredentials.first, devCredentials.second)
            }
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
                        launch { loadFavoriteTeams() }
                        launch { runCatching { hasMasterAccess = repo.checkMasterAccess() } }
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
        hasMasterAccess = null
        repo.clearCookies()
    }

    /** Loads the cached favorite-teams list, seeding the cache from the site on first launch. */
    private suspend fun loadFavoriteTeams() {
        val cached = runCatching { favoritesStore.loadTeams() }.getOrNull()
        if (cached != null) {
            favoriteTeams = cached
            return
        }
        val fetched = runCatching { repo.loadFeaturedTeams() }.getOrDefault(emptyList())
        favoriteTeams = fetched
        if (fetched.isNotEmpty()) runCatching { favoritesStore.saveTeams(fetched) }
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
