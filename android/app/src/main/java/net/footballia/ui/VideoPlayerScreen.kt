package net.footballia.ui

import android.view.LayoutInflater
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.util.Log
import net.footballia.R
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.tv.material3.IconButtonDefaults
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import net.footballia.data.Match
import androidx.tv.material3.IconButton as TvIconButton

private const val STREAM_TIMEOUT_MS = 25_000L
private const val CONTROLS_HIDE_DELAY_MS = 7_000L
private const val SKIP_MS = 10_000L
private const val SEEK_BAR_MIN_STEP_MS = 10_000L
private const val SEEK_BAR_MAX_STEP_MS = 600_000L
private const val SEEK_BAR_RAMP_MS = 7_000L
private const val HOLD_ENGAGE_DELAY_MS = 350L
private const val HOLD_TICK_MS = 220L
private const val HOLD_MAX_STEP_MS = 60_000L
private val ACCENT_GREEN = Color(0xFF22C55E)

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(match: Match, onClose: () -> Unit) {
    val context = LocalContext.current
    val streamChannel = remember { Channel<String>(Channel.CONFLATED) }
    var streamUrl by remember { mutableStateOf<String?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadFailed by remember { mutableStateOf(false) }

    var controlsVisible by remember { mutableStateOf(false) }
    var interactionTick by remember { mutableStateOf(0) }
    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableStateOf(0L) }
    var durationMs by remember { mutableStateOf(0L) }

    fun onInteraction() {
        controlsVisible = true
        interactionTick++
    }

    // Remote's back button exits the video instead of navigating within it.
    BackHandler(onBack = onClose)

    // Keep the display awake for the whole session. The TV otherwise dims and sleeps on its
    // inactivity timer: ExoPlayer alone doesn't hold a wake lock, and nothing here counts as
    // user input during playback. Driven off the composition's own View so it holds regardless
    // of how the Compose context is wrapped, and released as soon as the player goes away.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    // Receive stream URL from JS bridge on the main coroutine. Give up after a
    // timeout instead of spinning forever if the page never yields a stream.
    LaunchedEffect(Unit) {
        val url = withTimeoutOrNull(STREAM_TIMEOUT_MS) { streamChannel.receive() }
        if (url != null) streamUrl = url else loadFailed = true
        isLoading = false
    }

    // Controls auto-hide after a period of inactivity; any interaction resets it.
    LaunchedEffect(controlsVisible, interactionTick) {
        if (controlsVisible) {
            delay(CONTROLS_HIDE_DELAY_MS)
            controlsVisible = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onPreviewKeyEvent { event ->
                if (event.type == KeyEventType.KeyDown) onInteraction()
                false
            }
    ) {

        // Hidden WebView loads the match page and extracts the HLS stream URL via JS
        if (streamUrl == null) {
            AndroidView(
                factory = { ctx ->
                    WebView.setWebContentsDebuggingEnabled(true)
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        // Match desktop UA used elsewhere so footballia.eu serves the
                        // desktop layout with #jwplayer, not a mobile page without it.
                        settings.userAgentString =
                            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

                        addJavascriptInterface(
                            object {
                                @JavascriptInterface
                                fun streamFound(url: String) {
                                    if (!url.startsWith("blob:") && url.isNotEmpty()) {
                                        streamChannel.trySend(url)
                                    }
                                }
                            },
                            "Android"
                        )

                        webChromeClient = object : WebChromeClient() {
                            override fun onConsoleMessage(msg: ConsoleMessage): Boolean {
                                Log.d("FootballiaWebView", "${msg.message()} [${msg.sourceId()}:${msg.lineNumber()}]")
                                return true
                            }
                        }

                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, url: String?) {
                                view.evaluateJavascript(JS_HIDE_CHROME, null)
                                view.evaluateJavascript(JS_AUTO_PLAY, null)
                            }

                            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                                val host = request.url.host ?: return true
                                return !host.endsWith("footballia.eu") && !host.endsWith("footballia.net")
                            }
                        }

                        loadUrl(match.matchPageUrl)
                    }
                },
                modifier = Modifier.fillMaxSize().alpha(0f)
            )
        }

        // ExoPlayer once the HLS stream URL is resolved
        streamUrl?.let { url ->
            val player = remember(url) {
                ExoPlayer.Builder(context).build().apply {
                    setMediaItem(MediaItem.fromUri(url))
                    prepare()
                    playWhenReady = true
                }
            }

            DisposableEffect(player) {
                onDispose { player.release() }
            }

            // PlayerView's built-in controller is disabled (see video_player_view.xml);
            // this polls playback state for the custom Compose controls below instead.
            LaunchedEffect(player) {
                while (true) {
                    isPlaying = player.isPlaying
                    positionMs = player.currentPosition.coerceAtLeast(0)
                    durationMs = player.duration.coerceAtLeast(0)
                    delay(200)
                }
            }

            LaunchedEffect(url) { onInteraction() }

            AndroidView(
                factory = { ctx ->
                    // Inflated from XML so the PlayerView uses a TextureView surface
                    // (see res/layout/video_player_view.xml) — a SurfaceView would
                    // render behind the Compose overlay and show only black.
                    val view = LayoutInflater.from(ctx)
                        .inflate(R.layout.video_player_view, null) as PlayerView
                    view.player = player
                    // Controls are the custom Compose overlay below; don't let this
                    // view steal D-pad focus from it.
                    view.isFocusable = false
                    view
                },
                update = { view -> view.player = player },
                modifier = Modifier.fillMaxSize()
            )

            VideoControls(
                visible = controlsVisible,
                isPlaying = isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                onPlayPause = {
                    onInteraction()
                    if (player.isPlaying) player.pause() else player.play()
                },
                onSeekBy = { deltaMs ->
                    onInteraction()
                    val target = (player.currentPosition + deltaMs)
                        .coerceIn(0, player.duration.coerceAtLeast(0))
                    player.seekTo(target)
                },
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }

        // Loading / failure overlay
        if (isLoading || loadFailed) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    if (loadFailed) {
                        Text("Couldn't load this match", color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp)
                        Text("The video stream wasn't available.", color = Color.White.copy(alpha = 0.4f), fontSize = 13.sp)
                    } else {
                        CircularProgressIndicator(color = ACCENT_GREEN)
                        Text("Loading match…", color = Color.White.copy(alpha = 0.45f), fontSize = 14.sp)
                    }
                }
            }
        }

        // Top bar: shown while loading/failed (so the user can always go back),
        // and otherwise only while the playback controls overlay is visible.
        if (isLoading || loadFailed || controlsVisible) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .background(Color.Black.copy(alpha = if (isLoading || loadFailed) 1f else 0.55f))
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                IconButton(onClick = onClose) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.7f))
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(match.title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1)
                    val meta = listOf(match.competition, match.stage, match.date)
                        .filter { it.isNotEmpty() }.joinToString("  ·  ")
                    if (meta.isNotEmpty()) {
                        Text(meta, color = Color.White.copy(alpha = 0.38f), fontSize = 12.sp, maxLines = 1)
                    }
                }
            }
        }
    }
}

