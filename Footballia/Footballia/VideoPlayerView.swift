import SwiftUI
#if !os(tvOS)
import WebKit
#endif
import AVKit

// MARK: - Full-screen overlay

struct VideoPlayerOverlay: View {
    let match: Match
    let onClose: () -> Void

    @State private var streamURLs: [URL] = []
    @State private var currentHalfIndex: Int = 0
    @State private var isLoading = true
    @State private var halfBanner: String? = nil

    private var currentStreamURL: URL? {
        streamURLs.indices.contains(currentHalfIndex) ? streamURLs[currentHalfIndex] : nil
    }

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
                if streamURLs.isEmpty, let pageURL = match.matchPageURL {
                    WebVideoPlayer(
                        url: pageURL,
                        onPageLoaded: {
                            Task {
                                try? await Task.sleep(for: .seconds(5))
                                if streamURLs.isEmpty { isLoading = false }
                            }
                        },
                        onStreamURLs: { urls in
                            guard streamURLs.isEmpty else { return }
                            streamURLs = urls
                            isLoading = false
                        }
                    )
                }

                if !streamURLs.isEmpty {
                    NativeVideoPlayer(urls: streamURLs, onClose: onClose)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if isLoading {
                    loadingView.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isLoading)
            .animation(.easeInOut(duration: 0.4), value: streamURLs.isEmpty)
        }
    }
    #endif

    // MARK: macOS + iOS body
    #if !os(tvOS)
    private var regularBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                sharedVideoContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { ScreenSleepBlocker.shared.begin() }
        .onDisappear { ScreenSleepBlocker.shared.end() }
    }

    private var sharedVideoContent: some View {
        ZStack {
            if streamURLs.isEmpty, let pageURL = match.matchPageURL {
                WebVideoPlayer(
                    url: pageURL,
                    onPageLoaded: {
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            if streamURLs.isEmpty { isLoading = false }
                        }
                    },
                    onStreamURLs: { urls in
                        guard streamURLs.isEmpty else { return }
                        streamURLs = urls
                        isLoading = false
                    }
                )
            }

            if let streamURL = currentStreamURL {
                NativeVideoPlayer(
                    url: streamURL,
                    onVideoEnd: streamURLs.count > 1 ? { advanceHalf() } : nil
                )
                .id(streamURL)
                .transition(.opacity)
            }

            if isLoading {
                loadingView.transition(.opacity)
            }

            if let banner = halfBanner {
                halfTransitionBanner(banner)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isLoading)
        .animation(.easeInOut(duration: 0.4), value: currentHalfIndex)
        .animation(.easeInOut(duration: 0.3), value: halfBanner != nil)
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

            // Half-switch buttons — only shown when the match has multiple parts.
            if streamURLs.count > 1 {
                HStack(spacing: 6) {
                    ForEach(streamURLs.indices, id: \.self) { idx in
                        Button(action: { switchToHalf(idx) }) {
                            Text(halfLabel(for: idx, total: streamURLs.count))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(currentHalfIndex == idx ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(currentHalfIndex == idx
                                              ? Color.green
                                              : Color.white.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Invisible mirror of the back button keeps the title centred.
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("Library")
                }
                .font(.system(size: 14))
                .opacity(0)
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

    private func halfTransitionBanner(_ message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.green.opacity(0.9)))
            .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Half management

    private func advanceHalf() {
        guard currentHalfIndex + 1 < streamURLs.count else { return }
        switchToHalf(currentHalfIndex + 1)
    }

    private func switchToHalf(_ index: Int) {
        guard index != currentHalfIndex, streamURLs.indices.contains(index) else { return }
        currentHalfIndex = index
        let label = halfLabel(for: index, total: streamURLs.count)
        withAnimation { halfBanner = "Now Playing: \(label)" }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { halfBanner = nil }
        }
    }

    private func halfLabel(for index: Int, total: Int) -> String {
        total == 2 ? (index == 0 ? "1st Half" : "2nd Half") : "Part \(index + 1)"
    }
}

// MARK: - Screen sleep

#if !os(tvOS)
/// Keeps the display awake for the lifetime of the player overlay.
///
/// The stream is fed to AVPlayer from a WebView-extracted URL rather than being played by the
/// system's own media pipeline in a way it associates with the app being "active", so neither
/// platform reliably infers that video is on screen — the display would dim and sleep mid-match.
/// Reference-counted because the overlay can be re-created (e.g. on a stream retry) before the
/// outgoing instance's `onDisappear` runs.
@MainActor
final class ScreenSleepBlocker {
    static let shared = ScreenSleepBlocker()
    private var count = 0
    #if os(macOS)
    private var activity: NSObjectProtocol?
    #endif

    private init() {}

    func begin() {
        count += 1
        guard count == 1 else { return }
        #if os(macOS)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Playing a match"
        )
        #else
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    func end() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        #if os(macOS)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        #else
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }
}
#endif

// MARK: - Shared WebView coordinator (macOS + iOS)

#if !os(tvOS)
final class VideoPlayerCoordinator: NSObject, WKNavigationDelegate {
    private let url: URL
    private let onPageLoaded: (() -> Void)?
    private let onStreamURLs: (([URL]) -> Void)?
    private var reported = false

    init(url: URL, onPageLoaded: (() -> Void)?, onStreamURLs: (([URL]) -> Void)?) {
        self.url = url
        self.onPageLoaded = onPageLoaded
        self.onStreamURLs = onStreamURLs
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

    func handleMessage(_ body: String) {
        guard !reported else { return }

        let urls: [URL]
        if body.hasPrefix("["),
           let data = body.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            urls = array.compactMap { str in
                guard !str.hasPrefix("blob:"), let url = URL(string: str) else { return nil }
                return url
            }
        } else if !body.hasPrefix("blob:"), let url = URL(string: body) {
            urls = [url]
        } else {
            return
        }

        guard !urls.isEmpty else { return }
        reported = true
        DispatchQueue.main.async { self.onStreamURLs?(urls) }
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
    var onStreamURLs: (([URL]) -> Void)? = nil

    func makeCoordinator() -> VideoPlayerCoordinator {
        VideoPlayerCoordinator(url: url, onPageLoaded: onPageLoaded, onStreamURLs: onStreamURLs)
    }

    func makeNSView(context: Context) -> WKWebView { context.coordinator.buildWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}

struct NativeVideoPlayer: NSViewRepresentable {
    let url: URL
    var onVideoEnd: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        let player = AVPlayer(url: url)
        view.player = player
        view.controlsStyle = .floating
        player.play()
        context.coordinator.observe(player: player, onEnd: onVideoEnd)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(player: AVPlayer, onEnd: (() -> Void)?) {
            guard let onEnd else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in onEnd() }
        }

        deinit {
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        }
    }
}

#elseif os(iOS)

struct WebVideoPlayer: UIViewRepresentable {
    let url: URL
    var onPageLoaded: (() -> Void)? = nil
    var onStreamURLs: (([URL]) -> Void)? = nil

    func makeCoordinator() -> VideoPlayerCoordinator {
        VideoPlayerCoordinator(url: url, onPageLoaded: onPageLoaded, onStreamURLs: onStreamURLs)
    }

    func makeUIView(context: Context) -> WKWebView { context.coordinator.buildWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    var onVideoEnd: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.videoGravity = .resizeAspect
        vc.showsPlaybackControls = true
        let player = AVPlayer(url: url)
        vc.player = player
        player.play()
        context.coordinator.observe(player: player, onEnd: onVideoEnd)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(player: AVPlayer, onEnd: (() -> Void)?) {
            guard let onEnd else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in onEnd() }
        }

        deinit {
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        }
    }
}

#else

// MARK: tvOS — WebKit not available; extract all stream URLs from raw HTML

struct WebVideoPlayer: View {
    let url: URL
    var onPageLoaded: (() -> Void)? = nil
    var onStreamURLs: (([URL]) -> Void)? = nil

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

        let urls = extractAllStreamURLs(from: html)
        if !urls.isEmpty { onStreamURLs?(urls) }
    }

    private func extractAllStreamURLs(from html: String) -> [URL] {
        if let urls = extractPlaylistURLs(from: html), !urls.isEmpty { return urls }
        if let url = extractBase64URL(from: html, pattern: #"new Video\(["']([A-Za-z0-9+/=\s]+)["']\)"#) { return [url] }
        if let url = extractBase64URL(from: html, pattern: #"atob\(["']([A-Za-z0-9+/=\s]+)["']\)"#) { return [url] }
        if let url = extractDirectM3U8URL(from: html) { return [url] }
        return []
    }

    private func extractPlaylistURLs(from html: String) -> [URL]? {
        guard let regex = try? NSRegularExpression(pattern: #"var playlist = (\[[\s\S]*?\]);"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }

        let jsonString = String(html[range])
        guard let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        var urls: [URL] = []
        for item in items {
            guard let file = item["file"] as? String else { continue }
            let b64 = file.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let decoded = Data(base64Encoded: b64),
                  let urlString = String(data: decoded, encoding: .utf8),
                  !urlString.hasPrefix("blob:"),
                  let url = URL(string: urlString) else { continue }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
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

// MARK: tvOS native player — fully custom controls, multi-half support

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let urls: [URL]
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> TVVideoPlayerViewController {
        TVVideoPlayerViewController(urls: urls, onClose: onClose)
    }

    func updateUIViewController(_ vc: TVVideoPlayerViewController, context: Context) {}
}

// Parent VC: owns AVPlayerViewController (no system controls) + TVControlsOverlay + all input handling.
final class TVVideoPlayerViewController: UIViewController {
    private let urls: [URL]
    private let onClose: () -> Void
    private var currentHalfIndex = 0

    private var playerVC: AVPlayerViewController!
    private var player: AVPlayer!
    private var controls: TVControlsOverlay!
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private let halfBannerView = UIView()
    private let halfBannerLabel = UILabel()
    private var halfBannerTimer: Timer?

    // Controls auto-hide
    private var controlsVisible = false
    private var hideTimer: Timer?

    // Hold-to-seek
    private var holdTimer: Timer?
    private var holdStart: Date?
    private var holdDirection: Int = 0  // -1 or +1

    init(urls: [URL], onClose: @escaping () -> Void) {
        self.urls = urls
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        setupPlayerVC()
        loadHalf(at: 0, autoPlay: true)
        setupControls()
        setupHalfBanner()
        setupSwipeGestures()
    }

    // MARK: - Player

    private func setupPlayerVC() {
        playerVC = AVPlayerViewController()
        playerVC.showsPlaybackControls = false
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.didMove(toParent: self)
    }

    private func loadHalf(at index: Int, autoPlay: Bool) {
        guard urls.indices.contains(index) else { return }

        if let obs = endObserver { NotificationCenter.default.removeObserver(obs); endObserver = nil }
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }

        currentHalfIndex = index
        player = AVPlayer(url: urls[index])
        playerVC.player = player

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let item = self.player.currentItem,
                  item.duration.isNumeric else { return }
            self.controls.update(
                current: time.seconds,
                duration: item.duration.seconds,
                isPlaying: self.player.timeControlStatus == .playing,
                halfIndex: self.currentHalfIndex,
                halfCount: self.urls.count
            )
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let next = self.currentHalfIndex + 1
            guard next < self.urls.count else { return }
            self.loadHalf(at: next, autoPlay: true)
            self.showHalfBanner(self.halfLabel(for: next, total: self.urls.count))
        }

        if autoPlay { player.play() }
    }

    // MARK: - Half switching

    func switchToHalf(_ index: Int) {
        guard urls.indices.contains(index), index != currentHalfIndex else { return }
        loadHalf(at: index, autoPlay: true)
        showHalfBanner(halfLabel(for: index, total: urls.count))
    }

    private func halfLabel(for index: Int, total: Int) -> String {
        total == 2 ? (index == 0 ? "1st Half" : "2nd Half") : "Part \(index + 1)"
    }

    // MARK: - Controls setup

    private func setupControls() {
        controls = TVControlsOverlay(frame: view.bounds)
        controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controls.alpha = 0
        controls.onBack      = { [weak self] in self?.onClose() }
        controls.onPlayPause = { [weak self] in self?.togglePlayPause() }
        controls.onRewind    = { [weak self] in self?.seek(by: -10) }
        controls.onForward   = { [weak self] in self?.seek(by:  10) }
        controls.onSwitchHalf = { [weak self] idx in self?.switchToHalf(idx) }
        view.addSubview(controls)
        controls.update(current: 0, duration: 0, isPlaying: true,
                        halfIndex: 0, halfCount: urls.count)
    }

    // MARK: - Half banner

    private func setupHalfBanner() {
        halfBannerView.backgroundColor = UIColor(red: 0.08, green: 0.77, blue: 0.37, alpha: 0.92)
        halfBannerView.layer.cornerRadius = 12
        halfBannerView.alpha = 0
        halfBannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(halfBannerView)

        halfBannerLabel.textColor = .white
        halfBannerLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        halfBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        halfBannerView.addSubview(halfBannerLabel)

        NSLayoutConstraint.activate([
            halfBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            halfBannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            halfBannerLabel.topAnchor.constraint(equalTo: halfBannerView.topAnchor, constant: 14),
            halfBannerLabel.bottomAnchor.constraint(equalTo: halfBannerView.bottomAnchor, constant: -14),
            halfBannerLabel.leadingAnchor.constraint(equalTo: halfBannerView.leadingAnchor, constant: 28),
            halfBannerLabel.trailingAnchor.constraint(equalTo: halfBannerView.trailingAnchor, constant: -28),
        ])
    }

    private func showHalfBanner(_ label: String) {
        halfBannerLabel.text = "Now Playing: \(label)"
        halfBannerTimer?.invalidate()
        UIView.animate(withDuration: 0.3) { self.halfBannerView.alpha = 1 }
        halfBannerTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.halfBannerView.alpha = 0 }
        }
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

    private func setupSwipeGestures() {
        let left  = UISwipeGestureRecognizer(target: self, action: #selector(swipedLeft))
        left.direction = .left
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swipedRight))
        right.direction = .right
        view.addGestureRecognizer(left)
        view.addGestureRecognizer(right)
    }

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
        UIApplication.shared.isIdleTimerDisabled = false
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        holdTimer?.invalidate()
        hideTimer?.invalidate()
        halfBannerTimer?.invalidate()
    }
}

