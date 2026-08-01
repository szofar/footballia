import SwiftUI
#if !os(tvOS)
import WebKit
#endif
import AVKit

// MARK: - Full-screen overlay

struct VideoPlayerOverlay: View {
    let match: Match
    let onClose: () -> Void

    @State private var nativeStreamURL: URL?
    @State private var isLoading = true
    #if os(macOS)
    @State private var avPlayerView: AVPlayerView? = nil
    @State private var fsController: VideoFullScreenController? = nil
    #elseif os(iOS)
    @State private var isFullScreen = false
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        regularBody
        #endif
    }

    // MARK: tvOS body — no top bar so AVPlayerViewController receives full focus
    #if os(tvOS)
    private var tvBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZStack {
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
                    NativeVideoPlayer(url: streamURL, onClose: onClose)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if isLoading {
                    loadingView.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isLoading)
            .animation(.easeInOut(duration: 0.4), value: nativeStreamURL != nil)
        }
    }
    #endif

    // MARK: macOS + iOS body
    #if !os(tvOS)
    private var regularBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            if isFullScreen {
                ZStack(alignment: .topLeading) {
                    sharedVideoContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()

                    Button(action: { isFullScreen = false }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(10)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 54)
                    .padding(.leading, 16)
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    sharedVideoContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #else
            VStack(spacing: 0) {
                topBar
                sharedVideoContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #endif
        }
        #if os(iOS)
        .ignoresSafeArea(edges: isFullScreen ? .all : [])
        .statusBarHidden(isFullScreen)
        #endif
    }

    private var sharedVideoContent: some View {
        ZStack {
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
    #endif

    // MARK: Top bar (macOS + iOS only)
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

            // Invisible mirror keeps title centred; fullscreen button overlaid
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
                #elseif os(iOS)
                Button { isFullScreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
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

        inlineView.player = nil
        let fsView = AVPlayerView(frame: bounds)
        fsView.player = player
        fsView.controlsStyle = .floating
        fsView.autoresizingMask = [.width, .height]
        self.fullScreenView = fsView

        let container = NSView(frame: bounds)
        container.addSubview(fsView)

        let btn = makeExitButton(screenHeight: screen.frame.size.height)
        container.addSubview(btn)

        let w = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        window = nil

        NSApp.presentationOptions = []

        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }

        fullScreenView?.player = nil
        fullScreenView = nil
        inlineView?.player = player

        DispatchQueue.main.async { w.close() }
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        dismiss()
    }
}

#endif

// MARK: - Shared WebView coordinator (macOS + iOS)

#if !os(tvOS)
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
#endif

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

#elseif os(iOS)

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
        vc.videoGravity = .resizeAspect
        vc.showsPlaybackControls = true
        let player = AVPlayer(url: url)
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}

#else

// MARK: tvOS — WebKit not available; extract stream URL from raw HTML

struct WebVideoPlayer: View {
    let url: URL
    var onPageLoaded: (() -> Void)? = nil
    var onStreamURL: ((URL) -> Void)? = nil

    var body: some View {
        Color.clear.task { await fetchStream() }
    }

    private func fetchStream() async {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.setValue(JS.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            onPageLoaded?(); return
        }
        onPageLoaded?()

        if let streamURL = extractStreamURL(from: html) {
            onStreamURL?(streamURL)
        }
    }

    private func extractStreamURL(from html: String) -> URL? {
        if let url = extractBase64URL(from: html, pattern: #"new Video\(["']([A-Za-z0-9+/=\s]+)["']\)"#) {
            return url
        }
        if let url = extractBase64URL(from: html, pattern: #"atob\(["']([A-Za-z0-9+/=\s]+)["']\)"#) {
            return url
        }
        return extractDirectM3U8URL(from: html)
    }

    private func extractBase64URL(from html: String, pattern: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }

        let b64 = String(html[range]).components(separatedBy: .whitespacesAndNewlines).joined()
        guard let decoded = Data(base64Encoded: b64),
              let urlString = String(data: decoded, encoding: .utf8),
              !urlString.hasPrefix("blob:"),
              let url = URL(string: urlString) else { return nil }
        return url
    }

    private func extractDirectM3U8URL(from html: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>]+\.m3u8[^\s"'<>]*"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 0), in: html),
              let url = URL(string: String(html[range])) else { return nil }
        return url
    }
}

// MARK: tvOS native player — custom VC so AVPlayerViewController owns the focus

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> TVVideoPlayerViewController {
        TVVideoPlayerViewController(url: url, onClose: onClose)
    }

    func updateUIViewController(_ vc: TVVideoPlayerViewController, context: Context) {}
}

final class TVVideoPlayerViewController: UIViewController {
    private let url: URL
    private let onClose: () -> Void
    private var playerVC: AVPlayerViewController!

    init(url: URL, onClose: @escaping () -> Void) {
        self.url = url
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let player = AVPlayer(url: url)
        playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true

        // Back button shown/hidden in sync with the transport controls overlay
        playerVC.customOverlayViewController = TVBackButtonViewController { [weak self] in
            self?.onClose()
        }

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)

        player.play()
    }

    // Intercept the remote's menu/back button to dismiss the player
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            onClose()
        } else {
            super.pressesBegan(presses, with: event)
        }
    }
}

final class TVBackButtonViewController: UIViewController {
    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.left")
        config.title = "Back"
        config.baseForegroundColor = .white
        config.imagePadding = 8
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(backTapped), for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 60)
        ])
    }

    @objc private func backTapped() { onBack() }
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
