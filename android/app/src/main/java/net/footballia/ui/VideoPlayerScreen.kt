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
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.tv.material3.IconButtonDefaults
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import net.footballia.data.Match
import org.json.JSONArray
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

private fun parseStreamUrls(received: String): List<String> {
    return if (received.trimStart().startsWith("[")) {
        try {
            val arr = JSONArray(received)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) { emptyList() }
    } else {
        listOf(received)
    }
}

private fun halfLabel(index: Int, total: Int): String =
    if (total == 2) if (index == 0) "1st Half" else "2nd Half" else "Part ${index + 1}"

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(match: Match, onClose: () -> Unit) {
    val context = LocalContext.current
    val streamChannel = remember { Channel<String>(Channel.CONFLATED) }
    var streamUrls by remember { mutableStateOf<List<String>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadFailed by remember { mutableStateOf(false) }

    var controlsVisible by remember { mutableStateOf(false) }
    var interactionTick by remember { mutableStateOf(0) }
    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableStateOf(0L) }
    var durationMs by remember { mutableStateOf(0L) }
    var currentHalfIndex by remember { mutableStateOf(0) }
    var halfBanner by remember { mutableStateOf<String?>(null) }

    fun onInteraction() {
        controlsVisible = true
        interactionTick++
    }

    BackHandler(onBack = onClose)

    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    // Receive all stream URLs from the JS bridge.
    LaunchedEffect(Unit) {
        val received = withTimeoutOrNull(STREAM_TIMEOUT_MS) { streamChannel.receive() }
        if (received != null) {
            val urls = parseStreamUrls(received).filter { it.isNotEmpty() }
            if (urls.isNotEmpty()) streamUrls = urls else loadFailed = true
        } else {
            loadFailed = true
        }
        isLoading = false
    }

    // Controls auto-hide after a period of inactivity.
    LaunchedEffect(controlsVisible, interactionTick) {
        if (controlsVisible) {
            delay(CONTROLS_HIDE_DELAY_MS)
            controlsVisible = false
        }
    }

    // Auto-hide half banner after 3.5 s.
    LaunchedEffect(halfBanner) {
        if (halfBanner != null) {
            delay(3_500)
            halfBanner = null
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

        // Hidden WebView extracts all HLS stream URLs via JS.
        if (streamUrls == null) {
            AndroidView(
                factory = { ctx ->
                    WebView.setWebContentsDebuggingEnabled(true)
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.userAgentString =
                            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

                        addJavascriptInterface(
                            object {
                                @JavascriptInterface
                                fun streamFound(payload: String) {
                                    if (payload.isNotEmpty()) {
                                        streamChannel.trySend(payload)
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

        // ExoPlayer once the stream URLs are resolved. All parts are queued; ExoPlayer
        // auto-advances to the next when each one ends.
        streamUrls?.let { urls ->
            val player = remember(urls) {
                ExoPlayer.Builder(context).build().apply {
                    setMediaItems(urls.map { MediaItem.fromUri(it) })
                    prepare()
                    playWhenReady = true
                }
            }

            DisposableEffect(player) {
                // Listen for automatic half transitions to show the banner.
                val listener = object : Player.Listener {
                    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                        val idx = player.currentMediaItemIndex
                        currentHalfIndex = idx
                        if (urls.size > 1 && reason != Player.MEDIA_ITEM_TRANSITION_REASON_SEEK) {
                            halfBanner = "Now Playing: ${halfLabel(idx, urls.size)}"
                        }
                    }
                }
                player.addListener(listener)
                onDispose {
                    player.removeListener(listener)
                    player.release()
                }
            }

            LaunchedEffect(player) {
                while (true) {
                    isPlaying = player.isPlaying
                    positionMs = player.currentPosition.coerceAtLeast(0)
                    durationMs = player.duration.coerceAtLeast(0)
                    delay(200)
                }
            }

            LaunchedEffect(urls) { onInteraction() }

            AndroidView(
                factory = { ctx ->
                    val view = LayoutInflater.from(ctx)
                        .inflate(R.layout.video_player_view, null) as PlayerView
                    view.player = player
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
                halfCount = urls.size,
                currentHalfIndex = currentHalfIndex,
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
                onSwitchHalf = { idx ->
                    onInteraction()
                    if (idx != currentHalfIndex) {
                        player.seekToDefaultPosition(idx)
                        currentHalfIndex = idx
                        halfBanner = "Now Playing: ${halfLabel(idx, urls.size)}"
                    }
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

        // Top bar
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

        // Half-switch banner — shown briefly on auto-advance or manual switch.
        AnimatedVisibility(
            visible = halfBanner != null,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 80.dp),
            enter = fadeIn() + slideInVertically { -it },
            exit = fadeOut() + slideOutVertically { -it }
        ) {
            halfBanner?.let { msg ->
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(ACCENT_GREEN.copy(alpha = 0.92f))
                        .padding(horizontal = 20.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null,
                        tint = Color.White, modifier = Modifier.size(14.dp))
                    Text(msg, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

// MARK: - Custom playback controls

@Composable
private fun VideoControls(
    visible: Boolean,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    halfCount: Int,
    currentHalfIndex: Int,
    onPlayPause: () -> Unit,
    onSeekBy: (Long) -> Unit,
    onSwitchHalf: (Int) -> Unit,
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
        // Half-switch buttons — only visible when match has multiple parts.
        if (halfCount > 1) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                for (idx in 0 until halfCount) {
                    val isSelected = idx == currentHalfIndex
                    val label = halfLabel(idx, halfCount)
                    TvIconButton(
                        onClick = { onSwitchHalf(idx) },
                        colors = IconButtonDefaults.colors(
                            containerColor = if (isSelected) ACCENT_GREEN else Color.White.copy(alpha = 0.12f),
                            contentColor = if (isSelected) Color.Black else Color.White,
                            focusedContainerColor = if (isSelected) ACCENT_GREEN else Color.White.copy(alpha = 0.28f),
                            focusedContentColor = if (isSelected) Color.Black else Color.White
                        ),
                        modifier = Modifier.padding(horizontal = 6.dp)
                    ) {
                        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

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

// JS adapted from VideoPlayerView.swift — extracts ALL playlist parts and reports as JSON array.

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

    function report(urls) {
        if (reported || !urls || !urls.length) return;
        reported = true;
        if (fallbackTimer) clearTimeout(fallbackTimer);
        window.Android.streamFound(JSON.stringify(urls));
    }

    function extractFromPlaylist() {
        if (reported) return false;
        try {
            var m = document.documentElement.innerHTML.match(/var playlist = (\[[\s\S]*?\]);/);
            if (!m) return false;
            var items = JSON.parse(m[1]);
            if (!items || !items.length) return false;
            var urls = [];
            for (var i = 0; i < items.length; i++) {
                if (!items[i].file) continue;
                var url = window.atob(String(items[i].file).replace(/\s/g, ''));
                if (url && url.indexOf('http') === 0) urls.push(url);
            }
            if (!urls.length) return false;
            report(urls);
            return true;
        } catch(e) { return false; }
    }

    function extractURL(p) {
        if (reported) return;
        try {
            var item = p.getPlaylistItem();
            if (item && item.file) { report([item.file]); return; }
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