// MARK: - Custom playback controls
//
// PlayerView's built-in controller doesn't support footballia's TV seek
// conventions, so this is hand-rolled: the skip buttons jump a fixed ±10s on
// a tap, but scrub with progressively larger jumps if held; the timeline
// itself moves in 30s steps via D-pad left/right once it's focused.

@Composable
private fun VideoControls(
    visible: Boolean,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    onPlayPause: () -> Unit,
    onSeekBy: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val playPauseFocusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        runCatching { playPauseFocusRequester.requestFocus() }
    }

    val buttonColors = IconButtonDefaults.colors(
        containerColor = Color.White.copy(alpha = 0.12f),
        contentColor = Color.White,
        focusedContainerColor = ACCENT_GREEN,
        focusedContentColor = Color.Black
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .alpha(if (visible) 1f else 0f)
            .background(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    1f to Color.Black.copy(alpha = 0.75f)
                )
            )
            .padding(horizontal = 28.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            SkipButton(direction = -1, colors = buttonColors, onSeekBy = onSeekBy)
            Spacer(modifier = Modifier.width(28.dp))
            TvIconButton(
                onClick = onPlayPause,
                modifier = Modifier.focusRequester(playPauseFocusRequester),
                colors = buttonColors
            ) {
                Icon(
                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    modifier = Modifier.size(28.dp)
                )
            }
            Spacer(modifier = Modifier.width(28.dp))
            SkipButton(direction = 1, colors = buttonColors, onSeekBy = onSeekBy)
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(formatPlaybackTime(positionMs), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            SeekBar(
                positionMs = positionMs,
                durationMs = durationMs,
                onSeekBy = onSeekBy,
                modifier = Modifier.weight(1f)
            )
            Text(formatPlaybackTime(durationMs), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
        }
    }
}

