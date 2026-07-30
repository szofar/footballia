import SwiftUI
import WebKit
import AVKit

// MARK: - Full-screen overlay

struct VideoPlayerOverlay: View {
    let match: Match
    let onClose: () -> Void

    @State private var nativeStreamURL: URL?
    @State private var isLoading = true
    #if os(macOS)
    @State private var avPlayerView: AVPlayerView? = nil
    // Holds the controller alive for the duration of fullscreen playback.
    @State private var fsController: VideoFullScreenController? = nil
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ZStack {
                    // Only keep the web view in the hierarchy while we still need it.
                    // Removing it once the native URL is found eliminates cursor bleed-through
                    // from the underlying web content and prevents any accidental ad interaction.
                    if nativeStreamURL == nil, let pageURL = match.matchPageURL {
                        WebVideoPlayer(
                            url: pageURL,
                            onPageLoaded: {
                                Task {
                                    try? await Task.sleep(for: .seconds(5))
                                    if nativeStreamURL == nil { isLoading = false }
                                }
                            },
                            onStreamURL: { url in
                                guard nativeStreamURL == nil else { return }
                                nativeStreamURL = url
                                isLoading = false
                            }
                        )
                    }

                    if let streamURL = nativeStreamURL {
                        #if os(macOS)
                        NativeVideoPlayer(url: streamURL) { view in
                            avPlayerView = view
                        }
                        .transition(.opacity)
                        #else
                        NativeVideoPlayer(url: streamURL)
                            .transition(.opacity)
                        #endif
                    }

                    if isLoading {
                        loadingView.transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: isLoading)
                .animation(.easeInOut(duration: 0.4), value: nativeStreamURL != nil)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.65))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 3) {
                Text(match.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(match.competition)  ·  \(match.stage)  ·  \(match.date)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.38))
            }

            Spacer()

            // Invisible mirror keeps title centred; fullscreen button overlaid on macOS
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                Text("Library")
            }
            .font(.system(size: 14))
            .opacity(0)
            .overlay(alignment: .trailing) {
                #if os(macOS)
                Button {
                    guard let playerView = avPlayerView, let player = playerView.player else { return }
                    fsController = VideoFullScreenController(player: player, inlineView: playerView)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(avPlayerView != nil ? 0.65 : 0.2))
                }
                .buttonStyle(.plain)
                .disabled(avPlayerView == nil)
                #endif
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.green)
            Text("Loading match…")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - macOS fullscreen controller

#if os(macOS)

/// Self-contained AppKit controller for fullscreen video.
/// Owns the window, the fullscreen AVPlayerView, the key monitor, and the player
/// reference — nothing is read back from SwiftUI during teardown, which is the
/// cause of the use-after-free crashes seen with the NSHostingView approach.
final class VideoFullScreenController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private let player: AVPlayer
    private var fullScreenView: AVPlayerView?
    private weak var inlineView: AVPlayerView?

    init(player: AVPlayer, inlineView: AVPlayerView) {
        self.player = player
        self.inlineView = inlineView
        super.init()
        present(on: inlineView)
    }

    private func present(on inlineView: AVPlayerView) {
        guard let screen = NSScreen.main else { return }
        let bounds = CGRect(origin: .zero, size: screen.frame.size)

        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]

        // Detach the AVPlayer from the inline view and hand it to the fullscreen view.
        inlineView.player = nil
        let fsView = AVPlayerView(frame: bounds)
        fsView.player = player
        fsView.controlsStyle = .floating
        fsView.autoresizingMask = [.width, .height]
        self.fullScreenView = fsView

        // Plain NSView container — no SwiftUI hosting in the z-order where the
        // close button lives, so we never close the window from within a SwiftUI
        // action handler (which caused the objc_release crash).
        let container = NSView(frame: bounds)
        container.addSubview(fsView)

        // Close button: a minimal NSButton so teardown is purely AppKit.
        let btn = makeExitButton(screenHeight: screen.frame.size.height)
        container.addSubview(btn)

        let w = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Level above NSMainMenuWindowLevel (24) so the window sits over the
        // menu bar even when it briefly auto-shows at the screen edge.
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        w.backgroundColor = .black
        w.isOpaque = true
        w.contentView = container
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        self.window = w

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }
    }

    private func makeExitButton(screenHeight: CGFloat) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 18, y: screenHeight - 50, width: 152, height: 32))
        btn.title = "⤡  Exit Fullscreen"
        btn.bezelStyle = .rounded
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        btn.layer?.cornerRadius = 16
        btn.contentTintColor = .white
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(dismiss)
        return btn
    }

    @objc func dismiss() {
        guard let w = window else { return }
        window = nil           // block re-entry before anything async runs

        NSApp.presentationOptions = []

        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }

        // Return the player to the inline view synchronously.
        fullScreenView?.player = nil
        fullScreenView = nil
        inlineView?.player = player

        // Defer the actual NSWindow.close() to the next run-loop turn.
        // Calling close() synchronously from within an NSButton action that lives
        // inside this window's contentView can corrupt AppKit's event-dispatch
        // state (objc_release crash). Dispatching async avoids that entirely.
        DispatchQueue.main.async { w.close() }
    }

    // NSWindowDelegate: safety net if the window is closed by other means.
    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        dismiss()
    }
}

