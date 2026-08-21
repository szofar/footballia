import SwiftUI

struct VideoGridView: View {
    let title: String
    let matches: [Match]
    let isLoading: Bool
    let currentPage: Int
    let hasNextPage: Bool
    let isReversed: Bool
    let onSelect: (Match) -> Void
    let onNextPage: () -> Void
    let onPreviousPage: () -> Void

    private var hasPreviousPage: Bool { currentPage > 1 }
    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16)]

    private var displayedMatches: [Match] {
        isReversed ? matches.reversed() : matches
    }

    #if os(tvOS)
    @FocusState private var focusedID: String?
    @State private var rowLastFocus: [Int: String] = [:]
    @State private var columnCount: Int = 7  // refined at render time via GeometryReader
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        macBody
        #endif
    }

    #if os(tvOS)
    private var tvBody: some View {
        let leftEnabled = isReversed ? hasNextPage : hasPreviousPage
        let rightEnabled = isReversed ? hasPreviousPage : hasNextPage

        return ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)

                        if isLoading && matches.isEmpty {
                            Text("Loading matches…")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.35))
                        } else if !matches.isEmpty {
                            Text("\(matches.count) matches")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 100)
                    .padding(.top, 30)

                    // Geometry probe to determine column count for row-memory tracking
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            let w = geo.size.width
                            columnCount = max(1, Int((w + 16) / (230 + 16)))
                        }
                    }
                    .frame(height: 0)

                    ZStack(alignment: .center) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(displayedMatches) { match in
                                Button { onSelect(match) } label: {
                                    VideoCardView(match: match)
                                }
                                .buttonStyle(.plain)
                                .focused($focusedID, equals: match.id)
                                .focusEffectDisabled()
                            }
                        }
                        .opacity(isLoading ? 0.35 : 1)

                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                                .tint(.green)
                        }
                    }
                    .padding(.horizontal, 100)
                    .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: focusedID) { _, newID in
                applyRowMemory(focusedID: newID)
            }
            .onChange(of: displayedMatches) { _, _ in
                rowLastFocus = [:]
            }

            // Vertically-elongated page navigation arrows pinned to left/right edges
            HStack {
                if leftEnabled {
                    Button(action: isReversed ? onNextPage : onPreviousPage) {
                        TVArrowLabel(systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                } else {
                    Color.clear.frame(width: 64)
                }

                Spacer()

                if rightEnabled {
                    Button(action: isReversed ? onPreviousPage : onNextPage) {
                        TVArrowLabel(systemImage: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                } else {
                    Color.clear.frame(width: 64)
                }
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(!isLoading)
        }
    }

    private func applyRowMemory(focusedID newID: String?) {
        guard let newID,
              let newIdx = displayedMatches.firstIndex(where: { $0.id == newID })
        else { return }

        let newRow = newIdx / max(1, columnCount)

        // If we have a remembered position for this row and it differs from where
        // the focus engine landed, redirect focus to the remembered position.
        if let remembered = rowLastFocus[newRow],
           remembered != newID,
           displayedMatches.contains(where: { $0.id == remembered }) {
            focusedID = remembered
            return
        }

        // Record this as the current column for the row.
        rowLastFocus[newRow] = newID
    }
    #endif

    private var macBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                    .padding(.horizontal, 28)
                    .padding(.top, 30)

                ZStack(alignment: .center) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(displayedMatches) { match in
                            VideoCardView(match: match)
                                .onTapGesture { onSelect(match) }
                        }
                    }
                    .opacity(isLoading ? 0.35 : 1)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                            .tint(.green)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                if isLoading && matches.isEmpty {
                    Text("Loading matches…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                } else {
                    Text("\(matches.count) matches")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            HStack(spacing: 6) {
                pageButton(
                    systemImage: "chevron.left",
                    enabled: isReversed ? hasNextPage : hasPreviousPage,
                    action: isReversed ? onNextPage : onPreviousPage
                )
                pageButton(
                    systemImage: "chevron.right",
                    enabled: isReversed ? hasPreviousPage : hasNextPage,
                    action: isReversed ? onPreviousPage : onNextPage
                )
            }
        }
    }

    private func pageButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(enabled ? .white : .white.opacity(0.2))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(enabled ? 0.09 : 0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#if os(tvOS)
private struct TVArrowLabel: View {
    @Environment(\.isFocused) private var isFocused
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(isFocused ? 0.18 : 0.06))
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(isFocused ? .white : .white.opacity(0.4))
        }
        .frame(width: 56, height: 260)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
#endif
