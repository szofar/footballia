# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo contains **two independent client apps for the same service**, [footballia.eu](https://footballia.eu) (a football match video archive):

- `android/` — Android TV app, Kotlin + Jetpack Compose (Compose for TV).
- `Footballia/` — Apple app (macOS/tvOS), SwiftUI.

The two are functional ports of each other. The **Swift app is effectively the reference implementation**: the Android code was ported from it and its source files carry comments pointing back to their Swift counterparts (e.g. the video-extraction JS in `VideoPlayerScreen.kt` is "adapted from `VideoPlayerView.swift`"). When changing behavior in one app, check the sibling for the established approach, and keep parsing/auth logic in sync unless there's a platform reason to diverge.

## The core constraint: there is no API

footballia.eu has **no public API**. Both apps work entirely by:

1. **Scraping server-rendered HTML** for matches, teams, competitions, search results, and calendar data. All parsing is hand-rolled string/regex splitting (no HTML library) in `FootballiaRepository.kt` (Android) and `FootballiaService.swift` (Swift). The parsers use a **layered fallback strategy** — e.g. `parseMatchCards` → `parseMatchTable` → `parseMatchLinks` — because different pages (index, competition, player, search) use different HTML layouts. Preserve this fallback chain when editing parsers.
2. **Extracting the video stream via a hidden WebView.** There is no direct stream URL in the HTML. The match page runs JWPlayer; a hidden WebView loads the page, injects JS that pulls the HLS `.m3u8` URL out of `jwplayer(...).getPlaylistItem().file`, and hands it back to native code (`window.Android.streamFound` on Android / `window.webkit.messageHandlers` on Swift). That URL is then played by ExoPlayer (Android) / AVPlayer (Swift).

Two consequences to keep in mind whenever touching networking or the player:

- **A desktop User-Agent is mandatory everywhere.** footballia serves a mobile layout *without* `#jwplayer` to mobile UAs, which breaks stream extraction. Both the HTTP client and the WebView spoof `Version/17.4 Safari` (macOS). Don't change this.
- **Parsers are fragile against site markup changes.** If matches/streams suddenly stop loading, the site's HTML likely changed; fix the parser, don't assume a logic bug.

## Auth & session model

There is no token/OAuth — auth is **cookie-based**, matching the website's Devise login form (`POST /users/sign_in` with a CSRF `authenticity_token` scraped from the sign-in page, plus `remember_me=1`).

- **Cookie sharing is the key detail.** Both apps deliberately share one cookie store between the HTTP client and the WebView so a session logged in via HTTP also authenticates the video WebView. Android bridges OkHttp's `CookieJar` to the WebView `CookieManager` (`FootballiaRepository.kt`); Swift points `URLSession` at `HTTPCookieStorage.shared`.
- **Session persistence relies on the `remember_me` cookie**, which is written to disk by the cookie store and survives restarts. On launch both apps call `restoreSession()` — fetch the homepage and treat the user as logged in if the "Sign in" nav link (`<span>Sign in</span>`) is **absent** — before falling back to a credentials login. `logout()` clears the persisted cookies.
- **Dev auto-login:** a local `footballia-credentials.json` (`{"email","password"}`) auto-fills login for development. On Android it's a debug-only asset (`app/src/debug/assets/`, loaded by `DevCredentials`); the release variant has a no-op `DevCredentials`. On Swift it's read from `~/Downloads/`. This file is never shipped in release.

## Favourite teams

The site has no notion of a user's favourites, so both apps own the list locally. It's persisted (Android: `LocalStore`/DataStore; Swift: `FavoriteTeamsStore`/`UserDefaults`) with each team's name, logo path and slug cached, so the Favorites page renders straight from disk and never re-scrapes.

- **One source of truth.** Profile › Favorite Teams edits the same `favoriteTeams` state the Favorites page renders (`FootballiaViewModel` / `FootballiaService`), so the two stay in sync automatically. Route every mutation through `updateFavoriteTeams` / `setFavoriteTeams` so the change is persisted.
- **Seeded once, then user-owned.** The list is seeded from the homepage's featured-teams strip on first launch only. Presence of the *cache key* — not a non-empty list — is what marks it seeded, so "Clear All" (which persists an empty list) is not silently undone on the next launch.
- **Adding from search costs an extra fetch.** Team search results carry only a name and a slug, so `loadTeamDetails` pulls the crest and canonical name from the team page's `og:image` / `og:title` tags. A missing crest is not an error — cards fall back to initials — so a markup change degrades instead of blocking the add.

## Android architecture

Single-Activity Compose app, MVVM-ish:

- `MainActivity` → `RootScreen` switches between a session-checking spinner, `LoginScreen`, and `MainScreen` based on `FootballiaViewModel` state.
- **`FootballiaViewModel`** holds all UI state as Compose `mutableStateOf` and owns coroutine calls into the repository. It is the single source of truth; screens are otherwise stateless.
- **`FootballiaRepository`** is all networking + HTML parsing (OkHttp, `Dispatchers.IO`). Stateless aside from the shared cookie jar.
- `data/Models.kt` holds the domain types and derives all footballia URLs (thumbnails, logos, match pages) from `BASE_URL` + parsed slugs/hashes.
- Video playback (`VideoPlayerScreen.kt`) uses a `PlayerView` **inflated from `res/layout/video_player_view.xml` so it renders on a `TextureView`** — a default `SurfaceView` draws behind the Compose overlay and shows only black. Keep this.

## Build & run (Android)

Gradle needs a Java 17 runtime. If `./gradlew` reports "Unable to locate a Java Runtime", point it at Android Studio's bundled JBR:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

Common commands (run from `android/`):

```bash
./gradlew :app:compileDebugKotlin      # fast compile check (debug variant)
./gradlew :app:compileReleaseKotlin    # verify the release variant too — it has its own DevCredentials
./gradlew assembleDebug                # build debug APK
./gradlew installDebug                 # install to a connected device/emulator (Android TV)
```

There is currently no test suite. The app can only be meaningfully exercised on an Android TV device/emulator (login → browse → play a match).

## Build & run (Swift)

Open `Footballia/Footballia.xcodeproj` in Xcode and build/run the macOS (or tvOS) target. No package manager — dependencies are Apple frameworks only (SwiftUI, WebKit, AVKit).
