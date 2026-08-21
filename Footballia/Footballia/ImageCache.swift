import SwiftUI
import CryptoKit

// MARK: - Image cache

/// Two-level cache: NSCache (in-memory) + disk (survives across launches).
/// Avoids re-fetching team crests and logos every time a view appears.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, NSData>()
    private let cacheDir: URL

    private init() {
        memory.totalCostLimit = 32 * 1024 * 1024 // 32 MB
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("footballia-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> Image? {
        if let data = memory.object(forKey: url as NSURL) {
            return decode(data as Data)
        }
        if let data = try? Data(contentsOf: diskPath(for: url)) {
            memory.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            return decode(data)
        }
        return nil
    }

    func store(_ data: Data, for url: URL) {
        memory.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        try? data.write(to: diskPath(for: url), options: .atomic)
    }

    func decode(_ data: Data) -> Image? {
        #if os(macOS)
        guard let img = NSImage(data: data) else { return nil }
        return Image(nsImage: img)
        #else
        guard let img = UIImage(data: data) else { return nil }
        return Image(uiImage: img)
        #endif
    }

    private func diskPath(for url: URL) -> URL {
        // SHA-256 gives a stable, collision-resistant filename (hashValue is not stable across launches)
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name)
    }
}

// MARK: - Cached image view

/// Drop-in replacement for AsyncImage that persists fetched images to disk.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            await MainActor.run { phase = .empty }
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            await MainActor.run { phase = .success(cached) }
            return
        }
        await MainActor.run { phase = .empty }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = ImageCache.shared.decode(data) {
                ImageCache.shared.store(data, for: url)
                await MainActor.run { phase = .success(img) }
            } else {
                await MainActor.run { phase = .failure(URLError(.cannotDecodeContentData)) }
            }
        } catch {
            await MainActor.run { phase = .failure(error) }
        }
    }
}
