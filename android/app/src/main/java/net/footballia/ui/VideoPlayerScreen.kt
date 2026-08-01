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
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import net.footballia.data.Match

private const val STREAM_TIMEOUT_MS = 25_000L
private const val CONTROLLER_TIMEOUT_MS = 7_000

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(match: Match, onClose: () -> Unit) {
    val context = LocalContext.current
    val streamChannel = remember { Channel<String>(Channel.CONFLATED) }
    var streamUrl by remember { mutableStateOf<String?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadFailed by remember { mutableStateOf(false) }
    var controlsVisible by remember { mutableStateOf(false) }

    // Remote's back button exits the video instead of navigating within it.
    BackHandler(onBack = onClose)

    // Receive stream URL from JS bridge on the main coroutine. Give up after a
    // timeout instead of spinning forever if the page never yields a stream.
    LaunchedEffect(Unit) {
        val url = withTimeoutOrNull(STREAM_TIMEOUT_MS) { streamChannel.receive() }
        if (url != null) streamUrl = url else loadFailed = true
        isLoading = false
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {

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

            AndroidView(
                factory = { ctx ->
                    // Inflated from XML so the PlayerView uses a TextureView surface
                    // (see res/layout/video_player_view.xml) — a SurfaceView would
                    // render behind the Compose overlay and show only black.
                    val view = LayoutInflater.from(ctx)
                        .inflate(R.layout.video_player_view, null) as PlayerView
                    view.player = player
                    // Standard play/pause/seek controls, shown on D-pad center press
                    // (built into PlayerView for TV) and auto-hidden after 7s idle.
                    view.controllerShowTimeoutMs = CONTROLLER_TIMEOUT_MS
                    view.setControllerVisibilityListener(
                        PlayerView.ControllerVisibilityListener { visibility ->
                            controlsVisible = visibility == android.view.View.VISIBLE
                        }
                    )
                    view
                },
                update = { view ->
                    view.player = player
                    // requestFocus() in factory() can no-op if the view isn't attached
                    // to the window yet; update() reliably runs after attachment.
                    if (!view.hasFocus()) view.requestFocus()
                },
                modifier = Modifier.fillMaxSize()
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
                        CircularProgressIndicator(color = Color(0xFF22C55E))
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
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.7f))
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

    function extractURL(p) {
        if (reported) return;
        try {
            var item = p.getPlaylistItem();
            if (item && item.file) {
                reported = true;
                if (fallbackTimer) clearTimeout(fallbackTimer);
                window.Android.streamFound(item.file);
            }
        } catch(e) {}
    }

    function tryStart() {
        if (typeof jwplayer === 'undefined') return false;
        var p = jwplayer('jwplayer');
        if (!p || typeof p.getState !== 'function') return false;
        var col = document.querySelector('#match .col-md-7');
        if (col) col.className = col.className.replace('col-md-7', 'col-md-12');
        p.resize(document.documentElement.clientWidth, window.innerHeight);
        extractURL(p);
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
            p.resize(document.documentElement.clientWidth, window.innerHeight);
            extractURL(p);
        });
    } catch(e) {}

    var tries = 0;
    var poll = setInterval(function() {
        tries++;
        if (tries > 40) { clearInterval(poll); return; }
        if (tryStart() && reported) clearInterval(poll);
    }, 250);
})();
""".trimIndent()
