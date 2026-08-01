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

// MARK: tvOS native player — fully custom controls

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> TVVideoPlayerViewController {
        TVVideoPlayerViewController(url: url, onClose: onClose)
    }

    func updateUIViewController(_ vc: TVVideoPlayerViewController, context: Context) {}
}

// Parent VC: owns AVPlayerViewController (no system controls) + TVControlsOverlay + all input handling.
final class TVVideoPlayerViewController: UIViewController {
    private let url: URL
    private let onClose: () -> Void

    private var playerVC: AVPlayerViewController!
    private var player: AVPlayer!
    private var controls: TVControlsOverlay!
    private var timeObserver: Any?

    // Controls auto-hide
    private var controlsVisible = false
    private var hideTimer: Timer?

    // Hold-to-seek
    private var holdTimer: Timer?
    private var holdStart: Date?
    private var holdDirection: Int = 0  // -1 or +1

    init(url: URL, onClose: @escaping () -> Void) {
        self.url = url
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayer()
        setupControls()
        setupSwipeGestures()
    }

    private func setupPlayer() {
        player = AVPlayer(url: url)

        playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = false

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)

        // Periodic time updates → controls progress bar
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let item = self.player.currentItem,
                  item.duration.isNumeric else { return }
            self.controls.update(
                current: time.seconds,
                duration: item.duration.seconds,
                isPlaying: self.player.timeControlStatus == .playing
            )
        }

        player.play()
    }

    private func setupControls() {
        controls = TVControlsOverlay(frame: view.bounds)
        controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controls.alpha = 0
        controls.onBack      = { [weak self] in self?.onClose() }
        controls.onPlayPause = { [weak self] in self?.togglePlayPause() }
        controls.onRewind    = { [weak self] in self?.seek(by: -10) }
        controls.onForward   = { [weak self] in self?.seek(by:  10) }
        view.addSubview(controls)
    }

    // Touchpad horizontal swipes → ±30 s
    private func setupSwipeGestures() {
        let left  = UISwipeGestureRecognizer(target: self, action: #selector(swipedLeft))
        left.direction = .left
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swipedRight))
        right.direction = .right
        view.addGestureRecognizer(left)
        view.addGestureRecognizer(right)
    }

    // MARK: - Playback

    private func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
        controls.setPlaying(player.timeControlStatus == .playing)
        resetHideTimer()
    }

    private func seek(by seconds: Double) {
        let current  = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        let target   = max(0, min(current + seconds, duration))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        resetHideTimer()
    }

    // MARK: - Controls visibility

    private func showControls() {
        controlsVisible = true
        UIView.animate(withDuration: 0.2) { self.controls.alpha = 1 }
        resetHideTimer()
    }

    private func hideControls() {
        controlsVisible = false
        hideTimer?.invalidate()
        hideTimer = nil
        UIView.animate(withDuration: 0.2) { self.controls.alpha = 0 }
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    // MARK: - Swipe handlers

    @objc private func swipedLeft()  { seek(by: -30); if !controlsVisible { showControls() } }
    @objc private func swipedRight() { seek(by:  30); if !controlsVisible { showControls() } }

    // MARK: - Remote press handling

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { super.pressesBegan(presses, with: event); return }
        switch press.type {

        case .menu:
            if controlsVisible { hideControls() } else { onClose() }

        case .select:
            if controlsVisible { togglePlayPause() } else { showControls() }

        case .playPause:
            togglePlayPause()

        case .leftArrow:
            if !controlsVisible { showControls() }
            seek(by: -10)
            beginHold(direction: -1)

        case .rightArrow:
            if !controlsVisible { showControls() }
            seek(by: 10)
            beginHold(direction: 1)

        default:
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .leftArrow || $0.type == .rightArrow }) { endHold() }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .leftArrow || $0.type == .rightArrow }) { endHold() }
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - Progressive hold seek

    private func beginHold(direction: Int) {
        holdDirection = direction
        holdStart = Date()
        holdTimer?.invalidate()
        // Pause 0.5 s before repeating kicks in (distinguishes tap from hold)
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.repeatSeek()
        }
    }

    private func repeatSeek() {
        guard holdDirection != 0 else { return }
        let elapsed = Date().timeIntervalSince(holdStart ?? Date())
        // Skip amount grows with hold duration
        let skip: Double = elapsed < 2 ? 30 : elapsed < 5 ? 60 : 120
        seek(by: Double(holdDirection) * skip)
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.repeatSeek()
        }
    }

    private func endHold() {
        holdTimer?.invalidate(); holdTimer = nil
        holdDirection = 0; holdStart = nil
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        holdTimer?.invalidate()
        hideTimer?.invalidate()
    }
}

