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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                    .padding(.horizontal, 28)
                    .padding(.top, 30)

                ZStack(alignment: .center) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(matches) { match in
                            #if os(tvOS)
                            Button { onSelect(match) } label: {
                                VideoCardView(match: match)
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            #else
                            VideoCardView(match: match)
                                .onTapGesture { onSelect(match) }
                            #endif
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
                    Text("\(matches.count) matches · page \(currentPage)")
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