// MARK: - Custom controls overlay

final class TVControlsOverlay: UIView {
    var onBack:       (() -> Void)?
    var onPlayPause:  (() -> Void)?
    var onRewind:     (() -> Void)?
    var onForward:    (() -> Void)?
    var onSwitchHalf: ((Int) -> Void)?

    private let backButton      = UIButton(type: .system)
    private let rewindButton    = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton   = UIButton(type: .system)
    private let progressTrack   = UIView()
    private let progressFill    = UIView()
    private let currentLabel    = UILabel()
    private let durationLabel   = UILabel()
    private let halfButtonsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 16
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var fillWidthConstraint: NSLayoutConstraint!
    private var trackedHalfCount = 1
    private var trackedHalfIndex = 0

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

        // — Half buttons (top-right, built dynamically) —
        addSubview(halfButtonsStack)

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

            // Half buttons (top-right)
            halfButtonsStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            halfButtonsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -60),

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

    func update(current: Double, duration: Double, isPlaying: Bool, halfIndex: Int = 0, halfCount: Int = 1) {
        currentLabel.text  = format(current)
        durationLabel.text = format(duration)
        setPlaying(isPlaying)

        if halfCount != trackedHalfCount {
            trackedHalfCount = halfCount
            trackedHalfIndex = halfIndex
            rebuildHalfButtons()
        } else if halfIndex != trackedHalfIndex {
            trackedHalfIndex = halfIndex
            updateHalfButtonSelection()
        }

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

    // MARK: - Half buttons

    private func rebuildHalfButtons() {
        halfButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard trackedHalfCount > 1 else { return }

        for i in 0..<trackedHalfCount {
            let btn = UIButton(type: .system)
            let label = trackedHalfCount == 2 ? (i == 0 ? "1st Half" : "2nd Half") : "Part \(i + 1)"
            var cfg = UIButton.Configuration.filled()
            cfg.title = label
            cfg.baseForegroundColor = i == trackedHalfIndex ? .black : .white
            cfg.baseBackgroundColor = i == trackedHalfIndex
                ? UIColor(red: 0.08, green: 0.77, blue: 0.37, alpha: 1)
                : UIColor.white.withAlphaComponent(0.18)
            cfg.cornerStyle = .capsule
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
            btn.configuration = cfg
            btn.tag = i
            btn.addTarget(self, action: #selector(halfButtonTapped(_:)), for: .primaryActionTriggered)
            halfButtonsStack.addArrangedSubview(btn)
        }
    }

    private func updateHalfButtonSelection() {
        for (i, view) in halfButtonsStack.arrangedSubviews.enumerated() {
            guard let btn = view as? UIButton else { continue }
            var cfg = btn.configuration
            cfg?.baseForegroundColor = i == trackedHalfIndex ? .black : .white
            cfg?.baseBackgroundColor = i == trackedHalfIndex
                ? UIColor(red: 0.08, green: 0.77, blue: 0.37, alpha: 1)
                : UIColor.white.withAlphaComponent(0.18)
            btn.configuration = cfg
        }
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

    @objc private func backTapped()              { onBack?() }
    @objc private func playPauseTapped()         { onPlayPause?() }
    @objc private func rewindTapped()            { onRewind?() }
    @objc private func forwardTapped()           { onForward?() }
    @objc private func halfButtonTapped(_ sender: UIButton) { onSwitchHalf?(sender.tag) }
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

    // Extracts all playlist part URLs (handles multi-half matches), reports as JSON array.
    static let autoPlay = """
    (function() {
        var reported = false;
        var fallbackTimer = null;

        function report(urls) {
            if (reported || !urls || !urls.length) return;
            reported = true;
            if (fallbackTimer) clearTimeout(fallbackTimer);
            window.webkit.messageHandlers.streamFound.postMessage(JSON.stringify(urls));
        }

        function extractFromPlaylist() {
            try {
                var m = document.documentElement.innerHTML.match(/var playlist = (\\[[\\s\\S]*?\\]);/);
                if (!m) return false;
                var items = JSON.parse(m[1]);
                if (!items || !items.length) return false;
                var urls = [];
                for (var i = 0; i < items.length; i++) {
                    if (!items[i].file) continue;
                    var url = window.atob(String(items[i].file).replace(/\\s/g, ''));
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
                if (item && item.file) { report([item.file]); }
            } catch(e) {}
        }

        function tryStart() {
            if (extractFromPlaylist()) return true;
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
        if (!extractFromPlaylist()) {
            var poll = setInterval(function() {
                tries++;
                if (tries > 40) { clearInterval(poll); return; }
                if (tryStart() && reported) clearInterval(poll);
            }, 250);
        }
    })();
    """
}