#endif

// MARK: - Shared coordinator

final class VideoPlayerCoordinator: NSObject, WKNavigationDelegate {
    private let url: URL
    private let onPageLoaded: (() -> Void)?
    private let onStreamURL: ((URL) -> Void)?
    private var reportedURL = false

    init(url: URL, onPageLoaded: (() -> Void)?, onStreamURL: ((URL) -> Void)?) {
        self.url = url
        self.onPageLoaded = onPageLoaded
        self.onStreamURL = onStreamURL
    }

    func buildWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif

        let handler = WeakMessageHandler(coordinator: self)
        config.userContentController.add(handler, name: "streamFound")

        let hideScript = WKUserScript(
            source: JS.hideChrome,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(hideScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = JS.userAgent
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        webView.navigationDelegate = self

        Task { @MainActor in
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in HTTPCookieStorage.shared.cookies ?? [] {
                await store.setCookie(cookie)
            }
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme ?? ""
        let host   = url.host   ?? ""
        let allowed = scheme == "about" ||
                      host.hasSuffix("footballia.eu") ||
                      host.hasSuffix("footballia.net")
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPageLoaded?()
        webView.evaluateJavaScript(JS.autoPlay, completionHandler: nil)
    }

    func handleMessage(_ urlString: String) {
        guard !reportedURL,
              !urlString.hasPrefix("blob:"),
              let url = URL(string: urlString) else { return }
        reportedURL = true
        DispatchQueue.main.async { self.onStreamURL?(url) }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var coordinator: VideoPlayerCoordinator?
    init(coordinator: VideoPlayerCoordinator) { self.coordinator = coordinator }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "streamFound", let body = message.body as? String {
            coordinator?.handleMessage(body)
        }
    }
}

// MARK: - Platform-specific view wrappers

#if os(macOS)

struct WebVideoPlayer: NSViewRepresentable {
    let url: URL
    var onPageLoaded: (() -> Void)? = nil
    var onStreamURL: ((URL) -> Void)? = nil

    func makeCoordinator() -> VideoPlayerCoordinator {
        VideoPlayerCoordinator(url: url, onPageLoaded: onPageLoaded, onStreamURL: onStreamURL)
    }

    func makeNSView(context: Context) -> WKWebView { context.coordinator.buildWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}

struct NativeVideoPlayer: NSViewRepresentable {
    let url: URL
    var onReady: ((AVPlayerView) -> Void)? = nil

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        let player = AVPlayer(url: url)
        view.player = player
        view.controlsStyle = .floating
        player.play()
        DispatchQueue.main.async { self.onReady?(view) }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

#else

struct WebVideoPlayer: UIViewRepresentable {
    let url: URL
    var onPageLoaded: (() -> Void)? = nil
    var onStreamURL: ((URL) -> Void)? = nil

    func makeCoordinator() -> VideoPlayerCoordinator {
        VideoPlayerCoordinator(url: url, onPageLoaded: onPageLoaded, onStreamURL: onStreamURL)
    }

    func makeUIView(context: Context) -> WKWebView { context.coordinator.buildWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

#endif

// MARK: - Injected JavaScript

private enum JS {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static let hideChrome = """
    (function() {
        var s = document.createElement('style');
        s.textContent = `
            header.header-block,
            nav.nav-bottom,
            .top-advertisements,
            .breadcrumbs,
            .description.m-t,
            .side-col,
            footer.footer-block,
            .comments,
            .details,
            .social_links,
            .formations_images,
            .modal,
            #taboola-custom-widget,
            [id^="bg-ssp"],
            [id^="gpt-"],
            .alert-success,
            .alert-warning
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
    """

    static let autoPlay = """
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
                    window.webkit.messageHandlers.streamFound.postMessage(item.file);
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
    """
}