// Single click seeks by SKIP_MS once. Holding past HOLD_ENGAGE_DELAY_MS starts
// a repeating seek whose step grows each tick, so a long hold scrubs faster
// the longer it's held.
@Composable
private fun SkipButton(
    direction: Int,
    colors: androidx.tv.material3.ButtonColors,
    onSeekBy: (Long) -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    var holdEngaged by remember { mutableStateOf(false) }

    LaunchedEffect(isPressed) {
        if (isPressed) {
            holdEngaged = false
            delay(HOLD_ENGAGE_DELAY_MS)
            holdEngaged = true
            var stepMs = SKIP_MS
            while (isPressed) {
                onSeekBy(direction * stepMs)
                delay(HOLD_TICK_MS)
                stepMs = (stepMs * 8 / 5).coerceAtMost(HOLD_MAX_STEP_MS)
            }
        }
    }

    TvIconButton(
        onClick = { if (!holdEngaged) onSeekBy(direction * SKIP_MS) },
        interactionSource = interactionSource,
        colors = colors
    ) {
        Icon(
            if (direction < 0) Icons.Default.Replay10 else Icons.Default.Forward10,
            contentDescription = if (direction < 0) "Back 10 seconds" else "Forward 10 seconds",
            modifier = Modifier.size(22.dp)
        )
    }
}

@Composable
private fun SeekBar(
    positionMs: Long,
    durationMs: Long,
    onSeekBy: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var isFocused by remember { mutableStateOf(false) }
    val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
    val barHeight = if (isFocused) 6.dp else 4.dp

    Box(
        modifier = modifier
            .height(20.dp)
            .onFocusChanged { isFocused = it.isFocused }
            .focusable()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionLeft -> { onSeekBy(-seekBarHoldStepMs(event)); true }
                    Key.DirectionRight -> { onSeekBy(seekBarHoldStepMs(event)); true }
                    else -> false
                }
            },
        contentAlignment = Alignment.CenterStart
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(barHeight)
                .clip(RoundedCornerShape(50))
                .background(Color.White.copy(alpha = 0.25f))
        )
        Box(
            modifier = Modifier
                .fillMaxWidth(progress)
                .height(barHeight)
                .clip(RoundedCornerShape(50))
                .background(ACCENT_GREEN)
        )
    }
}

// D-pad key-repeat events carry the original downTime alongside each repeat's
// eventTime, so the true hold duration is derived from the native event rather
// than tracked by hand. Step size ramps linearly from SEEK_BAR_MIN_STEP_MS at
// press to SEEK_BAR_MAX_STEP_MS once held past SEEK_BAR_RAMP_MS.
private fun seekBarHoldStepMs(event: androidx.compose.ui.input.key.KeyEvent): Long {
    val heldMs = (event.nativeKeyEvent.eventTime - event.nativeKeyEvent.downTime).coerceAtLeast(0)
    val fraction = (heldMs.toFloat() / SEEK_BAR_RAMP_MS).coerceIn(0f, 1f)
    return (SEEK_BAR_MIN_STEP_MS + (SEEK_BAR_MAX_STEP_MS - SEEK_BAR_MIN_STEP_MS) * fraction).toLong()
}