// MARK: - Custom controls overlay

final class TVControlsOverlay: UIView {
    var onBack:      (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onRewind:    (() -> Void)?
    var onForward:   (() -> Void)?

    private let backButton      = UIButton(type: .system)
    private let rewindButton    = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton   = UIButton(type: .system)
    private let progressTrack   = UIView()
    private let progressFill    = UIView()
    private let currentLabel    = UILabel()
    private let durationLabel   = UILabel()

    private var fillWidthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        backgroundColor = UIColor.black.withAlphaComponent(0.52)

        // — Back button (top-left) —
        var bc = UIButton.Configuration.plain()
        bc.image = UIImage(systemName: "chevron.left")
        bc.title = "Back"
        bc.baseForegroundColor = .white
        bc.imagePadding = 8
        bc.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        backButton.configuration = bc
        backButton.addTarget(self, action: #selector(backTapped), for: .primaryActionTriggered)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backButton)

        // — Center control row: rewind | play/pause | forward —
        configureIconButton(rewindButton,    systemName: "gobackward.10",  size: 38)
        configureIconButton(playPauseButton, systemName: "play.fill",      size: 54)
        configureIconButton(forwardButton,   systemName: "goforward.10",   size: 38)

        rewindButton.addTarget(self,    action: #selector(rewindTapped),    for: .primaryActionTriggered)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .primaryActionTriggered)
        forwardButton.addTarget(self,   action: #selector(forwardTapped),   for: .primaryActionTriggered)

        let centerStack = UIStackView(arrangedSubviews: [rewindButton, playPauseButton, forwardButton])
        centerStack.axis = .horizontal
        centerStack.spacing = 80
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerStack)

        // — Progress bar —
        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        progressTrack.layer.cornerRadius = 3
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressTrack)

        progressFill.backgroundColor = .white
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        fillWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)

        // — Time labels —
        styleLabel(currentLabel,  size: 28, alpha: 1.0)
        styleLabel(durationLabel, size: 28, alpha: 0.55)
        currentLabel.text  = "0:00"
        durationLabel.text = "0:00"

        NSLayoutConstraint.activate([
            // Back button
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 60),

            // Center controls — vertically centred, offset slightly above middle
            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),

            // Current time label — bottom-left
            currentLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 60),
            currentLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -60),

            // Duration label — bottom-right
            durationLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -60),
            durationLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -60),

            // Progress track — between the two time labels
            progressTrack.leadingAnchor.constraint(equalTo: currentLabel.trailingAnchor, constant: 24),
            progressTrack.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -24),
            progressTrack.centerYAnchor.constraint(equalTo: currentLabel.centerYAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 6),

            // Progress fill — pinned to track's left, height matches track
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidthConstraint,
        ])
    }

    // MARK: - Update

    func update(current: Double, duration: Double, isPlaying: Bool) {
        currentLabel.text  = format(current)
        durationLabel.text = format(duration)
        setPlaying(isPlaying)

        // Update fill bar after layout so bounds are valid
        setNeedsLayout()
        layoutIfNeeded()
        let ratio = duration > 0 ? min(max(current / duration, 0), 1) : 0
        fillWidthConstraint.constant = progressTrack.bounds.width * CGFloat(ratio)
    }

    func setPlaying(_ playing: Bool) {
        var cfg = playPauseButton.configuration
        cfg?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill")
        playPauseButton.configuration = cfg
    }

    // MARK: - Helpers

    private func configureIconButton(_ button: UIButton, systemName: String, size: CGFloat) {
        var cfg = UIButton.Configuration.plain()
        cfg.image = UIImage(systemName: systemName)
        cfg.baseForegroundColor = .white
        cfg.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        button.configuration = cfg
    }

    private func styleLabel(_ label: UILabel, size: CGFloat, alpha: CGFloat) {
        label.font = .monospacedDigitSystemFont(ofSize: size, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(alpha)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    @objc private func backTapped()      { onBack?() }
    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func rewindTapped()    { onRewind?() }
    @objc private func forwardTapped()   { onForward?() }
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
