import SwiftUI

struct CompetitionsView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedCompetition: Competition? = nil
    @State private var selectedMatch: Match? = nil

    var body: some View {
        ZStack {
            if let comp = selectedCompetition {
                // Drill-down: show matches for this competition
                VStack(spacing: 0) {
                    backBar(title: comp.name)
                    VideoGridView(
                        title: comp.name,
                        matches: service.matches,
                        isLoading: service.isLoadingMatches,
                        currentPage: service.currentPage,
                        hasNextPage: service.hasNextPage,
                        isReversed: service.paginationReversed,
                        onSelect: { selectedMatch = $0 },
                        onNextPage: {
                            Task { await service.loadMatches(
                                filter: .competition(comp.slug),
                                page: service.currentPage + 1
                            )}
                        },
                        onPreviousPage: {
                            Task { await service.loadMatches(
                                filter: .competition(comp.slug),
                                page: service.currentPage - 1
                            )}
                        }
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .allowsHitTesting(selectedMatch == nil)
            } else {
                catalogueView
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .allowsHitTesting(selectedMatch == nil)
            }

            if let match = selectedMatch {
                VideoPlayerOverlay(match: match) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedMatch = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedCompetition != nil)
        .task { await service.loadCompetitions() }
    }

    // MARK: - Catalogue

    private var catalogueView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Competitions")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Browse by tournament or league")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)

                if service.isLoadingCompetitions {
                    ProgressView()
                        .tint(.green)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if service.competitionCategories.isEmpty {
                    Text("No competitions found.")
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(service.competitionCategories) { category in
                        categorySection(category)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func categorySection(_ category: CompetitionCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section separator + header
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 3, height: 18)
                    .clipShape(Capsule())
                Text(category.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(1.5)
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
            .padding(.horizontal, 28)

            ForEach(category.groups) { group in
                groupSection(group)
            }
        }
    }

    /// One sub-heading of a category — a country under Domestic, a continent under the
    /// national-team columns — followed by its competitions.
    ///
    /// The site only ships country flags as a CSS sprite sheet, with no image URL to load, so
    /// the flag is rendered from the sprite's country code as a Unicode flag instead. A group
    /// with no name (a flat category such as "Others") skips the separator entirely.
    @ViewBuilder
    private func groupSection(_ group: CompetitionGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !group.name.isEmpty {
                HStack(spacing: 8) {
                    if let flag = group.flagEmoji {
                        Text(verbatim: flag).font(.system(size: 15))
                    }
                    Text(group.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
                .padding(.horizontal, 28)
            }

            // Competition cards in a horizontal flow
            let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.competitions) { comp in
                    CompetitionCard(competition: comp) {
                        service.loadMatchesLastPage(filter: .competition(comp.slug))
                        selectedCompetition = comp
                    }
                }
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Back bar

    private func backBar(title: String) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selectedCompetition = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Competitions")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }
}

// MARK: - Competition card

private struct CompetitionCard: View {
    let competition: Competition
    let onTap: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let logoURL = competition.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                        default: iconPlaceholder
                        }
                    }
                    .frame(width: 36, height: 36)
                } else {
                    iconPlaceholder.frame(width: 36, height: 36)
                }

                Text(competition.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isHighlighted ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHighlighted ? 0.12 : 0.06), lineWidth: 1)
            )
            .scaleEffect(isHighlighted ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.2))
            )
    }
}