private fun formatPlaybackTime(ms: Long): String {
    if (ms <= 0) return "0:00"
    val totalSeconds = ms / 1000
    val h = totalSeconds / 3600
    val m = (totalSeconds % 3600) / 60
    val s = totalSeconds % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

// JS adapted from VideoPlayerView.swift — replaces window.webkit.messageHandlers
// with window.Android so the same JWPlayer extraction works on Android WebView.

private val JS_HIDE_CHROME = """
(function() {
    var s = document.createElement('style');
    s.textContent = `
        header.header-block, nav.nav-bottom, .top-advertisements, .breadcrumbs,
        .description.m-t, .side-col, footer.footer-block, .comments, .details,
        .social_links, .formations_images, .modal, #taboola-custom-widget,
        [id^="bg-ssp"], [id^="gpt-"], .alert-success, .alert-warning
        { display: none !important; }
        body, html { background: #000 !important; overflow: hidden !important; }
        .page-wrapper { background: #000 !important; box-shadow: none !important; }
        .content-block { padding: 0 !important; }
        .container.no-pad-t { padding: 0 !important; margin: 0 !important; max-width: 100vw !important; }
        #match > .row { margin: 0 !important; }
        #match .col-md-7 {
            width: 100% !important; max-width: 100% !important;
            flex: 0 0 100% !important; padding: 0 !important;
        }
        #match .video { height: 100vh !important; margin: 0 !important; }
        #jwplayer, .jwplayer { width: 100% !important; height: 100% !important; }
    `;
    document.head.appendChild(s);
})();
""".trimIndent()

private val JS_AUTO_PLAY = """
(function() {
    var reported = false;
    var fallbackTimer = null;

    function report(url) {
        if (reported || !url) return true;
        reported = true;
        if (fallbackTimer) clearTimeout(fallbackTimer);
        window.Android.streamFound(url);
        return true;
    }

    // Decode the stream straight out of the page's own "var playlist = [...]"
    // block. The site stores each file as base64 and decodes it via
    // new Video(file).url(). This path does not need JWPlayer to be alive.
    function extractFromPlaylist() {
        if (reported) return false;
        try {
            var m = document.documentElement.innerHTML.match(/var playlist = (\[[\s\S]*?\]);/);
            if (!m) return false;
            var items = JSON.parse(m[1]);
            if (!items || !items.length || !items[0].file) return false;
            var url = window.atob(String(items[0].file).replace(/\s/g, ''));
            if (!url || url.indexOf('http') !== 0) return false;
            return report(url);
        } catch(e) { return false; }
    }

    function extractURL(p) {
        if (reported) return;
        try {
            var item = p.getPlaylistItem();
            if (item && item.file) { report(item.file); return; }
        } catch(e) {}
        extractFromPlaylist();
    }

    function resizePlayer(p) {
        try {
            var col = document.querySelector('#match .col-md-7');
            if (col) col.className = col.className.replace('col-md-7', 'col-md-12');
            p.resize(document.documentElement.clientWidth, window.innerHeight);
        } catch(e) {}
    }

    function tryStart() {
        if (extractFromPlaylist()) return true;
        if (typeof jwplayer === 'undefined') return false;
        var p = jwplayer('jwplayer');
        if (!p || typeof p.getState !== 'function') return false;
        // Extract first: a failure inside resize() must never block playback.
        extractURL(p);
        resizePlayer(p);
        return true;
    }

    fallbackTimer = setTimeout(function() {
        if (!reported && typeof jwplayer !== 'undefined') {
            try { jwplayer('jwplayer').play(); } catch(e) {}
        }
    }, 4000);

    try {
        jwplayer('jwplayer').on('ready', function() {
            var p = jwplayer('jwplayer');
            extractURL(p);
            resizePlayer(p);
        });
    } catch(e) {}

    var tries = 0;
    if (!extractFromPlaylist()) {
    var poll = setInterval(function() {
        tries++;
        if (tries > 40) { clearInterval(poll); return; }
        if (tryStart() && reported) clearInterval(poll);
    }, 250);
    }
})();
""".trimIndent()